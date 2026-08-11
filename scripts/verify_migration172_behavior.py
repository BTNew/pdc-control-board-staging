#!/usr/bin/env python3
"""Rollback-only staging behavior proof for Migration 172."""
from __future__ import annotations

import json
import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "172_sublet_calendar_return_station_completion.sql"


def database_url() -> str:
    value = os.getenv("PDC_STAGING_DIRECT_DATABASE_URL") or os.getenv("PDC_STAGING_DATABASE_URL")
    if not value:
        raise SystemExit("Missing staging database URL")
    return value


def migration_body() -> str:
    text = MIGRATION.read_text(encoding="utf-8")
    if not text.startswith("-- Staging-only") or "\nbegin;" not in text or not text.rstrip().endswith("commit;"):
        raise AssertionError("Unexpected Migration 172 transaction wrapper")
    return text.replace("\nbegin;", "", 1).rsplit("commit;", 1)[0]


def main() -> None:
    connection = psycopg2.connect(database_url())
    connection.autocommit = False
    try:
        with connection.cursor() as cursor:
            cursor.execute(migration_body())
            cursor.execute("""
                select u.auth_user_id,u.email
                from public.pdc_user_roles u
                where u.active and u.account_status='approved'
                  and lower(u.role::text) in ('administrator','operator')
                order by case lower(u.role::text) when 'administrator' then 0 else 1 end,u.auth_user_id
                limit 1
            """)
            actor = cursor.fetchone()
            assert actor, "No approved Sublet actor fixture"
            actor_id, actor_email = actor
            cursor.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({"sub": str(actor_id), "email": actor_email, "role": "authenticated"}),))
            cursor.execute("""
                select v.id,v.version,p.id,p.name
                from public.vehicles v cross join lateral(
                  select id,name from public.sublet_providers where active order by id limit 1
                )p
                where v.deleted_at is null and v.lifecycle_state='active'
                  and not exists(select 1 from public.pdc_sublet_booking_instances b where b.vehicle_id=v.id and b.status='active')
                order by v.id limit 1
            """)
            fixture = cursor.fetchone()
            assert fixture, "No safe vehicle/provider fixture"
            vehicle_id, vehicle_version, provider_id, provider_name = fixture
            cursor.execute("""
                insert into public.vehicle_work_items(vehicle_id,work_key,required,completed)
                values(%s,'sublet',true,false)
                on conflict(vehicle_id,work_key) do update
                  set required=true,completed=false,completed_by=null,completed_at=null,updated_at=clock_timestamp()
                returning id
            """, (vehicle_id,))
            work_item_id = cursor.fetchone()[0]
            bookings = []
            for out_date, due_date in (("2099-01-03", "2099-01-04"), ("2099-01-05", "2099-01-06")):
                cursor.execute("""
                    insert into public.pdc_sublet_booking_instances(
                      vehicle_id,vehicle_version,provider_id,provider_name,provider_email,
                      out_date,expected_return_date,status,notes,source_kind,created_by,updated_by
                    ) values(%s,%s,%s,%s,'qa@example.invalid',%s,%s,'active','Migration 172 rollback QA','manual',%s,%s)
                    returning booking_id,version
                """, (vehicle_id, vehicle_version, provider_id, provider_name, out_date, due_date, actor_id, actor_id))
                bookings.append(cursor.fetchone())
            cursor.execute("select public.return_pdc_sublet_booking(%s,%s,%s)", (bookings[0][0], bookings[0][1], "2099-01-04T12:00:00+08:00"))
            first = cursor.fetchone()[0]
            assert first["ok"] and first["data"]["remaining_active_sublets"] == 1
            assert first["data"]["station_work_items_completed"] == 0
            cursor.execute("select completed from public.vehicle_work_items where id=%s", (work_item_id,))
            assert cursor.fetchone()[0] is False, "First of two returns completed Sublet station"
            cursor.execute("select public.return_pdc_sublet_booking(%s,%s,%s)", (bookings[1][0], bookings[1][1], "2099-01-06T12:00:00+08:00"))
            last = cursor.fetchone()[0]
            assert last["ok"] and last["data"]["remaining_active_sublets"] == 0
            assert last["data"]["sublet_station_completed"] is True
            assert last["data"]["station_work_items_completed"] == 1
            cursor.execute("select completed,completed_by,completed_at from public.vehicle_work_items where id=%s", (work_item_id,))
            completed, completed_by, completed_at = cursor.fetchone()
            assert completed and completed_by == actor_id and completed_at is not None
            cursor.execute("""
                select count(*) from public.audit_events
                where row_id=%s and metadata->>'source'='sublet_calendar_return_172'
                  and metadata->>'booking_id'=%s
            """, (work_item_id, str(bookings[1][0])))
            assert cursor.fetchone()[0] == 1, "Automatic station completion audit missing"
            cursor.execute("select has_function_privilege('authenticated','public.return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz)','EXECUTE')")
            assert cursor.fetchone()[0] is False
            print(json.dumps({"ok": True, "first_remaining": 1, "last_remaining": 0, "station_completed": True, "audit_rows": 1}, sort_keys=True))
    finally:
        connection.rollback()
        connection.close()


if __name__ == "__main__":
    main()
