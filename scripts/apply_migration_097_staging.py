#!/usr/bin/env python3
"""Atomically apply or rollback-test staging-only migration 097 with fail-closed checks."""
from __future__ import annotations
import hashlib,json,os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path: sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'097_authenticated_operation_snapshot.sql'
VERSION='097';NAME='authenticated_operation_snapshot';EXPECTED_LEDGER_HEAD='096'
ROLLBACK_ONLY=os.environ.get('PDC_MIGRATION_ROLLBACK_ONLY','').strip()=='1'
def scalar(cur,q,args=()): cur.execute(q,args);return cur.fetchone()[0]
def transaction_sql(source):
    text=source.strip();lower=text.lower();start=lower.find('\nbegin;')
    if start<0 or not lower.endswith('commit;'): raise RuntimeError('Migration 097 transaction wrappers invalid')
    return text[start+len('\nbegin;'):-len('commit;')].strip()
def function_has_operation_lines(cur):
    return bool(scalar(cur,"""select position('pdc_authenticated_email_operation_lines' in pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure))>0 and position('operation_lines' in pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure))>0"""))
def main():
    load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
    source=MIGRATION.read_text(encoding='utf-8')
    for token in ["project_ref='cdsmnqxtyyoeoznmbidd'",'pdc_authenticated_email_operation_lines',"'operation_lines'"]:
        if token not in source: raise RuntimeError('Migration 097 source contract invalid')
    conn=get_conn();conn.autocommit=False
    try:
      with conn.cursor() as cur:
        cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode')
        head=scalar(cur,"select version from supabase_migrations.schema_migrations order by version desc limit 1")
        if scalar(cur,"select count(*) from supabase_migrations.schema_migrations where version=%s",(VERSION,)):
            if not function_has_operation_lines(cur): raise RuntimeError('Migration 097 ledger/function mismatch')
            conn.rollback();print(json.dumps({'status':'already_applied','migration':VERSION,'projectRef':'cdsmnqxtyyoeoznmbidd'}));return
        if head!=EXPECTED_LEDGER_HEAD: raise RuntimeError(f'Migration ledger head changed: expected {EXPECTED_LEDGER_HEAD}, got {head}')
        queries={'vehicles':'select count(*) from public.vehicles','work_items':'select count(*) from public.vehicle_work_items','completed_work':'select count(*) from public.vehicle_work_items where completed','bookings':'select count(*) from public.workshop_bookings','operation_lines':'select count(*) from public.pdc_authenticated_email_operation_lines','email_revision':'select revision from public.pdc_email_vehicle_revision where singleton'}
        before={k:scalar(cur,q) for k,q in queries.items()};cur.execute(transaction_sql(source))
        if not function_has_operation_lines(cur): raise RuntimeError('Snapshot operation-line contract missing after migration')
        anonymous_grants=scalar(cur,"""select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='get_pdc_email_vehicle_location_snapshot' and grantee='anon' and privilege_type='EXECUTE'""")
        authenticated_grants=scalar(cur,"""select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='get_pdc_email_vehicle_location_snapshot' and grantee='authenticated' and privilege_type='EXECUTE'""")
        if anonymous_grants: raise RuntimeError('Snapshot has forbidden anonymous execute grant')
        if authenticated_grants!=1: raise RuntimeError('Snapshot authenticated execute grant missing or duplicated')
        cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",(VERSION,[source],NAME))
        after={k:scalar(cur,q) for k,q in queries.items()}
        if before!=after: raise RuntimeError(f'Migration changed operational state: {before} -> {after}')
        receipt={'status':'rollback_dry_run' if ROLLBACK_ONLY else 'applied','migration':VERSION,'priorLedgerHead':head,'sourceSha256':hashlib.sha256(source.encode()).hexdigest(),'operationalCounts':after,'productionChanged':False}
        if ROLLBACK_ONLY: conn.rollback()
        else: conn.commit()
        print(json.dumps(receipt,sort_keys=True))
    except Exception: conn.rollback();raise
    finally: conn.close()
if __name__=='__main__': main()
