#!/usr/bin/env python3
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from inspect_pdc14_staging import management_query
sql = r"""
select jsonb_build_object(
 'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
 'vehicle',(select to_jsonb(v) from public.vehicles v where v.stock_number_normalized='13048501' and v.deleted_at is null),
 'ops',(select coalesce(jsonb_agg(to_jsonb(o) order by source_row_no,operation_no),'[]'::jsonb) from public.pdc_authenticated_email_operation_lines o join public.vehicles v on v.id=o.vehicle_id where v.stock_number_normalized='13048501' and v.deleted_at is null),
 'adjustments',(select coalesce(jsonb_agg(to_jsonb(a) order by display_order,operation_code),'[]'::jsonb) from public.vehicle_workshop_line_adjustments a join public.vehicles v on v.id=a.vehicle_id where v.stock_number_normalized='13048501' and v.deleted_at is null),
 'bookings',(select coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.stock_number_normalized='13048501' and v.deleted_at is null),
 'admin_constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',conname,'def',pg_get_constraintdef(oid))),'[]'::jsonb) from pg_constraint where conrelid in ('public.workshop_admin_block_history'::regclass,'public.workshop_admin_block_receipts'::regclass)),
 'stages',(select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.workshop_stages s where upper(s.code) like '%PIT%')
 ,'salespeople',(select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.salespeople s where upper(s.code)='069' or lower(s.name)='stephen peck')
 ,'adjustment_constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',conname,'def',pg_get_constraintdef(oid))),'[]'::jsonb) from pg_constraint where conrelid='public.vehicle_workshop_line_adjustments'::regclass)
) as inspection
"""
print(json.dumps(management_query(sql)[0]['inspection'], indent=2, default=str))
