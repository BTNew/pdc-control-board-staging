"""
Real (non-mocked) staging integration tests for the account
registration/approval workflow (migration 018). Runs directly against
real staging Postgres and the real staging Supabase Auth REST API --
signup, email confirmation (via admin API, simulating a clicked
confirmation link), sign-in, RLS-enforced direct API access, and every
protected admin RPC (approve/reject/change-role/disable/restore),
including the last-administrator protection and the audit trail.

Never touches production. Cleans up every synthetic account it creates.
"""
import sys
import uuid

sys.path.insert(0, ".")
from staging_conn import get_conn
from staging_rest import _req, ANON_KEY, SERVICE_KEY, admin_create_user, admin_delete_user, sign_in, rpc
from staging_accounts import ADMIN_EMAIL, ADMIN_PASSWORD

TEMP_TEST_PASSWORD = "ReviewTemp!" + uuid.uuid4().hex + "aA1"

created_auth_ids = []


def cleanup():
    conn = get_conn()
    cur = conn.cursor()
    for email in (
        "pdc-account-test-1@gmail.com",
        "pdc-account-test-2@gmail.com",
        "pdc-account-test-3@gmail.com",
    ):
        cur.execute("select auth_user_id from public.pdc_user_roles where email=%s", (email,))
        row = cur.fetchone()
        if row and row[0]:
            admin_delete_user(str(row[0]))
        cur.execute("delete from public.audit_events where metadata->>'target_email' = %s", (email,))
        cur.execute("delete from public.pdc_user_roles where email=%s", (email,))
    conn.commit()
    conn.close()


def test_signup_creates_pending_no_role_account():
    status, body = admin_create_user("pdc-account-test-1@gmail.com", TEMP_TEST_PASSWORD, email_confirm=False)
    assert status == 200, body
    auth_id = body["id"]

    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        "select role, active, account_status, auth_user_id from public.pdc_user_roles where email=%s",
        ("pdc-account-test-1@gmail.com",),
    )
    row = cur.fetchone()
    conn.close()
    assert row is not None, "trigger did not create a pdc_user_roles row"
    role, active, status_val, stored_auth_id = row
    assert role is None, f"expected role NULL for a new self-registration, got {role}"
    assert active is False
    assert status_val == "pending"
    assert str(stored_auth_id) == auth_id
    print("PASS  1a signup trigger creates a pending, role=NULL, inactive account row")


def test_unconfirmed_user_cannot_sign_in():
    status, body = _req(
        "POST", "/auth/v1/token?grant_type=password",
        headers={"apikey": ANON_KEY, "Content-Type": "application/json"},
        body={"email": "pdc-account-test-1@gmail.com", "password": TEMP_TEST_PASSWORD},
    )
    assert status == 400 and body.get("error_code") == "email_not_confirmed", body
    print("PASS  2a unconfirmed email cannot sign in")


def test_confirmed_pending_user_sees_zero_operational_rows():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("select auth_user_id from public.pdc_user_roles where email=%s", ("pdc-account-test-1@gmail.com",))
    auth_id = str(cur.fetchone()[0])
    conn.close()

    status, body = _req(
        "PUT", f"/auth/v1/admin/users/{auth_id}",
        headers={"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"},
        body={"email_confirm": True},
    )
    assert status == 200, body

    status2, body2 = sign_in("pdc-account-test-1@gmail.com", TEMP_TEST_PASSWORD)
    assert status2 == 200, body2
    token = body2["access_token"]

    status3, body3 = _req(
        "GET", "/rest/v1/vehicles?select=id,stock_number,customer_name",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {token}"},
    )
    assert status3 == 200 and body3 == [], f"pending user must see zero vehicle rows, got {body3}"

    status4, body4 = _req(
        "GET", "/rest/v1/vehicle_timeline_events?select=id",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {token}"},
    )
    assert status4 == 200 and body4 == [], f"pending user must see zero timeline rows, got {body4}"

    status5, body5 = _req(
        "GET", "/rest/v1/audit_events?select=id",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {token}"},
    )
    assert status5 == 200 and body5 == [], f"pending user must see zero audit rows, got {body5}"

    status6, body6 = rpc(token, "current_pdc_account_status", {})
    assert status6 == 200 and body6 == "pending", (status6, body6)

    return token


