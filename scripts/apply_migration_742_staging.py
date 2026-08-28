#!/usr/bin/env python3
"""Fail-closed staging installer for the one-time Parts controller correction."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re
from pathlib import Path
from urllib.parse import urlsplit

ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260829090000_742_controller_parts_received_correction.sql'
EXPECTED_SHA256='79cdc5f65823bb44362cf5bce3b0e5153919f9f80e6730827957257d4bbd2450'
PROJECT_REF='cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF='vjdtsswhroyguxyfjdkt'
APPLY_ENV='PDC_APPROVE_STAGING_MIGRATION_742'
CONCURRENT_TOKEN='20260828_135232_8cb189'


def values():
    boot=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
    store=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
    s=importlib.util.spec_from_file_location('pdc_boot',boot); m=importlib.util.module_from_spec(s)
    if s is None or s.loader is None: raise RuntimeError('staging bootstrap unavailable')
    s.loader.exec_module(m); v=json.loads(m.unprotect(store.read_bytes()).decode('utf-8')); m.validate(v)
    if v.get('PDC_STAGING_PROJECT_REF')!=PROJECT_REF: raise RuntimeError('staging project mismatch')
    return v


def connect(v, app):
    import psycopg2
    p=urlsplit(v['PDC_STAGING_DATABASE_URL'])
    direct=p.hostname==f'db.{PROJECT_REF}.supabase.co' and p.username=='postgres' and p.port==5432
    pooler=bool(re.fullmatch(r'aws-[0-9]+-[a-z0-9]+(?:-[a-z0-9]+)*\.pooler\.supabase\.com',p.hostname or '')) and p.username==f'postgres.{PROJECT_REF}' and p.port in (5432,6543)
    if PRODUCTION_REF in v['PDC_STAGING_DATABASE_URL'].lower() or not (direct or pooler): raise RuntimeError('refusing non-staging endpoint')
    return psycopg2.connect(host=p.hostname,port=p.port or 5432,user=p.username,password=p.password,dbname='postgres',sslmode='verify-full',sslrootcert=v['PDC_STAGING_SSLROOTCERT'],connect_timeout=15,application_name=app)


def source():
    b=MIGRATION.read_bytes(); h=hashlib.sha256(b).hexdigest()
    if h!=EXPECTED_SHA256: raise RuntimeError('742 migration source hash mismatch')
    t=b.decode('utf-8','strict'); starts=list(re.finditer(r'(?im)^\s*BEGIN;\s*$',t)); commits=list(re.finditer(r'(?im)^\s*COMMIT;\s*$',t))
    if len(starts)!=1 or len(commits)!=1 or starts[0].start()>commits[0].start(): raise RuntimeError('742 transaction shape invalid')
    body=t[starts[0].end():commits[0].start()]
    if re.search(r'(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;\s*$',body): raise RuntimeError('742 nested transaction control found')
    return b,body


def state(cur):
    cur.execute("""select current_database(),current_user,session_user,
      (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s),
      to_regclass('public.pdc_production_environment_sentinel') is not null,
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version='20260829080000'),
      (select count(*) from supabase_migrations.schema_migrations where version='20260829050000' and name='738_authenticated_parts_received_auditor_wrapper'),
      (select count(*) from supabase_migrations.schema_migrations where version='20260829090000'),
      to_regprocedure('public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)') is not null,
      to_regclass('public.pdc_staging_parts_received_correction_authorizations_742') is not null,
      to_regclass('public.pdc_staging_parts_received_correction_receipts_742') is not null""",(PROJECT_REF,))
    r=cur.fetchone()
    cur.execute("""select pid,application_name,state,xact_start,query_start,wait_event_type,wait_event
      from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid()
       and (application_name ilike %s or query ilike %s) order by pid""",(f'%{CONCURRENT_TOKEN}%',f'%{CONCURRENT_TOKEN}%'))
    activity=[dict(zip(('pid','application_name','state','xact_start','query_start','wait_event_type','wait_event'),x)) for x in cur.fetchall()]
    return {'database':r[0],'current_user':r[1],'session_user':r[2],'staging_sentinel':r[3],'production_sentinel':r[4],'head':r[5],'head_name':r[6],'migration_738':r[7],'migration_742':r[8],'wrapper':r[9],'authorization_table':r[10],'receipt_table':r[11],'concurrent_lane':activity}


def assert_before(s):
    if (s['database'],s['current_user'],s['session_user'],s['staging_sentinel'],s['production_sentinel'])!=('postgres','postgres','postgres',1,False): raise RuntimeError('staging identity/sentinel mismatch')
    if s['head']!='20260829080000' or s['head_name']!='741_rft_transport_email_draft_regex_repair' or s['migration_738']!=1 or s['migration_742']!=0 or s['wrapper'] or s['authorization_table'] or s['receipt_table']: raise RuntimeError(f'742 exact prestate mismatch: {s}')
    if s['concurrent_lane']: raise RuntimeError('known concurrent migration worker/session is still applying')


def post(cur):
    cur.execute("""select
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version='20260829090000'),
      to_regprocedure('public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)') is not null,
      to_regclass('public.pdc_staging_parts_received_correction_authorizations_742') is not null,
      to_regclass('public.pdc_staging_parts_received_correction_receipts_742') is not null,
      (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_staging_parts_received_correction_authorizations_742'::regclass),
      (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_staging_parts_received_correction_receipts_742'::regclass),
      has_function_privilege('authenticated','public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)','execute'),
      has_function_privilege('anon','public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)','execute'),
      has_function_privilege('service_role','public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)','execute'),
      to_regclass('public.pdc_production_environment_sentinel') is not null,
      (select count(*) from public.pdc_staging_parts_received_correction_authorizations_742),
      (select count(*) from public.pdc_staging_parts_received_correction_receipts_742)""")
    return dict(zip(('head','name','wrapper','authorization_table','receipt_table','authorization_forced_rls','receipt_forced_rls','authenticated_execute','anon_execute','service_role_execute','production_sentinel','authorization_rows','receipt_rows'),cur.fetchone()))


def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=('preflight','apply','readback')); a=p.parse_args()
    result={'ok':False,'mode':a.mode,'committed':False,'production_touched':False}; cn=None
    try:
        b,body=source(); result['migration_sha256']=hashlib.sha256(b).hexdigest(); v=values(); cn=connect(v,'hermes_parts_controller_742_installer'); cn.autocommit=False
        with cn.cursor() as cur:
            cur.execute("select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0))")
            before=state(cur); result['before']=before
            if a.mode=='readback': result['after']=before; result['ok']=True
            else:
                assert_before(before); cur.execute(body); after=post(cur); result['after']=after
                if a.mode=='preflight': cn.rollback(); result['rollback_verified']=state(cn.cursor())['head']==before['head']; result['ok']=True
                else:
                    if os.environ.get(APPLY_ENV)!=f'apply migration 742 source {EXPECTED_SHA256}': raise RuntimeError('apply approval phrase missing')
                    cn.commit(); result['committed']=True; result['ok']=True
        if result['committed']:
            cn.close(); cn=connect(v,'hermes_parts_controller_742_readback')
            with cn.cursor() as cur:
                result['readback']=post(cur)
                r=result['readback']
                if r['head']!='20260829090000' or not r['wrapper'] or not r['authorization_table'] or not r['receipt_table'] or not r['authorization_forced_rls'] or not r['receipt_forced_rls'] or not r['authenticated_execute'] or r['anon_execute'] or r['service_role_execute'] or r['production_sentinel'] or r['authorization_rows']!=1 or r['receipt_rows']!=0: raise RuntimeError('742 poststate mismatch')
            cn.rollback()
    except Exception as e:
        if cn is not None:
            try: cn.rollback()
            except Exception: pass
        result['error']=str(e)[:1200]
    finally:
        if cn is not None:
            try: cn.close()
            except Exception: pass
    print(json.dumps(result,default=str,sort_keys=True,separators=(',',':'))); return 0 if result['ok'] else 1

if __name__=='__main__': raise SystemExit(main())
