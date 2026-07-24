#!/usr/bin/env python3
"""Apply reviewed migration 052 to the approved staging project only."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '_staging_test_tools'))
from staging_conn import get_conn  # noqa: E402
from staging_env import EXPECTED_STAGING_REF  # noqa: E402
from release_backup_gate import validate_release_backup  # noqa: E402

MIGRATION = ROOT / 'supabase/migrations/052_bus4x4_concurrency_safe_bay_reconciliation.sql'
NAME = 'bus4x4_concurrency_safe_bay_reconciliation'


def strip_transaction_wrapper(sql: str) -> str:
    body = re.sub(r'^\s*begin\s*;\s*', '', sql, count=1, flags=re.I)
    body = re.sub(r'\s*commit\s*;\s*$', '', body, count=1, flags=re.I)
    if body == sql:
        raise RuntimeError('migration transaction wrapper not found')
    return body


def operational_hashes(cursor):
    result = {}
    for table in ('vehicles', 'vehicle_work_items', 'workshop_bookings', 'workshop_booking_assignments', 'workshop_booking_history'):
        cursor.execute(f"select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id),'')) from public.{table} t")
        result[table] = cursor.fetchone()[0]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--confirm-project', required=True)
    parser.add_argument('--backup-path', required=True)
    parser.add_argument('--backup-sha256', required=True)
    parser.add_argument('--restore-schema', required=True)
    args = parser.parse_args()
    if args.confirm_project != EXPECTED_STAGING_REF:
        raise SystemExit('project confirmation mismatch')

    sql = MIGRATION.read_text(encoding='utf-8')
    required_sql = (
        'lock table public.workshop_bookings in share row exclusive mode',
        "wb.status in ('queued', 'planned', 'started', 'stoppage')",
        'bay.bay_number not between 1 and 8',
    )
    for fragment in required_sql:
        if fragment not in sql:
            raise RuntimeError(f'migration 052 safety fragment missing: {fragment}')
    if re.search(r'(?im)^\s*update\s+public\.workshop_bookings\b', sql):
        raise RuntimeError('migration 052 must not rewrite workshop bookings')
    body = strip_transaction_wrapper(sql)

    conn = get_conn()
    cursor = conn.cursor()
    try:
        backup_evidence = validate_release_backup(
            conn, args.backup_path, args.backup_sha256, args.restore_schema,
            expected_migration='051',
        )
        conn.rollback()
        cursor = conn.cursor()
        cursor.execute('begin')
        cursor.execute("select version from supabase_migrations.schema_migrations where version in('051','052') order by version")
        versions = [row[0] for row in cursor.fetchall()]
        if versions != ['051']:
            raise RuntimeError(f'ledger precondition failed: {versions}')
        before = operational_hashes(cursor)
        cursor.execute(body)
        after = operational_hashes(cursor)
        if before != after:
            raise RuntimeError('migration changed operational rows')
        cursor.execute("""select count(*) from public.workshop_bays b
          join public.workshop_stages s on s.id=b.stage_id
          where s.code='BUS_4X4' and b.is_active""")
        if cursor.fetchone()[0] != 8:
            raise RuntimeError('Bus 4x4 does not have exactly eight active bays')
        cursor.execute("""select count(*)
          from public.workshop_bookings wb
          join public.workshop_bays bay on bay.id=wb.bay_id
          join public.workshop_stages stage on stage.id=bay.stage_id
          where stage.code='BUS_4X4'
            and wb.deleted_at is null
            and wb.status in ('queued','planned','started','stoppage')
            and (bay.is_active is not true or bay.bay_number not between 1 and 8)""")
        if cursor.fetchone()[0] != 0:
            raise RuntimeError('active Bus 4x4 work is attached to a hidden or out-of-range bay')
        cursor.execute("insert into supabase_migrations.schema_migrations(version,name,statements) values('052',%s,%s)", (NAME, [sql]))
        conn.commit()
        print(json.dumps({
            'status': 'applied',
            'project_ref': EXPECTED_STAGING_REF,
            'migration': '052',
            'bus4x4_active_bays': 8,
            'hidden_active_bus4x4_bookings': 0,
            'operational_hashes_unchanged': True,
            'booking_dml_lock': 'share row exclusive',
            'backup_gate': backup_evidence,
        }, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
