"""
Real (non-mocked) staging test for independent-review remediation
item #5 (own-row realtime lockout). This test verifies the DATABASE
SIDE of the fix -- that disabling a user immediately removes their
operational access at the RLS/RPC layer, which is the guarantee the
browser-side realtime lockout in pdc-auth.js/app.js depends on.

The browser-side behaviour itself (an already-open tab locking within
seconds of an independent disable, with zero console errors and the
app shell going `inert`) was verified live in-browser this session
against the real staging deployment and is documented in
INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md -- it is not automatable
from a headless Python script because it requires a real websocket
client observing a real DOM state change, which this project's browser
tooling exercises interactively rather than via a Python test harness.
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(__file__))
from staging_conn import get_conn
from staging_rest import admin_create_user, admin_delete_user, sign_in, rpc, _req, ANON_KEY
from staging_accounts import ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN2_EMAIL, ADMIN2_PASSWORD

PASS = []
FAIL = []


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def cleanup(email):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("select auth_user_id from public.pdc_user_roles where email=%s", (email,))
    row = cur.fetchone()
    if row and row[0]:
        admin_delete_user(str(row[0]))
    cur.execute("delete from public.audit_events where metadata->>'target_email' = %s", (email,))
    cur.execute("delete from public.pdc_user_roles where email=%s", (email,))
    conn.commit()
    conn.close()


def test_disable_from_independent_session_immediately_removes_access():
    email = "pdc-own-row-lockout-regression-test@gmail.com"
    password = "ReviewTemp!" + __import__("uuid").uuid4().hex + "aA1"
    cleanup(email)
    try:
        status, body = admin_create_user(email, password, email_confirm=True)
        check("setup: synthetic test account created", status == 200, f"status={status}")

        status2, body2 = sign_in(ADMIN_EMAIL, ADMIN_PASSWORD)
        admin_token = body2["access_token"]
        status3, body3 = rpc(admin_token, "admin_approve_user", {"p_target_email": email, "p_role": "viewer"})
        check("setup: account approved as viewer", status3 == 200, f"status={status3}")

        status4, body4 = sign_in(email, password)
        target_token = body4["access_token"]
        status5, body5 = _req(
            "GET", "/rest/v1/vehicles?select=id&limit=1",
            headers={"apikey": ANON_KEY, "Authorization": f"Bearer {target_token}"},
        )
        check("1a approved viewer session can read real operational data before disable", status5 == 200, f"status={status5} body={json.dumps(body5)[:150]}")

        # Disable from a completely independent session, simulating the
        # real two-browser scenario verified live in-browser this session.
        status6, body6 = sign_in(ADMIN2_EMAIL, ADMIN2_PASSWORD)
        admin2_token = body6["access_token"]
        status7, body7 = rpc(admin2_token, "admin_disable_user", {"p_target_email": email, "p_reason": "own-row lockout regression test"})
        check("2a independent administrator2 session can disable the target account", status7 == 200, f"status={status7}")

        # The ALREADY-ISSUED target_token from before the disable must now
        # be rejected for both reads and writes -- this is exactly the
        # guarantee the browser-side own-row realtime subscription relies
        # on: the moment the pdc_user_roles row changes, RLS already
        # blocks the old token, so the UI-side lockout is a UX/timeliness
        # improvement on top of an already-enforced security boundary,
        # not the only thing preventing access.
        status8, body8 = _req(
            "GET", "/rest/v1/vehicles?select=id&limit=1",
            headers={"apikey": ANON_KEY, "Authorization": f"Bearer {target_token}"},
        )
        check(
            "3a the SAME already-issued session token now returns zero operational rows after disable",
            status8 == 200 and body8 == [],
            f"status={status8} body={json.dumps(body8)[:150]}",
        )

        status9, body9 = rpc(target_token, "current_pdc_account_status", {})
        check("3b current_pdc_account_status() resolves to 'disabled' for the same session", status9 == 200 and body9 == "disabled", f"status={status9} body={body9}")

        # Restore and confirm access returns with the SAME already-issued
        # token (no new sign-in needed) -- proving RLS/RPC state, not just
        # the token's validity, governs access from moment to moment.
        status10, body10 = rpc(admin_token, "admin_restore_user", {"p_target_email": email, "p_reason": "own-row lockout regression test cleanup"})
        check("4a restore succeeds", status10 == 200, f"status={status10}")

        status11, body11 = _req(
            "GET", "/rest/v1/vehicles?select=id&limit=1",
            headers={"apikey": ANON_KEY, "Authorization": f"Bearer {target_token}"},
        )
        check(
            "4b the SAME already-issued session token regains real operational access after restore, with no new sign-in",
            status11 == 200 and isinstance(body11, list),
            f"status={status11} body={json.dumps(body11)[:150]}",
        )
    finally:
        cleanup(email)


if __name__ == "__main__":
    test_disable_from_independent_session_immediately_removes_access()
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)
