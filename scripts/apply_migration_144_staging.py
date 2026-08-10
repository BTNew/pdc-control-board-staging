from __future__ import annotations
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
import psycopg2
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/"pdc-control-board"/"_staging_test_tools"))
from staging_env import assert_staging_target,load_local_env
EXPECTED_REF='cdsmnqxtyyoeoznmbidd'
EXPECTED_SHA='13c0fa06e9921f276c9c3f712295b88eb35b73a480ac6d40661e0f1665509703'
VERSION='144'; NAME='restore_narrow_pdc_monitor_canonical_importer'
MIGRATION=ROOT/'supabase'/'staging_only'/'144_restore_narrow_pdc_monitor_canonical_importer.sql'
SIGNATURE='public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)'
HOURS='public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'
def scalar(cur,q,p=()): cur.execute(q,p); return cur.fetchone()[0]
def body(s):
 b=re.search(r'(?im)^\s*begin;\s*$',s); cs=list(re.finditer(r'(?im)^\s*commit;\s*$',s))
 if not b or not cs: raise RuntimeError('Migration 144 wrapper missing')
 return s[b.end():cs[-1].start()]
def data(cur):
 return tuple(scalar(cur,q) for q in (
  'select count(*) from public.vehicles','select count(*) from public.vehicle_work_items',
  'select count(*) from public.pdc_authenticated_email_import_receipts','select count(*) from public.pdc_authenticated_email_operation_lines',
  'select count(*) from public.workshop_bookings','select revision from public.pdc_email_vehicle_revision where singleton'))
def verify(cur,before):
 definition=scalar(cur,'select pg_get_functiondef(%s::regprocedure)',(SIGNATURE,))
 comment=scalar(cur,"select obj_description(%s::regprocedure,'pg_proc')",(SIGNATURE,))
 for marker in ("'contract_version',3",'backend_stock_not_found','backend_stock_ambiguous','job_card_source_conflict','operational_job_card_conflict','pdc_monitor_canonical_stock_import_144','pdc_monitor_staging_guard()','pdc_monitor_stage_activation_writers'):
  if marker not in definition: raise RuntimeError('Migration 144 marker missing: '+marker)
 if 'Staging v3 canonical Monitor importer' not in comment: raise RuntimeError('Migration 144 comment/version missing')
 priv={r:scalar(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(r,SIGNATURE)) for r in ('public','anon','authenticated','service_role')}
 hp={r:scalar(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(r,HOURS)) for r in ('public','anon','authenticated','service_role')}
 if priv!={'public':False,'anon':False,'authenticated':True,'service_role':False} or hp!={'public':False,'anon':False,'authenticated':True,'service_role':False}: raise RuntimeError(f'privilege mismatch: canonical={priv}, hours={hp}')
 p=scalar(cur,"select prosecdef and proconfig=array['search_path=pg_catalog, public, extensions']::text[] from pg_proc where oid=%s::regprocedure",(SIGNATURE,))
 if not p: raise RuntimeError('security definer/search_path mismatch')
 if data(cur)!=before: raise RuntimeError('structural verification changed operational data')
 return {'canonical_privileges':priv,'hours_privileges':hp,'security_definer':True,'fixed_search_path':True}
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--apply',action='store_true'); ap.add_argument('--expected-commit'); a=ap.parse_args()
 if a.apply and (not a.expected_commit or not re.fullmatch(r'[a-f0-9]{40}',a.expected_commit)): raise RuntimeError('--apply requires exact reviewed commit')
 raw=MIGRATION.read_bytes(); sha=hashlib.sha256(raw).hexdigest()
 if sha!=EXPECTED_SHA: raise RuntimeError('Migration 144 digest mismatch: '+sha)
 load_local_env(); dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL'); assert_staging_target(database_url=dsn)
 if a.apply:
  actual=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
  dirty=subprocess.run(['git','status','--porcelain','--untracked-files=all'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
  if actual!=a.expected_commit or dirty: raise RuntimeError('refusing apply from unreviewed or dirty worktree')
 conn=psycopg2.connect(dsn)
 try:
  with conn.cursor() as cur:
   if scalar(cur,'select project_ref from public.pdc_staging_environment_sentinel where singleton')!=EXPECTED_REF or scalar(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null"): raise RuntimeError('staging sentinel mismatch')
   head=scalar(cur,'select version from supabase_migrations.schema_migrations order by version::integer desc limit 1'); installed=scalar(cur,'select count(*) from supabase_migrations.schema_migrations where version=%s',(VERSION,))
   if head!='143' or installed: raise RuntimeError(f'unexpected ledger pre-state: head={head}, installed={installed}')
   before=data(cur); original=scalar(cur,'select pg_get_functiondef(%s::regprocedure)',(SIGNATURE,))
   cur.execute(body(raw.decode()))
   outcome=verify(cur,before)
   if a.apply: conn.commit()
   else:
    conn.rollback()
    with conn.cursor() as q:
     if scalar(q,'select pg_get_functiondef(%s::regprocedure)',(SIGNATURE,))!=original or data(q)!=before or scalar(q,'select count(*) from supabase_migrations.schema_migrations where version=%s',(VERSION,)): raise RuntimeError('rehearsal rollback leaked')
    print(json.dumps({'ok':True,'mode':'rehearsal','migration':VERSION,'sha256':sha,'outcome':outcome,'rollback_restored':True,'production_changed':False},sort_keys=True)); return
  with conn.cursor() as cur:
   if scalar(cur,'select count(*) from supabase_migrations.schema_migrations where version=%s and name=%s',(VERSION,NAME))!=1: raise RuntimeError('persisted ledger mismatch')
   outcome=verify(cur,data(cur))
  conn.rollback(); print(json.dumps({'ok':True,'mode':'apply','migration':VERSION,'sha256':sha,'outcome':outcome,'production_changed':False},sort_keys=True))
 except Exception: conn.rollback(); raise
 finally: conn.close()
if __name__=='__main__': main()
