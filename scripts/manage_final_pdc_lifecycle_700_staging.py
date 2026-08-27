#!/usr/bin/env python3
"""Fail-closed Supabase-management controller for final staging lifecycle 700."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
MIGRATION = ROOT / "supabase/staging_only/20260827101000_700_authoritative_pdc_lifecycle.sql"
EXPECTED_MIGRATION_SHA256 = "0ca2b75638cd9701fbb3b8f7ccbce201df2155d7ab06d93b4daf4823b8132a11"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_700"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"

STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827067200','20260827101000')),
 'predecessor_hashes',jsonb_build_object('reconcile',encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex'),'snapshot',encode(extensions.digest(convert_to(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure),'UTF8'),'sha256'),'hex')),
 'security',jsonb_build_object('qc_399',has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','execute'),'qc_700',case when to_regprocedure('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)') is null then false else has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','execute') end,'book_412',has_function_privilege('authenticated','public.book_rft_transport_412(uuid,integer,uuid)','execute'),'book_700',case when to_regprocedure('public.book_rft_transport_700(uuid,integer,uuid)') is null then false else has_function_privilege('authenticated','public.book_rft_transport_700(uuid,integer,uuid)','execute') end,'collect_412',has_function_privilege('authenticated','public.collect_rft_transport_412(uuid,integer,uuid)','execute'),'collect_700',case when to_regprocedure('public.collect_rft_transport_700(uuid,integer,uuid)') is null then false else has_function_privilege('authenticated','public.collect_rft_transport_700(uuid,integer,uuid)','execute') end,'snapshot',has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','execute'),'direct_dml',(select count(*)=0 from information_schema.role_table_grants where grantee='authenticated' and table_schema='public' and table_name='pdc_final_pdc_lifecycle_receipts_700' and privilege_type in('INSERT','UPDATE','DELETE','TRUNCATE')),'history_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid=to_regclass('public.pdc_final_pdc_lifecycle_receipts_700'))),
 'objects',jsonb_build_object('receipts',to_regclass('public.pdc_final_pdc_lifecycle_receipts_700') is not null,'delivery',to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') is not null,'qc',to_regprocedure('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)') is not null,'book',to_regprocedure('public.book_rft_transport_700(uuid,integer,uuid)') is not null,'collect',to_regprocedure('public.collect_rft_transport_700(uuid,integer,uuid)') is not null),
 'counts',jsonb_build_object('notifications',(select count(*) from public.vehicle_notifications),'outbox_399',(select count(*) from public.pdc_qc_salesperson_update_outbox_399),'outbox_412',(select count(*) from public.pdc_rft_transport_salesperson_outbox_412),'outbox_412_duplicate_vehicles',(select count(*) from(select vehicle_id from public.pdc_rft_transport_salesperson_outbox_412 group by vehicle_id having count(*)>1)x))
) as evidence;
"""


