from __future__ import annotations
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
import psycopg2
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(Path.home()/'pdc-control-board'/'_staging_test_tools'))
from staging_env import load_local_env,assert_staging_target
M=ROOT/'supabase'/'staging_only'/'146_bind_monitor_import_to_retained_proposal.sql'; SHA='e953774a5a92eb2108234177f2a83ab3e58f54fad786a432be00b69ce89e2638'; SIG='public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)'
def one(c,q,p=()): c.execute(q,p); return c.fetchone()[0]
def data(c): return tuple(one(c,q) for q in ('select count(*) from public.vehicles','select count(*) from public.navision_board_activations','select count(*) from public.vehicle_work_items','select count(*) from public.vehicle_parts_updates','select count(*) from public.workshop_bookings','select count(*) from public.pdc_authenticated_email_import_receipts','select count(*) from public.pdc_authenticated_email_operation_lines','select revision from public.pdc_email_vehicle_revision where singleton'))
def body(s): b=re.search(r'(?im)^\s*begin;\s*$',s); cs=list(re.finditer(r'(?im)^\s*commit;\s*$',s)); return s[b.end():cs[-1].start()]
def verify(c,before):
 d=one(c,'select pg_get_functiondef(%s::regprocedure)',(SIG,)); comment=one(c,"select obj_description(%s::regprocedure,'pg_proc')",(SIG,))
 for x in ("'contract_version',5",'source_proposal_binding_mismatch','p.source_hash','p.evidence_hash','p.source_uid','p.sender_address','p.authentication','p.source_received_at','p.subject','p.stock_number','p.observations','pdc_monitor_canonical_stock_import_146'):
  if x not in d: raise RuntimeError('v5 marker missing: '+x)
 for forbidden in ('insert into public.vehicles','insert into public.navision_board_activations','update public.navision_board_activations','vehicle_parts_updates','pdc_ai_intake_history','workshop_bookings'):
  if forbidden in d.lower(): raise RuntimeError('forbidden v5 token: '+forbidden)
 if d.lower().count('update public.vehicles set')!=1 or not re.search(r'update public\.vehicles set\s+job_card_number=v_job_card,version=version\+1,updated_by=v_actor_id\s+where id=v_vehicle\.id',d,re.I): raise RuntimeError('JC-only vehicle update invariant failed')
 if 'Staging v5 Monitor importer' not in comment: raise RuntimeError('v5 comment missing')
 p={r:one(c,"select has_function_privilege(%s,%s,'EXECUTE')",(r,SIG)) for r in ('public','anon','authenticated','service_role')}
 if p!={'public':False,'anon':False,'authenticated':True,'service_role':False}: raise RuntimeError('ACL mismatch '+str(p))
 if not one(c,"select prosecdef and proconfig=array['search_path=pg_catalog, public, extensions']::text[] from pg_proc where oid=%s::regprocedure",(SIG,)): raise RuntimeError('security/search_path mismatch')
 if data(c)!=before: raise RuntimeError('structural install changed business data')
 return {'source_proposal_binding':True,'authenticated_execute_only':True,'forbidden_mutators_absent':True}
def main():
 p=argparse.ArgumentParser(); p.add_argument('--apply',action='store_true'); p.add_argument('--expected-commit'); a=p.parse_args(); raw=M.read_bytes(); sha=hashlib.sha256(raw).hexdigest()
 if sha!=SHA: raise RuntimeError('digest mismatch '+sha)
 if a.apply:
  if not a.expected_commit or not re.fullmatch(r'[a-f0-9]{40}',a.expected_commit): raise RuntimeError('exact reviewed commit required')
  head=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip(); dirty=subprocess.run(['git','status','--porcelain','--untracked-files=all'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
  if head!=a.expected_commit or dirty: raise RuntimeError('unreviewed or dirty apply refused')
 load_local_env(); dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL'); assert_staging_target(database_url=dsn); conn=psycopg2.connect(dsn)
 try:
  with conn.cursor() as c:
   if one(c,'select project_ref from pdc_staging_environment_sentinel where singleton')!='cdsmnqxtyyoeoznmbidd' or one(c,"select to_regclass('public.pdc_production_environment_sentinel') is not null"): raise RuntimeError('sentinel mismatch')
   if one(c,'select version from supabase_migrations.schema_migrations order by version::integer desc limit 1')!='145' or one(c,"select exists(select 1 from supabase_migrations.schema_migrations where version='146')"): raise RuntimeError('ledger pre-state mismatch')
   before=data(c); old=one(c,'select pg_get_functiondef(%s::regprocedure)',(SIG,)); c.execute(body(raw.decode())); outcome=verify(c,before)
   if a.apply: conn.commit()
   else:
    conn.rollback()
    with conn.cursor() as q:
     if one(q,'select pg_get_functiondef(%s::regprocedure)',(SIG,))!=old or data(q)!=before or one(q,"select exists(select 1 from supabase_migrations.schema_migrations where version='146')"): raise RuntimeError('rollback leaked')
    print(json.dumps({'ok':True,'mode':'rehearsal','migration':'146','sha256':sha,'outcome':outcome,'rollback_verified':True},sort_keys=True)); return
  with conn.cursor() as c:
   if one(c,"select count(*) from supabase_migrations.schema_migrations where version='146' and name='bind_monitor_import_to_retained_proposal'")!=1: raise RuntimeError('ledger persistence failed')
  conn.rollback(); print(json.dumps({'ok':True,'mode':'apply','migration':'146','sha256':sha,'outcome':outcome,'production_changed':False},sort_keys=True))
 except Exception: conn.rollback(); raise
 finally: conn.close()
if __name__=='__main__': main()
