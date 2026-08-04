from __future__ import annotations
import hashlib,json,os,sys
from pathlib import Path
import psycopg

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'pdc-control-board'/'_staging_test_tools'))
from staging_env import assert_staging_target,load_local_env

BATCH="public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb)"
LEGACY="public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)"
HELPER="public.pdc_email_receipt_single_source_guard()"
EXPECTED_REF='cdsmnqxtyyoeoznmbidd'
EXPECTED_MIGRATION_SHA='7b913e6eb88ebf59b6eae8b21610c2b4ba5fedb2d4b61c4dff0ba0e21bed1f23'

def scalar(cur,sql,params=()):
    cur.execute(sql,params); return cur.fetchone()[0]

load_local_env(); dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL')
if not dsn: raise RuntimeError('staging database URL is not configured')
assert_staging_target(database_url=dsn)
with psycopg.connect(dsn) as conn, conn.cursor() as cur:
    project_ref=scalar(cur,"select project_ref from public.pdc_staging_environment_sentinel where singleton")
    production_sentinel=scalar(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")
    ledger=scalar(cur,"select count(*) from supabase_migrations.schema_migrations where version='132' and name='stock_only_authenticated_email_batch_fanout'")
    function_def=scalar(cur,"select pg_get_functiondef(%s::regprocedure)",(BATCH,))
    function_hash=hashlib.sha256(function_def.encode()).hexdigest()
    privileges={}
    for role in ('public','anon','authenticated','service_role'):
        privileges[role]={
            'batch_execute':scalar(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(role,BATCH)),
            'legacy_execute':scalar(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(role,LEGACY)),
            'helper_execute':scalar(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(role,HELPER)),
        }
    tables={}
    for table in ('pdc_authenticated_email_import_receipts','pdc_authenticated_email_batch_receipts'):
        tables[table]={
            'rls':scalar(cur,"select relrowsecurity from pg_class where oid=%s::regclass",('public.'+table,)),
            'authenticated_direct':scalar(cur,"select has_table_privilege('authenticated',%s,'SELECT,INSERT,UPDATE,DELETE')",('public.'+table,)),
            'service_role_direct':scalar(cur,"select has_table_privilege('service_role',%s,'SELECT,INSERT,UPDATE,DELETE')",('public.'+table,)),
        }
    cur.execute("""select tgname,tgenabled,pg_get_triggerdef(oid,true) from pg_trigger
      where not tgisinternal and tgrelid in ('public.pdc_authenticated_email_import_receipts'::regclass,'public.pdc_authenticated_email_batch_receipts'::regclass)
        and tgname in ('pdc_email_single_receipt_source_guard','pdc_email_batch_receipt_source_guard') order by tgname""")
    trigger_rows=cur.fetchall()
    triggers={name:{'enabled':enabled,'sha256':hashlib.sha256(definition.encode()).hexdigest()} for name,enabled,definition in trigger_rows}
    metadata={
        'source_claims':scalar(cur,'select count(*) from public.pdc_email_source_claims'),
        'single_receipts':scalar(cur,'select count(*) from public.pdc_authenticated_email_import_receipts'),
        'batch_receipts':scalar(cur,'select count(*) from public.pdc_authenticated_email_batch_receipts'),
        'latest_batch_receipt_at':str(scalar(cur,'select max(created_at) from public.pdc_authenticated_email_batch_receipts')),
        'unconsumed_claims':scalar(cur,"""select count(*) from public.pdc_email_source_claims c where not exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.source_hash=c.source_hash) and not exists(select 1 from public.pdc_authenticated_email_batch_receipts r where r.source_hash=c.source_hash)"""),
    }
    surfaces={name:scalar(cur,f'select count(*) from public.{table}') for name,table in {
        'bookings':'workshop_bookings','work_items':'vehicle_work_items','parts_updates':'vehicle_parts_updates','movements':'vehicle_movements','notifications':'vehicle_notifications','activations':'navision_board_activations'
    }.items()}

assert project_ref==EXPECTED_REF and not production_sentinel and ledger==1
assert privileges['authenticated']['batch_execute'] and all(not privileges[r]['batch_execute'] for r in ('public','anon','service_role'))
assert all(not values['legacy_execute'] and not values['helper_execute'] for values in privileges.values())
assert len(triggers)==2 and all(v['enabled']=='O' for v in triggers.values())
if not all(v['rls'] and not v['authenticated_direct'] and not v['service_role_direct'] for v in tables.values()):
    raise RuntimeError(f'receipt table ACL mismatch: {tables}')
print(json.dumps({'ok':True,'migration':'132','migration_sha256':EXPECTED_MIGRATION_SHA,'function_def_sha256':function_hash,'privileges':privileges,'receipt_tables':tables,'triggers':triggers,'metadata':metadata,'operational_surface_counts':surfaces},sort_keys=True))
