from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path

import psycopg2
from psycopg2 import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from scripts.pdc_backup import deterministic_table_hash, export_table  # noqa: E402
from staging_env import assert_staging_target, load_local_env  # noqa: E402

MIGRATIONS = (
    ("160", "email_communication_board_actions", "b78f1b8b610eb9348954723b2c1e734ad401cc20cfa0b6204257b6f9317520bc"),
    ("161", "non_navision_jobcard_board_creation", "b2a447bd1412da545673713d97f3c67474bb6e8440e3db079ed96e66fa4ecc09"),
    ("162", "manager_approved_workbook_canonical_activation", "a2e1e442750d9b92a2ee38c1db3fe7c4327119b3085acb7bb411868512da7a79"),
)
TABLES = (
    "pdc_email_communication_receipts", "pdc_email_communication_action_receipts",
    "pdc_email_evidence_consumptions", "pdc_non_navision_jobcard_receipts",
    "pdc_non_navision_jobcard_source_row_receipts", "pdc_pmb_canonical_manager_authorities",
    "pdc_pmb_canonical_manager_approvals", "pdc_pmb_canonical_admin_countersignatures",
    "pdc_pmb_canonical_apply_authorizations", "pdc_pmb_canonical_apply_receipts",
    "pdc_pmb_canonical_pair_receipts",
)
RECOVERY_BINDING_TABLES = (
    "vehicles", "vehicle_aliases", "navision_backend_records", "navision_board_activations",
    "navision_backend_revision", "vehicle_master_revision", "vehicle_lifecycle_resolver_revision",
    "vehicle_work_items", "pdc_authenticated_email_import_receipts", "pdc_authenticated_email_operation_lines",
    "pdc_pmb_workbook_previews", "pdc_pmb_workbook_pair_reviews", "pdc_pmb_workbook_operation_reviews",
    "pdc_pmb_workbook_pair_approvals", "pdc_pmb_workbook_apply_authorizations", "pdc_pmb_workbook_apply_receipts",
    "pdc_pmb_workbook_pair_receipts", "pdc_user_roles", "pdc_monitor_stage_activation_writers",
)
FUNCTION_ACL = {
    "public.process_pdc_email_communication(uuid,text,text,jsonb,text)": {"authenticated": True, "service_role": False},
    "public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)": {"authenticated": True, "service_role": False},
    "public.configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text)": {"authenticated": True, "service_role": False},
    "public.manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text)": {"authenticated": True, "service_role": False},
    "public.administrator_countersign_pdc_pmb_canonical_activation(uuid,text,text,text)": {"authenticated": True, "service_role": False},
    "public.authorize_pdc_pmb_canonical_activation_apply(uuid,text,text,integer,text)": {"authenticated": True, "service_role": False},
    "public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text)": {"authenticated": True, "service_role": False},
}


def scalar(cur, sql: str, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]


def body(source: str) -> str:
    start = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not start or not commits:
        raise RuntimeError("migration transaction markers missing")
    return source[start.end():commits[-1].start()]


def operational_state(cur, relations: tuple[str, ...] | None = None) -> dict[str, tuple[int, str]]:
    if relations is None:
        cur.execute(
            "select tablename from pg_catalog.pg_tables where schemaname='public' and tablename<>all(%s) order by tablename",
            (list(TABLES),),
        )
        relations = tuple(row[0] for row in cur.fetchall())
    result: dict[str, tuple[int, str]] = {}
    for name in relations:
        cur.execute(sql.SQL("""
            select count(*)::bigint,
                   encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'UTF8'),'sha256'),'hex')
            from {}.{} t
        """).format(sql.Identifier("public"), sql.Identifier(name)))
        result[name] = cur.fetchone()
    return result


def validate_recovery_gate(cur, manifest_arg: str, restore_run_arg: str) -> dict[str, str]:
    manifest_path = Path(manifest_arg).expanduser().resolve(strict=True)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    required = {"backup_run_id", "environment", "backup_format_version", "migration_version", "file_name", "file_size_bytes", "file_sha256", "table_hashes", "schema_object_hashes", "encrypted"}
    if not required.issubset(manifest) or manifest["environment"] != "staging" or manifest["backup_format_version"] != "2" or manifest["migration_version"] != "159" or manifest["encrypted"] is not True:
        raise RuntimeError("backup manifest contract mismatch")
    backup_run_id = str(uuid.UUID(str(manifest["backup_run_id"])))
    restore_run_id = str(uuid.UUID(restore_run_arg))
    artifact = (manifest_path.parent / manifest["file_name"]).resolve(strict=True)
    if artifact.parent != manifest_path.parent or artifact.stat().st_size != manifest["file_size_bytes"]:
        raise RuntimeError("backup artifact path or size mismatch")
    artifact_hash = hashlib.sha256(artifact.read_bytes()).hexdigest()
    if artifact_hash != manifest["file_sha256"] or not re.fullmatch(r"[a-f0-9]{64}", artifact_hash):
        raise RuntimeError("backup artifact digest mismatch")
    cur.execute("""
        select environment,status::text,migration_version,file_sha256,file_size_bytes,
               finished_at>clock_timestamp()-interval '2 hours'
        from public.backup_runs where id=%s
    """, (backup_run_id,))
    backup_row = cur.fetchone()
    if backup_row != ("staging", "success", "159", artifact_hash, artifact.stat().st_size, True):
        raise RuntimeError(f"backup database evidence mismatch: {backup_row}")
    cur.execute("""
        select backup_run_id::text,environment,status::text,target_schema,row_count_matches,verification_report
        from public.restore_test_runs where id=%s
    """, (restore_run_id,))
    restore_row = cur.fetchone()
    if not restore_row:
        raise RuntimeError("isolated restore receipt missing")
    restored_backup, environment, status, schema_name, row_counts_match, report = restore_row
    format_evidence = report.get("format_evidence", {}) if isinstance(report, dict) else {}
    if (restored_backup != backup_run_id or environment != "staging" or status != "success" or row_counts_match is not True
            or report.get("all_checks_passed") is not True or report.get("migration_version") != "159"
            or report.get("backup_run_id") != backup_run_id or report.get("foreign_keys_skipped") != []
            or report.get("foreign_keys_added") != report.get("foreign_keys_discovered")
            or format_evidence.get("all_hashes_match") is not True
            or format_evidence.get("all_schema_objects_match") is not True
            or set(format_evidence.get("table_hashes", {})) != set(manifest["table_hashes"])
            or set(format_evidence.get("schema_objects", {})) != set(manifest["schema_object_hashes"])):
        raise RuntimeError("isolated restore evidence is incomplete or mismatched")
    if scalar(cur, "select to_regnamespace(%s) is not null", (schema_name,)):
        raise RuntimeError("isolated restore schema was not cleaned up")
    for table in RECOVERY_BINDING_TABLES:
        columns, rows = export_table(cur, table)
        if deterministic_table_hash(columns, rows) != manifest["table_hashes"].get(table):
            raise RuntimeError(f"backup no longer matches current staging recovery state ({table})")
    return {"backup_run_id": backup_run_id, "backup_sha256": artifact_hash, "restore_run_id": restore_run_id}


