from pathlib import Path
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260831310000_pdc_checklist_completion_history_preservation.sql'
BOOTSTRAP = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
EXPECTED_HEAD = ('20260831300000', 'pdc_email_ai_transaction_successor')
TARGET_HEAD = ('20260831310000', 'pdc_checklist_completion_history_preservation')
FUNCTION = 'public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'


def scalar(cursor, query):
    cursor.execute(query)
    row = cursor.fetchone()
    return row[0] if row else None


def main():
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    credentials = json.loads(module.unprotect(SECRETS.read_bytes()).decode())
    module.validate(credentials)
    database_url = credentials['PDC_STAGING_DATABASE_URL']
    if REF not in database_url or PRODUCTION_REF in database_url:
        raise RuntimeError('PDC_CHECKLIST_3100_NON_STAGING_TARGET')
    migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()

    import psycopg2
    connection = psycopg2.connect(
        database_url,
        sslmode='verify-full',
        sslrootcert=credentials['PDC_STAGING_SSLROOTCERT'],
        application_name='pdc-checklist-closure-3100-staging-controller',
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        head = tuple(cursor.fetchone() or ())
        if head != EXPECTED_HEAD:
            raise RuntimeError(f'PDC_CHECKLIST_3100_UNEXPECTED_LIVE_HEAD:{head}')
        if scalar(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError('PDC_CHECKLIST_3100_PRODUCTION_SENTINEL_PRESENT')
        cursor.execute(MIGRATION.read_text(encoding='utf-8'))
        connection.commit()

        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        new_head = tuple(cursor.fetchone() or ())
        definition = scalar(cursor, f"select pg_get_functiondef('{FUNCTION}'::regprocedure)") or ''
        owner, security_definer, acl = None, False, None
        cursor.execute(f"select p.proowner::regrole::text,p.prosecdef,p.proacl::text from pg_proc p where p.oid='{FUNCTION}'::regprocedure")
        row = cursor.fetchone()
        if row:
            owner, security_definer, acl = row
        out = {
            'ok': new_head == TARGET_HEAD,
            'environment': 'staging',
            'project_ref': REF,
            'migration_sha256': migration_sha256,
            'ledger_head': new_head,
            'booking_history_preserved': 'booking_preserved' in definition and 'actor,email,v.id,NULL)' in definition,
            'idempotency_lock_retained': 'pg_advisory_xact_lock' in definition and 'pdc_vehicle_department_completion_receipts_772' in definition,
            'security_identity': owner == 'postgres' and security_definer and not any(role in (acl or '') for role in ('public', 'anon', 'service_role')),
            'production_contacted': False,
            'outbound_email_enabled': False,
        }
        if not all((out['ok'], out['booking_history_preserved'], out['idempotency_lock_retained'], out['security_identity'])):
            raise RuntimeError('PDC_CHECKLIST_3100_POST_APPLY_READBACK_FAILED:' + json.dumps(out, sort_keys=True))
        connection.commit()
        print(json.dumps(out, sort_keys=True))
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({
            'ok': False,
            'error': str(error),
            'environment': 'staging',
            'production_contacted': False,
            'outbound_email_enabled': False,
        }, sort_keys=True))
        raise SystemExit(1)
