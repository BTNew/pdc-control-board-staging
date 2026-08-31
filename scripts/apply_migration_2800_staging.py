from pathlib import Path
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260831280000_pdc_checklist_completion_booking_preservation.sql'
BOOTSTRAP = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
EXPECTED_HEAD = ('20260831270000', '861_null_storage_predicate_successor')
TARGET_HEAD = ('20260831280000', 'pdc_checklist_completion_booking_preservation')


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
        raise RuntimeError('PDC_CHECKLIST_2800_NON_STAGING_TARGET')
    migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()

    import psycopg2
    connection = psycopg2.connect(
        database_url,
        sslmode='verify-full',
        sslrootcert=credentials['PDC_STAGING_SSLROOTCERT'],
        application_name='pdc-checklist-closure-2800-staging-controller',
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        head = tuple(cursor.fetchone() or ())
        if head != EXPECTED_HEAD:
            raise RuntimeError(f'PDC_CHECKLIST_2600_UNEXPECTED_LIVE_HEAD:{head}')
        if scalar(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError('PDC_CHECKLIST_2600_PRODUCTION_SENTINEL_PRESENT')
        cursor.execute(MIGRATION.read_text(encoding='utf-8'))
        connection.commit()

        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        new_head = tuple(cursor.fetchone() or ())
        work_def = scalar(cursor, "select pg_get_functiondef('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure)") or ''
        completion_def = scalar(cursor, "select pg_get_functiondef('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure)") or ''
        out = {
            'ok': new_head == TARGET_HEAD,
            'environment': 'staging',
            'project_ref': REF,
            'migration_sha256': migration_sha256,
            'ledger_head': new_head,
            'requirement_completion_allowed_with_booking': "state IN('none','complete')" not in work_def and "state IN('none')" in work_def,
            'department_completion_preserves_booking': 'booking_preserved' in completion_def and "deleted_reason='Department completed from vehicle card" not in completion_def,
            'production_contacted': False,
            'outbound_email_enabled': False,
        }
        if not all((out['ok'], out['requirement_completion_allowed_with_booking'], out['department_completion_preserves_booking'])):
            raise RuntimeError('PDC_CHECKLIST_2600_POST_APPLY_READBACK_FAILED:' + json.dumps(out, sort_keys=True))
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
