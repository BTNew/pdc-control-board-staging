from __future__ import annotations
import os, subprocess, sys, unittest
from pathlib import Path
import psycopg

ROOT=Path(__file__).parent
if os.environ.get('PDC_RUN_LIVE_STAGING_FAULT_TESTS') != '1':
    raise unittest.SkipTest('set PDC_RUN_LIVE_STAGING_FAULT_TESTS=1 for credentialed live-staging rollback probe')
sys.path.insert(0,str(Path.home()/'pdc-control-board'/'_staging_test_tools'))
from staging_env import load_local_env,assert_staging_target

BATCH="public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb)"
LEGACY="public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)"

def state(dsn):
    with psycopg.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute("""
          select
            exists(select 1 from supabase_migrations.schema_migrations where version='132'),
            has_function_privilege('authenticated',%s,'EXECUTE'),
            has_function_privilege('authenticated',%s,'EXECUTE'),
            exists(select 1 from pg_trigger where tgrelid='public.pdc_authenticated_email_import_receipts'::regclass and tgname='pdc_email_single_receipt_source_guard' and not tgisinternal),
            exists(select 1 from pg_trigger where tgrelid='public.pdc_authenticated_email_batch_receipts'::regclass and tgname='pdc_email_batch_receipt_source_guard' and not tgisinternal),
            (select count(*) from public.vehicles),
            (select count(*) from public.workshop_bookings),
            (select count(*) from public.vehicle_work_items),
            (select count(*) from public.pdc_authenticated_email_batch_receipts)
        """,(BATCH,LEGACY))
        return cur.fetchone()

load_local_env(); dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL'); assert_staging_target(database_url=dsn)
before=state(dsn)
expected_commit=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
proc=subprocess.run([
    sys.executable,str(ROOT/'scripts'/'apply_migration_132_staging.py'),
    '--apply','--expected-commit',expected_commit,'--fault-inject-postcheck-failure'
],capture_output=True,text=True,env=os.environ.copy())
after=state(dsn)
assert proc.returncode != 0, 'fault injection unexpectedly succeeded'
assert 'intentional postcheck failure before commit' in (proc.stdout+proc.stderr)
assert after == before, f'fault rollback leaked state: {before} -> {after}'
print('Migration 132 installer fault rollback: ok')
