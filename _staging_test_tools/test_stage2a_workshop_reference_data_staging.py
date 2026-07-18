"""
Real (non-mocked) staging tests for Stage 2A -- shared workshop
lookup/configuration data (mechanics, salespeople, sublet providers,
workshop bays, workshop configuration).

Requires the standard staging environment variables (see
_staging_test_tools/.env.example). Every test exercises the real REST
API against real staging Postgres data -- no mocks.
"""
import sys
import os
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from staging_conn import get_conn
from staging_rest import sign_in, rpc, admin_create_user, admin_delete_user, rest_insert
from staging_accounts import ADMIN_EMAIL, ADMIN_PW, CTRL_A_EMAIL, CTRL_A_PW, VIEWER_EMAIL, VIEWER_PW

PASS = []
FAIL = []

CONTROLLER_EMAIL = CTRL_A_EMAIL
CONTROLLER_PW = CTRL_A_PW


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def cleanup_test_rows():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("delete from public.workshop_technicians where name like 'Stage2A Test%'")
    cur.execute("delete from public.salespeople where name like 'Stage2A Test%'")
    cur.execute("delete from public.sublet_providers where name like 'Stage2A Test%'")
    conn.commit()
    conn.close()


def test_technician_crud():
    admin_status, admin_body = sign_in(ADMIN_EMAIL, ADMIN_PW)
    check("1a admin sign-in succeeds", admin_status == 200, admin_body)
    admin_token = admin_body["access_token"]

    unique = uuid.uuid4().hex[:8]
    name = f"Stage2A Test Mechanic {unique}"

    status, body = rpc(admin_token, "add_technician", {"p_name": name, "p_role_type": "technician"})
    check("1b add_technician succeeds", status == 200 and body.get("ok") is True, body)
    tech_id = body["technician"]["id"]
    tech_version = body["technician"]["version"]

    status, body = rpc(admin_token, "add_technician", {"p_name": name})
    check("1c duplicate name rejected", status == 200 and body.get("ok") is False and body.get("error") == "duplicate_name", body)

    status, body = rpc(admin_token, "edit_technician", {
        "p_technician_id": tech_id, "p_expected_version": tech_version, "p_role_type": "provider",
    })
    check("1d edit_technician succeeds", status == 200 and body.get("ok") is True and body["technician"]["role_type"] == "provider", body)
    tech_version = body["technician"]["version"]

    status, body = rpc(admin_token, "edit_technician", {
        "p_technician_id": tech_id, "p_expected_version": 1, "p_role_type": "technician",
    })
    check("1e stale version rejected", status == 200 and body.get("ok") is False and body.get("error") == "version_conflict", body)

    status, body = rpc(admin_token, "set_technician_active", {
        "p_technician_id": tech_id, "p_expected_version": tech_version, "p_active": False,
    })
    check("1f deactivate succeeds", status == 200 and body.get("ok") is True and body["technician"]["active"] is False, body)
    tech_version = body["technician"]["version"]

    status, body = rpc(admin_token, "list_technicians", {"p_include_inactive": False})
    ids = [row["id"] for row in body] if status == 200 else []
    check("1g deactivated technician excluded from active-only list", tech_id not in ids, body)

    status, body = rpc(admin_token, "list_technicians", {"p_include_inactive": True})
    ids = [row["id"] for row in body] if status == 200 else []
    check("1h deactivated technician still present in include-inactive list", tech_id in ids, body)

    # Role restriction checks
    controller_status, controller_body = sign_in(CONTROLLER_EMAIL, CONTROLLER_PW)
    check("1i controller sign-in succeeds", controller_status == 200, controller_body)
    controller_token = controller_body["access_token"]

    status, body = rpc(controller_token, "add_technician", {"p_name": f"Stage2A Test Controller Add {unique}"})
    check("1j controller (operator) cannot add_technician", status == 403 and body.get("code") == "42501", body)

    status, body = rpc(controller_token, "list_technicians", {})
    check("1k controller CAN list_technicians (read)", status == 200 and isinstance(body, list), body)

    viewer_status, viewer_body = sign_in(VIEWER_EMAIL, VIEWER_PW)
    check("1l viewer sign-in succeeds", viewer_status == 200, viewer_body)
    viewer_token = viewer_body["access_token"]

    status, body = rpc(viewer_token, "add_technician", {"p_name": f"Stage2A Test Viewer Add {unique}"})
    check("1m viewer cannot add_technician", status == 403 and body.get("code") == "42501", body)

    status, body = rpc(viewer_token, "set_technician_active", {
        "p_technician_id": tech_id, "p_expected_version": tech_version, "p_active": True,
    })
    check("1n viewer cannot set_technician_active", status == 403 and body.get("code") == "42501", body)

    status, body = rpc(viewer_token, "list_technicians", {})
    check("1o viewer CAN list_technicians (read)", status == 200 and isinstance(body, list), body)


