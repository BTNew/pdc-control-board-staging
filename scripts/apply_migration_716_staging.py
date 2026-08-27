from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828040000_716_close_all_raw_navision_acl_grantees.sql"
PREVIOUS = ROOT / "supabase/staging_only/20260828030000_715_remove_leaked_navision_714_test_probes.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_BASE_COMMIT = "5d60baa07f32d696e3d494fad8be00dcb579fff4"
EXPECTED_BASE_TREE = "45932e116e25d06f64f7df8c265bf43f223b671d"
EXPECTED_PREVIOUS_SHA256 = "1df478da87e0c5ddb3735ce5489246251f91fc877ebc7700403630e62fca461d"
EXPECTED_MIGRATION_SHA256 = "864c417ef07ee9c6978eba3cfb1165664f70ac813e6a34ac6dae5337ab82f228"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def load_staging_values() -> dict:
    spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
    spec = importlib.util.spec_from_file_location("bootstrap716apply", spec_path)
    bootstrap = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(bootstrap)
    values = json.loads(
        bootstrap.unprotect(
            Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()
        ).decode()
    )
    bootstrap.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project reference mismatch")
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()

    if sha256(PREVIOUS) != EXPECTED_PREVIOUS_SHA256:
        raise RuntimeError("715 source digest mismatch")
    if EXPECTED_MIGRATION_SHA256.startswith("__") or sha256(MIGRATION) != EXPECTED_MIGRATION_SHA256:
        raise RuntimeError("716 source digest mismatch")
    if args.apply:
        expected_commit = args.expected_commit or git("rev-parse", "HEAD")
        if git("rev-parse", "HEAD^") != EXPECTED_BASE_COMMIT:
            raise RuntimeError("716 apply requires the exact approved candidate as the immediate parent")
        if git("rev-parse", "HEAD^{tree}") == EXPECTED_BASE_TREE:
            raise RuntimeError("716 apply requires a successor tree, not the unchanged candidate tree")
        if git("status", "--porcelain", "--untracked-files=all"):
            raise RuntimeError("716 apply requires a clean release worktree")
        if git("rev-parse", "HEAD") != expected_commit:
            raise RuntimeError("unexpected release commit")

    values = load_staging_values()
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
        conn.commit()
    print(json.dumps({"ok": True, "applied": args.apply, "migration_sha256": sha256(MIGRATION), "ledger": result}, sort_keys=True))


if __name__ == "__main__":
    main()
