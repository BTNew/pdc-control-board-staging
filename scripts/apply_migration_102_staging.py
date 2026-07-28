#!/usr/bin/env python3
"""Atomically apply or rollback-test guarded-staging migration 102."""
from __future__ import annotations
import hashlib,json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pdc_staging_runtime import load_local_env,assert_staging_target,required,get_conn
ROOT=Path(__file__).resolve().parents[1];MIGRATION=ROOT/'supabase'/'staging_only'/'102_vehicle_workshop_line_conflict_responses.sql';VERSION='102';NAME='vehicle_workshop_line_conflict_responses';ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','').lower() in {'1','true','yes'}
def scalar(c,q,p=()):c.execute(q,p);r=c.fetchone();return r[0] if r else None
def tx(s):
 s=s.strip();s=s[6:].lstrip() if s.lower().startswith('begin;') else s
 return s[:-7].rstrip() if s.lower().endswith('commit;') else s
def sig(c,t):return scalar(c,f"select md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')) from public.{t} x")
def checks(c):
 u=scalar(c,"select pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure)") or '';d=scalar(c,"select pg_get_functiondef('public.delete_vehicle_workshop_line_adjustment(uuid,uuid,bigint)'::regprocedure)") or ''
 if "'stale_line_version'" not in u or "'stale_vehicle_version'" not in u or "'stale_line_version'" not in d:raise RuntimeError('canonical stale response missing')
 if "ERRCODE = '40001'" in u or "ERRCODE = '40001'" in d:raise RuntimeError('retryable conflict SQLSTATE retained')
 for r in ('upsert_vehicle_workshop_line_adjustment','delete_vehicle_workshop_line_adjustment'):
  if scalar(c,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name=%s and grantee='authenticated' and privilege_type='EXECUTE'",(r,))<1:raise RuntimeError(r+' authenticated grant missing')
  if scalar(c,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name=%s and grantee in ('PUBLIC','anon') and privilege_type='EXECUTE'",(r,)):raise RuntimeError(r+' forbidden grant')
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'));source=MIGRATION.read_text('utf-8');sha=hashlib.sha256(source.encode()).hexdigest();conn=get_conn();conn.autocommit=False
 try:
  with conn.cursor() as c:
   c.execute('lock table supabase_migrations.schema_migrations in exclusive mode');head=scalar(c,'select version from supabase_migrations.schema_migrations order by version desc limit 1')
   if scalar(c,'select count(*) from supabase_migrations.schema_migrations where version=%s',(VERSION,)):
    c.execute('select name,statements from supabase_migrations.schema_migrations where version=%s',(VERSION,));r=c.fetchone();recorded=(r[1] or [''])[0]
    if r[0]!=NAME or hashlib.sha256(recorded.encode()).hexdigest()!=sha:raise RuntimeError('ledger checksum/name mismatch')
    checks(c);conn.rollback();print(json.dumps({'status':'already_applied','migration':VERSION,'productionChanged':False}));return 0
   if head!='101':raise RuntimeError(f'ledger head mismatch: {head}')
   tables=['vehicles','vehicle_work_items','vehicle_parts_updates','workshop_bookings','workshop_booking_history','workshop_parts_overrides','pdc_authenticated_email_operation_lines','vehicle_workshop_line_adjustments','pdc_email_vehicle_revision'];before={t:sig(c,t) for t in tables};c.execute(tx(source));checks(c);c.execute('insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)',(VERSION,[source],NAME));after={t:sig(c,t) for t in tables}
   if before!=after:raise RuntimeError('migration changed operational data signatures')
   status='rollback_dry_run' if ROLLBACK_ONLY else 'applied';conn.rollback() if ROLLBACK_ONLY else conn.commit();print(json.dumps({'status':status,'migration':VERSION,'sourceSha256':sha,'operationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True));return 0
 except Exception as e:conn.rollback();print('MIGRATION_102_FAILED: '+str(e),file=sys.stderr);return 1
 finally:conn.close()
if __name__=='__main__':raise SystemExit(main())
