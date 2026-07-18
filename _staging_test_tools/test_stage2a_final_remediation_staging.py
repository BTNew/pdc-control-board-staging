"""Live staging-only checks for migration 026.

Uses synthetic reference rows and fully restores workshop settings. The helper
modules refuse any non-staging project before this file imports.
"""
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from staging_conn import get_conn
from staging_rest import rest_select, rpc, sign_in
from staging_accounts import ADMIN_EMAIL, ADMIN_PW, CTRL_A_EMAIL, CTRL_A_PW, VIEWER_EMAIL, VIEWER_PW

PASS = []
FAIL = []
PREFIX = f"Stage2A Final {uuid.uuid4().hex[:8]}"


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


def create_inactive_rows():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("insert into public.workshop_technicians(name, role_type, active) values (%s, 'technician', false) returning id", (PREFIX + " Technician",))
    technician = str(cur.fetchone()[0])
    cur.execute("insert into public.salespeople(name, active) values (%s, false) returning id", (PREFIX + " Salesperson",))
    salesperson = str(cur.fetchone()[0])
    cur.execute("insert into public.sublet_providers(name, active) values (%s, false) returning id", (PREFIX + " Provider",))
    provider = str(cur.fetchone()[0])
    cur.execute("select id from public.workshop_stages where active order by sort_order limit 1")
    stage_id = cur.fetchone()[0]
    cur.execute("insert into public.workshop_bays(stage_id, code, display_name, is_active) values (%s, %s, %s, false) returning id", (stage_id, "S2F-" + uuid.uuid4().hex[:7].upper(), PREFIX + " Bay"))
    bay = str(cur.fetchone()[0])
    conn.commit()
    conn.close()
    return {
        "workshop_technicians": technician,
        "salespeople": salesperson,
        "sublet_providers": provider,
        "workshop_bays": bay,
    }


def cleanup(rows, technician_id=None, booking_id=None):
    conn = get_conn()
    cur = conn.cursor()
    for table, row_id in rows.items():
        cur.execute(f"delete from public.{table} where id = %s", (row_id,))
    if booking_id:
        cur.execute("delete from public.workshop_bookings where id = %s", (booking_id,))
    if technician_id:
        cur.execute("delete from public.workshop_technicians where id = %s", (technician_id,))
    conn.commit()
    conn.close()


def direct_role_matrix(admin, operator, viewer, rows):
    for table, row_id in rows.items():
        status, body = rest_select(viewer, table, f"?select=id&id=eq.{row_id}")
        check(f"viewer direct REST hides inactive {table}", status == 200 and body == [], (status, body))
        status, body = rest_select(operator, table, f"?select=id&id=eq.{row_id}")
        check(f"operator direct REST can read inactive {table}", status == 200 and any(str(row.get('id')) == row_id for row in body), (status, body))
        status, body = rest_select(admin, table, f"?select=id&id=eq.{row_id}")
        check(f"administrator direct REST can read inactive {table}", status == 200 and any(str(row.get('id')) == row_id for row in body), (status, body))

    for fn, key in [
        ("list_technicians", "workshop_technicians"),
        ("list_salespeople", "salespeople"),
        ("list_sublet_providers", "sublet_providers"),
        ("list_workshop_bays", "workshop_bays"),
    ]:
        status, body = rpc(viewer, fn, {"p_include_inactive": True})
        ids = {str(row.get("id")) for row in body} if status == 200 and isinstance(body, list) else set()
        check(f"viewer {fn} cannot expose inactive rows", status == 200 and rows[key] not in ids, (status, body))


