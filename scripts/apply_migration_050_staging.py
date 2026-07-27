#!/usr/bin/env python3
"""Apply reviewed migration 050 to the approved staging project only."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.pdc_staging_runtime import get_conn  # noqa: E402
from scripts.pdc_staging_runtime import EXPECTED_STAGING_REF  # noqa: E402
from release_backup_gate import validate_release_backup  # noqa: E402

MIGRATION = ROOT / 'supabase/migrations/050_workshop_tile_completion_and_live_bay.sql'
NAME = 'workshop_tile_completion_and_live_bay'


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
    body = strip_transaction_wrapper(sql)
    conn = get_conn()
    cursor = conn.cursor()
    try:
        backup_evidence = validate_release_backup(
            conn, args.backup_path, args.backup_sha256, args.restore_schema,
            expected_migration='049',
        )
        conn.rollback()
        cursor = conn.cursor()
        cursor.execute('begin')
        cursor.execute("select version from supabase_migrations.schema_migrations where version in('049','050') order by version")
        versions = [row[0] for row in cursor.fetchall()]
        if versions != ['049']:
            raise RuntimeError(f'ledger precondition failed: {versions}')
        cursor.execute("""select count(*) from (
          select bay_id from public.workshop_bookings
          where deleted_at is null and status='started' and bay_id is not null
          group by bay_id having count(*)>1
        ) d""")
        if cursor.fetchone()[0] != 0:
            raise RuntimeError('duplicate started jobs already exist in a physical bay')
        before = operational_hashes(cursor)
        cursor.execute(body)
        after = operational_hashes(cursor)
        if before != after:
            raise RuntimeError('migration changed operational rows')
        cursor.execute("""select count(*) from pg_indexes where schemaname='public'
          and indexname='workshop_bookings_one_started_per_bay_uidx'""")
        if cursor.fetchone()[0] != 1:
            raise RuntimeError('live-bay unique index missing')
        cursor.execute("select pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure)")
        if "'customer_name',v.customer_name" not in cursor.fetchone()[0]:
            raise RuntimeError('customer name missing from restricted station snapshot')
        cursor.execute("insert into supabase_migrations.schema_migrations(version,name,statements) values('050',%s,%s)", (NAME, [sql]))
        conn.commit()
        print(json.dumps({
            'status': 'applied',
            'project_ref': EXPECTED_STAGING_REF,
            'migration': '050',
            'operational_hashes_unchanged': True,
            'backup_gate': backup_evidence,
        }, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
