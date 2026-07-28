#!/usr/bin/env python3
"""Atomically apply or rollback-test staging-only migration 099 with fail-closed checks."""
from __future__ import annotations
import hashlib,json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pdc_staging_runtime import load_local_env,assert_staging_target,required,get_conn
ROOT=Path(__file__).resolve().parents[1];MIGRATION=ROOT/'supabase'/'staging_only'/'099_authenticated_pd_accessory_lines.sql'
EXPECTED_LEDGER_HEAD='098';VERSION='099';NAME='authenticated_pd_accessory_lines';ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','').lower() in {'1','true','yes'}
def scalar(cur,q,p=()):cur.execute(q,p);r=cur.fetchone();return r[0] if r else None
def transaction_sql(source):
 s=source.strip();s=s[6:].lstrip() if s.lower().startswith('begin;') else s
 if s.lower().endswith('commit;'):s=s[:-7].rstrip()
 return s
def signature(cur,table):
 return scalar(cur,f"select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
def rpc_postconditions(cur):
 cur.execute("select pg_get_functiondef('public.import_pdc_authenticated_email_pd_lines(text,text,jsonb)'::regprocedure)");pd=cur.fetchone()[0]
 cur.execute("select pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)");snap=cur.fetchone()[0]
 if "^PD[0-9]{3}-[A-F0-9]{8}$" not in pd or 'security definer' not in pd.lower() or 'set search_path to' not in pd.lower():raise RuntimeError('PD RPC definition mismatch')
 if 'limit 50' not in snap.lower() or "operation_no like 'OP%'" not in snap:raise RuntimeError('Snapshot bounded mixed-line ordering mismatch')
 grants=scalar(cur,"""select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='import_pdc_authenticated_email_pd_lines' and grantee='authenticated' and privilege_type='EXECUTE'""")
 forbidden=scalar(cur,"""select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='import_pdc_authenticated_email_pd_lines' and grantee in ('PUBLIC','anon') and privilege_type='EXECUTE'""")
 if grants!=1 or forbidden:raise RuntimeError('PD RPC grants mismatch')
 constraint=scalar(cur,"select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.pdc_authenticated_email_operation_lines'::regclass and conname='pdc_authenticated_email_operation_lines_operation_no_check'") or ''
 if 'PD[0-9]{3}-[A-F0-9]{8}' not in constraint:raise RuntimeError('PD line-key constraint missing')
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'));source=MIGRATION.read_text('utf-8');sha=hashlib.sha256(source.encode()).hexdigest();conn=get_conn();conn.autocommit=False
 try:
  with conn.cursor() as cur:
   cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode')
   head=scalar(cur,"select version from supabase_migrations.schema_migrations order by version desc limit 1")
   if scalar(cur,"select count(*) from supabase_migrations.schema_migrations where version=%s",(VERSION,)):
     cur.execute("select name,statements from supabase_migrations.schema_migrations where version=%s",(VERSION,));record=cur.fetchone()
     recorded_source=(record[1] or [''])[0] if record else ''
     if not record or record[0]!=NAME or hashlib.sha256(recorded_source.encode()).hexdigest()!=sha:raise RuntimeError('applied migration ledger checksum/name mismatch')
     rpc_postconditions(cur);conn.rollback();print(json.dumps({'status':'already_applied','migration':VERSION,'productionChanged':False},sort_keys=True));return 0
   if head!=EXPECTED_LEDGER_HEAD:raise RuntimeError(f'ledger head mismatch: expected {EXPECTED_LEDGER_HEAD}, got {head}')
   tables=['vehicles','vehicle_work_items','vehicle_parts_updates','workshop_bookings','pdc_authenticated_email_operation_lines','pdc_authenticated_email_import_receipts','pdc_email_vehicle_revision']
   before={t:signature(cur,t) for t in tables};cur.execute(transaction_sql(source));rpc_postconditions(cur)
   cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",(VERSION,[source],NAME));after={t:signature(cur,t) for t in tables}
   if before!=after:raise RuntimeError('Migration changed operational data signatures')
   if ROLLBACK_ONLY:conn.rollback();status='rollback_dry_run'
   else:conn.commit();status='applied'
   print(json.dumps({'status':status,'migration':VERSION,'priorLedgerHead':head,'sourceSha256':sha,'operationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True));return 0
 except Exception as exc:conn.rollback();print(f'MIGRATION_099_FAILED: {exc}',file=sys.stderr);return 1
 finally:conn.close()
if __name__=='__main__':raise SystemExit(main())
