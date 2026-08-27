#!/usr/bin/env python3
"""Guarded staging-only controller for the 708 scope alignment successor."""
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
MIGRATION = ROOT / "supabase/staging_only/20260827110100_708_navision_delivery_scope_674_alignment_successor.sql"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_708"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"

STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827107000','20260827109000','20260827109100','20260827110000','20260827110100')),
 'definitions',jsonb_build_object('delivery',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then '' else pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure) end,'wrapper',case when to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is null then '' else pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) end),
 'security',jsonb_build_object('delivery_authenticated',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('authenticated','public.reconcile_navision_delivery_700(uuid)','execute') end,'delivery_anon',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('anon','public.reconcile_navision_delivery_700(uuid)','execute') end,'delivery_service_role',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('service_role','public.reconcile_navision_delivery_700(uuid)','execute') end,'delivery_db_monitor',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('pdc_email_monitor','public.reconcile_navision_delivery_700(uuid)','execute') end,'old_delivery_authenticated',case when to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') is null then false else has_function_privilege('authenticated','public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)','execute') end,'wrapper_authenticated',has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'wrapper_anon',has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'wrapper_service_role',has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'wrapper_db_monitor',has_function_privilege('pdc_email_monitor','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'))
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


def migration_bytes() -> bytes:
    if MIGRATION.is_symlink() or not MIGRATION.is_file():
        raise RuntimeError("MIGRATION_SOURCE_MISSING")
    raw = MIGRATION.read_bytes()
    if EXPECTED_REF.encode() not in raw or PRODUCTION_REF.encode() in raw:
        raise RuntimeError("MIGRATION_TARGET_GUARD_MISMATCH")
    return raw


def assert_pre(value: dict) -> None:
    if value["target"] != {"database": "postgres", "current_user": "postgres", "session_user": "postgres", "staging_sentinel": 1, "production_sentinel": False}:
        raise RuntimeError("EXACT_STAGING_TARGET_PRESTATE_REQUIRED")
    if value["head"] != "20260827110000" or value["ledger"] != [
        {"version": "20260827107000", "name": "706_final_booked_synthetic_payload_identity_repair_after_673_collision"},
        {"version": "20260827109000", "name": "675_authenticated_monitor_enqueue_trigger_compatibility"},
        {"version": "20260827109100", "name": "707_navision_delivery_monitor_identity_security_successor"},
        {"version": "20260827110000", "name": "676_authenticated_monitor_rollback_control_repair"},
    ]:
        raise RuntimeError("EXACT_707_LEDGER_PRESTATE_REQUIRED")
    if value["definitions"]["delivery"].count("pdc_monitor_authenticated_active_scope_673") != 1 or value["definitions"]["wrapper"].count("pdc_monitor_authenticated_active_scope_673") != 1:
        raise RuntimeError("STALE_673_SCOPE_PRESTATE_REQUIRED")


def assert_post(value: dict) -> None:
    if value["target"]["production_sentinel"] or value["head"] != "20260827110100" or value["ledger"] != [
        {"version": "20260827107000", "name": "706_final_booked_synthetic_payload_identity_repair_after_673_collision"},
        {"version": "20260827109000", "name": "675_authenticated_monitor_enqueue_trigger_compatibility"},
        {"version": "20260827109100", "name": "707_navision_delivery_monitor_identity_security_successor"},
        {"version": "20260827110000", "name": "676_authenticated_monitor_rollback_control_repair"},
        {"version": "20260827110100", "name": "708_navision_delivery_scope_674_alignment_successor"},
    ]:
        raise RuntimeError("SUCCESSOR_POSTSTATE_LEDGER_MISMATCH")
    if value["definitions"]["delivery"].count("pdc_monitor_authenticated_active_scope_674") != 1 or "pdc_monitor_authenticated_active_scope_673" in value["definitions"]["delivery"] or value["definitions"]["wrapper"].count("pdc_monitor_authenticated_active_scope_674") != 1 or "pdc_monitor_authenticated_active_scope_673" in value["definitions"]["wrapper"]:
        raise RuntimeError("SUCCESSOR_POSTSTATE_SCOPE_MISMATCH")
    if value["security"] != {"delivery_authenticated": True, "delivery_anon": False, "delivery_service_role": False, "delivery_db_monitor": False, "old_delivery_authenticated": False, "wrapper_authenticated": True, "wrapper_anon": False, "wrapper_service_role": False, "wrapper_db_monitor": False}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_ACL_MISMATCH")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preflight-708", "rehearse-708", "apply-708"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args(argv)
    event = {"ok": False, "mode": args.mode, "committed": False, "production_touched": False, "vehicle_mutation": False}
    try:
        raw = migration_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        event["migration_sha256"] = digest
        before = state()
        assert_pre(before)
        event["before"] = before
        if args.mode == "preflight-708":
            event["ok"] = True
        elif args.mode == "rehearse-708":
            body = raw.decode("utf-8").split("BEGIN;", 1)[1].rsplit("COMMIT;", 1)[0]
            run_query("BEGIN;\n" + body + "\nROLLBACK;")
            after = state()
            assert_pre(after)
            event.update(after=after, rollback_verified=True, ok=True)
        else:
            if os.environ.get(APPROVAL_ENV) != f"apply migration 708 source {digest}":
                raise RuntimeError("APPLY_APPROVAL_MISSING")
            run_query("", source=MIGRATION)
            event["committed"] = True
            after = state()
            assert_post(after)
            event.update(after=after, ok=True)
    except Exception as exc:
        event["error"] = str(exc)[:500]
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
