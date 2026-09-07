from __future__ import annotations
import json
from inspect_pdc14_staging import STAGING_REF, management_query
if STAGING_REF != 'cdsmnqxtyyoeoznmbidd': raise RuntimeError('refusing non-STAGING target')
rows=management_query("""select jsonb_build_object(
'columns',(select jsonb_agg(jsonb_build_array(column_name,data_type,is_nullable,column_default) order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='pdc_authenticated_email_import_receipts'),
'constraints',(select jsonb_agg(jsonb_build_array(conname,pg_get_constraintdef(oid)) order by conname) from pg_constraint where conrelid='public.pdc_authenticated_email_import_receipts'::regclass),
'operation_triggers',(select jsonb_agg(jsonb_build_array(tgname,pg_get_triggerdef(oid)) order by tgname) from pg_trigger where tgrelid='public.pdc_authenticated_email_operation_lines'::regclass and not tgisinternal)
) proof""")
print(json.dumps({'project_ref':STAGING_REF,'production_contacted':False,'proof':rows[0]['proof']},indent=2))
