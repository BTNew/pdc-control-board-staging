from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "apply_migration_716_staging.py"
MANIFEST_PATH = ROOT / "scripts" / "controller_wheelhouse" / "apply_migration_716_manifest.json"
MIGRATION = ROOT / "supabase/staging_only/20260828040000_716_close_all_raw_navision_acl_grantees.sql"
PREVIOUS = ROOT / "supabase/staging_only/20260828030000_715_remove_leaked_navision_714_test_probes.sql"
TRUSTED_BOOTSTRAP_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
TRUSTED_SECRET_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
# These aliases are test seams only; production execution receives their values
# from the immutable manifest and never from argv or the environment.
BOOTSTRAP_PATH = TRUSTED_BOOTSTRAP_PATH
SECRET_PATH = TRUSTED_SECRET_PATH

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_PARENT_COMMIT = "b96c8fae340a8e0471196a5cf3e9b8bc8a6b9c1a"
EXPECTED_PARENT_TREE = "4884de6c46f2294df81427f9a5e4904373790f6f"
EXPECTED_PREVIOUS_SHA256 = "1df478da87e0c5ddb3735ce5489246251f91fc877ebc7700403630e62fca461d"
EXPECTED_MIGRATION_SHA256 = "864c417ef07ee9c6978eba3cfb1165664f70ac813e6a34ac6dae5337ab82f228"
EXPECTED_GIT_IDENTITY = "Hermes Agent\x00hermes-agent@local\x00Hermes Agent\x00hermes-agent@local"
APPLY_CONFIRM_ENV = "PDC_APPROVE_STAGING_MIGRATION_716"


class Stop(RuntimeError):
    def __init__(self, code: str, phase: str):
        super().__init__(code)
        self.code = code
        self.phase = phase


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.strip()


def _exact_file(path: Path, code: str, *, parent: Path | None = None) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise Stop(code, "attestation")
    try:
        resolved = path.resolve(strict=True)
    except OSError as exc:
        raise Stop(code, "attestation") from exc
    if resolved != path.absolute():
        raise Stop(code, "attestation")
    if parent is not None and resolved.parent != parent.resolve(strict=True):
        raise Stop(code, "attestation")
    return resolved


def _load_manifest() -> dict[str, object]:
    manifest = _exact_file(MANIFEST_PATH, "TRUST_MANIFEST_INVALID", parent=MANIFEST_PATH.parent)
    try:
        values = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Stop("TRUST_MANIFEST_INVALID", "attestation") from exc
    if not isinstance(values, dict) or values.get("schema") != "pdc-716-installer-trust-v1":
        raise Stop("TRUST_MANIFEST_INVALID", "attestation")
    return values


def _verify_source_and_paths(manifest: dict[str, object]) -> dict[str, Path]:
    script = _exact_file(SCRIPT_PATH, "CONTROLLER_PATH_INVALID", parent=SCRIPT_PATH.parent)
    if sha256(script) != manifest.get("controller_sha256"):
        raise Stop("CONTROLLER_SOURCE_HASH_MISMATCH", "attestation")

    migration = _exact_file(MIGRATION, "MIGRATION_SOURCE_INVALID", parent=MIGRATION.parent)
    previous = _exact_file(PREVIOUS, "PREVIOUS_SOURCE_INVALID", parent=PREVIOUS.parent)
    if sha256(previous) != EXPECTED_PREVIOUS_SHA256 or manifest.get("previous_sha256") != EXPECTED_PREVIOUS_SHA256:
        raise Stop("PREVIOUS_SOURCE_HASH_MISMATCH", "attestation")
    if sha256(migration) != EXPECTED_MIGRATION_SHA256 or manifest.get("migration_sha256") != EXPECTED_MIGRATION_SHA256:
        raise Stop("MIGRATION_SOURCE_HASH_MISMATCH", "attestation")

    bootstrap = _exact_file(TRUSTED_BOOTSTRAP_PATH, "BOOTSTRAP_PATH_INVALID", parent=TRUSTED_BOOTSTRAP_PATH.parent)
    secret = _exact_file(TRUSTED_SECRET_PATH, "SECRET_PATH_INVALID", parent=TRUSTED_SECRET_PATH.parent)
    if manifest.get("bootstrap_path") != str(bootstrap) or manifest.get("secret_path") != str(secret):
        raise Stop("TRUST_PATH_MANIFEST_MISMATCH", "attestation")
    if sha256(bootstrap) != manifest.get("bootstrap_sha256"):
        raise Stop("BOOTSTRAP_SOURCE_HASH_MISMATCH", "attestation")

    if manifest.get("approved_parent_commit") != EXPECTED_PARENT_COMMIT:
        raise Stop("TRUST_MANIFEST_INVALID", "attestation")
    if manifest.get("approved_parent_tree") != EXPECTED_PARENT_TREE:
        raise Stop("TRUST_MANIFEST_INVALID", "attestation")
    if manifest.get("git_identity") != EXPECTED_GIT_IDENTITY:
        raise Stop("TRUST_MANIFEST_INVALID", "attestation")
    return {"migration": migration, "previous": previous, "bootstrap": bootstrap, "secret": secret}


