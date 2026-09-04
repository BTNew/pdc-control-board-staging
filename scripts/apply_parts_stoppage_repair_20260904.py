#!/usr/bin/env python3
"""Dry-run, apply, and read back the STAGING Parts STOPPAGE repair."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF

TASK = "t_fd63d897"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ["20260904011400", "pdc14_location_replay_partial_cleanup_identifier_repair"]
TARGET = ["20260904011500", "parts_stoppage_runtime_containment_repair"]
EXPECTED_PRE_SHA256 = "d2a2e96c38633fec639a3cd6b2ef0adb18d96ff3640a2f08ef19feb7c19ea82f"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260904011500"
ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260904011500_parts_stoppage_runtime_containment_repair.sql"
OUT_DIR = ROOT / "review-evidence" / TASK


def inspect() -> dict[str, object]:
    return management_write("""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'function_definition',pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'function_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
        'function_owner',(select pg_get_userbyid(proowner) from pg_proc where oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'security_definer',(select prosecdef from pg_proc where oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'function_config',(select to_jsonb(proconfig) from pg_proc where oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'acl',jsonb_build_object(
          'public',has_function_privilege('public','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute'),
          'anon',has_function_privilege('anon','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute'),
          'authenticated',has_function_privilege('authenticated','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute'),
          'service_role',has_function_privilege('service_role','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute')),
        'receipt_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.pdc_parts_stoppage_receipts_376'::regclass),
        'receipt_acl',jsonb_build_object(
          'public',has_table_privilege('public','public.pdc_parts_stoppage_receipts_376','select,insert,update,delete'),
          'anon',has_table_privilege('anon','public.pdc_parts_stoppage_receipts_376','select,insert,update,delete'),
          'authenticated',has_table_privilege('authenticated','public.pdc_parts_stoppage_receipts_376','select,insert,update,delete'),
          'service_role',has_table_privilege('service_role','public.pdc_parts_stoppage_receipts_376','select,insert,update,delete')),
        'monitor_staging_guard',public.pdc_monitor_staging_guard(),
        'active_mailbox_count',(select count(*) from public.monitored_mailboxes where active),
        'active_writer_count',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
        'notification_count',(select count(*) from public.vehicle_notifications),
        'receipt_count',(select count(*) from public.pdc_parts_stoppage_receipts_376),
        'audit_count',(select count(*) from public.audit_events)
      ) as result
    """)[0]["result"]


def dry_run_sql(source: str) -> str:
    trailer = "NOTIFY pgrst,'reload schema';\nCOMMIT;"
    if (not source.startswith("-- STAGING ONLY:") or source.count("\nBEGIN;") != 1
            or source.count(trailer) != 1 or not source.rstrip().endswith(trailer)):
        raise RuntimeError("unexpected migration transaction envelope")
    body = source.replace("\nBEGIN;", "", 1)
    body = body.rsplit(trailer, 1)[0]
    return "BEGIN;\n" + body + "\nROLLBACK;"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inspect", "dry-run", "apply"))
    args = parser.parse_args()
    source = MIGRATION.read_text(encoding="utf-8")
    migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    if STAGING_REF not in source or PRODUCTION_REF in source:
        raise RuntimeError("migration target guard markers invalid")
    before = inspect()
    if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")
    result: dict[str, object] = {
        "task": TASK,
        "mode": args.mode,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "project_ref": STAGING_REF,
        "migration": MIGRATION.name,
        "migration_sha256": migration_sha256,
        "before": before,
        "production_contacted": False,
        "production_mutated": False,
        "email_sent": False,
        "credentials_redacted": True,
    }
    if args.mode == "inspect":
        pass
    elif args.mode == "dry-run":
        if before["head"] != PREDECESSOR or before["function_sha256"] != EXPECTED_PRE_SHA256:
            raise RuntimeError(f"dry-run predecessor mismatch: {before['head']} {before['function_sha256']}")
        management_write(dry_run_sql(source))
        result["dry_run_compiled_and_rolled_back"] = True
        result["after"] = inspect()
        if result["after"]["head"] != PREDECESSOR or result["after"]["function_sha256"] != EXPECTED_PRE_SHA256:
            raise RuntimeError("dry-run changed live state")
    else:
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for authorized STAGING-only apply")
        if before["head"] == PREDECESSOR:
            management_write(source)
            result["applied"] = True
        elif before["head"] == TARGET:
            result["applied"] = False
            result["idempotent_existing"] = True
        else:
            raise RuntimeError(f"unexpected live migration head: {before['head']}")
        after = inspect()
        result["after"] = after
        expected_acl = {"public": False, "anon": False, "authenticated": True, "service_role": False}
        if (after["head"] != TARGET or after["function_owner"] != "postgres" or not after["security_definer"]
                or after["function_config"] != ["search_path=pg_catalog, public, extensions", "statement_timeout=90s"]
                or after["acl"] != expected_acl
                or after["receipt_acl"] != {"public": False, "anon": False, "authenticated": False, "service_role": False}
                or after["receipt_rls"] != [True, False]
                or not after["monitor_staging_guard"]
                or "monitored_mailboxes WHERE active" in after["function_definition"]
                or "pdc_monitor_stage_activation_writers WHERE active" in after["function_definition"]
                or "v_notifications_after<>v_notifications_before" not in after["function_definition"]
                or after["receipt_count"] != before["receipt_count"]
                or after["audit_count"] != before["audit_count"]):
            raise RuntimeError(f"STAGING postcondition failed: {after}")
        result["security_advisors"] = security_advisor_summary()
    result["finished_at"] = datetime.now(timezone.utc).isoformat()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"parts-stoppage-{args.mode}.json"
    out.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "mode": args.mode, "evidence": str(out), "head": (result.get("after") or before)["head"], "migration_sha256": migration_sha256}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