def test_pending_user_cannot_call_operational_or_self_approve_rpc(token):
    status, body = rpc(token, "move_vehicle", {
        "p_vehicle_id": "00000000-0000-0000-0000-000000000000",
        "p_expected_version": 1,
        "p_to_location": "test",
    })
    assert status == 403 and body.get("code") == "42501", body

    status2, body2 = rpc(token, "admin_approve_user", {
        "p_target_email": "pdc-account-test-1@gmail.com", "p_role": "administrator",
    })
    assert status2 == 403 and body2.get("code") == "42501", body2
    print("PASS  3a/3b pending user: zero operational rows via direct API, cannot call "
          "operational RPCs, cannot self-approve")


def test_admin_approve_sets_role_and_grants_access():
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    admin_token = body["access_token"]

    status2, body2 = rpc(admin_token, "admin_approve_user", {
        "p_target_email": "pdc-account-test-1@gmail.com", "p_role": "viewer", "p_notes": "test approval",
    })
    assert status2 == 200 and body2["role"] == "viewer" and body2["active"] is True, body2
    assert body2["account_status"] == "approved"

    status3, body3 = sign_in("pdc-account-test-1@gmail.com", TEMP_TEST_PASSWORD)
    token = body3["access_token"]
    status4, body4 = _req(
        "GET", "/rest/v1/vehicles?select=id",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {token}"},
    )
    assert status4 == 200 and len(body4) > 0, "approved viewer should see vehicle rows"
    print("PASS  4a admin_approve_user sets role + grants real read access")
    return token


def test_viewer_cannot_write(viewer_token):
    status, body = rpc(viewer_token, "move_vehicle", {
        "p_vehicle_id": "00000000-0000-0000-0000-000000000000",
        "p_expected_version": 1,
        "p_to_location": "test",
    })
    assert status == 403, body
    status2, body2 = rpc(viewer_token, "admin_change_role", {
        "p_target_email": "pdc-account-test-1@gmail.com", "p_role": "administrator",
    })
    assert status2 == 403, body2
    print("PASS  5a viewer cannot write operational data or call admin RPCs")


def test_change_role_to_controller_and_verify():
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    admin_token = body["access_token"]
    status2, body2 = rpc(admin_token, "admin_change_role", {
        "p_target_email": "pdc-account-test-1@gmail.com", "p_role": "operator", "p_reason": "promote to controller",
    })
    assert status2 == 200 and body2["role"] == "operator", body2
    print("PASS  6a admin_change_role promotes viewer to controller (operator)")


def test_disable_removes_access_and_restore_returns_it():
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    admin_token = body["access_token"]

    status2, body2 = rpc(admin_token, "admin_disable_user", {
        "p_target_email": "pdc-account-test-1@gmail.com", "p_reason": "test disable",
    })
    assert status2 == 200 and body2["account_status"] == "disabled" and body2["active"] is False, body2

    status3, body3 = sign_in("pdc-account-test-1@gmail.com", TEMP_TEST_PASSWORD)
    token = body3["access_token"]
    status4, body4 = _req(
        "GET", "/rest/v1/vehicles?select=id",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {token}"},
    )
    assert status4 == 200 and body4 == [], "disabled user must see zero operational rows"
    status5, body5 = rpc(token, "current_pdc_account_status", {})
    assert status5 == 200 and body5 == "disabled", (status5, body5)

    status6, body6 = rpc(admin_token, "admin_restore_user", {
        "p_target_email": "pdc-account-test-1@gmail.com", "p_reason": "test restore",
    })
    assert status6 == 200 and body6["account_status"] == "approved" and body6["active"] is True, body6
    assert body6["role"] == "operator", "restore must preserve the previously-assigned role"
    print("PASS  7a disable removes access + shows 'disabled' status; restore returns exact prior role")


