from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib

import psycopg2

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260830081000_stock_13017855_restore_navision_parity_successor.sql'
BOOTSTRAP = pathlib.Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = pathlib.Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
REF = 'cdsmnqxtyyoeoznmbidd'
PROD = 'vjdtsswhroyguxyfjdkt'
PREDECESSOR = ('20260830080000', 'stock_13017855_integrity_and_lifecycle_guards')
NEW = ('20260830081000', 'stock_13017855_restore_navision_parity_successor')


def load_values():
    spec = importlib.util.spec_from_file_location('pdc_773_bootstrap', BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError('staging bootstrap unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode('utf-8'))
    module.validate(values)
    if REF not in values['PDC_STAGING_DATABASE_URL'] or PROD in values['PDC_STAGING_DATABASE_URL']:
        raise RuntimeError('PDC_773_NON_STAGING_DATABASE_TARGET')
    return values


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    if __import__('os').environ.get('PDC_APPROVE_STOCK_13017855_773') != f'apply Stock 13017855 migration 773 source {digest}':
        raise RuntimeError('PDC_773_EXPLICIT_STAGING_APPROVAL_MISSING')
    values = load_values()
    conn = psycopg2.connect(values['PDC_STAGING_DATABASE_URL'], sslmode='verify-full', sslrootcert=values['PDC_STAGING_SSLROOTCERT'], application_name='pdc-stock-13017855-parity-773')
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute("select version,name from supabase_migrations.schema_migrations order by version::bigint desc limit 1")
            head = tuple(cur.fetchone())
            if head == PREDECESSOR:
                cur.execute(MIGRATION.read_text(encoding='utf-8'))
            elif head != NEW:
                raise RuntimeError(f'PDC_773_PREDECESSOR_MISMATCH:{head}')
            cur.execute("select version,name from supabase_migrations.schema_migrations order by version::bigint desc limit 1")
            final_head = tuple(cur.fetchone())
            if final_head != NEW:
                raise RuntimeError(f'PDC_773_HEAD_FAILED:{final_head}')
            cur.execute("select position('navision_updated_at' in pg_get_functiondef('public.restore_stock_13017855_archived_vehicle_772(uuid,uuid,integer,text,text,text,text)'::regprocedure))>0")
            if not cur.fetchone()[0]:
                raise RuntimeError('PDC_773_RESTORE_PARITY_PATCH_MISSING')
            print(json.dumps({'ok': True, 'environment': 'staging', 'project_ref': REF, 'migration': f'{NEW[0]}_{NEW[1]}', 'migration_sha256': digest, 'predecessor': PREDECESSOR, 'production_contacted': False}))
    finally:
        conn.close()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error), 'production_contacted': False}))
        raise SystemExit(1)
