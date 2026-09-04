#!/usr/bin/env python3
"""Read back the exact Workshop recovery authority on STAGING only."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF

TASK = "t_cae774e3"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review-evidence" / TASK / "workshop-recovery-live-diagnosis.json"


def inspect() -> dict[str, object]:
    return management_write("""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'recovery_definition',pg_get_functiondef('public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure),
        'recovery_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure),'UTF8'),'sha256'),'hex'),
        'recovery_owner',(select pg_get_userbyid(proowner) from pg_proc where oid='public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure),
        'recovery_security_definer',(select prosecdef from pg_proc where oid='public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure),
        'recovery_config',(select to_jsonb(proconfig) from pg_proc where oid='public.recover_overdue_planned_workshop_bookings(text,timestamptz)'::regprocedure),
        'recovery_acl',jsonb_build_object(
          'public',has_function_privilege('public','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute'),
          'anon',has_function_privilege('anon','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute'),
          'authenticated',has_function_privilege('authenticated','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute'),
          'service_role',has_function_privilege('service_role','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute')),
        'snapshot_definition',pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure),
        'snapshot_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure),'UTF8'),'sha256'),'hex'),
        'snapshot_owner',(select pg_get_userbyid(proowner) from pg_proc where oid='public.get_station_workshop_snapshot(text,date,date)'::regprocedure),
        'snapshot_security_definer',(select prosecdef from pg_proc where oid='public.get_station_workshop_snapshot(text,date,date)'::regprocedure),
        'snapshot_config',(select to_jsonb(proconfig) from pg_proc where oid='public.get_station_workshop_snapshot(text,date,date)'::regprocedure),
        'snapshot_acl',jsonb_build_object(
          'public',has_function_privilege('public','public.get_station_workshop_snapshot(text,date,date)','execute'),
          'anon',has_function_privilege('anon','public.get_station_workshop_snapshot(text,date,date)','execute'),
          'authenticated',has_function_privilege('authenticated','public.get_station_workshop_snapshot(text,date,date)','execute'),
          'service_role',has_function_privilege('service_role','public.get_station_workshop_snapshot(text,date,date)','execute')),
        'station_snapshot_chain',(select jsonb_object_agg(p.proname,pg_get_functiondef(p.oid) order by p.proname)
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.proname like 'get_station_workshop_snapshot%'),
        'role_helper_definition',pg_get_functiondef('public.workshop_require_planner_operator()'::regprocedure),
        'role_helper_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_require_planner_operator()'::regprocedure),'UTF8'),'sha256'),'hex'),
        'role_predicate_definition',pg_get_functiondef('public.workshop_is_planner_operator()'::regprocedure),
        'role_columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
          from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
          where a.attrelid='public.pdc_user_roles'::regclass and a.attnum>0 and not a.attisdropped),
        'role_values',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid='public.pdc_role'::regtype),
        'account_status_values',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid='public.pdc_account_status'::regtype),
        'role_constraints',(select jsonb_object_agg(c.conname,pg_get_constraintdef(c.oid)) from pg_constraint c where c.conrelid='public.pdc_user_roles'::regclass),
        'receipt_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.workshop_schedule_recovery_receipts'::regclass),
        'receipt_acl',jsonb_build_object(
          'public',has_table_privilege('public','public.workshop_schedule_recovery_receipts','select,insert,update,delete'),
          'anon',has_table_privilege('anon','public.workshop_schedule_recovery_receipts','select,insert,update,delete'),
          'authenticated',has_table_privilege('authenticated','public.workshop_schedule_recovery_receipts','select,insert,update,delete'),
          'service_role',has_table_privilege('service_role','public.workshop_schedule_recovery_receipts','select,insert,update,delete')),
        'monitor_staging_guard',public.pdc_monitor_staging_guard()
      ) as result
    """)[0]["result"]


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    result = inspect()
    if result["staging_sentinel_count"] != 1 or result["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")
    evidence = {
        "task": TASK,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "project_ref": STAGING_REF,
        "production_contacted": False,
        "email_sent": False,
        "credentials_redacted": True,
        "live": result,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
    print(json.dumps({
        "evidence": str(OUT),
        "head": result["head"],
        "recovery_acl": result["recovery_acl"],
        "snapshot_acl": result["snapshot_acl"],
        "recovery_owner": result["recovery_owner"],
        "snapshot_owner": result["snapshot_owner"],
        "recovery_security_definer": result["recovery_security_definer"],
        "snapshot_security_definer": result["snapshot_security_definer"],
        "role_helper_sha256": result["role_helper_sha256"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
