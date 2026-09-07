from __future__ import annotations

import json

from inspect_pdc14_staging import STAGING_REF, management_query


def main() -> None:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("refusing non-STAGING target")
    rows = management_query("""
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'activation_function',pg_get_functiondef('public.activate_navision_backend_record(text,uuid,bigint,text)'::regprocedure),
  'columns',(select jsonb_object_agg(table_name,columns) from (
    select table_name,jsonb_agg(jsonb_build_array(column_name,data_type,is_nullable,column_default) order by ordinal_position) columns
    from information_schema.columns
    where table_schema='public' and table_name in ('pdc_authenticated_email_operation_lines','vehicle_workshop_line_adjustments','vehicles','navision_backend_records')
    group by table_name
  ) c),
  'constraints',(select jsonb_agg(jsonb_build_array(c.conrelid::regclass::text,c.conname,pg_get_constraintdef(c.oid)) order by c.conrelid::regclass::text,c.conname)
    from pg_constraint c where c.conrelid in ('public.pdc_authenticated_email_operation_lines'::regclass,'public.vehicle_workshop_line_adjustments'::regclass))
) proof
""")
    print(json.dumps({"project_ref": STAGING_REF, "production_contacted": False, "proof": rows[0]["proof"]}, indent=2))


if __name__ == "__main__":
    main()
