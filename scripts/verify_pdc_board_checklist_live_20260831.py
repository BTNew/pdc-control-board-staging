from pathlib import Path
import importlib.util
import json

BOOTSTRAP = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
REF = 'cdsmnqxtyyoeoznmbidd'
PROD = 'vjdtsswhroyguxyfjdkt'
STOCK = '13080534'


def main():
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    credentials = json.loads(module.unprotect(SECRETS.read_bytes()).decode())
    module.validate(credentials)
    database_url = credentials['PDC_STAGING_DATABASE_URL']
    if REF not in database_url or PROD in database_url:
        raise RuntimeError('PDC_BOARD_LIVE_NON_STAGING_TARGET')

    import psycopg2
    connection = psycopg2.connect(
        database_url,
        sslmode='verify-full',
        sslrootcert=credentials['PDC_STAGING_SSLROOTCERT'],
        application_name='pdc-board-checklist-live-readback-20260831',
    )
    try:
        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        head = tuple(cursor.fetchone() or ())
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version='20260831280000' and name='pdc_checklist_completion_booking_preservation'")
        checklist_migration = tuple(cursor.fetchone() or ())
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version='20260831310000' and name='pdc_checklist_completion_history_preservation'")
        history_migration = tuple(cursor.fetchone() or ())
        cursor.execute("select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (REF,))
        sentinel = cursor.fetchone()[0]
        cursor.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
        production_sentinel = bool(cursor.fetchone()[0])
        cursor.execute("""
            select v.id, v.current_location, v.lifecycle_state::text,
                   (select count(*) from public.pdc_sublet_booking_instances s where s.vehicle_id=v.id and s.status='active'),
                   (select count(*) from public.pdc_sublet_booking_instances s where s.vehicle_id=v.id and s.status='returned'),
                   (select count(*) from public.pdc_sublet_booking_instances s where s.vehicle_id=v.id and s.status='cancelled'),
                   (select count(*) from public.pdc_sublet_booking_instance_history h where h.vehicle_id=v.id)
            from public.vehicles v
            where v.stock_number_normalized=%s
        """, (STOCK,))
        vehicle_rows = cursor.fetchall()
        cursor.execute("select public.get_pdc_email_vehicle_location_snapshot()")
        snapshot = cursor.fetchone()[0] or {}
        data = snapshot.get('data', snapshot) if isinstance(snapshot, dict) else {}
        rows = data.get('vehicles', []) if isinstance(data, dict) else []
        stock_rows = [row for row in rows if str(row.get('stock_number', '')).strip() == STOCK]
        sublet_snapshot = []
        for row in stock_rows:
            bookings = row.get('sublet_bookings') or row.get('sublet_booking') or []
            if isinstance(bookings, dict):
                bookings = [bookings]
            sublet_snapshot.extend(bookings if isinstance(bookings, list) else [])
        cursor.execute("select pg_get_functiondef('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure)")
        completion_definition = str(cursor.fetchone()[0] or '')
        cursor.execute("select p.proowner::regrole::text,p.prosecdef,p.proacl::text from pg_proc p where p.oid='public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure")
        function_identity = cursor.fetchone() or (None, False, None)
        out = {
            'ok': bool(checklist_migration == ('20260831280000', 'pdc_checklist_completion_booking_preservation') and history_migration == ('20260831310000', 'pdc_checklist_completion_history_preservation') and sentinel == 1 and not production_sentinel and len(vehicle_rows) == 1 and len(stock_rows) == 1 and 'booking_preserved' in completion_definition and 'actor,email,v.id,NULL)' in completion_definition and 'pg_advisory_xact_lock' in completion_definition and 'pdc_vehicle_department_completion_receipts_772' in completion_definition and function_identity[0] == 'postgres' and bool(function_identity[1]) and not any(role in (function_identity[2] or '') for role in ('public', 'anon', 'service_role'))),
            'environment': 'staging',
            'project_ref': REF,
            'current_migration_head': head,
            'checklist_migration': checklist_migration,
            'history_migration': history_migration,
            'completion_function_booking_preserved': 'booking_preserved' in completion_definition and 'actor,email,v.id,NULL)' in completion_definition,
            'completion_function_idempotency_lock': 'pg_advisory_xact_lock' in completion_definition and 'pdc_vehicle_department_completion_receipts_772' in completion_definition,
            'completion_function_security_identity': function_identity[0] == 'postgres' and bool(function_identity[1]) and not any(role in (function_identity[2] or '') for role in ('public', 'anon', 'service_role')),
            'staging_sentinel_count': sentinel,
            'production_sentinel_present': production_sentinel,
            'stock': STOCK,
            'canonical_vehicle_count': len(vehicle_rows),
            'vehicle_projection_count': len(stock_rows),
            'vehicle_rows': [
                {
                    'vehicle_id': row[0], 'current_location': row[1], 'lifecycle_state': row[2],
                    'active_sublet_bookings': row[3], 'returned_sublet_bookings': row[4],
                    'cancelled_sublet_bookings': row[5], 'sublet_history_rows': row[6],
                }
                for row in vehicle_rows
            ],
            'snapshot_sublet_bookings': [
                {
                    'booking_id': row.get('booking_id'), 'status': row.get('status'),
                    'out_date': row.get('out_date'), 'expected_return_date': row.get('expected_return_date'),
                }
                for row in sublet_snapshot
            ],
        }
        print(json.dumps(out, default=str, sort_keys=True))
        if not out['ok']:
            raise SystemExit(1)
    finally:
        connection.close()


if __name__ == '__main__':
    main()
