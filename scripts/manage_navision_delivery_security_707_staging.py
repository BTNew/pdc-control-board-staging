#!/usr/bin/env python3
"""Guarded staging-only controller for the 707 Navision delivery security successor."""
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
MIGRATION = ROOT / "supabase/staging_only/20260827109100_707_navision_delivery_monitor_identity_security_successor.sql"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_707"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"

STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827107000','20260827109000','20260827109100')),
 'objects',jsonb_build_object('old_delivery',to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') is not null,'new_delivery',to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is not null,'old_delivery_private',to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') is not null,'wrapper',to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is not null,'old_wrapper_private',to_regprocedure('public.reconcile_navision_operational_record_pre707(uuid,uuid,text)') is not null),
 'security',jsonb_build_object('delivery_authenticated',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('authenticated','public.reconcile_navision_delivery_700(uuid)','execute') end,'delivery_anon',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('anon','public.reconcile_navision_delivery_700(uuid)','execute') end,'delivery_service_role',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('service_role','public.reconcile_navision_delivery_700(uuid)','execute') end,'delivery_db_monitor',case when to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is null then false else has_function_privilege('pdc_email_monitor','public.reconcile_navision_delivery_700(uuid)','execute') end,'wrapper_authenticated',has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'wrapper_anon',has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'wrapper_service_role',has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'wrapper_db_monitor',has_function_privilege('pdc_email_monitor','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),'old_delivery_authenticated',case when to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') is null then false else has_function_privilege('authenticated','public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)','execute') end,'old_wrapper_authenticated',case when to_regprocedure('public.reconcile_navision_operational_record_pre707(uuid,uuid,text)') is null then false else has_function_privilege('authenticated','public.reconcile_navision_operational_record_pre707(uuid,uuid,text)','execute') end),
 'production_ref_present',position('vjdtsswhroyguxyfjdkt' in coalesce((select string_agg(view_definition,' ') from information_schema.views where table_schema='public'),'') )>0
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
        result = subprocess.run(
            [SUPABASE_CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", EXPECTED_REF, "--output-format", "json", "--file", str(source)],
            cwd=ROOT, capture_output=True, text=True, timeout=300, check=False,
        )
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
    if value["head"] != "20260827109000" or value["ledger"] != [
        {"version": "20260827107000", "name": "706_final_booked_synthetic_payload_identity_repair_after_673_collision"},
        {"version": "20260827109000", "name": "675_authenticated_monitor_enqueue_trigger_compatibility"},
    ]:
        raise RuntimeError("EXACT_LIVE_675_LEDGER_PRESTATE_REQUIRED")
    if value["objects"] != {"old_delivery": True, "new_delivery": False, "old_delivery_private": False, "wrapper": True, "old_wrapper_private": False}:
        raise RuntimeError("EXACT_706_OBJECT_PRESTATE_REQUIRED")


def assert_post(value: dict) -> None:
    if value["target"]["production_sentinel"] or value["head"] != "20260827109100" or value["ledger"] != [
        {"version": "20260827107000", "name": "706_final_booked_synthetic_payload_identity_repair_after_673_collision"},
        {"version": "20260827109000", "name": "675_authenticated_monitor_enqueue_trigger_compatibility"},
        {"version": "20260827109100", "name": "707_navision_delivery_monitor_identity_security_successor"},
    ]:
        raise RuntimeError("SUCCESSOR_POSTSTATE_LEDGER_MISMATCH")
    if value["objects"] != {"old_delivery": False, "new_delivery": True, "old_delivery_private": True, "wrapper": True, "old_wrapper_private": True}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_OBJECT_MISMATCH")
    if value["security"] != {"delivery_authenticated": True, "delivery_anon": False, "delivery_service_role": False, "delivery_db_monitor": False, "wrapper_authenticated": True, "wrapper_anon": False, "wrapper_service_role": False, "wrapper_db_monitor": False, "old_delivery_authenticated": False, "old_wrapper_authenticated": False}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_ACL_MISMATCH")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preflight-707", "rehearse-707", "apply-707"))
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
        if args.mode == "preflight-707":
            event["ok"] = True
        elif args.mode == "rehearse-707":
            body = raw.decode("utf-8").split("BEGIN;", 1)[1].rsplit("COMMIT;", 1)[0]
            run_query("BEGIN;\n" + body + "\nROLLBACK;")
            after = state()
            assert_pre(after)
            event.update(after=after, rollback_verified=True, ok=True)
        else:
            expected = f"apply migration 707 source {digest}"
            if os.environ.get(APPROVAL_ENV) != expected:
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
