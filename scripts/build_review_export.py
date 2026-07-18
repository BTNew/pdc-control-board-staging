"""Build the fail-closed Stage 2A independent-review ZIP.

The source side is allow-list based: only Git-tracked files at the current clean
HEAD are copied. The deployed side is an exact ``git archive`` of the recorded
staging deployment commit. Runtime directories and credentials are never
walked or copied.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BRANCH = "fix/stage2a-independent-review-findings"
EXPECTED_STAGING_DEPLOY_COMMIT = "505c524915d9a567078d08f73dfd63229f178d06"
DEFAULT_STAGING_DEPLOY_REPO = Path(r"C:\tmp\pdc-staging-deploy")
ZIP_NAME = "PDC-Control-Board-Stage-2A-Final-Contained-Review-2026-07-18.zip"

FORBIDDEN_PATH_PATTERNS = [
    "*.imap_attachments*", "*.outlook_attachments*", "*email_publish.log*",
    "*_backup_*.zip", "*PDC_Control_Board_Backup*", "*.env", "*.env.local",
    "*.env.staging", "*.env.production", "*node_modules*", "*.venv*",
    "*__pycache__*", "*.pyc", "*backups/*", "*.git/*", "*.bin",
    "*browser-session*", "*playwright-report*", "*test-results*",
]
ALLOWED_ENV_EXAMPLES = {"_staging_test_tools/.env.example", "backend/.env.example"}
FORBIDDEN_CONTENT_PATTERNS = [
    ("database URL with embedded password", None),
]
REQUIRED_SOURCE_PATHS = [
    "app.js", "index.html", "staging.html", "test_all.js",
    "workshop-planner.js", "workshop-planner.css",
    "workshop-reference-data-service.js", "test_workshop_planner_shared_mode.js",
    "test_workshop_reference_data_service.js", "requirements-review.txt",
    "package-review.json", "REVIEW-INSTRUCTIONS.md",
    "STAGE-2A-INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md",
    "STAGE-2A-SHARED-REFERENCE-DATA-HANDOVER.md",
    "test_workshop_planner_configuration.js",
    "supabase/migrations/026_stage2a_final_review_remediation.sql",
    "backend/test_stage2a_final_remediation.py",
    "_staging_test_tools/test_stage2a_final_remediation_staging.py",
    "scripts/stage2a_live_acceptance.js", "scripts/verify_stage2a_review_package.py",
    "review-evidence/final-contained/FINAL-STAGE2A-CONTAINED-VERIFICATION.md",
    "review-evidence/final-contained/MIGRATION-LEDGER-026.txt",
    "review-evidence/final-contained/STAGING-MIGRATION-026-RESULT.txt",
    "review-evidence/final-contained/cross-platform-ci-run.json",
    "review-evidence/final-contained/two-browser-planner-acceptance.json",
    "review-evidence/post-resume/full-schema-report.json",
    "review-evidence/post-resume/grants-rls-report.json",
    "review-evidence/post-resume/realtime-publication-replica-identity-report.json",
    "review-evidence/post-resume/migration-ledger.txt",
    "review-evidence/post-resume/two-browser-realtime-acceptance.json",
]


def run(*args: str, cwd: Path = REPO_ROOT) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_forbidden_path(rel_posix: str) -> bool:
    rel_posix = rel_posix.replace("\\", "/")
    while rel_posix.startswith("./"):
        rel_posix = rel_posix[2:]
    if rel_posix in ALLOWED_ENV_EXAMPLES:
        return False
    parts = rel_posix.split("/")
    if any(part in {".git", "node_modules", "__pycache__", ".review-venv", "_build"}
           or part.startswith(".venv") for part in parts):
        return True
    for pattern in FORBIDDEN_PATH_PATTERNS:
        if fnmatch.fnmatch(rel_posix, pattern) or fnmatch.fnmatch("/" + rel_posix, pattern):
            return True
        if fnmatch.fnmatch(Path(rel_posix).name, pattern):
            return True
    return False


def tracked_files(repo_root: Path = REPO_ROOT) -> list[str]:
    if (repo_root / ".git").exists():
        output = run("git", "ls-files", cwd=repo_root)
        return [line.replace("\\", "/") for line in output.splitlines() if line.strip()]
    # Extracted review packages intentionally contain no .git directory.
    # Their checksum manifest is the immutable allow-list for independent
    # exporter tests. Exclude exporter-generated metadata and the separate
    # deployed snapshot when reconstructing the reviewed source list.
    checksum_file = repo_root / "SHA256SUMS.txt"
    if checksum_file.is_file():
        generated = {
            "FINAL-SOURCE-HEAD.txt", "REVIEW-MANIFEST.json",
            "STAGING-DEPLOYMENT-COMMIT.txt",
        }
        result = []
        for line in checksum_file.read_text(encoding="utf-8").splitlines():
            _, rel = line.split("  ", 1)
            if rel not in generated and not rel.startswith("deployed-staging-snapshot/"):
                result.append(rel)
        return result
    raise RuntimeError("neither a Git checkout nor an extracted package checksum manifest was found")


def build_export_file_list(repo_root: Path = REPO_ROOT) -> list[str]:
    return sorted(rel for rel in tracked_files(repo_root) if not is_forbidden_path(rel))


def _database_url_has_password(data: bytes) -> bool:
    import re
    text = data.decode("utf-8", errors="ignore")
    # Placeholder *** and angle-bracket values are permitted in examples.
    pattern = re.compile(r"postgres(?:ql)?://[^\s:/]+:([^@\s]+)@", re.I)
    allowed_placeholders = {"***", "<password>", "REPLACE_WITH_PASSWORD", "REPLACE_WITH_YOUR_PASSWORD"}
    return any(match.group(1) not in allowed_placeholders
               for match in pattern.finditer(text))


def scan_content_safety(file_list: list[str], root: Path = REPO_ROOT) -> list[str]:
    problems: list[str] = []
    for rel in file_list:
        full = root / rel
        if not full.is_file():
            problems.append(f"{rel}: missing file")
            continue
        data = full.read_bytes()
        text = data.decode("utf-8", errors="ignore")
        # Match credential-shaped values, not documentation/validator source
        # that merely names the prohibited prefix or PEM delimiter.
        import re
        if re.search(r"sb_secret_[A-Za-z0-9_-]{20,}", text):
            problems.append(f"{rel}: matched forbidden Supabase secret key")
        if re.search(r"-----BEGIN (?:RSA )?PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{100,}", text):
            problems.append(f"{rel}: matched forbidden private key material")
        if re.search(r"(?:SERVICE_ROLE_KEY|service_role_key)\s*[=:]\s*['\"](?!REPLACE_|<|\[REDACTED\])[A-Za-z0-9._-]{20,}", text):
            problems.append(f"{rel}: matched forbidden service-role credential assignment")
        for label, needle in FORBIDDEN_CONTENT_PATTERNS:
            if needle is not None and needle in data:
                problems.append(f"{rel}: matched forbidden {label}")
        if _database_url_has_password(data):
            problems.append(f"{rel}: matched forbidden database URL with embedded password")
    return problems


def verify_no_forbidden_paths_in_export(file_list: list[str]) -> list[str]:
    return [rel for rel in file_list if is_forbidden_path(rel)]


def _copy_tracked_sources(
    files: list[str], destination: Path, repo_root: Path, source_head: str
) -> None:
    """Copy exact Git-blob bytes, bypassing checkout/archive EOL conversion."""
    for rel in files:
        data = subprocess.check_output(
            ["git", "-C", str(repo_root), "cat-file", "blob", f"{source_head}:{rel}"]
        )
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def _archive_staging_deployment(deploy_repo: Path, destination: Path) -> None:
    if not (deploy_repo / ".git").exists():
        raise RuntimeError(f"staging deployment checkout missing: {deploy_repo}")
    actual = run("git", "rev-parse", "HEAD", cwd=deploy_repo)
    if actual != EXPECTED_STAGING_DEPLOY_COMMIT:
        raise RuntimeError(f"wrong staging deployment commit: {actual}")
    if run("git", "status", "--porcelain", cwd=deploy_repo):
        raise RuntimeError("staging deployment checkout is dirty")
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        tar_path = Path(temp) / "deploy.tar"
        subprocess.run(
            ["git", "archive", "--format=tar", f"--output={tar_path}", actual],
            cwd=deploy_repo, check=True,
        )
        with tarfile.open(tar_path) as archive:
            archive.extractall(destination, filter="data")


def _all_package_files(root: Path) -> list[str]:
    return sorted(
        path.relative_to(root).as_posix() for path in root.rglob("*")
        if path.is_file() and path.name != "SHA256SUMS.txt"
    )


def _write_checksums(root: Path) -> None:
    lines = [f"{sha256_file(root / rel)}  {rel}" for rel in _all_package_files(root)]
    (root / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def _verify_required(stage: Path) -> None:
    missing = [rel for rel in REQUIRED_SOURCE_PATHS if not (stage / rel).is_file()]
    deployment_required = [
        "deployed-staging-snapshot/index.html",
        "deployed-staging-snapshot/app.js",
        "deployed-staging-snapshot/workshop-planner.js",
        "deployed-staging-snapshot/workshop-planner.css",
        "deployed-staging-snapshot/workshop-reference-data-service.js",
    ]
    missing += [rel for rel in deployment_required if not (stage / rel).is_file()]
    staging_tests = list((stage / "_staging_test_tools").glob("test_*.py"))
    if len(staging_tests) < 12:
        missing.append(f"all staging Python tests (found {len(staging_tests)}, expected at least 12)")
    backend_tests = list((stage / "backend").glob("test_*.py"))
    if not backend_tests:
        missing.append("backend tests")
    if missing:
        raise RuntimeError("review export missing required dependencies: " + ", ".join(missing))


def build_package(output_dir: Path, deploy_repo: Path = DEFAULT_STAGING_DEPLOY_REPO) -> dict:
    branch = run("git", "branch", "--show-current")
    source_head = run("git", "rev-parse", "HEAD")
    if branch != EXPECTED_BRANCH:
        raise RuntimeError(f"wrong source branch: {branch}")
    if run("git", "status", "--porcelain"):
        raise RuntimeError("source working tree is dirty; commit reviewed changes before export")

    file_list = build_export_file_list()
    forbidden = verify_no_forbidden_paths_in_export(file_list)
    content_problems = scan_content_safety(file_list)
    if forbidden or content_problems:
        raise RuntimeError(f"unsafe source export: paths={forbidden}, content={content_problems}")

    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    zip_path = output_dir / ZIP_NAME
    with tempfile.TemporaryDirectory(prefix="pdc-stage2a-review-") as temp:
        stage = Path(temp) / ZIP_NAME.removesuffix(".zip")
        stage.mkdir()
        _copy_tracked_sources(file_list, stage, REPO_ROOT, source_head)
        _archive_staging_deployment(deploy_repo, stage / "deployed-staging-snapshot")

        (stage / "FINAL-SOURCE-HEAD.txt").write_text(source_head + "\n", encoding="utf-8")
        (stage / "STAGING-DEPLOYMENT-COMMIT.txt").write_text(
            EXPECTED_STAGING_DEPLOY_COMMIT + "\n", encoding="utf-8"
        )
        manifest = {
            "package": ZIP_NAME,
            "source_branch": branch,
            "source_head": source_head,
            "staging_url": "https://btnew.github.io/pdc-control-board-staging/",
            "staging_deployment_commit": EXPECTED_STAGING_DEPLOY_COMMIT,
            "app_version": "2026.07.18.01-stage2a-final-contained",
            "source_file_count": len(file_list),
            "deployed_snapshot_file_count": len(list((stage / "deployed-staging-snapshot").rglob("*"))),
            "production_touched": False,
            "stage_2b_started": False,
        }
        (stage / "REVIEW-MANIFEST.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        _verify_required(stage)
        package_files = _all_package_files(stage)
        package_forbidden = verify_no_forbidden_paths_in_export(package_files)
        package_content = scan_content_safety(package_files, stage)
        if package_forbidden or package_content:
            raise RuntimeError(f"unsafe staged package: paths={package_forbidden}, content={package_content}")
        _write_checksums(stage)

        if zip_path.exists():
            zip_path.unlink()
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file():
                    archive.write(path, (Path(stage.name) / path.relative_to(stage)).as_posix())

    return {
        "zip_path": str(zip_path),
        "zip_size": zip_path.stat().st_size,
        "zip_sha256": sha256_file(zip_path),
        "source_branch": branch,
        "source_head": source_head,
        "staging_deployment_commit": EXPECTED_STAGING_DEPLOY_COMMIT,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT.parent)
    parser.add_argument("--staging-deploy-repo", type=Path, default=DEFAULT_STAGING_DEPLOY_REPO)
    parser.add_argument("--list-only", action="store_true")
    args = parser.parse_args()
    if args.list_only:
        file_list = build_export_file_list()
        problems = verify_no_forbidden_paths_in_export(file_list) + scan_content_safety(file_list)
        if problems:
            raise SystemExit("\n".join(problems))
        print(json.dumps({"files": file_list, "count": len(file_list)}, indent=2))
        return
    print(json.dumps(build_package(args.output_dir, args.staging_deploy_repo), indent=2))


if __name__ == "__main__":
    main()
