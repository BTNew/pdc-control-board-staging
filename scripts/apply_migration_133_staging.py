from __future__ import annotations
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
import psycopg

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'pdc-control-board'/'_staging_test_tools'))
from staging_env import assert_staging_target,load_local_env

MIGRATION=ROOT/'supabase'/'staging_only'/'133_close_email_receipt_table_direct_authority.sql'
EXPECTED_REF='cdsmnqxtyyoeoznmbidd'
EXPECTED_SHA='e676106f2ae5f627045fcf191e8df4304f4fb9a8607cb4862ab836a033c69459'
BATCH="public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb)"
TABLES=('public.pdc_authenticated_email_import_receipts','public.pdc_authenticated_email_batch_receipts')
ROLES=('public','anon','authenticated','service_role')

def scalar(cur,sql,params=()): cur.execute(sql,params); return cur.fetchone()[0]
def state(cur):
    return {
      'vehicles':scalar(cur,'select count(*) from public.vehicles'),
      'bookings':scalar(cur,'select count(*) from public.workshop_bookings'),
      'work_items':scalar(cur,'select count(*) from public.vehicle_work_items'),
      'parts':scalar(cur,'select count(*) from public.vehicle_parts_updates'),
      'movements':scalar(cur,'select count(*) from public.vehicle_movements'),
      'notifications':scalar(cur,'select count(*) from public.vehicle_notifications'),
      'activations':scalar(cur,'select count(*) from public.navision_board_activations'),
      'single_receipts':scalar(cur,'select count(*) from public.pdc_authenticated_email_import_receipts'),
      'batch_receipts':scalar(cur,'select count(*) from public.pdc_authenticated_email_batch_receipts'),
      'navision_revision':scalar(cur,'select revision from public.navision_backend_revision where singleton'),
      'navision_audit':scalar(cur,'select count(*) from public.navision_backend_audit'),
    }
def direct_acl(cur):
    return {role:{table:scalar(cur,"select has_table_privilege(%s,%s,'SELECT,INSERT,UPDATE,DELETE')",(role,table)) for table in TABLES} for role in ROLES}
def verify(cur):
    ledger=scalar(cur,"select count(*) from supabase_migrations.schema_migrations where version='133' and name='close_email_receipt_table_direct_authority'")
    rls={table:scalar(cur,'select relrowsecurity from pg_class where oid=%s::regclass',(table,)) for table in TABLES}
    acl=direct_acl(cur)
    batch={role:scalar(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(role,BATCH)) for role in ROLES}
    ok=ledger==1 and all(rls.values()) and not any(value for row in acl.values() for value in row.values()) and batch=={'public':False,'anon':False,'authenticated':True,'service_role':False}
    return ok,{'ledger':ledger,'rls':rls,'direct_acl':acl,'batch_execute':batch}

def main():
    p=argparse.ArgumentParser(); p.add_argument('--apply',action='store_true'); p.add_argument('--expected-commit'); p.add_argument('--fault-inject-postcheck-failure',action='store_true',help=argparse.SUPPRESS); args=p.parse_args()
    if args.apply and (not args.expected_commit or not re.fullmatch(r'[a-f0-9]{40}',args.expected_commit)): raise RuntimeError('--apply requires exact reviewed --expected-commit')
    if args.fault_inject_postcheck_failure and not args.apply: raise RuntimeError('fault injection requires --apply')
    load_local_env(); dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL')
    if not dsn: raise RuntimeError('staging database URL is not configured')
    assert_staging_target(database_url=dsn)
    raw=MIGRATION.read_bytes(); sha=hashlib.sha256(raw).hexdigest(); sql=raw.decode()
    if sha!=EXPECTED_SHA: raise RuntimeError(f'Migration 133 digest mismatch: {sha}')
    if args.apply:
        actual=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
        dirty=subprocess.run(['git','status','--porcelain','--untracked-files=all'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
        if actual!=args.expected_commit: raise RuntimeError(f'reviewed commit mismatch: {actual}')
        if dirty: raise RuntimeError('refusing Migration 133 apply from dirty worktree')
    body=sql.replace('begin;','',1).rsplit('commit;',1)[0]
    with psycopg.connect(dsn) as conn:
      try:
        with conn.cursor() as cur:
          if scalar(cur,"select project_ref from public.pdc_staging_environment_sentinel where singleton")!=EXPECTED_REF or scalar(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null"): raise RuntimeError('staging sentinel mismatch')
          if not scalar(cur,"select exists(select 1 from supabase_migrations.schema_migrations where version='132')") or scalar(cur,"select exists(select 1 from supabase_migrations.schema_migrations where version='133')"): raise RuntimeError('unexpected 132/133 ledger pre-state')
          before=state(cur); acl_before=direct_acl(cur)
          cur.execute(body)
          ok,details=verify(cur); after=state(cur)
          if not ok or before!=after: raise RuntimeError(f'Migration 133 postcheck failed: {details}; counts_equal={before==after}')
          if args.fault_inject_postcheck_failure: raise RuntimeError('intentional Migration 133 postcheck failure before commit')
          if not args.apply:
            conn.rollback()
            with conn.cursor() as check:
              if state(check)!=before or direct_acl(check)!=acl_before or scalar(check,"select exists(select 1 from supabase_migrations.schema_migrations where version='133')"): raise RuntimeError('Migration 133 rehearsal rollback leaked state')
            print(json.dumps({'ok':True,'migration':'133','mode':'rehearsal','sha256':sha,'operational_counts_unchanged':True})); return
          conn.commit()
        with conn.cursor() as cur:
          ok,details=verify(cur)
          if not ok: raise RuntimeError(f'Migration 133 persisted postcheck failed: {details}')
        print(json.dumps({'ok':True,'migration':'133','mode':'apply','sha256':sha,'operational_counts_unchanged':True,'direct_receipt_authority_revoked':True}))
      except Exception:
        conn.rollback(); raise
if __name__=='__main__': main()
