"""Standard-library verifier for an extracted Stage 2A review package."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_DEPLOY = "505c524915d9a567078d08f73dfd63229f178d06"
EXPECTED_BRANCH = "fix/stage2a-independent-review-findings"
FORBIDDEN_PARTS = {
    ".git", "node_modules", "__pycache__", ".review-venv", "backups",
    ".imap_attachments", ".outlook_attachments", "_build",
}
FORBIDDEN_SUFFIXES = {".bin", ".pyc", ".pfx", ".p12", ".key"}
REQUIRED = [
    "FINAL-SOURCE-HEAD.txt", "STAGING-DEPLOYMENT-COMMIT.txt",
    "REVIEW-MANIFEST.json", "SHA256SUMS.txt", "REVIEW-INSTRUCTIONS.md",
    "STAGE-2A-INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md",
    "STAGE-2A-SHARED-REFERENCE-DATA-HANDOVER.md",
    "app.js", "test_all.js", "workshop-planner.js", "workshop-planner.css",
    "workshop-reference-data-service.js", "requirements-review.txt",
    "test_workshop_planner_configuration.js",
    "test_workshop_shared_scheduling_assignment.js",
    "supabase/migrations/026_stage2a_final_review_remediation.sql",
    "supabase/migrations/027_stage2a_assignment_interval_enforcement.sql",
    "backend/test_stage2a_final_remediation.py",
    "backend/test_stage2a_assignment_interval_enforcement.py",
    "_staging_test_tools/test_stage2a_final_remediation_staging.py",
    "_staging_test_tools/test_stage2a_assignment_interval_enforcement_staging.py",
    "_staging_test_tools/cleanup_stage2a_assignment_acceptance.py",
    "scripts/stage2a_assignment_live_acceptance.js",
    "backend", "_staging_test_tools/.env.example",
    "deployed-staging-snapshot/index.html",
    "deployed-staging-snapshot/app.js",
    "deployed-staging-snapshot/workshop-planner.js",
    "deployed-staging-snapshot/workshop-planner.css",
    "deployed-staging-snapshot/workshop-reference-data-service.js",
    "review-evidence/post-resume/full-schema-report.json",
    "review-evidence/post-resume/grants-rls-report.json",
    "review-evidence/post-resume/realtime-publication-replica-identity-report.json",
    "review-evidence/post-resume/migration-ledger.txt",
    "review-evidence/post-resume/two-browser-realtime-acceptance.json",
    "review-evidence/final-contained/FINAL-STAGE2A-CONTAINED-VERIFICATION.md",
    "review-evidence/final-contained/MIGRATION-LEDGER-027.txt",
    "review-evidence/final-contained/STAGING-MIGRATION-027-RESULT.txt",
    "review-evidence/final-contained/cross-platform-ci-run.json",
    "review-evidence/final-contained/two-browser-planner-acceptance.json",
    "review-evidence/final-contained/two-browser-assignment-acceptance.json",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_checksums() -> list[str]:
    problems = []
    lines = (ROOT / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines()
    seen = set()
    for line in lines:
        expected, rel = line.split("  ", 1)
        target = ROOT / rel
        seen.add(rel)
        if not target.is_file():
            problems.append(f"checksum target missing: {rel}")
        elif sha256(target) != expected:
            problems.append(f"checksum mismatch: {rel}")
    actual = {
        path.relative_to(ROOT).as_posix() for path in ROOT.rglob("*")
        if path.is_file() and path.name != "SHA256SUMS.txt"
    }
    for rel in sorted(actual - seen):
        problems.append(f"file missing from checksum manifest: {rel}")
    for rel in sorted(seen - actual):
        problems.append(f"manifest names absent file: {rel}")
    return problems


def verify_prohibited_content() -> list[str]:
    problems = []
    db_url = re.compile(r"postgres(?:ql)?://[^\s:/]+:([^@\s]+)@", re.I)
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT).as_posix()
        parts = set(path.relative_to(ROOT).parts)
        if parts & FORBIDDEN_PARTS:
            problems.append(f"forbidden directory: {rel}")
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            problems.append(f"forbidden binary/credential suffix: {rel}")
        if path.name == ".env" or (path.name.startswith(".env.") and path.name != ".env.example"):
            problems.append(f"real environment file: {rel}")
        data = path.read_bytes()
        text = data.decode("utf-8", errors="ignore")
        if re.search(r"sb_secret_[A-Za-z0-9_-]{20,}", text):
            problems.append(f"Supabase secret key value: {rel}")
        if re.search(r"-----BEGIN (?:RSA )?PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{100,}", text):
            problems.append(f"private key material: {rel}")
        if re.search(r"(?:SERVICE_ROLE_KEY|service_role_key)\s*[=:]\s*['\"](?!REPLACE_|<|\[REDACTED\])[A-Za-z0-9._-]{20,}", text):
            problems.append(f"service-role credential assignment: {rel}")
        for match in db_url.finditer(text):
            if match.group(1) not in {"***", "<password>", "REPLACE_WITH_PASSWORD", "REPLACE_WITH_YOUR_PASSWORD"}:
                problems.append(f"database URL with password: {rel}")
    return problems


def normalized(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="strict").splitlines()


def main() -> None:
    problems = []
    for rel in REQUIRED:
        if not (ROOT / rel).exists():
            problems.append(f"required path missing: {rel}")
    manifest = json.loads((ROOT / "REVIEW-MANIFEST.json").read_text(encoding="utf-8"))
    if manifest.get("source_branch") != EXPECTED_BRANCH:
        problems.append("wrong source branch in manifest")
    if manifest.get("staging_deployment_commit") != EXPECTED_DEPLOY:
        problems.append("wrong deployment commit in manifest")
    if (ROOT / "STAGING-DEPLOYMENT-COMMIT.txt").read_text().strip() != EXPECTED_DEPLOY:
        problems.append("deployment commit record mismatch")
    if manifest.get("production_touched") is not False or manifest.get("stage_2b_started") is not False:
        problems.append("safety flags are not false")
    staging_tests = list((ROOT / "_staging_test_tools").glob("test_*.py"))
    if len(staging_tests) < 12:
        problems.append(f"only {len(staging_tests)} staging tests present")
    if not list((ROOT / "backend").glob("test_*.py")):
        problems.append("backend tests absent")
    source_deploy_pairs = [
        ("staging.html", "deployed-staging-snapshot/index.html"),
        ("app.js", "deployed-staging-snapshot/app.js"),
        ("workshop-planner.js", "deployed-staging-snapshot/workshop-planner.js"),
        ("workshop-planner.css", "deployed-staging-snapshot/workshop-planner.css"),
        ("workshop-reference-data-service.js", "deployed-staging-snapshot/workshop-reference-data-service.js"),
    ]
    for source, deployed in source_deploy_pairs:
        if normalized(ROOT / source) != normalized(ROOT / deployed):
            problems.append(f"deployed snapshot differs from reviewed source: {source}")
    problems.extend(verify_checksums())
    problems.extend(verify_prohibited_content())
    if problems:
        print("FAIL")
        for problem in problems:
            print(f"- {problem}")
        raise SystemExit(1)
    print(json.dumps({
        "result": "PASS",
        "checksums_verified": len((ROOT / "SHA256SUMS.txt").read_text().splitlines()),
        "staging_tests": len(staging_tests),
        "source_head": manifest["source_head"],
        "staging_deployment_commit": manifest["staging_deployment_commit"],
        "prohibited_content_findings": 0,
        "production_touched": False,
        "stage_2b_started": False,
    }, indent=2))


if __name__ == "__main__":
    main()
