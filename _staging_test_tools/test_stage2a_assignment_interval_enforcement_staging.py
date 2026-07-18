"""Staging-only integration checks for migration 027.

Creates only UUID-tagged synthetic rows, restores workshop configuration exactly,
and deletes every synthetic row in ``finally``. staging_conn/staging_rest refuse
any project other than the approved staging ref before this module can connect.
"""
from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from staging_accounts import ADMIN_EMAIL, ADMIN_PW, CTRL_A_EMAIL, CTRL_A_PW, VIEWER_EMAIL, VIEWER_PW
from staging_conn import get_conn
from staging_rest import rest_select, rpc, sign_in

PASS = []
FAIL = []
RUN_ID = uuid.uuid4().hex[:10]
PREFIX = f"S2A027-{RUN_ID}"
TECH_ACTIVE = str(uuid.uuid4())
TECH_INACTIVE = str(uuid.uuid4())
MISSING_TECH = str(uuid.uuid4())
VEHICLES = [str(uuid.uuid4()) for _ in range(4)]
BOOKINGS = []
ORIGINAL_LEAVE = None


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def token(email, password):
    status, body = sign_in(email, password)
    if status != 200:
        raise RuntimeError(f"staging sign-in failed for {email}: {status} {body}")
    return body["access_token"]


def db_row(sql, params=()):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        row = cur.fetchone()
        conn.commit()
        return row
    finally:
        conn.close()


def setup_fixtures():
    global ORIGINAL_LEAVE
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("select id from auth.users where email = %s", (ADMIN_EMAIL,))
        admin_id = cur.fetchone()[0]
        cur.execute(
            "insert into public.workshop_technicians(id, name, role_type, active) values (%s, %s, 'technician', true)",
            (TECH_ACTIVE, PREFIX + " Active Technician"),
        )
        cur.execute(
            "insert into public.workshop_technicians(id, name, role_type, active) values (%s, %s, 'technician', false)",
            (TECH_INACTIVE, PREFIX + " Inactive Technician"),
        )
        for index, vehicle_id in enumerate(VEHICLES, 1):
            cur.execute(
                "insert into public.vehicles(id, permanent_vehicle_id, stock_number, customer_name, visible_on_board, current_location, created_by, updated_by) "
                "values (%s, %s, %s, %s, false, 'PMB', %s, %s)",
                (vehicle_id, f"{PREFIX}-PERM-{index}", f"{PREFIX}-STK-{index}", PREFIX + " Synthetic", admin_id, admin_id),
            )
        cur.execute("select value, version, updated_by, updated_at from public.workshop_settings where key = 'technician_leave' for update")
        ORIGINAL_LEAVE = cur.fetchone()
        conn.commit()
    finally:
        conn.close()


def set_leave(dates):
    conn = get_conn()
    try:
        cur = conn.cursor()
        value = list(ORIGINAL_LEAVE[0]) + [{"technician_id": TECH_ACTIVE, "date": date} for date in dates]
        cur.execute("update public.workshop_settings set value = %s::jsonb where key = 'technician_leave'", (json.dumps(value),))
        conn.commit()
    finally:
        conn.close()


def booking_state(booking_id):
    return db_row(
        "select version, scheduled_start_at, scheduled_end_at, status from public.workshop_bookings where id = %s",
        (booking_id,),
    )


def cleanup():
    conn = get_conn()
    try:
        cur = conn.cursor()
        if ORIGINAL_LEAVE is not None:
            cur.execute(
                "update public.workshop_settings set value = %s::jsonb, version = %s, updated_by = %s, updated_at = %s where key = 'technician_leave'",
                (json.dumps(ORIGINAL_LEAVE[0]), ORIGINAL_LEAVE[1], ORIGINAL_LEAVE[2], ORIGINAL_LEAVE[3]),
            )
        cur.execute("update public.vehicles set active_workshop_booking_id = null where id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.workshop_parts_overrides where vehicle_id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.workshop_booking_history where booking_id in (select id from public.workshop_bookings where vehicle_id = any(%s::uuid[]))", (VEHICLES,))
        cur.execute("delete from public.workshop_booking_assignments where booking_id in (select id from public.workshop_bookings where vehicle_id = any(%s::uuid[]))", (VEHICLES,))
        cur.execute("delete from public.workshop_bookings where vehicle_id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.vehicle_work_items where vehicle_id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.vehicle_parts_updates where vehicle_id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.vehicle_movements where vehicle_id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.audit_events where vehicle_id = any(%s::uuid[]) or before_data::text like %s or after_data::text like %s or metadata::text like %s", (VEHICLES, f"%{PREFIX}%", f"%{PREFIX}%", f"%{PREFIX}%"))
        cur.execute("delete from public.vehicles where id = any(%s::uuid[])", (VEHICLES,))
        cur.execute("delete from public.workshop_technicians where id = any(%s::uuid[])", ([TECH_ACTIVE, TECH_INACTIVE],))
        conn.commit()
    finally:
        conn.close()


