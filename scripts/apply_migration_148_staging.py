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

MIGRATION = ROOT / "supabase" / "staging_only" / "148_bind_canonical_document_evidence_to_retained_source.sql"
EXPECTED_SHA256 = "2731530f97e5b132ce67bd87d0b98312d944de413acb8e1e400462afa51341b5"
SIGNATURE = "public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)"


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]


def operational_state(cur):
    return tuple(
        scalar(cur, query)
        for query in (
            "select count(*) from public.vehicles",
            "select count(*) from public.navision_board_activations",
            "select count(*) from public.vehicle_work_items",
            "select count(*) from public.vehicle_parts_updates",
            "select count(*) from public.workshop_bookings",
            "select count(*) from public.pdc_authenticated_email_import_receipts",
            "select count(*) from public.pdc_authenticated_email_operation_lines",
            "select revision from public.pdc_email_vehicle_revision where singleton",
        )
    )


def transaction_body(source: str) -> str:
    start = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not start or not commits:
        raise RuntimeError("migration transaction markers missing")
    return source[start.end() : commits[-1].start()]


def verify(cur, before):
    definition = scalar(cur, "select pg_get_functiondef(%s::regprocedure)", (SIGNATURE,))
    comment = scalar(cur, "select obj_description(%s::regprocedure,'pg_proc')", (SIGNATURE,))
    for marker in (
        "'contract_version',7",
        "source_proposal_binding_mismatch",
        "p.action_type='board_activate_only'",
        "public.normalize_vehicle_stock_number(v_activation.activated_stock_number) IS DISTINCT FROM v_stock",
        "pdc_monitor_canonical_stock_import_148",
    ):
        if marker.lower() not in definition.lower():
            raise RuntimeError(f"v7 marker missing: {marker}")
    if "lower(p.evidence_hash) = v_evidence_hash" in definition.lower():
        raise RuntimeError("message-level proposal hash is still incorrectly required to equal canonical document hash")
    for forbidden in (
        "insert into public.vehicles",
        "insert into public.navision_board_activations",
        "update public.navision_board_activations",
        "vehicle_parts_updates",
        "pdc_ai_intake_history",
        "workshop_bookings",
    ):
        if forbidden in definition.lower():
            raise RuntimeError(f"forbidden v7 token: {forbidden}")
    if definition.lower().count("update public.vehicles set") != 1 or not re.search(
        r"update public\.vehicles set\s+job_card_number=v_job_card,version=version\+1,updated_by=v_actor_id\s+where id=v_vehicle\.id",
        definition,
        re.I,
    ):
        raise RuntimeError("JC-only vehicle update invariant failed")
    if "Staging v7 Monitor importer" not in comment:
        raise RuntimeError("v7 comment missing")
    acl = {role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, SIGNATURE)) for role in ("public", "anon", "authenticated", "service_role")}
    if acl != {"public": False, "anon": False, "authenticated": True, "service_role": False}:
        raise RuntimeError(f"ACL mismatch: {acl}")
    if not scalar(cur, "select prosecdef and proconfig=array['search_path=pg_catalog, public, extensions']::text[] from pg_proc where oid=%s::regprocedure", (SIGNATURE,)):
        raise RuntimeError("security-definer/search_path mismatch")
    if operational_state(cur) != before:
        raise RuntimeError("structural install changed operational data")
    return {
        "activation_stock_binding": True,
        "canonical_document_hash_receipt_binding": True,
        "retained_source_proposal_binding": True,
        "authenticated_execute_only": True,
        "forbidden_mutators_absent": True,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    raw = MIGRATION.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA256:
        raise RuntimeError(f"digest mismatch: {digest}")
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
    try:
        with conn.cursor() as cur:
            if scalar(cur, "select project_ref from pdc_staging_environment_sentinel where singleton") != "cdsmnqxtyyoeoznmbidd" or scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError("sentinel mismatch")
            if scalar(cur, "select version from supabase_migrations.schema_migrations order by version::integer desc limit 1") != "147" or scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='148')"):
                raise RuntimeError("ledger pre-state mismatch")
            before = operational_state(cur)
            old_definition = scalar(cur, "select pg_get_functiondef(%s::regprocedure)", (SIGNATURE,))
            cur.execute(transaction_body(raw.decode("utf-8")))
            outcome = verify(cur, before)
            if args.apply:
                conn.commit()
            else:
                conn.rollback()
                with conn.cursor() as check:
                    if scalar(check, "select pg_get_functiondef(%s::regprocedure)", (SIGNATURE,)) != old_definition or operational_state(check) != before or scalar(check, "select exists(select 1 from supabase_migrations.schema_migrations where version='148')"):
                        raise RuntimeError("rollback leaked state")
                print(json.dumps({"ok": True, "mode": "rehearsal", "migration": "148", "sha256": digest, "outcome": outcome, "rollback_verified": True}, sort_keys=True))
                return
        with conn.cursor() as cur:
            if scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='148' and name='bind_canonical_document_evidence_to_retained_source'") != 1:
                raise RuntimeError("ledger persistence failed")
        conn.rollback()
        print(json.dumps({"ok": True, "mode": "apply", "migration": "148", "sha256": digest, "outcome": outcome, "production_changed": False}, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
