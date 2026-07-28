#!/usr/bin/env python3
"""Atomically apply and ledger staging-only migration 093 with fail-closed checks."""
from __future__ import annotations
import hashlib
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target, get_conn, load_local_env, required

MIGRATION = ROOT / 'supabase' / 'staging_only' / '093_authenticated_email_operation_lines.sql'
VERSION = '093'
NAME = 'authenticated_email_operation_lines'
EXPECTED_LEDGER_HEAD = '072'


def scalar(cur, query, args=()):
    cur.execute(query, args)
    return cur.fetchone()[0]


def transaction_sql(source: str) -> str:
    text = source.strip()
    lower = text.lower()
    marker = "\nbegin;"
    start = lower.find(marker)
    if start < 0 or not lower.endswith('commit;'):
        raise RuntimeError('Migration 093 must retain explicit transaction wrappers')
    return text[start + len(marker): -len('commit;')].strip()


def main():
    load_local_env()
    assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
    source = MIGRATION.read_text(encoding='utf-8')
    required_tokens = [
        "project_ref='cdsmnqxtyyoeoznmbidd'", 'pdc_authenticated_email_operation_lines',
        'import_pdc_authenticated_email_operations', "work_key in ('bus4x4'", "'booking_created',false",
    ]
    if any(token not in source for token in required_tokens):
        raise RuntimeError('Migration 093 source contract invalid')
    conn = get_conn()
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            head = scalar(cur, "select version from supabase_migrations.schema_migrations order by version desc limit 1")
            already = scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version=%s", (VERSION,))
            if already:
                table_name = scalar(cur, "select to_regclass('public.pdc_authenticated_email_operation_lines')::text")
                function_name = scalar(cur, "select to_regprocedure('public.import_pdc_authenticated_email_operations(text,text,jsonb)')::text")
                if not table_name or not function_name:
                    raise RuntimeError('Migration 093 ledger/object mismatch')
                print(json.dumps({'status': 'already_applied', 'migration': VERSION, 'projectRef': 'cdsmnqxtyyoeoznmbidd'}))
                conn.rollback()
                return
            if head != EXPECTED_LEDGER_HEAD:
                raise RuntimeError(f'Migration ledger head changed: expected {EXPECTED_LEDGER_HEAD}, got {head}')
            if scalar(cur, "select to_regclass('public.pdc_authenticated_email_operation_lines') is not null"):
                raise RuntimeError('Unledgered migration 093 table already exists')
            if scalar(cur, "select to_regprocedure('public.import_pdc_authenticated_email_operations(text,text,jsonb)') is not null"):
                raise RuntimeError('Unledgered migration 093 function already exists')

            before = {
                'vehicles': scalar(cur, 'select count(*) from public.vehicles'),
                'work_items': scalar(cur, 'select count(*) from public.vehicle_work_items'),
                'completed_work': scalar(cur, 'select count(*) from public.vehicle_work_items where completed'),
                'bookings': scalar(cur, 'select count(*) from public.workshop_bookings'),
                'email_receipts': scalar(cur, 'select count(*) from public.pdc_authenticated_email_import_receipts'),
                'email_revision': scalar(cur, 'select revision from public.pdc_email_vehicle_revision where singleton'),
            }
            cur.execute(transaction_sql(source))
            cur.execute(
                "insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",
                (VERSION, [source], NAME),
            )
            after = {
                'vehicles': scalar(cur, 'select count(*) from public.vehicles'),
                'work_items': scalar(cur, 'select count(*) from public.vehicle_work_items'),
                'completed_work': scalar(cur, 'select count(*) from public.vehicle_work_items where completed'),
                'bookings': scalar(cur, 'select count(*) from public.workshop_bookings'),
                'email_receipts': scalar(cur, 'select count(*) from public.pdc_authenticated_email_import_receipts'),
                'email_revision': scalar(cur, 'select revision from public.pdc_email_vehicle_revision where singleton'),
            }
            if after != before:
                raise RuntimeError(f'Migration changed operational state: {before} -> {after}')
            if scalar(cur, 'select count(*) from public.pdc_authenticated_email_operation_lines') != 0:
                raise RuntimeError('Operation-line table was not empty after DDL')
            direct = scalar(cur, """select count(*) from information_schema.table_privileges
                where table_schema='public' and table_name='pdc_authenticated_email_operation_lines'
                  and grantee in ('anon','authenticated')""")
            if direct:
                raise RuntimeError('Operation-line table has forbidden direct browser grants')
            execute_grants = scalar(cur, """select count(*) from information_schema.routine_privileges
                where specific_schema='public' and routine_name='import_pdc_authenticated_email_operations'
                  and grantee='authenticated' and privilege_type='EXECUTE'""")
            if execute_grants < 1:
                raise RuntimeError('Typed operation importer lacks authenticated execute grant')
            conn.commit()
            print(json.dumps({
                'status': 'applied', 'migration': VERSION, 'name': NAME,
                'projectRef': 'cdsmnqxtyyoeoznmbidd', 'priorLedgerHead': head,
                'sourceSha256': hashlib.sha256(source.encode()).hexdigest(),
                'operationalCounts': after, 'operationRows': 0,
                'productionChanged': False,
            }, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
