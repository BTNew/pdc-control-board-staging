from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env  # noqa: E402

MIGRATIONS = (
    ("160", "email_communication_board_actions", "6c24cfa241a3a6c0104e3c51f932a2d4120e73e9e9ae473ede988d27a7cd9522"),
    ("161", "non_navision_jobcard_board_creation", "9199d131eabc817d509e64deaf04adedaa8e150409133e8265f51d6cd039eaee"),
    ("162", "manager_approved_workbook_canonical_activation", "82882062d36baa41d722136d651d089b147a33e34ae9d3a0c4096df363d2aa3b"),
)
TABLES = (
    "pdc_email_communication_receipts", "pdc_email_communication_action_receipts",
    "pdc_email_evidence_consumptions", "pdc_non_navision_jobcard_receipts",
    "pdc_non_navision_jobcard_source_row_receipts", "pdc_pmb_canonical_manager_authorities",
    "pdc_pmb_canonical_manager_approvals", "pdc_pmb_canonical_admin_countersignatures",
    "pdc_pmb_canonical_apply_authorizations", "pdc_pmb_canonical_apply_receipts",
    "pdc_pmb_canonical_pair_receipts",
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


def operational_state(cur) -> tuple[int, ...]:
    relations = (
        "vehicles", "navision_board_activations", "vehicle_work_items", "vehicle_parts_updates",
        "workshop_bookings", "pdc_authenticated_email_import_receipts", "pdc_authenticated_email_operation_lines",
        "pdc_pmb_workbook_previews", "pdc_pmb_workbook_pair_reviews", "pdc_pmb_workbook_operation_reviews",
    )
    counts = [scalar(cur, f"select count(*) from public.{name}") for name in relations]
    counts += [scalar(cur, "select revision from public.navision_backend_revision where singleton"),
               scalar(cur, "select coalesce(sum(revision),0)::bigint from public.workshop_revision")]
    return tuple(counts)


def verify(cur, before):
    if operational_state(cur) != before:
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
            before = operational_state(cur)
            for source in sources:
                cur.execute(body(source))
            outcome = verify(cur, before)
            if args.apply:
                conn.commit()
            else:
                conn.rollback()
                with conn.cursor() as check:
                    if scalar(check, "select count(*) from supabase_migrations.schema_migrations where version in ('160','161','162')") or operational_state(check) != before or any(scalar(check, "select to_regclass(%s) is not null", (f"public.{name}",)) for name in TABLES):
                        raise RuntimeError("rollback leaked candidate state")
                print(json.dumps({"ok": True, "mode": "rehearsal", "hashes": hashes, "rollback_verified": True, "outcome": outcome}, sort_keys=True))
                return 0
        with conn.cursor() as cur:
            persisted = verify(cur, before)
        conn.rollback()
        print(json.dumps({"ok": True, "mode": "apply", "hashes": hashes, "outcome": persisted, "production_changed": False}, sort_keys=True))
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
