#!/usr/bin/env python3
"""Verify Workshop snapshot/recovery authority in deployed STAGING only."""
from __future__ import annotations

import json
import secrets
import string
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import sync_playwright

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, supabase_access_token

TASK = "t_cae774e3"
EMAIL = "functional.pdc.staging@example.com"
MISMATCH_EMAIL = "functional.pdc.mismatch.staging@example.com"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
BASE = f"https://{STAGING_REF}.supabase.co"
URL = "https://btnew.github.io/pdc-control-board-staging/"
ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "review-evidence" / TASK
OUT = OUT_DIR / "workshop-recovery-deployed-authenticated.json"


def http_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: dict | None = None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, data=data, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            body = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            body = {"raw_present": bool(raw)}
        return error.code, body


def live_state(user_id: str = "") -> dict[str, object]:
    actor = f"'{user_id}'::uuid" if user_id else "null::uuid"
    return management_write(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'auth_count',(select count(*) from auth.users where lower(email) in ('{EMAIL}','{MISMATCH_EMAIL}')),
        'role_count',(select count(*) from public.pdc_user_roles where lower(email) in ('{EMAIL}','{MISMATCH_EMAIL}') or auth_user_id={actor}),
        'receipt_count',(select count(*) from public.workshop_schedule_recovery_receipts where actor_user_id={actor}),
        'receipts',(select coalesce(jsonb_agg(jsonb_build_object('key',idempotency_key,'request_hash',request_hash,'response',response) order by created_at),'[]'::jsonb) from public.workshop_schedule_recovery_receipts where actor_user_id={actor}),
        'snapshot_acl',jsonb_build_object(
          'public',has_function_privilege('public','public.get_station_workshop_snapshot(text,date,date)','execute'),
          'anon',has_function_privilege('anon','public.get_station_workshop_snapshot(text,date,date)','execute'),
          'authenticated',has_function_privilege('authenticated','public.get_station_workshop_snapshot(text,date,date)','execute'),
          'service_role',has_function_privilege('service_role','public.get_station_workshop_snapshot(text,date,date)','execute')),
        'recovery_acl',jsonb_build_object(
          'public',has_function_privilege('public','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute'),
          'anon',has_function_privilege('anon','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute'),
          'authenticated',has_function_privilege('authenticated','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute'),
          'service_role',has_function_privilege('service_role','public.recover_overdue_planned_workshop_bookings(text,timestamptz)','execute')),
        'receipt_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.workshop_schedule_recovery_receipts'::regclass),
        'receipt_acl',jsonb_build_object(
          'public',has_table_privilege('public','public.workshop_schedule_recovery_receipts','select,insert,update,delete'),
          'anon',has_table_privilege('anon','public.workshop_schedule_recovery_receipts','select,insert,update,delete'),
          'authenticated',has_table_privilege('authenticated','public.workshop_schedule_recovery_receipts','select,insert,update,delete'),
          'service_role',has_table_privilege('service_role','public.workshop_schedule_recovery_receipts','select,insert,update,delete')),
        'monitor_staging_guard',public.pdc_monitor_staging_guard()
      ) as result
    """)[0]["result"]


def set_role(user_id: str, role: str | None, *, active: bool = True, status: str = "approved", email: str = EMAIL) -> None:
    role_sql = "null" if role is None else f"'{role}'::public.pdc_role"
    management_write(f"""
      update public.pdc_user_roles
      set role={role_sql},
          active={'true' if active else 'false'},
          account_status='{status}'::public.pdc_account_status,
          email='{email}',
          updated_at=clock_timestamp()
      where auth_user_id='{user_id}'::uuid
    """)


def snapshot(headers: dict[str, str]) -> tuple[int, object]:
    today = datetime.now(timezone.utc).date().isoformat()
    return http_json(
        f"{BASE}/rest/v1/rpc/get_station_workshop_snapshot",
        method="POST",
        headers=headers,
        payload={"p_stage_code": "FITTING", "p_date_from": today, "p_date_to": today},
    )


def compact(status: int, body: object) -> dict[str, object]:
    if isinstance(body, dict):
        return {
            "status": status,
            "ok": status == 200,
            "revision": body.get("revision"),
            "scope": body.get("scope"),
            "booking_count": len(body.get("bookings") or []),
            "error": body.get("error") or body.get("code"),
            "message": body.get("message"),
        }
    return {"status": status, "ok": status == 200, "body_type": type(body).__name__}


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    evidence: dict[str, object] = {
        "task": TASK,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "url": URL,
        "project_ref": STAGING_REF,
        "production_contacted": False,
        "production_mutated": False,
        "email_sent": False,
        "credentials_redacted": True,
    }
    user_id = ""
    service_key = ""
    assignment_applied = False
    cleanup_errors: list[str] = []
    try:
        before = live_state()
        evidence["before"] = before
        if before["head"] != ["20260904011500", "parts_stoppage_runtime_containment_repair"]:
            raise RuntimeError(f"unexpected STAGING head: {before['head']}")
        if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"] or not before["monitor_staging_guard"]:
            raise RuntimeError("STAGING sentinel preflight failed")
        if before["auth_count"] or before["role_count"]:
            raise RuntimeError("bounded auth/role namespace is not clean")

        management_headers = {"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"}
        _, keys = http_json(f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys", headers=management_headers)
        service_key = str(next((item.get("api_key") for item in keys or [] if item.get("name") == "service_role"), ""))
        public_key = str(next((item.get("api_key") for item in keys or [] if item.get("name") in {"anon", "publishable"}), ""))
        if not service_key or not public_key:
            raise RuntimeError("STAGING API keys unavailable")
        admin_headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json", "Accept": "application/json"}
        status, created = http_json(f"{BASE}/auth/v1/admin/users", method="POST", headers=admin_headers, payload={"email": EMAIL, "password": password, "email_confirm": True})
        user_id = str((created or {}).get("id") or "")
        if status != 200 or not user_id:
            raise RuntimeError(f"temporary Auth create failed: {status}")
        status, token_body = http_json(f"{BASE}/auth/v1/token?grant_type=password", method="POST", headers={"apikey": public_key, "Content-Type": "application/json", "Accept": "application/json"}, payload={"email": EMAIL, "password": password})
        access_token = str((token_body or {}).get("access_token") or "")
        if status != 200 or not access_token:
            raise RuntimeError(f"temporary login failed: {status}")
        user_headers = {"apikey": public_key, "Authorization": f"Bearer {access_token}", "Content-Type": "application/json", "Accept": "application/json"}
        assignment = management_write("select public.apply_pdc14_staging_test_operator_role() as outcome")[0]["outcome"]
        assignment_applied = assignment.get("ok") is True
        evidence["operator_assignment"] = assignment
        if not assignment_applied:
            raise RuntimeError("temporary Operator assignment failed")

        matrix: dict[str, object] = {}
        evidence["matrix"] = matrix
        first_status, first_body = snapshot(user_headers)
        first_state = live_state(user_id)
        second_status, second_body = snapshot(user_headers)
        second_state = live_state(user_id)
        matrix["operator"] = {"first": compact(first_status, first_body), "same_minute_duplicate": compact(second_status, second_body)}
        matrix["same_minute_idempotency"] = {
            "receipt_count_after_first": first_state["receipt_count"],
            "receipt_count_after_second": second_state["receipt_count"],
            "controlled_receipts": second_state["receipts"],
        }

        direct_status, direct_body = http_json(
            f"{BASE}/rest/v1/rpc/recover_overdue_planned_workshop_bookings",
            method="POST",
            headers=user_headers,
            payload={"p_idempotency_key": f"{TASK}-browser-route-must-stay-denied", "p_as_of": datetime.now(timezone.utc).isoformat()},
        )
        matrix["direct_recovery_acl"] = compact(direct_status, direct_body)

        set_role(user_id, "administrator")
        admin_status, admin_body = snapshot(user_headers)
        matrix["administrator"] = compact(admin_status, admin_body)

        for role in ("viewer", "importer"):
            set_role(user_id, role)
            denied_status, denied_body = snapshot(user_headers)
            matrix[role] = compact(denied_status, denied_body)

        set_role(user_id, None, active=False, status="pending")
        denied_status, denied_body = snapshot(user_headers)
        matrix["unapproved"] = compact(denied_status, denied_body)

        set_role(user_id, "operator", active=False, status="disabled")
        denied_status, denied_body = snapshot(user_headers)
        matrix["inactive"] = compact(denied_status, denied_body)

        set_role(user_id, "operator", email=MISMATCH_EMAIL)
        denied_status, denied_body = snapshot(user_headers)
        matrix["identity_mismatch"] = compact(denied_status, denied_body)

        anon_status, anon_body = snapshot({"apikey": public_key, "Authorization": f"Bearer {public_key}", "Content-Type": "application/json", "Accept": "application/json"})
        matrix["anon"] = compact(anon_status, anon_body)

        set_role(user_id, "operator")
        browser_events = {"rpc_requests": [], "http_errors": [], "page_errors": [], "console_errors": [], "production_requests": []}
        evidence["browser_events"] = browser_events
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1440, "height": 1000})
            page = context.new_page()
            page.on("request", lambda request: browser_events["rpc_requests"].append({"method": request.method, "url": request.url}) if "/rest/v1/rpc/" in request.url else None)
            page.on("request", lambda request: browser_events["production_requests"].append(request.url) if PRODUCTION_REF in request.url else None)
            page.on("response", lambda response: browser_events["http_errors"].append({"status": response.status, "url": response.url}) if response.status >= 400 else None)
            page.on("pageerror", lambda error: browser_events["page_errors"].append(str(error)))
            page.on("console", lambda message: browser_events["console_errors"].append(message.text) if message.type == "error" else None)
            page.goto(URL + "?workshop-recovery=" + TASK, wait_until="domcontentloaded", timeout=90000)
            page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
            page.locator("#pdc-login-email").fill(EMAIL)
            page.locator("#pdc-login-password").fill(password)
            page.locator("#pdc-password-login").click()
            page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=30000)
            page.locator("[data-view='planner-fitting']").click()
            page.wait_for_function("() => window.__workshopDataService?.getScope?.()?.stageCode === 'FITTING'", timeout=30000)
            page.wait_for_function("() => window.__workshopDataService?.getTrustedSnapshot?.()?.revision != null", timeout=30000)
            browser_events["rpc_requests"].clear()
            browser_events["http_errors"].clear()
            await_result = page.evaluate("""async () => {
              const first = await window.__workshopDataService.loadSnapshot('t_cae774e3-first');
              const second = await window.__workshopDataService.loadSnapshot('t_cae774e3-same-minute');
              return {firstRevision:first?.revision ?? null,secondRevision:second?.revision ?? null,state:window.__workshopDataService.getState(),trustedRevision:window.__workshopDataService.getTrustedSnapshot()?.revision ?? null};
            }""")
            page.screenshot(path=str(OUT_DIR / "workshop-planner-single-authority.png"), full_page=True)
            evidence["browser"] = {"role": page.evaluate("() => window.PDC_AUTH_CONTEXT?.role || null"), "refresh": await_result}
            context.close()
            browser.close()

        browser_rpc_names = [entry["url"].split("/rest/v1/rpc/", 1)[1].split("?", 1)[0] for entry in browser_events["rpc_requests"]]
        evidence["browser"]["rpc_names"] = browser_rpc_names
        approved_statuses = [first_status, second_status, admin_status]
        denied_statuses = [matrix[key]["status"] for key in ("viewer", "importer", "unapproved", "inactive", "identity_mismatch", "anon")]
        if approved_statuses != [200, 200, 200]:
            raise RuntimeError(f"approved snapshot matrix failed: {approved_statuses}")
        if any(status not in (401, 403) for status in denied_statuses):
            raise RuntimeError(f"denied matrix did not fail closed: {denied_statuses}")
        if direct_status != 403:
            raise RuntimeError(f"direct recovery ACL unexpectedly exposed: {direct_status}")
        if first_state["receipt_count"] < 1 or second_state["receipt_count"] != first_state["receipt_count"]:
            raise RuntimeError("same-minute snapshot recovery was not receipt-idempotent")
        if "recover_overdue_planned_workshop_bookings" in browser_rpc_names:
            raise RuntimeError("deployed browser still made redundant direct recovery request")
        if browser_rpc_names.count("get_station_workshop_snapshot") != 2:
            raise RuntimeError(f"deployed explicit refreshes did not use exactly two snapshot requests: {browser_rpc_names}")
        if browser_events["http_errors"] or browser_events["page_errors"] or browser_events["console_errors"] or browser_events["production_requests"]:
            raise RuntimeError(f"deployed browser emitted errors or contacted Production: {browser_events}")
        evidence["security_advisors"] = security_advisor_summary()
        evidence["all_checks_passed"] = True
    except Exception as error:
        evidence["execution_error"] = str(error)
        evidence["all_checks_passed"] = False
    finally:
        if user_id:
            try:
                management_write(f"delete from public.workshop_schedule_recovery_receipts where actor_user_id='{user_id}'::uuid")
            except Exception as error:
                cleanup_errors.append(f"recovery receipt cleanup failed: {error}")
        if assignment_applied:
            try:
                if user_id:
                    set_role(user_id, "operator")
                management_write(f"select public.rollback_pdc14_staging_test_operator_role('{TASK} deployed recovery verification complete')")
            except Exception as error:
                cleanup_errors.append(f"role rollback failed: {error}")
        if user_id and service_key:
            status, body = http_json(f"{BASE}/auth/v1/admin/users/{user_id}", method="DELETE", headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Accept": "application/json"})
            if status not in (200, 204):
                cleanup_errors.append(f"auth cleanup failed: {status} {body}")
        if user_id:
            try:
                management_write(f"delete from public.pdc_user_roles where auth_user_id='{user_id}'::uuid or lower(email) in ('{EMAIL}','{MISMATCH_EMAIL}')")
            except Exception as error:
                cleanup_errors.append(f"role cleanup failed: {error}")
        try:
            evidence["cleanup"] = live_state(user_id)
        except Exception as error:
            cleanup_errors.append(f"cleanup readback failed: {error}")
        evidence["cleanup_errors"] = cleanup_errors
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence["password_retained"] = False
        password = service_key = ""
        OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
        print(json.dumps({
            "evidence": str(OUT),
            "all_checks_passed": evidence.get("all_checks_passed", False),
            "execution_error": evidence.get("execution_error"),
            "cleanup": evidence.get("cleanup"),
            "cleanup_errors": cleanup_errors,
        }, indent=2, default=str))
    clean = evidence.get("cleanup") or {}
    return 0 if evidence.get("all_checks_passed") and not cleanup_errors and clean.get("auth_count") == 0 and clean.get("role_count") == 0 and clean.get("receipt_count") == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
