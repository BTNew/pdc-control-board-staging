#!/usr/bin/env python3
"""Rollback-only functional rehearsal for staging migration 106."""
from __future__ import annotations
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from pdc_staging_runtime import assert_staging_target, get_conn, load_local_env, required  # noqa: E402

MIGRATION = ROOT / 'supabase' / 'staging_only' / '106_workshop_booked_chip_move_cascade.sql'


def tx(source: str) -> str:
    source = source.strip()
    if source.lower().startswith('begin;'):
        source = source[6:].lstrip()
    if source.lower().endswith('commit;'):
        source = source[:-7].rstrip()
    return source


def main() -> int:
    load_local_env()
    url = required('PDC_STAGING_DATABASE_URL')
    assert_staging_target(database_url=url)
    conn = get_conn(); conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("set local statement_timeout='120s'")
            cur.execute(tx(MIGRATION.read_text(encoding='utf-8')))
            cur.execute("""
              select t.id,t.version,s.code,db.bay_number,d.scheduled_start_at,t.default_duration_minutes,d.id,
                     t.bay_id,db.id,t.vehicle_id
              from public.workshop_bookings t
              join public.workshop_bays tb on tb.id=t.bay_id
              join public.workshop_stages s on s.id=t.stage_id
              join public.workshop_bays db on db.stage_id=t.stage_id and db.id<>t.bay_id and db.is_active
              join lateral (
                select x.* from public.workshop_bookings x
                where x.bay_id=db.id and x.status='planned' and x.deleted_at is null
                order by x.scheduled_start_at,x.id limit 1
              ) d on true
              where t.status='planned' and t.deleted_at is null
                and t.default_duration_minutes>=60
                and not exists(
                  select 1 from public.workshop_bookings x
                  where x.vehicle_id=t.vehicle_id and x.id<>t.id and x.deleted_at is null
                    and x.status in('planned','started','stoppage')
                    and x.scheduled_start_at<public.workshop_add_operational_minutes(d.scheduled_start_at,t.default_duration_minutes)
                    and x.scheduled_end_at>d.scheduled_start_at
                )
                and not exists(
                  select 1 from public.workshop_bookings x
                  where x.bay_id=db.id and x.deleted_at is null and x.status in('started','stoppage')
                    and x.scheduled_start_at<public.workshop_add_operational_minutes(d.scheduled_start_at,t.default_duration_minutes)
                    and x.scheduled_end_at>d.scheduled_start_at
                )
              order by d.scheduled_start_at,t.scheduled_start_at
              limit 1
            """)
            candidate = cur.fetchone()
            if not candidate:
                raise RuntimeError('no safe cross-bay planned fixture candidate available')
            target_id, version, stage, bay_number, drop_start, duration, pushed_id, source_bay_id, destination_bay_id, vehicle_id = candidate
            cur.execute("select u.id::text,lower(u.email) from auth.users u join public.pdc_user_roles r on r.auth_user_id=u.id where r.role='administrator' and r.active and r.account_status='approved' order by r.email limit 1")
            actor = cur.fetchone()
            if not actor:
                raise RuntimeError('approved Administrator fixture unavailable')
            cur.execute('set local role authenticated')
            cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({'sub': actor[0], 'email': actor[1], 'role': 'authenticated'}),))
            cur.execute('select scheduled_start_at,version from public.workshop_bookings where id=%s', (pushed_id,))
            pushed_before, pushed_version = cur.fetchone()
            cur.execute('select public.cascade_workshop_booking_move(%s,%s,%s,%s,%s,%s,%s,%s::jsonb)',
                        (target_id, version, stage, bay_number, drop_start, duration,
                         'Rollback-only migration 106 cascade rehearsal',
                         json.dumps({'source': 'migration_106_rollback_rehearsal'})))
            result = cur.fetchone()[0]
            if not result.get('ok'):
                raise RuntimeError(f'cascade move failed: {result}')
            cur.execute('select bay_id,scheduled_start_at,version from public.workshop_bookings where id=%s', (target_id,))
            moved_bay, moved_start, moved_version = cur.fetchone()
            cur.execute('select scheduled_start_at,version from public.workshop_bookings where id=%s', (pushed_id,))
            pushed_after, pushed_after_version = cur.fetchone()
            cur.execute("select count(*) from public.workshop_booking_history where booking_id=%s and event_type='cascade_move_shifted'", (pushed_id,))
            history_count = cur.fetchone()[0]
            if moved_bay != destination_bay_id or moved_start != drop_start or moved_version != version + 1:
                raise RuntimeError('target chip did not move exactly once to the destination bay/time')
            if pushed_after <= pushed_before or pushed_after_version != pushed_version + 1:
                raise RuntimeError('occupied destination chip was not pushed later exactly once')
            if history_count < 1 or pushed_id not in result.get('shifted_booking_ids', []):
                raise RuntimeError('shifted booking identity/history missing')
            cur.execute('set local role postgres')
            conn.rollback()
            print(json.dumps({
                'status': 'rollback_rehearsal_passed', 'migration': '106',
                'targetBooking': str(target_id), 'pushedBooking': str(pushed_id),
                'sourceBay': str(source_bay_id), 'destinationBay': str(destination_bay_id),
                'vehicle': str(vehicle_id), 'shiftMinutes': result.get('shift_minutes'),
                'shiftedCount': result.get('shifted_count'), 'productionChanged': False,
            }, sort_keys=True))
            return 0
    except Exception as exc:
        conn.rollback()
        print(f'MIGRATION_106_REHEARSAL_FAILED: {exc}', file=sys.stderr)
        return 1
    finally:
        conn.close()


if __name__ == '__main__':
    raise SystemExit(main())