def run_query(sql: str, source: Path | None = None) -> dict:
    temp: Path | None = None
    try:
        if source is None:
            handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", prefix="hermes-verify-", delete=False)
            handle.write(sql)
            handle.close()
            temp = Path(handle.name)
            source = temp
        result = subprocess.run([SUPABASE_CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", EXPECTED_REF, "--output-format", "json", "--file", str(source)], cwd=ROOT, capture_output=True, text=True, timeout=300, check=False)
        if result.returncode:
            raise RuntimeError(f"management query failed: {result.returncode}")
        start = result.stdout.find("{")
        if start < 0:
            raise RuntimeError("management query returned no JSON")
        value, _ = json.JSONDecoder().raw_decode(result.stdout[start:])
        return value
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)


def state() -> dict:
    return run_query(STATE_SQL)["rows"][0]["evidence"]


def assert_pre(value: dict) -> None:
    if value["target"] != {"database": "postgres", "current_user": "postgres", "session_user": "postgres", "staging_sentinel": 1, "production_sentinel": False}:
        raise RuntimeError("EXACT_STAGING_TARGET_PRESTATE_REQUIRED")
    if value["head"] != "20260827067200" or value["ledger"] != [{"version": "20260827067200", "name": "672_authenticated_active_email_monitor_identity_successor"}]:
        raise RuntimeError("EXACT_672_LEDGER_PRESTATE_REQUIRED")
    if value["predecessor_hashes"] != {"reconcile": "2b2201e6cf5a5b13ef07250fe94c8d2a79375daa9aa93da58cef62432e7723f7", "snapshot": "f383e043dc27e5bcf089cea9b23a8c976df2393bb85c2a727b56f02665ac8691"}:
        raise RuntimeError("EXACT_PREDECESSOR_FUNCTION_HASHES_REQUIRED")
    if value["counts"]["outbox_412_duplicate_vehicles"] != 0:
        raise RuntimeError("PRESTATE_OUTBOX_DUPLICATE_REQUIRED_ZERO")


def assert_post(value: dict) -> None:
    if value["target"]["production_sentinel"] or value["head"] != "20260827101000" or value["ledger"] != [
        {"version": "20260827067200", "name": "672_authenticated_active_email_monitor_identity_successor"},
        {"version": "20260827101000", "name": "700_final_authoritative_pdc_lifecycle"},
    ]:
        raise RuntimeError("SUCCESSOR_POSTSTATE_LEDGER_MISMATCH")
    if value["objects"] != {"receipts": True, "delivery": True, "qc": True, "book": True, "collect": True}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_OBJECT_MISMATCH")
    if value["security"] != {"qc_399": False, "qc_700": True, "book_412": False, "book_700": True, "collect_412": False, "collect_700": True, "snapshot": True, "direct_dml": True, "history_rls": True}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_SECURITY_MISMATCH")
    if value["counts"]["outbox_412_duplicate_vehicles"] != 0:
        raise RuntimeError("SUCCESSOR_POSTSTATE_OUTBOX_DUPLICATE")


def migration_bytes() -> bytes:
    if MIGRATION.is_symlink() or not MIGRATION.is_file():
        raise RuntimeError("MIGRATION_SOURCE_MISSING")
    raw = MIGRATION.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_MIGRATION_SHA256:
        raise RuntimeError("MIGRATION_SOURCE_HASH_MISMATCH")
    if EXPECTED_REF.encode() not in raw or PRODUCTION_REF.encode() in raw:
        raise RuntimeError("MIGRATION_TARGET_GUARD_MISMATCH")
    return raw


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preflight-700", "rehearse-700", "apply-700"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args(argv)
    event = {"ok": False, "mode": args.mode, "committed": False, "production_touched": False, "mailbox_contacted": False, "outbound_email_enabled": False}
    try:
        if not args.evidence.is_absolute() or args.evidence.exists() or args.evidence.resolve().is_relative_to(ROOT):
            raise RuntimeError("EVIDENCE_PATH_INVALID")
        raw = migration_bytes()
        event["migration_sha256"] = hashlib.sha256(raw).hexdigest()
        before = state()
        assert_pre(before)
        event["before"] = before
        if args.mode == "preflight-700":
            event["ok"] = True
        elif args.mode == "rehearse-700":
            body = raw.decode("utf-8").split("BEGIN;", 1)[1].rsplit("COMMIT;", 1)[0]
            rehearsal = "BEGIN;\n" + body + "\nROLLBACK;\n"
            run_query(rehearsal)
            after = state()
            assert_pre(after)
            event.update(after=after, rollback_verified=True, ok=True)
        else:
            if os.environ.get(APPROVAL_ENV) != f"apply migration 700 source {EXPECTED_MIGRATION_SHA256}":
                raise RuntimeError("APPLY_APPROVAL_MISSING")
            run_query("", source=MIGRATION)
            event["committed"] = True
            after = state()
            assert_post(after)
            event.update(after=after, ok=True)
    except Exception as exc:
        event["error"] = str(exc)[:400]
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