def test_last_administrator_cannot_be_disabled_or_demoted():
    """
    Verifies the last-active-administrator protection. This staging
    project intentionally keeps two permanent administrator accounts
    (administrator@ and administrator2@) for real recovery testing, so
    this test temporarily disables the second one for the duration of
    the assertion (via the real admin_disable_user RPC, exercising the
    exact same code path a real recovery scenario would use) and restores
    it again afterward, rather than assuming only one administrator
    exists on a freshly seeded database.
    """
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    admin_token = body["access_token"]

    conn = get_conn()
    cur = conn.cursor()
    cur.execute("select email from public.pdc_user_roles where role='administrator' and active=true and email != %s", (ADMIN_EMAIL,))
    other_admins = [r[0] for r in cur.fetchall()]
    conn.close()

    for other_email in other_admins:
        status_d, body_d = rpc(admin_token, "admin_disable_user", {
            "p_target_email": other_email, "p_reason": "temporarily disabled for last-administrator protection test",
        })
        assert status_d == 200, body_d

    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("select count(*) from public.pdc_user_roles where role='administrator' and active=true")
        admin_count = cur.fetchone()[0]
        conn.close()
        assert admin_count == 1, f"expected exactly one active administrator after temporarily disabling others, found {admin_count}"

        status2, body2 = rpc(admin_token, "admin_disable_user", {"p_target_email": ADMIN_EMAIL})
        assert status2 == 403 and "last active administrator" in body2.get("message", ""), body2

        status3, body3 = rpc(admin_token, "admin_change_role", {"p_target_email": ADMIN_EMAIL, "p_role": "viewer"})
        assert status3 == 403 and "last active administrator" in body3.get("message", ""), body3
    finally:
        for other_email in other_admins:
            rpc(admin_token, "admin_restore_user", {
                "p_target_email": other_email, "p_reason": "restored after last-administrator protection test",
            })
    print("PASS  8a the last active administrator cannot be disabled or demoted by anyone, including themselves")


def test_rejection_leaves_role_null():
    status, body = admin_create_user("pdc-account-test-2@gmail.com", "RejectMe!2026abc", email_confirm=True)
    assert status == 200, body

    status2, body2 = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    admin_token = body2["access_token"]
    status3, body3 = rpc(admin_token, "admin_reject_registration", {
        "p_target_email": "pdc-account-test-2@gmail.com", "p_reason": "not a recognised staff member",
    })
    assert status3 == 200 and body3["account_status"] == "rejected" and body3["role"] is None, body3
    print("PASS  9a rejection leaves role permanently NULL, account_status='rejected'")


def test_audit_trail_records_every_change():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        "select action, metadata->>'operation' from public.audit_events "
        "where table_name='pdc_user_roles' and metadata->>'target_email' = 'pdc-account-test-1@gmail.com' "
        "order by created_at"
    )
    rows = cur.fetchall()
    conn.close()
    operations = [r[1] for r in rows]
    for expected in ("admin_approve_user", "admin_change_role", "admin_disable_user", "admin_restore_user"):
        assert expected in operations, f"missing audit record for {expected}: {operations}"
    print("PASS  10a every approve/change-role/disable/restore action recorded in audit_events")


def main():
    cleanup()
    try:
        test_signup_creates_pending_no_role_account()
        test_unconfirmed_user_cannot_sign_in()
        pending_token = test_confirmed_pending_user_sees_zero_operational_rows()
        test_pending_user_cannot_call_operational_or_self_approve_rpc(pending_token)
        viewer_token = test_admin_approve_sets_role_and_grants_access()
        test_viewer_cannot_write(viewer_token)
        test_change_role_to_controller_and_verify()
        test_disable_removes_access_and_restore_returns_it()
        test_last_administrator_cannot_be_disabled_or_demoted()
        test_rejection_leaves_role_null()
        test_audit_trail_records_every_change()
    finally:
        cleanup()
    print("\nTOTAL: all account registration/approval tests passed")


if __name__ == "__main__":
    main()
