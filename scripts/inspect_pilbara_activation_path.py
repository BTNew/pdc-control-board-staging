from __future__ import annotations

import json

from inspect_pdc14_staging import STAGING_REF, management_query

if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
    raise RuntimeError("refusing non-STAGING target")

rows = management_query("""
select jsonb_build_object(
  'activation_triggers',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'name',t.tgname,
      'definition',pg_get_triggerdef(t.oid),
      'function',pg_get_functiondef(t.tgfoid)
    ) order by t.tgname),'[]'::jsonb)
    from pg_trigger t
    where t.tgrelid='public.navision_board_activations'::regclass and not t.tgisinternal
  ),
  'refresh_function',pg_get_functiondef('public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)'::regprocedure),
  'reconcile_function',pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),
  'delivery_functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid)))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
      and (p.proname ilike '%delivery%' or pg_get_functiondef(p.oid) ilike '%reconcile_navision_delivery_734%')),
  'snapshot_function',pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure),
  'revision',(select revision from public.navision_backend_revision where singleton),
  'counts',jsonb_build_object(
    'current_navision',(select count(*) from public.navision_backend_records where source_system='microsoft_navision' and is_current and record_status='current'),
    'activations',(select count(*) from public.navision_board_activations where active),
    'linked_current',(select count(*) from public.navision_backend_records where source_system='microsoft_navision' and is_current and record_status='current' and canonical_vehicle_id is not null)
  )
) proof
""")
print(json.dumps({"project_ref": STAGING_REF, "production_contacted": False, "proof": rows[0]["proof"]}, indent=2))
