#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
EXPECTED_REF='cdsmnqxtyyoeoznmbidd'; PRODUCTION_REF='vjdtsswhroyguxyfjdkt'; EXPECTED_BRANCH='qa/workshop-bulletproof-20260728'
VERSION='108'; NAME='remove_pit_inspection_workshop_planner'; MIGRATION=ROOT/'supabase'/'staging_only'/'108_remove_pit_inspection_workshop_planner.sql'
ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','1').lower() not in {'0','false','no'}
PROTECTED=('vehicles','vehicle_work_items','vehicle_parts_updates','workshop_bookings','workshop_booking_assignments','workshop_booking_history')
def scalar(cur,q,p=()): cur.execute(q,p); r=cur.fetchone(); return r[0] if r else None
def body(s):
 s=s.strip(); s=s[6:].lstrip() if s.lower().startswith('begin;') else s; s=s[:-7].rstrip() if s.lower().endswith('commit;') else s; return s
def sig(cur,t):
 cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')) from public.{t} x"); n,d=cur.fetchone(); return int(n),str(d)
def checks(cur):
 if scalar(cur,"select count(*) from public.workshop_stages where code='PIT_INSPECTION' and planner_enabled")!=0: raise RuntimeError('Pit planner remains enabled')
 if scalar(cur,"select count(*) from public.workshop_bays b join public.workshop_stages s on s.id=b.stage_id where s.code='PIT_INSPECTION' and b.is_active")!=0: raise RuntimeError('Pit bay remains active')
 if scalar(cur,"select count(*) from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id where s.code='PIT_INSPECTION' and b.deleted_at is null and b.status in ('queued','planned','started','stoppage')")!=0: raise RuntimeError('active Pit booking contradiction')
 definition=scalar(cur,"select pg_get_functiondef('public.pdc_qc_gate_issues(uuid)'::regprocedure)") or ''
 if 'outstanding_required_work' not in definition: raise RuntimeError('QC outstanding-work gate changed unexpectedly')
 return {'pitPlannerEnabled':False,'activePitBays':0,'activePitBookings':0,'pitRequirementPreserved':True}
def main():
 branch=subprocess.check_output(['git','-C',str(ROOT),'branch','--show-current'],text=True).strip()
 if branch!=EXPECTED_BRANCH: raise RuntimeError(f'refusing migration 108 from branch {branch!r}')
 load_local_env(); url=required('PDC_STAGING_DATABASE_URL'); assert_staging_target(database_url=url)
 if PRODUCTION_REF in url.lower() or EXPECTED_REF not in url.lower(): raise RuntimeError('refusing endpoint outside staging')
 source=MIGRATION.read_text(encoding='utf-8'); sha=hashlib.sha256(source.encode()).hexdigest(); conn=get_conn(); conn.autocommit=False
 try:
  with conn.cursor() as cur:
   cur.execute("set local statement_timeout='120s'"); cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode')
   if scalar(cur,'select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s',(EXPECTED_REF,))!=1: raise RuntimeError('PDC_STAGING_SENTINEL_MISMATCH')
   existing=scalar(cur,'select count(*) from supabase_migrations.schema_migrations where version=%s',(VERSION,))
   if existing:
    cur.execute('select name,statements from supabase_migrations.schema_migrations where version=%s',(VERSION,)); name,statements=cur.fetchone(); recorded=(statements or [''])[0]
    if name!=NAME or hashlib.sha256(recorded.encode()).hexdigest()!=sha: raise RuntimeError('migration 108 ledger checksum/name mismatch')
    result=checks(cur); conn.rollback(); print(json.dumps({'status':'already_applied','migration':VERSION,'sourceSha256':sha,**result,'productionChanged':False},sort_keys=True)); return 0
   head=str(scalar(cur,'select version from supabase_migrations.schema_migrations order by version::int desc limit 1'))
   if head!='107': raise RuntimeError(f'migration head must be 107, found {head}')
   before={t:sig(cur,t) for t in PROTECTED}; cur.execute(body(source)); result=checks(cur); after={t:sig(cur,t) for t in PROTECTED}
   if before!=after: raise RuntimeError('protected operational signatures changed')
   if ROLLBACK_ONLY:
    conn.rollback(); print(json.dumps({'status':'rollback_verified','migration':VERSION,'sourceSha256':sha,**result,'protectedOperationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True)); return 0
   cur.execute('insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)',(VERSION,[source],NAME)); conn.commit(); print(json.dumps({'status':'applied','migration':VERSION,'sourceSha256':sha,**result,'protectedOperationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True)); return 0
 finally:
  conn.close()
if __name__=='__main__':
 try: raise SystemExit(main())
 except Exception as e: print(f'MIGRATION_108_FAILED: {e}',file=sys.stderr); raise SystemExit(1)
