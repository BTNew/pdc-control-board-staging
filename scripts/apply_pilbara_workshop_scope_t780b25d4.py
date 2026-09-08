#!/usr/bin/env python3
"""Dry-run/apply/read back narrow Pilbara Workshop scope on STAGING."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_t_780b25d4_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260908151000_pilbara_workshop_cross_source_scope.sql"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
APPROVAL = "PDC_APPROVE_T780_PILBARA_SCOPE_STAGING"


def readback() -> dict:
    return management_query("""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'migration_count',(select count(*) from supabase_migrations.schema_migrations where version='20260908151000'),
        'detail_definition',pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure),
        'batch_definition',pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure),
        'helper_present',to_regprocedure('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)') is not null,
        'helper_authenticated_execute',case when to_regprocedure('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)') is null then false else has_function_privilege('authenticated','public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)','execute') end,
        'scope_rows',(select coalesce(jsonb_agg(jsonb_build_array(dealer_code,environment,active,auth_user_id) order by dealer_code,environment,auth_user_id),'[]'::jsonb) from public.pdc_auditor_user_dealer_scopes),
        'business_state',jsonb_build_object(
          'vehicles',(select coalesce(jsonb_agg(jsonb_build_array(v.stock_number,v.id,v.version,v.updated_at) order by v.stock_number),'[]'::jsonb) from public.vehicles v where v.stock_number in ('12705177','13007660','13015144') and v.lifecycle_state='active' and v.deleted_at is null),
          'pilbara_operations',(select coalesce(jsonb_agg(to_jsonb(o) order by o.stock_number,o.original_line_number,o.operation_id),'[]'::jsonb) from public.pdc_pilbara_service_operations o where o.stock_number in ('12705177','13007660','13015144')),
          'adjustments',(select coalesce(jsonb_agg(to_jsonb(a) order by a.vehicle_id,a.line_key,a.adjustment_id),'[]'::jsonb) from public.vehicle_workshop_line_adjustments a join public.vehicles v on v.id=a.vehicle_id where v.stock_number in ('12705177','13007660','13015144')),
          'bookings',(select coalesce(jsonb_agg(to_jsonb(b) order by b.vehicle_id,b.id),'[]'::jsonb) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.stock_number in ('12705177','13007660','13015144'))
        ),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
      ) evidence
    """)[0]["evidence"]


def predicate_readback() -> dict:
    rows = management_write("""
      BEGIN READ ONLY;
      SELECT jsonb_build_object(
        'pdc_14450_to_exact_pilbara_37047',public.pdc_workshop_actor_vehicle_allowed('{"environment":"staging","role":"operator","dealer_code":"14450"}'::jsonb,(select id from public.vehicles where stock_number='12705177' and lifecycle_state='active' and deleted_at is null),'37047'),
        'wrong_requested_dealer_rejected',not public.pdc_workshop_actor_vehicle_allowed('{"environment":"staging","role":"operator","dealer_code":"14450"}'::jsonb,(select id from public.vehicles where stock_number='12705177' and lifecycle_state='active' and deleted_at is null),'14450'),
        'wrong_actor_dealer_rejected',not public.pdc_workshop_actor_vehicle_allowed('{"environment":"staging","role":"operator","dealer_code":"99999"}'::jsonb,(select id from public.vehicles where stock_number='12705177' and lifecycle_state='active' and deleted_at is null),'37047'),
        'production_environment_rejected',not public.pdc_workshop_actor_vehicle_allowed('{"environment":"production","role":"operator","dealer_code":"14450"}'::jsonb,(select id from public.vehicles where stock_number='12705177' and lifecycle_state='active' and deleted_at is null),'37047')
      ) predicate;
      COMMIT;
    """)
    return rows[0]["predicate"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.dry_run == args.apply:
        raise RuntimeError("choose exactly one of --dry-run or --apply")
    sql = MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("non-STAGING migration refused")
    if not sql.rstrip().endswith("COMMIT;"):
        raise RuntimeError("migration transaction terminator drift")
    before = readback()
    if before.get("production_sentinel_present") is not False:
        raise RuntimeError("Production sentinel refusal")
    if args.dry_run:
        management_write(sql.rstrip()[:-len("COMMIT;")] + "ROLLBACK;\n")
        after = readback()
        if before != after:
            raise RuntimeError("dry-run changed persistent STAGING state")
        result = {"ok": True, "mode": "dry-run", "before": before, "after": after}
    else:
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for STAGING apply")
        management_write(sql)
        after = readback()
        if (after.get("head") != ["20260908151000", "pilbara_workshop_cross_source_scope"]
                or after.get("migration_count") != 1
                or after.get("helper_present") is not True
                or after.get("helper_authenticated_execute") is not False
                or before.get("scope_rows") != after.get("scope_rows")
                or before.get("business_state") != after.get("business_state")
                or "pdc_workshop_actor_vehicle_allowed" not in after.get("detail_definition", "")
                or "pdc_workshop_actor_vehicle_allowed" not in after.get("batch_definition", "")):
            raise RuntimeError(f"STAGING readback failed: {after}")
        predicate = predicate_readback()
        if not all(predicate.values()):
            raise RuntimeError(f"scope predicate truth table failed: {predicate}")
        result = {"ok": True, "mode": "apply", "before": before, "after": after, "predicate": predicate}
    result.update({"project_ref": STAGING_REF, "production_contacted": False, "production_writes": False})
    out = ROOT / "review-evidence" / "t_780b25d4" / f"pilbara-scope-migration-{result['mode']}.json"
    out.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": result["ok"], "mode": result["mode"], "project_ref": STAGING_REF,
        "head": result["after"]["head"], "scope_rows_unchanged": before["scope_rows"] == result["after"]["scope_rows"],
        "business_state_unchanged": before["business_state"] == result["after"]["business_state"],
        "predicate": result.get("predicate"), "production_contacted": False, "production_writes": False,
        "output": str(out),
    }, indent=2, default=str))


if __name__ == "__main__":
    main()
