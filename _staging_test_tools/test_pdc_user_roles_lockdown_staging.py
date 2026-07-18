"""
Real (non-mocked) direct-API test for independent-review remediation
item #6 (lock down public.pdc_user_roles direct writes).

Run against real staging Postgres/REST/Auth. Requires the tracked,
credential-free staging_conn.py and staging_rest.py helpers plus a local,
ignored .env populated from .env.example. Never commit real values.
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(__file__))
from staging_conn import get_conn
from staging_rest import sign_in, rpc, _req, ANON_KEY
from staging_accounts import ADMIN_EMAIL, ADMIN_PASSWORD, VIEWER_EMAIL

PASS = []
FAIL = []


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def test_direct_admin_write_to_pdc_user_roles_fails():
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    token = body["access_token"]

    status2, body2 = _req(
        "PATCH",
        f"/rest/v1/pdc_user_roles?email=eq.{VIEWER_EMAIL}",
        headers={
            "apikey": ANON_KEY,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        body={"role": "administrator"},
    )
    check(
        "1a a signed-in administrator's DIRECT PATCH to pdc_user_roles is rejected (permission denied)",
        status2 == 403 and body2.get("code") == "42501",
        f"got status={status2} body={json.dumps(body2)[:200]}",
    )

    status3, body3 = _req(
        "POST",
        "/rest/v1/pdc_user_roles",
        headers={
            "apikey": ANON_KEY,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        body={"email": "should-never-be-inserted@example.com", "account_status": "approved", "role": "administrator", "active": True},
    )
    check(
        "1b a signed-in administrator's DIRECT INSERT to pdc_user_roles is rejected (permission denied)",
        status3 == 403 and body3.get("code") == "42501",
        f"got status={status3} body={json.dumps(body3)[:200]}",
    )


def test_direct_admin_delete_fails():
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    token = body["access_token"]
    status2, body2 = _req(
        "DELETE",
        f"/rest/v1/pdc_user_roles?email=eq.{VIEWER_EMAIL}",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {token}"},
    )
    check(
        "2a a signed-in administrator's DIRECT DELETE on pdc_user_roles is rejected",
        status2 == 403 and body2.get("code") == "42501",
        f"got status={status2} body={json.dumps(body2)[:200]}",
    )


def test_protected_rpc_still_succeeds_and_audits():
    status, body = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
    token = body["access_token"]

    status2, body2 = rpc(token, "admin_change_role", {
        "p_target_email": VIEWER_EMAIL,
        "p_role": "viewer",
        "p_reason": "remediation regression test -- protected RPC still functions after lockdown",
    })
    check(
        "3a admin_change_role (protected RPC) still succeeds after the direct-write lockdown",
        status2 == 200 and body2.get("role") == "viewer",
        f"got status={status2} body={json.dumps(body2)[:200]}",
    )

    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        """
        select count(*) from public.audit_events
        where action = 'role_change'
          and metadata->>'target_email' = %s
          and metadata->>'reason' like %s
        """,
        (VIEWER_EMAIL, "%remediation regression test%"),
    )
    (count,) = cur.fetchone()
    conn.close()
    check(
        "3b the protected RPC's action is recorded in audit_events",
        count >= 1,
        f"found {count} matching audit rows",
    )


def test_invalid_status_role_combination_rejected_by_constraint():
    conn = get_conn()
    cur = conn.cursor()
    conn.autocommit = False
    try:
        cur.execute(
            "update public.pdc_user_roles set active = false where email = %s and account_status = 'approved'",
            (VIEWER_EMAIL,),
        )
        conn.commit()
        check("4a CHECK constraint blocks an invalid (approved, active=false) combination", False, "update unexpectedly succeeded")
    except Exception as e:
        conn.rollback()
        check(
            "4a CHECK constraint blocks an invalid (approved, active=false) combination",
            "pdc_user_roles_status_role_active_consistency" in str(e),
            str(e)[:200],
        )
    finally:
        conn.close()


if __name__ == "__main__":
    test_direct_admin_write_to_pdc_user_roles_fails()
    test_direct_admin_delete_fails()
    test_protected_rpc_still_succeeds_and_audits()
    test_invalid_status_role_combination_rejected_by_constraint()
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)
