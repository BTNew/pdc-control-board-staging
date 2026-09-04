#!/usr/bin/env python3
"""Compile, apply, and read back the linked Navision projection successor on STAGING."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260905010000_navision_linked_location_projection.sql"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260905010000"
EXPECTED_PREDECESSOR = ["20260904011500", "parts_stoppage_runtime_containment_repair"]
EXPECTED_HEAD = ["20260905010000", "navision_linked_location_projection"]


def inspect() -> dict[str, object]:
    return management_query("""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'projection_exists',to_regprocedure('public.pdc_project_linked_navision_location_20260905(uuid,uuid,text)') is not null,
        'predecessor_exists',to_regprocedure('public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(uuid,uuid,text)') is not null,
        'refresh_wraps_projection',case when to_regprocedure('public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)') is null then false else position('pdc_project_linked_navision_location_20260905' in pg_get_functiondef('public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)'::regprocedure))>0 end,
        'public_wrapper_734',case when to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is null then false else position('reconcile_navision_operational_record_pre_734' in pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure))>0 and position('reconcile_navision_delivery_734' in pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure))>0 end,
        'refresh_private',case when to_regprocedure('public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)') is null then false else not has_function_privilege('public','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute') and not has_function_privilege('anon','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute') and not has_function_privilege('authenticated','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute') and not has_function_privilege('service_role','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute') end,
        'public_acl_preserved',has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute') and has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute') and not has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),
        'cleanup_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid=to_regclass('public.pdc_navision_projection_cleanup_history_20260905')),
        'cleanup_private',case when to_regclass('public.pdc_navision_projection_cleanup_history_20260905') is null then false else not has_table_privilege('authenticated','public.pdc_navision_projection_cleanup_history_20260905','select,insert,update,delete') and not has_table_privilege('service_role','public.pdc_navision_projection_cleanup_history_20260905','select,insert,update,delete') end
      ) inspection
    """)[0]["inspection"]


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("mode",choices=("inspect","dry-run","apply"))
    args=parser.parse_args()
    if STAGING_REF!="cdsmnqxtyyoeoznmbidd" or STAGING_REF==PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    sql=MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("migration containment marker failed")
    before=inspect()
    result={"ok":True,"project_ref":STAGING_REF,"mode":args.mode,"before":before,
            "production_contacted":False,"email_sent":False}
    if before["staging_sentinel_count"]!=1 or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")
    if args.mode=="dry-run":
        if before["head"]!=EXPECTED_PREDECESSOR:
            raise RuntimeError(f"dry-run requires exact predecessor, got {before['head']}")
        management_write(sql.rsplit("COMMIT;",1)[0]+"ROLLBACK;\n")
        result["compiled_and_rolled_back"]=True
    elif args.mode=="apply":
        if os.environ.get(APPROVAL)!="YES":
            raise RuntimeError(f"set {APPROVAL}=YES for this authorized STAGING-only apply")
        if before["head"]==EXPECTED_PREDECESSOR:
            management_write(sql); result["applied"]=True
        elif before["head"]==EXPECTED_HEAD:
            result["applied"]=False; result["idempotent_existing"]=True
        else:
            raise RuntimeError(f"unexpected live head {before['head']}")
    after=inspect(); result["after"]=after
    if args.mode=="dry-run" and after!=before:
        raise RuntimeError("dry-run changed live state")
    if args.mode=="apply":
        checks=[after["head"]==EXPECTED_HEAD,after["projection_exists"],after["predecessor_exists"],
                after["refresh_wraps_projection"],after["public_wrapper_734"],after["refresh_private"],
                after["public_acl_preserved"],after["cleanup_rls"]==[True,True],after["cleanup_private"]]
        if not all(checks): raise RuntimeError(f"postcondition failed: {after}")
        result["security_advisors"]=security_advisor_summary()
    print(json.dumps(result,indent=2,default=str)); return 0


if __name__=="__main__": raise SystemExit(main())
