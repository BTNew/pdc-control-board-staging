#!/usr/bin/env python3
"""Atomically apply or rollback-test guarded-staging migration 100."""
from __future__ import annotations
import hashlib,json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pdc_staging_runtime import load_local_env,assert_staging_target,required,get_conn
ROOT=Path(__file__).resolve().parents[1];MIGRATION=ROOT/'supabase'/'staging_only'/'100_workshop_future_planning_without_parts_override.sql'
EXPECTED_LEDGER_HEAD='099';VERSION='100';NAME='workshop_future_planning_without_parts_override';ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','').lower() in {'1','true','yes'}
def scalar(cur,q,p=()):cur.execute(q,p);r=cur.fetchone();return r[0] if r else None
def transaction_sql(source):
 s=source.strip();s=s[6:].lstrip() if s.lower().startswith('begin;') else s
 if s.lower().endswith('commit;'):s=s[:-7].rstrip()
 return s
def signature(cur,table):return scalar(cur,f"select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
def postconditions(cur):
 schedule=scalar(cur,"select pg_get_functiondef('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'::regprocedure)") or ''
 cascade=scalar(cur,"select pg_get_functiondef('public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'::regprocedure)") or ''
 start=scalar(cur,"select pg_get_functiondef('public.start_workshop_work(uuid,integer,timestamptz,jsonb)'::regprocedure)") or ''
 if 'workshop_candidate_schedule_gate' not in schedule or ('workshop_'+'create_booking') not in schedule:raise RuntimeError('schedule authority definition mismatch')
 if 'workshop_parts_overrides' in schedule or "require_pdc_role('administrator')" in schedule:raise RuntimeError('future planning still creates/escalates a Parts override')
 if '__future_planning_does_not_reserve_parts__' not in cascade or 'cascade_workshop_schedule_pre_087' not in cascade:raise RuntimeError('cascade compatibility authority mismatch')
 if 'parts_incomplete_entry' not in start or "require_pdc_role('administrator')" not in start:raise RuntimeError('physical Start Parts gate changed')
 for routine in ('schedule_vehicle_work','cascade_workshop_schedule'):
  grants=scalar(cur,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name=%s and grantee='authenticated' and privilege_type='EXECUTE'",(routine,))
  forbidden=scalar(cur,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name=%s and grantee in ('PUBLIC','anon') and privilege_type='EXECUTE'",(routine,))
  if grants<1 or forbidden:raise RuntimeError(f'{routine} grants mismatch')
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'));source=MIGRATION.read_text('utf-8');sha=hashlib.sha256(source.encode()).hexdigest();conn=get_conn();conn.autocommit=False
 try:
  with conn.cursor() as cur:
   cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode');head=scalar(cur,"select version from supabase_migrations.schema_migrations order by version desc limit 1")
   if scalar(cur,"select count(*) from supabase_migrations.schema_migrations where version=%s",(VERSION,)):
    cur.execute("select name,statements from supabase_migrations.schema_migrations where version=%s",(VERSION,));record=cur.fetchone();recorded=(record[1] or [''])[0] if record else ''
    if not record or record[0]!=NAME or hashlib.sha256(recorded.encode()).hexdigest()!=sha:raise RuntimeError('applied migration ledger checksum/name mismatch')
    postconditions(cur);conn.rollback();print(json.dumps({'status':'already_applied','migration':VERSION,'productionChanged':False},sort_keys=True));return 0
   if head!=EXPECTED_LEDGER_HEAD:raise RuntimeError(f'ledger head mismatch: expected {EXPECTED_LEDGER_HEAD}, got {head}')
   tables=['vehicles','vehicle_work_items','vehicle_parts_updates','workshop_bookings','workshop_booking_history','workshop_parts_overrides','pdc_email_vehicle_revision']
   before={t:signature(cur,t) for t in tables};cur.execute(transaction_sql(source));postconditions(cur);cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",(VERSION,[source],NAME));after={t:signature(cur,t) for t in tables}
   if before!=after:raise RuntimeError('migration changed operational data signatures')
   if ROLLBACK_ONLY:conn.rollback();status='rollback_dry_run'
   else:conn.commit();status='applied'
   print(json.dumps({'status':status,'migration':VERSION,'priorLedgerHead':head,'sourceSha256':sha,'operationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True));return 0
 except Exception as exc:conn.rollback();print(f'MIGRATION_100_FAILED: {exc}',file=sys.stderr);return 1
 finally:conn.close()
if __name__=='__main__':raise SystemExit(main())