def zero_fixture_count():
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "select "
            "(select count(*) from public.vehicles where permanent_vehicle_id like %s) + "
            "(select count(*) from public.workshop_technicians where name like %s) + "
            "(select count(*) from public.workshop_bookings where vehicle_id = any(%s::uuid[])) + "
            "(select count(*) from public.workshop_booking_assignments where technician_id = any(%s::uuid[]))",
            (PREFIX + "%", PREFIX + "%", VEHICLES, [TECH_ACTIVE, TECH_INACTIVE]),
        )
        return int(cur.fetchone()[0])
    finally:
        conn.close()


def window_validation(admin):
    status, config = rpc(admin, "get_workshop_configuration", {})
    check("configuration is readable", status == 200 and isinstance(config, dict), (status, config))
    cases = [
        ("break_windows", [{"start": "10:00", "end": "10:15", "date": "2097-02-30"}], "window_date_not_valid_iso_date"),
        ("overtime_windows", [{"start": "17:00", "end": "18:00", "scope": "holiday"}], "window_scope_unknown"),
        ("break_windows", [{"start": "10:00", "end": "10:15", "day": "noday"}], "window_day_unknown"),
        ("overtime_windows", [{"start": "17:00", "end": "18:00", "scope": "monday", "day": "tuesday"}], "window_scope_day_conflict"),
    ]
    for key, value, reason in cases:
        status, body = rpc(admin, "update_workshop_configuration", {
            "p_key": key,
            "p_expected_version": int(config[key]["version"]),
            "p_value": value,
        })
        check(f"{key} rejects {reason} structurally", status == 200 and body.get("ok") is False and body.get("reason") == reason, (status, body))


def schedule(admin, vehicle_id, start, technician_id, bay=1, duration=60):
    return rpc(admin, "schedule_vehicle_work", {
        "p_vehicle_id": vehicle_id,
        "p_vehicle_expected_version": 1,
        "p_stage_code": "HOIST",
        "p_bay_number": bay,
        "p_scheduled_start_at": start,
        "p_duration_minutes": duration,
        "p_technician_id": technician_id,
    })


