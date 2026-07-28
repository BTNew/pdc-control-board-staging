#!/usr/bin/env python3
"""Guarded staging-only apply or rollback rehearsal for migration 107."""
from __future__ import annotations
import hashlib, json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from pdc_staging_runtime import assert_staging_target, get_conn, load_local_env, required  # noqa: E402

EXPECTED_REF='cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF='vjdtsswhroyguxyfjdkt'
EXPECTED_BRANCH='qa/workshop-bulletproof-20260728'
MIGRATION=ROOT/'supabase'/'staging_only'/'107_authenticated_operation_line_identity.sql'
VERSION='107'
NAME='authenticated_operation_line_identity'
PRIOR_VERSION='106'
PRIOR_NAME='workshop_booked_chip_move_cascade'
PRIOR_SHA256='7068dcc12959922b0e1d347efc3e6d20463af0f6aeda0a100179bd07a7ba5d85'
ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','1').lower() not in {'0','false','no'}
PROTECTED_TABLES=('vehicles','vehicle_work_items','vehicle_parts_updates','workshop_bookings','workshop_booking_assignments','workshop_booking_history')


def scalar(cur,query,params=()):
    cur.execute(query,params); row=cur.fetchone(); return row[0] if row else None


def transaction_body(source:str)->str:
    source=source.strip()
    if source.lower().startswith('begin;'): source=source[6:].lstrip()
    if source.lower().endswith('commit;'): source=source[:-7].rstrip()
    return source


def signature(cur,table:str):
    cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
    count,digest=cur.fetchone(); return int(count),str(digest)


def legacy_unambiguous_count(cur)->int:
    return int(scalar(cur,"""
      with unique_source as (
        select vehicle_id,operation_no,(array_agg(operation_line_id order by operation_line_id))[1] operation_line_id
        from public.pdc_authenticated_email_operation_lines
        group by vehicle_id,operation_no having count(*)=1
      )
      select count(*) from public.vehicle_workshop_line_adjustments a
      join unique_source u on u.vehicle_id=a.vehicle_id
        and a.line_key='operation:'||upper(btrim(u.operation_no))
      where not exists(select 1 from public.vehicle_workshop_line_adjustments e
        where e.vehicle_id=a.vehicle_id and e.line_key='source:'||u.operation_line_id::text
          and e.adjustment_id<>a.adjustment_id)
    """))


def legacy_ambiguous_count(cur)->int:
    return int(scalar(cur,"""
      select count(*)
      from public.vehicle_workshop_line_adjustments a
      where a.line_key like 'operation:%%'
        and (select count(*) from public.pdc_authenticated_email_operation_lines ol
             where ol.vehicle_id=a.vehicle_id
               and upper(btrim(ol.operation_no))=substring(a.line_key from 11))>1
    """))