def attest(expected_commit: str) -> dict[str, object]:
    """Complete every stdlib-only release/source gate before local code or DB access."""
    if not re.fullmatch(r"[0-9a-f]{40}", expected_commit or ""):
        raise Stop("EXPECTED_CANDIDATE_INVALID", "attestation")
    manifest = _load_manifest()
    paths = _verify_source_and_paths(manifest)
    try:
        repo_root = Path(git("rev-parse", "--show-toplevel")).resolve(strict=True)
        head = git("rev-parse", "HEAD")
        parent = git("rev-parse", "HEAD^")
        tree = git("rev-parse", "HEAD^{tree}")
        status = git("status", "--porcelain=v1", "--untracked-files=all")
        identity = git("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", "HEAD")
    except (OSError, subprocess.CalledProcessError) as exc:
        raise Stop("GIT_ATTESTATION_FAILED", "attestation") from exc
    if repo_root != ROOT.resolve(strict=True):
        raise Stop("REPOSITORY_ROOT_MISMATCH", "attestation")
    if head != expected_commit:
        raise Stop("CANDIDATE_COMMIT_MISMATCH", "attestation")
    if parent != EXPECTED_PARENT_COMMIT:
        raise Stop("PARENT_COMMIT_MISMATCH", "attestation")
    if tree == EXPECTED_PARENT_TREE:
        raise Stop("CANDIDATE_TREE_UNCHANGED", "attestation")
    if status:
        raise Stop("REPOSITORY_NOT_CLEAN", "attestation")
    if identity != EXPECTED_GIT_IDENTITY:
        raise Stop("GIT_IDENTITY_MISMATCH", "attestation")
    return {"manifest": manifest, "paths": paths, "candidate_commit": head}


def load_staging_values(attestation: dict[str, object]) -> dict[str, str]:
    paths = attestation["paths"]
    assert isinstance(paths, dict)
    bootstrap_path = BOOTSTRAP_PATH
    secret_path = SECRET_PATH
    if bootstrap_path != paths["bootstrap"] or secret_path != paths["secret"]:
        raise Stop("TRUST_PATH_RUNTIME_MISMATCH", "attestation")
    spec = importlib.util.spec_from_file_location("bootstrap716apply", bootstrap_path)
    bootstrap = importlib.util.module_from_spec(spec)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap loader unavailable")
    spec.loader.exec_module(bootstrap)
    values = json.loads(bootstrap.unprotect(secret_path.read_bytes()).decode("utf-8"))
    bootstrap.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project reference mismatch")
    return values


def _apply_confirmation(candidate_commit: str) -> str:
    return f"apply migration 716 source {EXPECTED_MIGRATION_SHA256} candidate {candidate_commit}"


def main(argv: list[str] | None = None) -> dict[str, object]:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit", required=True)
    args = parser.parse_args(argv)

    attestation = attest(args.expected_commit)
    if args.apply and os.environ.get(APPLY_CONFIRM_ENV) != _apply_confirmation(args.expected_commit):
        raise Stop("APPLY_CONFIRMATION_MISSING", "authorization")
    values = load_staging_values(attestation)
    import psycopg2

    dsn = values["PDC_STAGING_DATABASE_URL"]
    with psycopg2.connect(
        dsn,
        host=None,
        connect_timeout=15,
        application_name="pdc716_acl_apply",
        sslmode="verify-full",
        sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
    ) as conn:
        with conn.cursor() as cur:
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            if cur.fetchone() != (EXPECTED_REF,):
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone()[0]:
                raise RuntimeError("production sentinel present")
            cur.execute("select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'")
            expected_head = "20260828030000" if args.apply else "20260828040000"
            if cur.fetchone()[0] != expected_head:
                raise RuntimeError(f"live database is not at expected head {expected_head}")
            if args.apply:
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
            cur.execute(
                """select version,name from supabase_migrations.schema_migrations
                   where version='20260828040000'"""
            )
            result = cur.fetchall()
        if args.apply:
            conn.commit()
        else:
            conn.rollback()
    return {"ok": True, "applied": args.apply, "migration_sha256": sha256(MIGRATION), "ledger": result}


if __name__ == "__main__":
    print(json.dumps(main(), sort_keys=True))
