#!/usr/bin/env python3
"""Read-only STAGING evidence for Job Card hours repair."""
from __future__ import annotations

import json
from pathlib import Path

from inspect_pdc14_staging import management_query

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review-evidence" / "t_780b25d4" / "live-diagnostic.json"

QUERY = r"""
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'vehicle',(select jsonb_build_object('id',id,'stock_number',stock_number,'job_card_number',job_card_number,'version',version,'source_system',source_system,'source_record_id',source_record_id) from public.vehicles where stock_number='12705177' and lifecycle_state='active' and deleted_at is null),
  'source_state',(select jsonb_build_object(
    'requirements',(select coalesce(jsonb_agg(to_jsonb(wi) order by wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=v.id),
    'bookings',(select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at,b.id),'[]'::jsonb) from public.workshop_bookings b where b.vehicle_id=v.id),
    'operation_lines',(select coalesce(jsonb_agg(to_jsonb(ol) order by ol.source_row_no,ol.operation_line_id),'[]'::jsonb) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=v.id),
    'line_adjustments',(select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at,a.adjustment_id),'[]'::jsonb) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=v.id),
    'hours_receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc),'[]'::jsonb) from public.vehicle_workshop_hours_batch_receipts_768 r where r.vehicle_id=v.id)
  ) from public.vehicles v where v.stock_number='12705177' and v.lifecycle_state='active' and v.deleted_at is null),
  'related',jsonb_build_object(
    'all_stock_vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'version',version,'stock_number',stock_number,'job_card_number',job_card_number,'lifecycle_state',lifecycle_state,'deleted_at',deleted_at) order by created_at,id),'[]'::jsonb) from public.vehicles where stock_number='12705177'),
    'navision_scope_records',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'dealer_code',dealer_code,'is_current',is_current,'record_status',record_status,'canonical_vehicle_id',canonical_vehicle_id) order by id),'[]'::jsonb) from public.navision_backend_records where canonical_vehicle_id='a1b2ea79-1933-5453-81e3-b0b1945c94bf'::uuid),
    'job_card_operation_lines',(select coalesce(jsonb_agg(to_jsonb(ol) order by ol.source_row_no,ol.operation_line_id),'[]'::jsonb) from public.pdc_authenticated_email_operation_lines ol where ol.job_card_number='JC14123887'),
    'pilbara_tables',(select coalesce(jsonb_agg(table_name order by table_name),'[]'::jsonb) from information_schema.tables where table_schema='public' and table_name like '%pilbara%'),
    'pilbara_operation_columns',(select coalesce(jsonb_agg(jsonb_build_object('column_name',column_name,'data_type',data_type) order by ordinal_position),'[]'::jsonb) from information_schema.columns where table_schema='public' and table_name='pdc_pilbara_service_operations'),
    'pilbara_operations',(select coalesce(jsonb_agg(to_jsonb(o) order by to_jsonb(o)->>'operation_index'),'[]'::jsonb) from public.pdc_pilbara_service_operations o where to_jsonb(o)->>'vehicle_id'='a1b2ea79-1933-5453-81e3-b0b1945c94bf'),
    'pilbara_classification_current',(select coalesce(jsonb_agg(to_jsonb(c) order by to_jsonb(c)->>'operation_id'),'[]'::jsonb) from public.pdc_pilbara_service_classification_current c where to_jsonb(c)->>'vehicle_id'='a1b2ea79-1933-5453-81e3-b0b1945c94bf'),
    'pilbara_work_controls',(select coalesce(jsonb_agg(to_jsonb(c) order by to_jsonb(c)->>'operation_id'),'[]'::jsonb) from public.pdc_pilbara_service_classification_work_controls c where to_jsonb(c)->>'vehicle_id'='a1b2ea79-1933-5453-81e3-b0b1945c94bf')
  ),
  'functions',jsonb_build_object(
    'base',pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure),
    'scoped',pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure),
    'actor_scope',pg_get_functiondef('public.pdc_auditor_actor_scope()'::regprocedure),
    'snapshot',pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure),
    'vehicle_dealer',pg_get_functiondef('public.pdc_auditor_vehicle_dealer(uuid)'::regprocedure),
    'batch',pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure)
  ),
  'grants',jsonb_build_object(
    'scoped_authenticated',has_function_privilege('authenticated','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute'),
    'base_authenticated',has_function_privilege('authenticated','public.get_vehicle_workshop_detail(uuid)','execute'),
    'batch_authenticated',has_function_privilege('authenticated','public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','execute')
  ),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
) evidence
"""


def main() -> None:
    rows = management_query(QUERY)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rows, indent=2, default=str) + "\n", encoding="utf-8")
    evidence = rows[0]["evidence"]
    for name, definition in evidence.get("functions", {}).items():
        (OUT.parent / f"live-{name}-function.sql").write_text(str(definition).rstrip() + "\n", encoding="utf-8")
    detail = evidence.get("source_state") or {}
    summary = {
        "head": evidence.get("head"),
        "vehicle": evidence.get("vehicle"),
        "grants": evidence.get("grants"),
        "production_sentinel_present": evidence.get("production_sentinel_present"),
        "source_state_keys": sorted(detail),
        "related": evidence.get("related"),
        "requirements": len(detail.get("requirements", [])),
        "bookings": len(detail.get("bookings", [])),
        "operation_lines": len(detail.get("operation_lines", [])),
        "line_adjustments": len(detail.get("line_adjustments", [])),
        "output": str(OUT),
    }
    print(json.dumps(summary, indent=2, default=str))


if __name__ == "__main__":
    main()
