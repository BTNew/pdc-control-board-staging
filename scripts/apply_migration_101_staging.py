#!/usr/bin/env python3
"""Atomically apply or rollback-test guarded-staging migration 101."""
from __future__ import annotations
import hashlib,json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pdc_staging_runtime import load_local_env,assert_staging_target,required,get_conn
ROOT=Path(__file__).resolve().parents[1];MIGRATION=ROOT/'supabase'/'staging_only'/'101_vehicle_workshop_line_adjustments.sql'
EXPECTED_LEDGER_HEAD='100';VERSION='101';NAME='vehicle_workshop_line_adjustments';ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','').lower() in {'1','true','yes'}
def scalar(cur,q,p=()):cur.execute(q,p);r=cur.fetchone();return r[0] if r else None
def transaction_sql(source):
 s=source.strip();s=s[6:].lstrip() if s.lower().startswith('begin;') else s
 if s.lower().endswith('commit;'):s=s[:-7].rstrip()
 return s
def signature(cur,table):return scalar(cur,f"select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
def postconditions(cur):
 table=scalar(cur,"select to_regclass('public.vehicle_workshop_line_adjustments')::text")
 rls=scalar(cur,"select relrowsecurity from pg_class where oid='public.vehicle_workshop_line_adjustments'::regclass") if table else False
 grants=scalar(cur,"select count(*) from information_schema.table_privileges where table_schema='public' and table_name='vehicle_workshop_line_adjustments' and grantee in ('PUBLIC','anon','authenticated')") if table else -1
 if table!='vehicle_workshop_line_adjustments' or not rls or grants:raise RuntimeError('line adjustment table authority mismatch')
 upsert=scalar(cur,"select pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure)") or ''
 delete=scalar(cur,"select pg_get_functiondef('public.delete_vehicle_workshop_line_adjustment(uuid,uuid,bigint)'::regprocedure)") or ''
 detail=scalar(cur,"select pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure)") or ''
 if "require_pdc_role('operator')" not in upsert or 'stale_line_version' not in upsert or 'audit_events' not in upsert:raise RuntimeError('upsert authority mismatch')
 if "require_pdc_role('operator')" not in delete or 'stale_line_version' not in delete or 'audit_events' not in delete:raise RuntimeError('delete authority mismatch')
 if "require_pdc_role('viewer')" not in detail or "'line_adjustments'" not in detail:raise RuntimeError('detail projection mismatch')
 for routine in ('upsert_vehicle_workshop_line_adjustment','delete_vehicle_workshop_line_adjustment','get_vehicle_workshop_detail'):
  allowed=scalar(cur,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name=%s and grantee='authenticated' and privilege_type='EXECUTE'",(routine,))
  forbidden=scalar(cur,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name=%s and grantee in ('PUBLIC','anon') and privilege_type='EXECUTE'",(routine,))
  if allowed<1 or forbidden:raise RuntimeError(f'{routine} grants mismatch')
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
   tables=['vehicles','vehicle_work_items','vehicle_parts_updates','workshop_bookings','workshop_booking_history','workshop_parts_overrides','pdc_authenticated_email_operation_lines','pdc_email_vehicle_revision']
   before={t:signature(cur,t) for t in tables};cur.execute(transaction_sql(source));postconditions(cur);cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",(VERSION,[source],NAME));after={t:signature(cur,t) for t in tables}
   if before!=after:raise RuntimeError('migration changed operational data signatures')
   if ROLLBACK_ONLY:conn.rollback();status='rollback_dry_run'
   else:conn.commit();status='applied'
   print(json.dumps({'status':status,'migration':VERSION,'priorLedgerHead':head,'sourceSha256':sha,'operationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True));return 0
 except Exception as exc:conn.rollback();print(f'MIGRATION_101_FAILED: {exc}',file=sys.stderr);return 1
 finally:conn.close()
if __name__=='__main__':raise SystemExit(main())
