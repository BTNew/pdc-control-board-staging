#!/usr/bin/env python3
"""Read-only diagnostics for the deployed non-Navision Job Card functions."""
from __future__ import annotations

import json

from inspect_pdc14_staging import management_query

SQL = r"""
with defs as (
 select pg_get_functiondef('public.read_pdc_non_navision_jobcard_receipt(uuid)'::regprocedure) rd,
        pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure) fn
)
select jsonb_build_object(
 'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
 'read_initial_location_context',substr(rd,greatest(strpos(rd,'initial_location')-120,1),480),
 'inner_hours_context',substr(fn,greatest(strpos(fn,'safe_nonnegative_numeric')-120,1),480),
 'inner_creation_context',substr(fn,greatest(strpos(fn,E'values(''EMAIL-''')-180,1),900),
 'inner_work_context',substr(fn,greatest(strpos(fn,'insert into public.vehicle_work_items')-120,1),720)
) proof from defs
"""

print(json.dumps(management_query(SQL)[0]["proof"], indent=2))