def test_direct_table_write_blocked():
    admin_status, admin_body = sign_in(ADMIN_EMAIL, ADMIN_PW)
    admin_token = admin_body["access_token"]
    status, body = rest_insert(admin_token, "workshop_technicians", {"name": "Stage2A Test Direct Write Attempt"})
    check("2a direct REST insert into workshop_technicians blocked even for administrator", status in (401, 403), (status, body))

    status, body = rest_insert(admin_token, "salespeople", {"name": "Stage2A Test Direct Write Attempt"})
    check("2b direct REST insert into salespeople blocked even for administrator (grant revoked in migration 022)", status in (401, 403), (status, body))


def test_audit_created():
    admin_status, admin_body = sign_in(ADMIN_EMAIL, ADMIN_PW)
    admin_token = admin_body["access_token"]
    unique = uuid.uuid4().hex[:8]
    name = f"Stage2A Test Audit {unique}"
    status, body = rpc(admin_token, "add_technician", {"p_name": name})
    check("3a add_technician for audit test succeeds", status == 200 and body.get("ok"), body)
    tech_id = body["technician"]["id"]

    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        "select action, table_name, row_id, metadata from public.audit_events "
        "where table_name = 'workshop_technicians' and row_id = %s order by created_at desc limit 1",
        (tech_id,),
    )
    row = cur.fetchone()
    conn.close()
    check("3b audit_events row created for add_technician", row is not None and row[0] == "reference_change", row)


def test_salespeople_and_sublet_providers():
    admin_status, admin_body = sign_in(ADMIN_EMAIL, ADMIN_PW)
    admin_token = admin_body["access_token"]
    unique = uuid.uuid4().hex[:8]

    status, body = rpc(admin_token, "add_salesperson", {"p_name": f"Stage2A Test Sales {unique}", "p_email": f"stage2a.{unique}@example.com", "p_code": f"S2A{unique[:3]}"})
    check("4a add_salesperson succeeds", status == 200 and body.get("ok"), body)
    sp_id, sp_version = body["salesperson"]["id"], body["salesperson"]["version"]

    status, body = rpc(admin_token, "add_salesperson", {"p_name": f"Stage2A Test Sales {unique}"})
    check("4b duplicate salesperson name rejected", status == 200 and body.get("error") == "duplicate_name", body)

    status, body = rpc(admin_token, "edit_salesperson", {"p_salesperson_id": sp_id, "p_expected_version": sp_version, "p_email": "not-an-email"})
    check("4c invalid email rejected", status == 200 and body.get("error") == "invalid_email", body)

    status, body = rpc(admin_token, "add_sublet_provider", {"p_name": f"Stage2A Test Provider {unique}", "p_phone": "0400000000"})
    check("4d add_sublet_provider succeeds", status == 200 and body.get("ok"), body)
    provider_id, provider_version = body["provider"]["id"], body["provider"]["version"]

    status, body = rpc(admin_token, "set_sublet_provider_active", {"p_provider_id": provider_id, "p_expected_version": provider_version, "p_active": False})
    check("4e deactivate sublet provider succeeds", status == 200 and body.get("ok") and body["provider"]["active"] is False, body)


