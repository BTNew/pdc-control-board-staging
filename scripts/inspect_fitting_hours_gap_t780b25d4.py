#!/usr/bin/env python3
"""Read-only STAGING diagnosis for Fitting planner hours."""
from __future__ import annotations

import json
from pathlib import Path

from inspect_pdc14_staging import management_query

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review-evidence" / "t_780b25d4" / "fitting-hours-gap-live.json"
STOCKS = ("12705177", "13007660", "13015144")

QUERY = r"""
with target_vehicles as (
  select v.*,
    (select n.dealer_code from public.navision_backend_records n
      where n.canonical_vehicle_id=v.id and n.is_current and n.record_status='current'
      order by n.id desc limit 1) dealer_code
  from public.vehicles v
  where v.stock_number in ('12705177','13007660','13015144')
    and v.lifecycle_state='active' and v.deleted_at is null
)
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'function_definition',pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'stock_number',v.stock_number,'dealer_code',v.dealer_code,'version',v.version,
    'current_location',v.current_location,'eta_to_kewdale',v.eta_to_kewdale,
    'work_items',(select coalesce(jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed) order by wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=v.id),
    'email_operations',(select coalesce(jsonb_agg(jsonb_build_object('operation_line_id',ol.operation_line_id,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,'estimated_hours',ol.estimated_hours) order by ol.source_row_no,ol.operation_line_id),'[]'::jsonb) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=v.id),
    'pilbara_operations',(select coalesce(jsonb_agg(jsonb_build_object(
      'operation_id',o.operation_id,'repair_order_number',o.repair_order_number,'original_line_number',o.original_line_number,
      'description',o.operation_description,'source_estimated_hours',o.source_estimated_hours,
      'effective_estimated_hours',o.effective_estimated_hours,'hours_provenance',o.hours_provenance,
      'category',coalesce(h.category,'REVIEW')) order by o.original_line_number,o.operation_id),'[]'::jsonb)
      from public.pdc_pilbara_service_operations o
      left join public.pdc_pilbara_service_classification_current cc using(operation_id)
      left join public.pdc_pilbara_service_classification_history h using(classification_id)
      where o.vehicle_id=v.id),
    'adjustments',(select coalesce(jsonb_agg(jsonb_build_object('adjustment_id',a.adjustment_id,'line_key',a.line_key,'source_kind',a.source_kind,'stage_code',a.stage_code,'estimated_hours',a.estimated_hours,'correction_origin',a.correction_origin,'active',a.active,'version',a.version) order by a.created_at,a.adjustment_id),'[]'::jsonb) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=v.id)
  ) order by v.stock_number),'[]'::jsonb) from target_vehicles v),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
) evidence
"""


def main() -> None:
    rows = management_query(QUERY)
    evidence = rows[0]["evidence"]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
    summary = {
        "head": evidence.get("head"),
        "vehicles": [
            {
                "stock_number": row.get("stock_number"),
                "location": row.get("current_location"),
                "email_operations": len(row.get("email_operations", [])),
                "pilbara_operations": len(row.get("pilbara_operations", [])),
                "adjustments": len(row.get("adjustments", [])),
            }
            for row in evidence.get("vehicles", [])
        ],
        "production_contacted": False,
        "production_sentinel_present": evidence.get("production_sentinel_present"),
        "output": str(OUT),
    }
    print(json.dumps(summary, indent=2, default=str))


if __name__ == "__main__":
    main()
