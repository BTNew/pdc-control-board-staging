#!/usr/bin/env python3
"""Apply guarded PDC-14 partial fixture-cleanup repair to STAGING only."""
from __future__ import annotations
import argparse,json,os,sys
from pathlib import Path
from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF,management_query
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260904011300_pdc14_location_replay_partial_fixture_cleanup.sql'
APPROVAL='PDC_APPROVE_STAGING_MIGRATION_20260904011300'
TARGET=['20260904011300','pdc14_location_replay_partial_fixture_cleanup']
def state():
 return management_query("""select jsonb_build_object('head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,'cleanup_function',to_regprocedure('public.cleanup_pdc14_location_replay_fixture_20260904()')::text,'cleanup_history',to_regclass('public.pdc14_location_replay_fixture_cleanup_history_20260904')::text) as state""")[0]['state']
def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','dry-run','apply']);a=p.parse_args();before=state();out={'task':'t_67594974','mode':a.mode,'project_ref':STAGING_REF,'before':before,'production_contacted':False,'credentials_redacted':True}
 if STAGING_REF!='cdsmnqxtyyoeoznmbidd' or before['production_sentinel_present'] or before['staging_sentinel_count']!=1: raise RuntimeError('STAGING guard failed')
 sql=MIGRATION.read_text(encoding='utf-8')
 if a.mode=='dry-run': management_write('begin;\n'+sql.replace('BEGIN;','',1).rsplit('COMMIT;',1)[0]+'\nrollback;');out['dry_run_rolled_back']=True
 elif a.mode=='apply':
  if os.environ.get(APPROVAL)!='YES': raise RuntimeError(f'{APPROVAL}=YES required')
  management_write(sql);out['after']=state()
  if out['after']['head']!=TARGET or not out['after']['cleanup_function']: raise RuntimeError('apply readback failed')
 print(json.dumps(out,indent=2))
if __name__=='__main__':
 try: main()
 except Exception as e: print(json.dumps({'ok':False,'error':str(e),'credentials_redacted':True},indent=2));sys.exit(1)