def strict_validation(admin):
    status, config = rpc(admin, "get_workshop_configuration", {})
    check("configuration available for strict validation", status == 200 and isinstance(config, dict), (status, config))
    leave_version = int(config["technician_leave"]["version"])
    status, body = rpc(admin, "update_workshop_configuration", {
        "p_key": "technician_leave", "p_expected_version": leave_version,
        "p_value": [{"technician_id": "not-a-uuid", "date": "2026-07-20"}],
    })
    check("malformed technician UUID returns a structured validation error", status == 200 and body.get("ok") is False and body.get("error") == "invalid_value" and body.get("reason") == "leave_technician_id_not_valid_uuid", (status, body))

    closure_version = int(config["closures"]["version"])
    for value in ("2026-2-03", "2026-02-31"):
        status, body = rpc(admin, "update_workshop_configuration", {
            "p_key": "closures", "p_expected_version": closure_version,
            "p_value": [{"date": value}],
        })
        check(f"non-exact/non-roundtrip date {value} returns a structured validation error", status == 200 and body.get("ok") is False and body.get("error") == "invalid_value" and body.get("reason") == "closure_date_not_valid_iso_date", (status, body))


def leave_rpc_enforcement(admin):
    status, created = rpc(admin, "add_technician", {"p_name": PREFIX + " Leave RPC"})
    check("synthetic active technician created", status == 200 and created.get("ok") is True, (status, created))
    technician_id = created["technician"]["id"]

    conn = get_conn()
    cur = conn.cursor()
    cur.execute("select id from public.vehicles order by created_at limit 1")
    vehicle_id = cur.fetchone()[0]
    cur.execute("select id from public.workshop_stages where active order by sort_order limit 1")
    stage_id = cur.fetchone()[0]
    cur.execute("select id from auth.users where email = %s", (ADMIN_EMAIL,))
    admin_id = cur.fetchone()[0]
    leave_date = "2098-03-03"
    cur.execute(
        "insert into public.workshop_bookings(vehicle_id, stage_id, scheduled_start_at, scheduled_end_at, default_duration_minutes, created_by, updated_by) "
        "values (%s, %s, %s::date + time '09:00', %s::date + time '10:00', 60, %s, %s) returning id, version",
        (vehicle_id, stage_id, leave_date, leave_date, admin_id, admin_id),
    )
    booking_row = cur.fetchone()
    conn.commit()
    conn.close()
    booking = (booking_row[0], booking_row[1], leave_date)

    status, config = rpc(admin, "get_workshop_configuration", {})
    original_leave = config["technician_leave"]["value"]
    leave_version = int(config["technician_leave"]["version"])
    synthetic_leave = list(original_leave) + [{"technician_id": technician_id, "date": booking[2]}]
    status, updated = rpc(admin, "update_workshop_configuration", {
        "p_key": "technician_leave", "p_expected_version": leave_version, "p_value": synthetic_leave,
    })
    check("synthetic technician leave applied", status == 200 and updated.get("ok") is True, (status, updated))
    if not updated.get("ok"):
        return technician_id

    try:
        status, denied = rpc(admin, "assign_booking_technician", {
            "p_booking_id": str(booking[0]), "p_expected_version": int(booking[1]),
            "p_technician_id": technician_id,
            "p_metadata": {},
        })
        check("assignment RPC returns structured technician_on_leave", status == 200 and denied.get("ok") is False and denied.get("error") == "technician_on_leave" and denied.get("technician_id") == technician_id, (status, denied))
    finally:
        status, restored = rpc(admin, "update_workshop_configuration", {
            "p_key": "technician_leave", "p_expected_version": int(updated["setting"]["version"]), "p_value": original_leave,
        })
        check("technician leave setting fully restored", status == 200 and restored.get("ok") is True, (status, restored))
    return technician_id, str(booking[0])


if __name__ == "__main__":
    admin = token(ADMIN_EMAIL, ADMIN_PW)
    operator = token(CTRL_A_EMAIL, CTRL_A_PW)
    viewer = token(VIEWER_EMAIL, VIEWER_PW)
    rows = create_inactive_rows()
    technician_id = None
    booking_id = None
    try:
        direct_role_matrix(admin, operator, viewer, rows)
        strict_validation(admin)
        technician_id, booking_id = leave_rpc_enforcement(admin)
    finally:
        cleanup(rows, technician_id, booking_id)
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        raise SystemExit(1)
