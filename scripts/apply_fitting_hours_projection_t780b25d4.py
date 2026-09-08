#!/usr/bin/env python3
"""Dry-run/apply/read back the Pilbara planner-hours STAGING migration."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_t_780b25d4_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260908150000_pilbara_fitting_stage_hours_projection.sql"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
APPROVAL = "PDC_APPROVE_T780_PILBARA_HOURS_STAGING"
TARGET_STOCKS = ("12705177", "13007660", "13015144")


def readback() -> dict:
    return management_query("""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'migration_count',(select count(*) from supabase_migrations.schema_migrations where version='20260908150000'),
        'function_definition',pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure),
        'authenticated_execute',has_function_privilege('authenticated','public.workshop_vehicle_stage_estimated_hours(uuid,text)','execute'),
        'anon_execute',has_function_privilege('anon','public.workshop_vehicle_stage_estimated_hours(uuid,text)','execute'),
        'service_execute',has_function_privilege('service_role','public.workshop_vehicle_stage_estimated_hours(uuid,text)','execute'),
        'business_state',jsonb_build_object(
          'vehicles',(select coalesce(jsonb_agg(jsonb_build_array(v.stock_number,v.id,v.version,v.updated_at) order by v.stock_number),'[]'::jsonb) from public.vehicles v where v.stock_number in ('12705177','13007660','13015144') and v.lifecycle_state='active' and v.deleted_at is null),
          'pilbara_operations',(select coalesce(jsonb_agg(to_jsonb(o) order by o.stock_number,o.original_line_number,o.operation_id),'[]'::jsonb) from public.pdc_pilbara_service_operations o where o.stock_number in ('12705177','13007660','13015144')),
          'adjustments',(select coalesce(jsonb_agg(to_jsonb(a) order by a.vehicle_id,a.line_key,a.adjustment_id),'[]'::jsonb) from public.vehicle_workshop_line_adjustments a join public.vehicles v on v.id=a.vehicle_id where v.stock_number in ('12705177','13007660','13015144')),
          'bookings',(select coalesce(jsonb_agg(to_jsonb(b) order by b.vehicle_id,b.id),'[]'::jsonb) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.stock_number in ('12705177','13007660','13015144'))
        ),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
      ) evidence
    """)[0]["evidence"]


def live_projection_readback() -> dict:
    rows = management_write("""
      BEGIN READ ONLY;
      SELECT jsonb_build_object(
        '12705177',public.workshop_vehicle_stage_estimated_hours((select id from public.vehicles where stock_number='12705177' and lifecycle_state='active' and deleted_at is null),'FITTING'),
        '13007660',public.workshop_vehicle_stage_estimated_hours((select id from public.vehicles where stock_number='13007660' and lifecycle_state='active' and deleted_at is null),'FITTING'),
        '13015144',public.workshop_vehicle_stage_estimated_hours((select id from public.vehicles where stock_number='13015144' and lifecycle_state='active' and deleted_at is null),'FITTING')
      ) projected_hours;
      COMMIT;
    """)
    return rows[0]["projected_hours"]


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
    before = readback()
    if before.get("production_sentinel_present") is not False:
        raise RuntimeError("Production sentinel refusal")
    if args.dry_run:
        if not sql.rstrip().endswith("COMMIT;"):
            raise RuntimeError("migration transaction terminator drift")
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
        if (after.get("head") != ["20260908150000", "pilbara_fitting_stage_hours_projection"]
                or after.get("migration_count") != 1
                or after.get("authenticated_execute") is not False
                or after.get("anon_execute") is not False
                or after.get("service_execute") is not False
                or before.get("business_state") != after.get("business_state")):
            raise RuntimeError(f"STAGING readback failed: {after}")
        projected = live_projection_readback()
        expected = {"12705177": 2.25, "13007660": 1.5, "13015144": 2.83}
        if projected != expected:
            raise RuntimeError(f"live Fitting projection mismatch: expected {expected}, got {projected}")
        result = {"ok": True, "mode": "apply", "before": before, "after": after, "projected_fitting_hours": projected}
    result.update({"project_ref": STAGING_REF, "target_stocks": TARGET_STOCKS, "production_contacted": False, "production_writes": False})
    out = ROOT / "review-evidence" / "t_780b25d4" / f"fitting-hours-migration-{result['mode']}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": result["ok"], "mode": result["mode"], "project_ref": STAGING_REF,
        "head": result["after"]["head"], "business_state_unchanged": before["business_state"] == result["after"]["business_state"],
        "projected_fitting_hours": result.get("projected_fitting_hours"),
        "production_contacted": False, "production_writes": False, "output": str(out),
    }, indent=2, default=str))


if __name__ == "__main__":
    main()
