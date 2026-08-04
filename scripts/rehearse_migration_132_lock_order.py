from __future__ import annotations
import os, sys, threading, time
from pathlib import Path
import psycopg

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'pdc-control-board'/'_staging_test_tools'))
from staging_env import assert_staging_target, load_local_env

M132=(ROOT/'supabase'/'staging_only'/'132_stock_only_authenticated_email_batch_fanout.sql').read_text(encoding='utf-8').lower()
ADMIN=(ROOT/'supabase'/'staging_only'/'065_pdc_ai_intake_admin_decisions.sql').read_text(encoding='utf-8').lower()
NAV="pg_advisory_xact_lock(hashtextextended('navision-backend-store',0))"
assert M132.index(NAV) < M132.index('lock table public.vehicles,public.vehicle_aliases')
assert ADMIN.index(NAV) < ADMIN.index('lock table public.vehicles, public.vehicle_aliases')

load_local_env()
dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL')
if not dsn: raise RuntimeError('staging database URL is not configured')
assert_staging_target(database_url=dsn)
ready=threading.Event(); errors=[]; waits=[]

def lane(name: str, first: bool) -> None:
    try:
        with psycopg.connect(dsn) as conn:
            with conn.cursor() as cur:
                cur.execute("set local lock_timeout='3s'")
                cur.execute("set local statement_timeout='8s'")
                if not first:
                    if not ready.wait(3): raise RuntimeError('admin lane did not acquire global lock')
                started=time.monotonic()
                cur.execute("select pg_advisory_xact_lock(hashtextextended('navision-backend-store',0))")
                waits.append((name,time.monotonic()-started))
                if first:
                    ready.set()
                    time.sleep(0.35)
                cur.execute('lock table public.vehicles,public.vehicle_aliases in share row exclusive mode')
                if first: time.sleep(0.35)
                conn.rollback()
    except Exception as exc:
        errors.append(f'{name}: {exc!r}')

admin=threading.Thread(target=lane,args=('admin-apply-order',True),daemon=True)
batch=threading.Thread(target=lane,args=('batch-import-order',False),daemon=True)
admin.start(); batch.start(); admin.join(10); batch.join(10)
if admin.is_alive() or batch.is_alive(): raise RuntimeError('lock-order lanes did not finish')
if errors: raise RuntimeError('; '.join(errors))
wait=dict(waits)
if wait.get('batch-import-order',0)<0.5:
    raise RuntimeError(f'batch lane did not serialize behind global lock: {wait}')
print({'ok':True,'admin_wait_seconds':round(wait['admin-apply-order'],3),'batch_wait_seconds':round(wait['batch-import-order'],3),'deadlock':False,'writes':0})