def test_workshop_bays_and_configuration():
    admin_status, admin_body = sign_in(ADMIN_EMAIL, ADMIN_PW)
    admin_token = admin_body["access_token"]

    status, body = rpc(admin_token, "list_workshop_bays", {})
    check("5a list_workshop_bays returns real bays", status == 200 and len(body) > 0, body)

    status, body = rpc(admin_token, "get_workshop_configuration", {})
    check("5b get_workshop_configuration returns known keys", status == 200 and "day_start_time" in body, body)

    day_start = body["day_start_time"]
    status, body2 = rpc(admin_token, "update_workshop_configuration", {
        "p_key": "day_start_time", "p_expected_version": day_start["version"], "p_value": day_start["value"],
    })
    check("5c update_workshop_configuration succeeds with unchanged value (round-trip)", status == 200 and body2.get("ok"), body2)

    status, body3 = rpc(admin_token, "update_workshop_configuration", {
        "p_key": "day_start_time", "p_expected_version": day_start["version"], "p_value": day_start["value"],
    })
    check("5d stale version rejected on second attempt with old version", status == 200 and body3.get("ok") is False and body3.get("error") == "version_conflict", body3)

    status, body4 = rpc(admin_token, "update_workshop_configuration", {
        "p_key": "not_a_real_key", "p_expected_version": 1, "p_value": "x",
    })
    check("5e unknown setting key rejected", status == 200 and body4.get("error") == "unknown_setting_key", body4)

    status, body5 = rpc(admin_token, "update_workshop_configuration", {
        "p_key": "day_start_time", "p_expected_version": body2["setting"]["version"], "p_value": 12345,
    })
    check("5f wrong value shape rejected (number instead of string)", status == 200 and body5.get("error") == "invalid_value_shape", body5)

    controller_status, controller_body = sign_in(CONTROLLER_EMAIL, CONTROLLER_PW)
    controller_token = controller_body["access_token"]
    status, body6 = rpc(controller_token, "update_workshop_configuration", {
        "p_key": "day_start_time", "p_expected_version": body2["setting"]["version"], "p_value": day_start["value"],
    })
    check("5g controller (operator) cannot update_workshop_configuration", status == 403 and body6.get("code") == "42501", body6)


def test_historical_booking_retains_inactive_technician():
    admin_status, admin_body = sign_in(ADMIN_EMAIL, ADMIN_PW)
    admin_token = admin_body["access_token"]
    unique = uuid.uuid4().hex[:8]
    name = f"Stage2A Test Historical {unique}"
    status, body = rpc(admin_token, "add_technician", {"p_name": name})
    check("6a add technician for historical test succeeds", status == 200 and body.get("ok"), body)
    tech_id, tech_version = body["technician"]["id"], body["technician"]["version"]

    conn = get_conn()
    cur = conn.cursor()
    cur.execute("select id from public.workshop_bookings where deleted_at is null limit 1")
    row = cur.fetchone()
    booking_id = row[0] if row else None
    conn.close()

    if booking_id is None:
        check("6b (skipped) no active booking exists in staging to attach a historical technician reference to", True, "skipped -- not a failure")
        return

    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        "insert into public.workshop_booking_assignments (booking_id, technician_id, assignment_type, assigned_at, assigned_by, scheduled_start_at, scheduled_end_at) "
        "values (%s, %s, 'primary', now(), (select id from auth.users where email = %s), now(), now() + interval '1 hour') returning id",
        (booking_id, tech_id, ADMIN_EMAIL),
    )
    assignment_id = cur.fetchone()[0]
    conn.commit()
    conn.close()

    status, body = rpc(admin_token, "set_technician_active", {"p_technician_id": tech_id, "p_expected_version": tech_version, "p_active": False})
    check("6c deactivate the now-historically-assigned technician succeeds", status == 200 and body.get("ok"), body)

    conn = get_conn()
    cur = conn.cursor()
    cur.execute("select technician_id from public.workshop_booking_assignments where id = %s", (assignment_id,))
    row = cur.fetchone()
    cur.execute("delete from public.workshop_booking_assignments where id = %s", (assignment_id,))
    conn.commit()
    conn.close()
    check("6d historical assignment still references the real (now-inactive) technician_id after deactivation", row is not None and row[0] == tech_id, row)


if __name__ == "__main__":
    cleanup_test_rows()
    test_technician_crud()
    test_direct_table_write_blocked()
    test_audit_created()
    test_salespeople_and_sublet_providers()
    test_workshop_bays_and_configuration()
    test_historical_booking_retains_inactive_technician()
    cleanup_test_rows()
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)
