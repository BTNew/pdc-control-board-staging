#!/usr/bin/env python3
"""Apply reviewed migrations 046 and 049 to the approved staging project only.

Requires an encrypted backup plus a successful isolated restore record bound to
that exact backup. Applies both migrations atomically and verifies the planner
safety boundary before commit. Never contacts production.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '_staging_test_tools'))
from staging_conn import get_conn  # noqa: E402
from staging_env import EXPECTED_STAGING_REF  # noqa: E402
from release_backup_gate import validate_release_backup  # noqa: E402

MIGRATIONS = [
    ('046', 'workshop_authoritative_validation_and_lifecycle', ROOT / 'supabase/migrations/046_workshop_authoritative_validation_and_lifecycle.sql'),
    ('049', 'soft_launch_planner_safety', ROOT / 'supabase/migrations/049_soft_launch_planner_safety.sql'),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--confirm-project', required=True)
    parser.add_argument('--backup-path', required=True)
    parser.add_argument('--backup-sha256', required=True)
    parser.add_argument('--restore-schema', required=True)
    args = parser.parse_args()
    if args.confirm_project != EXPECTED_STAGING_REF:
        raise SystemExit('project confirmation mismatch')

    sql_by_version = {version: path.read_text(encoding='utf-8') for version, _, path in MIGRATIONS}
    conn = get_conn()
    try:
        backup_evidence = validate_release_backup(
            conn, args.backup_path, args.backup_sha256, args.restore_schema,
            expected_migration='048',
        )
        conn.rollback()
        cur = conn.cursor()
        cur.execute('begin')
        cur.execute("select version from supabase_migrations.schema_migrations where version in ('045','046','047','048','049') order by version")
        versions = [row[0] for row in cur.fetchall()]
        if versions != ['045', '047', '048']:
            raise RuntimeError(f'ledger precondition failed: {versions}')

        for version, _, _ in MIGRATIONS:
            sql = sql_by_version[version]
            cur.execute(sql)

        cur.execute("select count(*) from public.workshop_bookings where legacy_ambiguity_quarantined")
        quarantined = cur.fetchone()[0]
        if quarantined != 8:
            raise RuntimeError(f'expected exactly 8 quarantined legacy Hoist rows, found {quarantined}')

        cur.execute("""
          select count(*) from public.workshop_bookings a
          join public.workshop_bookings b on b.vehicle_id=a.vehicle_id and b.id>a.id
            and b.deleted_at is null and not b.legacy_ambiguity_quarantined
            and b.status in ('queued','planned','started','stoppage')
            and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')
                && tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')
          where a.deleted_at is null and not a.legacy_ambiguity_quarantined
            and a.status in ('queued','planned','started','stoppage')
        """)
        unquarantined_overlaps = cur.fetchone()[0]
        if unquarantined_overlaps:
            raise RuntimeError(f'unquarantined active overlap count: {unquarantined_overlaps}')

        cur.execute("""select public.workshop_validate_booking(
          null,null,null,null,date_trunc('minute',now()-interval '1 hour'),
          date_trunc('minute',now()),60,'planned')""")
        past_result = cur.fetchone()[0]
        if past_result != {'ok': False, 'error': 'past_start'}:
            raise RuntimeError(f'past scheduling gate drift: {past_result}')

        cur.execute("select proconfig from pg_proc where oid='public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'::regprocedure")
        cascade_config = cur.fetchone()[0] or []
        if 'search_path=pg_catalog, public' not in cascade_config:
            raise RuntimeError(f'unsafe cascade search_path: {cascade_config}')

        cur.execute("select count(*) from pg_trigger where tgrelid='public.workshop_bookings'::regclass and not tgisinternal and tgname in ('workshop_booking_046a_lifecycle_guard','workshop_booking_046b_validation_guard')")
        trigger_count = cur.fetchone()[0]
        if trigger_count != 2:
            raise RuntimeError(f'expected both 046 booking triggers, found {trigger_count}')

        cur.execute("select has_table_privilege('authenticated','public.workshop_bookings','INSERT,UPDATE,DELETE,TRUNCATE')")
        if cur.fetchone()[0]:
            raise RuntimeError('authenticated unexpectedly has direct Workshop booking DML')

        conn.commit()
        print(json.dumps({
            'status': 'applied',
            'project_ref': EXPECTED_STAGING_REF,
            'migrations': ['046', '049'],
            'ledger_repair_required': ['046', '049'],
            'ledger_repair_command': 'supabase migration repair <version> --status applied --linked',
            'quarantined_legacy_rows': quarantined,
            'unquarantined_active_overlaps': unquarantined_overlaps,
            'past_scheduling_result': past_result,
            'cascade_search_path': cascade_config,
            'booking_guard_triggers': trigger_count,
            'backup_gate': backup_evidence,
        }, sort_keys=True, default=str))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
