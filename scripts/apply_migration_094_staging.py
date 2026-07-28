#!/usr/bin/env python3
"""Atomically apply and ledger staging-only migration 094 with fail-closed checks."""
from __future__ import annotations
import hashlib, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path: sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'094_authenticated_operation_replay_revision.sql'
VERSION='094';NAME='authenticated_operation_replay_revision';EXPECTED_LEDGER_HEAD='093'

def scalar(cur,q,args=()): cur.execute(q,args);return cur.fetchone()[0]
def transaction_sql(source):
    text=source.strip();lower=text.lower();start=lower.find('\nbegin;')
    if start<0 or not lower.endswith('commit;'): raise RuntimeError('Migration 094 transaction wrappers invalid')
    return text[start+len('\nbegin;'):-len('commit;')].strip()

def main():
    load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
    source=MIGRATION.read_text(encoding='utf-8')
    for token in ["project_ref='cdsmnqxtyyoeoznmbidd'",'for each row execute function public.bump_pdc_email_vehicle_revision()']:
        if token not in source: raise RuntimeError('Migration 094 source contract invalid')
    conn=get_conn();conn.autocommit=False
    try:
        with conn.cursor() as cur:
            head=scalar(cur,"select version from supabase_migrations.schema_migrations order by version desc limit 1")
            if scalar(cur,"select count(*) from supabase_migrations.schema_migrations where version=%s",(VERSION,)):
                timing=scalar(cur,"""select action_orientation from information_schema.triggers where event_object_schema='public' and event_object_table='pdc_authenticated_email_operation_lines' and trigger_name='pdc_email_vehicle_revision_operation_lines' limit 1""")
                if timing!='ROW': raise RuntimeError('Migration 094 ledger/trigger mismatch')
                conn.rollback();print(json.dumps({'status':'already_applied','migration':VERSION,'projectRef':'cdsmnqxtyyoeoznmbidd'}));return
            if head!=EXPECTED_LEDGER_HEAD: raise RuntimeError(f'Migration ledger head changed: expected {EXPECTED_LEDGER_HEAD}, got {head}')
            before={k:scalar(cur,q) for k,q in {
                'vehicles':'select count(*) from public.vehicles','work_items':'select count(*) from public.vehicle_work_items',
                'completed_work':'select count(*) from public.vehicle_work_items where completed','bookings':'select count(*) from public.workshop_bookings',
                'operation_lines':'select count(*) from public.pdc_authenticated_email_operation_lines',
                'email_revision':'select revision from public.pdc_email_vehicle_revision where singleton'}.items()}
            cur.execute(transaction_sql(source))
            orientation=scalar(cur,"""select action_orientation from information_schema.triggers where event_object_schema='public' and event_object_table='pdc_authenticated_email_operation_lines' and trigger_name='pdc_email_vehicle_revision_operation_lines' limit 1""")
            if orientation!='ROW': raise RuntimeError('Operation revision trigger is not row-level')
            cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",(VERSION,[source],NAME))
            after={k:scalar(cur,q) for k,q in {
                'vehicles':'select count(*) from public.vehicles','work_items':'select count(*) from public.vehicle_work_items',
                'completed_work':'select count(*) from public.vehicle_work_items where completed','bookings':'select count(*) from public.workshop_bookings',
                'operation_lines':'select count(*) from public.pdc_authenticated_email_operation_lines',
                'email_revision':'select revision from public.pdc_email_vehicle_revision where singleton'}.items()}
            if before!=after: raise RuntimeError(f'Migration changed operational state: {before} -> {after}')
            conn.commit();print(json.dumps({'status':'applied','migration':VERSION,'priorLedgerHead':head,'sourceSha256':hashlib.sha256(source.encode()).hexdigest(),'operationalCounts':after,'productionChanged':False},sort_keys=True))
    except Exception: conn.rollback();raise
    finally: conn.close()
if __name__=='__main__': main()