def effective_checks(cur):
    definition=scalar(cur,"select pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)") or ''
    for text in ('operation_line_id','estimated_hours'):
        if text.lower() not in definition.lower(): raise RuntimeError(f'effective snapshot definition missing: {text}')
    if scalar(cur,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='get_pdc_email_vehicle_location_snapshot' and grantee='authenticated' and privilege_type='EXECUTE'")<1:
        raise RuntimeError('authenticated snapshot grant missing')
    if scalar(cur,"select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='get_pdc_email_vehicle_location_snapshot' and grantee in ('PUBLIC','anon') and privilege_type='EXECUTE'"):
        raise RuntimeError('forbidden snapshot grant present')
    return {'durableOperationIdentity':True,'authenticatedReadOnly':True}


def main()->int:
    branch=subprocess.check_output(['git','-C',str(ROOT),'branch','--show-current'],text=True).strip()
    if branch!=EXPECTED_BRANCH: raise RuntimeError(f'refusing migration 107 from branch {branch!r}')
    source_commit=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip()
    load_local_env(); database_url=required('PDC_STAGING_DATABASE_URL'); lowered=database_url.lower()
    if PRODUCTION_REF in lowered or EXPECTED_REF not in lowered: raise RuntimeError('refusing endpoint outside guarded staging')
    assert_staging_target(database_url=database_url)
    source=MIGRATION.read_text(encoding='utf-8'); source_sha=hashlib.sha256(source.encode()).hexdigest()
    conn=get_conn(); conn.autocommit=False
    try:
      with conn.cursor() as cur:
        cur.execute("set local statement_timeout='120s'")
        cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode')
        if scalar(cur,'select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s',(EXPECTED_REF,))!=1: raise RuntimeError('PDC_STAGING_SENTINEL_MISMATCH')
        head=str(scalar(cur,'select version from supabase_migrations.schema_migrations order by version::int desc limit 1'))
        existing=scalar(cur,'select count(*) from supabase_migrations.schema_migrations where version=%s',(VERSION,))
        if existing:
          cur.execute('select name,statements from supabase_migrations.schema_migrations where version=%s',(VERSION,)); name,statements=cur.fetchone(); recorded=(statements or [''])[0]
          if name!=NAME or hashlib.sha256(recorded.encode()).hexdigest()!=source_sha: raise RuntimeError('migration 107 ledger checksum/name mismatch')
          checks=effective_checks(cur)
          if legacy_unambiguous_count(cur)!=0: raise RuntimeError('legacy unambiguous operation adjustments remain')
          conn.rollback(); print(json.dumps({'status':'already_applied','migration':VERSION,**checks,'productionChanged':False},sort_keys=True)); return 0
        if head!=PRIOR_VERSION: raise RuntimeError(f'ledger head mismatch: {head}')
        cur.execute('select name,statements from supabase_migrations.schema_migrations where version=%s',(PRIOR_VERSION,)); prior_name,prior_statements=cur.fetchone(); prior_source=(prior_statements or [''])[0]
        if prior_name!=PRIOR_NAME or hashlib.sha256(prior_source.encode()).hexdigest()!=PRIOR_SHA256: raise RuntimeError('migration 106 prerequisite checksum/name mismatch')
        protected_before={table:signature(cur,table) for table in PROTECTED_TABLES}
        eligible_before=legacy_unambiguous_count(cur)
        ambiguous_before=legacy_ambiguous_count(cur)
        if ambiguous_before:
          raise RuntimeError(f'{ambiguous_before} ambiguous legacy operation adjustments require manual review')
        adjustment_count_before=int(scalar(cur,'select count(*) from public.vehicle_workshop_line_adjustments'))
        audit_before=int(scalar(cur,'select count(*) from public.audit_events'))
        cur.execute(transaction_body(source))
        checks=effective_checks(cur)
        if legacy_unambiguous_count(cur)!=0: raise RuntimeError('legacy unambiguous operation adjustments remain after repair')
        if int(scalar(cur,'select count(*) from public.vehicle_workshop_line_adjustments'))!=adjustment_count_before: raise RuntimeError('adjustment row count changed')
        if int(scalar(cur,'select count(*) from public.audit_events'))-audit_before!=eligible_before: raise RuntimeError('identity repair audit count mismatch')
        if {table:signature(cur,table) for table in PROTECTED_TABLES}!=protected_before: raise RuntimeError('migration 107 changed protected operational signatures')
        cur.execute('insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)',(VERSION,[source],NAME))
        status='rollback_dry_run' if ROLLBACK_ONLY else 'applied'; conn.rollback() if ROLLBACK_ONLY else conn.commit()
        print(json.dumps({'status':status,'migration':VERSION,'sourceSha256':source_sha,'sourceBranch':branch,'sourceCommit':source_commit,'unambiguousAdjustmentsRemapped':eligible_before,'ambiguousLegacyAdjustments':ambiguous_before,'protectedOperationalSignaturesUnchanged':True,**checks,'productionChanged':False},sort_keys=True)); return 0
    except Exception as exc:
      conn.rollback(); print(f'MIGRATION_107_FAILED: {exc}',file=sys.stderr); return 1
    finally: conn.close()

if __name__=='__main__': raise SystemExit(main())