def assignment_and_interval_enforcement(admin, operator, viewer):
    active_name = PREFIX + " Active Technician"
    status, body = schedule(operator, VEHICLES[0], "2097-03-01T09:00:00+08:00", TECH_ACTIVE)
    check("new booking with selected active technician succeeds", status == 200 and body.get("ok") is True, (status, body))
    booking_id = body.get("booking", {}).get("booking_id")
    if booking_id:
        BOOKINGS.append(booking_id)
    assignment = body.get("booking", {}).get("assignment", {})
    check("selected technician UUID persists", assignment.get("technician_id") == TECH_ACTIVE, assignment)
    check("selected technician name persists", assignment.get("technician_name") == active_name, assignment)

    status, snapshot = rpc(operator, "get_workshop_snapshot", {"p_date_from": "2097-03-01", "p_date_to": "2097-03-06"})
    snap_booking = next((row for row in snapshot.get("bookings", []) if row.get("booking_id") == booking_id), {}) if isinstance(snapshot, dict) else {}
    check("authoritative snapshot retains selected technician", snap_booking.get("assignment", {}).get("technician_id") == TECH_ACTIVE and snap_booking.get("assignment", {}).get("technician_name") == active_name, snap_booking)

    status, body = schedule(operator, VEHICLES[1], "2097-03-04T09:00:00+08:00", MISSING_TECH)
    check("unresolved technician UUID cannot be scheduled", status == 200 and body.get("ok") is False and body.get("error") == "technician_not_found", (status, body))
    status, body = schedule(operator, VEHICLES[2], "2097-03-05T09:00:00+08:00", TECH_INACTIVE)
    check("inactive technician cannot be scheduled", status == 200 and body.get("ok") is False and body.get("error") == "technician_inactive", (status, body))

    state = booking_state(booking_id)
    status, body = rpc(operator, "move_workshop_booking", {
        "p_booking_id": booking_id, "p_expected_version": state[0], "p_stage_code": "HOIST", "p_bay_number": 1,
        "p_scheduled_start_at": "2097-03-02T09:00:00+08:00", "p_duration_minutes": 60,
    })
    check("ordinary assigned move still succeeds", status == 200 and body.get("ok") is True, (status, body))
    state = booking_state(booking_id)
    status, body = rpc(operator, "resize_workshop_booking", {
        "p_booking_id": booking_id, "p_expected_version": state[0], "p_duration_minutes": 75,
    })
    check("ordinary assigned resize still succeeds", status == 200 and body.get("ok") is True, (status, body))

    resume_date = db_row("select to_char((public.workshop_normalize_start_date(now()) at time zone 'Australia/Brisbane')::date, 'YYYY-MM-DD')")[0]
    set_leave(["2097-03-03", resume_date])

    status, body = schedule(operator, VEHICLES[3], "2097-03-03T09:00:00+08:00", TECH_ACTIVE, bay=2)
    check("technician on leave cannot be scheduled", status == 200 and body.get("ok") is False and body.get("error") == "technician_on_leave", (status, body))

    before = booking_state(booking_id)
    status, body = rpc(operator, "move_workshop_booking", {
        "p_booking_id": booking_id, "p_expected_version": before[0], "p_stage_code": "HOIST", "p_bay_number": 1,
        "p_scheduled_start_at": "2097-03-03T09:00:00+08:00", "p_duration_minutes": 75,
    })
    after = booking_state(booking_id)
    check("move onto technician leave is rejected", status == 200 and body.get("ok") is False and body.get("error") == "technician_on_leave", (status, body))
    check("rejected leave move changes no booking interval/version", after == before, (before, after))

    status, body = rpc(operator, "resize_workshop_booking", {
        "p_booking_id": booking_id, "p_expected_version": before[0], "p_duration_minutes": 960,
    })
    after_resize = booking_state(booking_id)
    check("resize across technician leave is rejected", status == 200 and body.get("ok") is False and body.get("error") == "technician_on_leave", (status, body))
    check("rejected leave resize changes no booking interval/version", after_resize == before, (before, after_resize))

    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("update public.workshop_bookings set status = 'stoppage', stoppage_started_at = now() where id = %s", (booking_id,))
        conn.commit()
    finally:
        conn.close()
    stopped = booking_state(booking_id)
    status, body = rpc(operator, "resume_workshop_work", {"p_booking_id": booking_id, "p_expected_version": stopped[0], "p_metadata": {}})
    after_resume = booking_state(booking_id)
    check("resume/reschedule across technician leave is rejected", status == 200 and body.get("ok") is False and body.get("error") == "technician_on_leave", (status, body))
    check("rejected leave resume changes no booking interval/version", after_resume == stopped, (stopped, after_resume))

    status, rows = rest_select(viewer, "workshop_technicians", f"?select=id&id=eq.{TECH_INACTIVE}")
    check("direct viewer inactive technician restriction is unchanged", status == 200 and rows == [], (status, rows))


if __name__ == "__main__":
    admin_token = token(ADMIN_EMAIL, ADMIN_PW)
    operator_token = token(CTRL_A_EMAIL, CTRL_A_PW)
    viewer_token = token(VIEWER_EMAIL, VIEWER_PW)
    setup_fixtures()
    try:
        window_validation(admin_token)
        assignment_and_interval_enforcement(admin_token, operator_token, viewer_token)
    finally:
        cleanup()
    remaining = zero_fixture_count()
    check("cleanup leaves zero synthetic fixtures", remaining == 0, remaining)
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        raise SystemExit(1)