def verify(cur, before):
    if operational_state(cur, tuple(before)) != before:
        raise RuntimeError("structural install changed operational state")
    ledger = []
    for version, name, _ in MIGRATIONS:
        count = scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version=%s and name=%s", (version, name))
        if count != 1:
            raise RuntimeError(f"ledger verification failed for {version}")
        ledger.append(version)
    missing = [name for name in TABLES if scalar(cur, "select to_regclass(%s) is null", (f"public.{name}",))]
    if missing:
        raise RuntimeError(f"new relations missing: {missing}")
    acl = {}
    for signature, expected in FUNCTION_ACL.items():
        if scalar(cur, "select to_regprocedure(%s) is null", (signature,)):
            raise RuntimeError(f"function missing: {signature}")
        actual = {role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, signature)) for role in expected}
        if actual != expected:
            raise RuntimeError(f"function ACL mismatch: {signature}: {actual}")
        acl[signature] = actual
    service_table_access = [name for name in TABLES if scalar(
        cur,
        "select has_table_privilege('service_role',%s,'SELECT') or has_table_privilege('service_role',%s,'INSERT') or has_table_privilege('service_role',%s,'UPDATE') or has_table_privilege('service_role',%s,'DELETE')",
        (f"public.{name}", f"public.{name}", f"public.{name}", f"public.{name}"),
    )]
    if service_table_access:
        raise RuntimeError(f"service role relation authority leaked: {service_table_access}")
    return {"ledger": ledger, "new_relation_count": len(TABLES), "function_acl_count": len(acl), "operational_state_unchanged": True}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    parser.add_argument("--backup-manifest")
    parser.add_argument("--restore-run-id")
    args = parser.parse_args()
    sources = []
    hashes = {}
    for version, _, expected in MIGRATIONS:
        path = next((ROOT / "supabase" / "staging_only").glob(f"{version}_*.sql"))
        raw = path.read_bytes()
        actual = hashlib.sha256(raw).hexdigest()
        if actual != expected:
            raise RuntimeError(f"migration {version} digest mismatch: {actual}")
        sources.append(raw.decode("utf-8"))
        hashes[version] = actual
    if args.apply:
        if not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit):
            raise RuntimeError("exact reviewed commit required")
        if not args.backup_manifest or not args.restore_run_id:
            raise RuntimeError("exact backup manifest and isolated restore receipt required")
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        if head != args.expected_commit or dirty:
            raise RuntimeError("unreviewed or dirty apply refused")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=dsn)
    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            if scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != "cdsmnqxtyyoeoznmbidd" or scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError("staging sentinel mismatch")
            latest = scalar(cur, "select version from supabase_migrations.schema_migrations order by version::integer desc limit 1")
            if latest != "159" or scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version in ('160','161','162')"):
                raise RuntimeError(f"ledger pre-state mismatch: latest={latest}")
            recovery = validate_recovery_gate(cur, args.backup_manifest, args.restore_run_id) if args.apply else None
            before = operational_state(cur)
            for source in sources:
                cur.execute(body(source))
            outcome = verify(cur, before)
            if args.apply:
                conn.commit()
            else:
                conn.rollback()
                with conn.cursor() as check:
                    if scalar(check, "select count(*) from supabase_migrations.schema_migrations where version in ('160','161','162')") or operational_state(check, tuple(before)) != before or any(scalar(check, "select to_regclass(%s) is not null", (f"public.{name}",)) for name in TABLES):
                        raise RuntimeError("rollback leaked candidate state")
                print(json.dumps({"ok": True, "mode": "rehearsal", "hashes": hashes, "rollback_verified": True, "outcome": outcome}, sort_keys=True))
                return 0
        with conn.cursor() as cur:
            persisted = verify(cur, before)
        conn.rollback()
        print(json.dumps({"ok": True, "mode": "apply", "hashes": hashes, "recovery": recovery, "outcome": persisted, "production_changed": False}, sort_keys=True))
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
