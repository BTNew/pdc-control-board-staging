#!/usr/bin/env python3
import json, os
from pathlib import Path
from inspect_pdc14_staging import management_query
from apply_pdc14_staging import management_write
root=Path(__file__).resolve().parents[1]
if os.getenv('PDC_APPROVE_STAGING_MIGRATION_20260904010200')!='YES': raise SystemExit('approval env missing')
head=management_query("select version from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")[0]['version']
if head!='20260904010200': management_write((root/'supabase/staging_only/20260904010200_remove_pit_workshop_booking.sql').read_text(encoding='utf-8'))
q="""select jsonb_build_object(
'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version='20260904010200'),
'pit_planner_enabled',(select planner_enabled from public.workshop_stages where code='PIT_INSPECTION'),
'active_pit_bookings',(select count(*) from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id where s.code='PIT_INSPECTION' and b.deleted_at is null and lower(b.status::text) in ('queued','planned','started','stoppage')),
'op9_retained',(select count(*) from public.pdc_authenticated_email_operation_lines o join public.vehicles v on v.id=o.vehicle_id where v.stock_number_normalized='13048501' and o.operation_no='OP9' and upper(o.description) like '%PIT%')) as proof"""
proof=management_query(q)[0]['proof']; out=root/'review-evidence/t_dbd0c6bf-pit-post.json';out.write_text(json.dumps(proof,indent=2),encoding='utf-8');print(json.dumps(proof,sort_keys=True))
