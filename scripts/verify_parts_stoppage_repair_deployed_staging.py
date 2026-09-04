#!/usr/bin/env python3
"""Behavior/API/deployed-UI verification for the STAGING Parts STOPPAGE repair."""
from __future__ import annotations

import json
import secrets
import string
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import sync_playwright

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, supabase_access_token

TASK = "t_fd63d897"
EMAIL = "functional.pdc.staging@example.com"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
BASE = f"https://{STAGING_REF}.supabase.co"
PAGES = "https://btnew.github.io/pdc-control-board-staging/"
VEHICLE_ID = "fd63d897-0000-5000-8000-000000000376"
LIFECYCLE_VEHICLE_ID = "fd63d897-0000-5000-8000-000000000377"
STOCK = "HERMES-PARTS-STOPPAGE-FD63D897"
IMPORT_RECEIPT_ID = "fd63d897-0000-5000-8000-000000000378"
OUT_DIR = Path(__file__).resolve().parents[1] / "review-evidence" / TASK
OUT = OUT_DIR / "parts-stoppage-deployed-authenticated.json"


def http_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: dict | None = None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, data=body, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = {"raw": raw}
        return error.code, parsed


def query_result(sql: str) -> object:
    rows = management_write(sql)
    return rows[0]["result"] if rows else None


def counts() -> dict[str, object]:
    return query_result(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),
        'role_count',(select count(*) from public.pdc_user_roles where lower(email) in ('{EMAIL}','wrong.identity@example.com')),
        'vehicle_count',(select count(*) from public.vehicles where id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid)),
        'work_count',(select count(*) from public.vehicle_work_items where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid)),
        'parts_count',(select count(*) from public.vehicle_parts_updates where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid)),
        'receipt_count',(select count(*) from public.pdc_parts_stoppage_receipts_376 where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid)),
        'audit_count',(select count(*) from public.audit_events where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid)),
        'import_receipt_count',(select count(*) from public.pdc_authenticated_email_import_receipts where receipt_id='{IMPORT_RECEIPT_ID}'::uuid),
        'cleanup_evidence_count',(select count(*) from public.pdc_parts_stoppage_verification_cleanup_20260904 where task_key='{TASK}'),
        'notification_count',(select count(*) from public.vehicle_notifications)
      ) result
    """)


def vehicle_state(vehicle_id: str = VEHICLE_ID) -> dict[str, object]:
    return query_result(f"""
      select jsonb_build_object(
        'vehicle',(select jsonb_build_object('id',id,'version',version,'lifecycle',lifecycle_state,'visible',visible_on_board) from public.vehicles where id='{vehicle_id}'::uuid),
        'parts',(select jsonb_build_object('id',id,'stoppage',parts_stoppage,'reason',parts_stoppage_reason,'received',parts_received,'updated_by',updated_by) from public.vehicle_parts_updates where vehicle_id='{vehicle_id}'::uuid order by updated_at desc,id desc limit 1),
        'receipt_count',(select count(*) from public.pdc_parts_stoppage_receipts_376 where vehicle_id='{vehicle_id}'::uuid),
        'audit_count',(select count(*) from public.audit_events where vehicle_id='{vehicle_id}'::uuid),
        'notification_count',(select count(*) from public.vehicle_notifications)
      ) result
    """)


def set_role(*, role: str, active: bool, status: str, email: str = EMAIL) -> dict[str, object]:
    return query_result(f"""
      update public.pdc_user_roles
      set email='{email}',display_name='PDC Parts STOPPAGE Verifier',role='{role}'::public.pdc_role,
          active={'true' if active else 'false'},account_status='{status}'::public.pdc_account_status,
          approved_at=case when '{status}'='approved' then coalesce(approved_at,clock_timestamp()) else null end,
          rejected_at=case when '{status}'='rejected' then clock_timestamp() else null end,
          rejection_reason=case when '{status}'='rejected' then 'bounded denial verification' else null end,
          disabled_at=case when '{status}'='disabled' then clock_timestamp() else null end,
          disabled_reason=case when '{status}'='disabled' then 'bounded denial verification' else null end
      where auth_user_id=(select id from auth.users where lower(auth.users.email)='{EMAIL}')
      returning jsonb_build_object('email',email,'role',role,'active',active,'status',account_status) result
    """)


def rpc(headers: dict[str, str], *, vehicle_id: str = VEHICLE_ID, expected_version: int = 1, key: str, action: str, reason: str):
    return http_json(
        f"{BASE}/rest/v1/rpc/set_pdc_parts_stoppage_376",
        method="POST",
        headers=headers,
        payload={"p_vehicle_id": vehicle_id, "p_expected_version": expected_version, "p_idempotency_key": key, "p_action": action, "p_reason": reason},
    )


def create_fixtures(user_id: str) -> None:
    management_write(f"""
      insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,
        lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,version,created_by,updated_by)
      values
        ('{VEHICLE_ID}'::uuid,'HERMES-PARTS-PERM-FD63D897','{STOCK}','HERMES-JC-FD63D897','Parts Stoppage Fixture','Bounded Parts STOPPAGE verification',
         'active',true,'YH','hermes_test','{TASK}','parts-stoppage-active',jsonb_build_object('bounded_fixture','{TASK}','email_sent',false),1,'{user_id}'::uuid,'{user_id}'::uuid),
        ('{LIFECYCLE_VEHICLE_ID}'::uuid,'HERMES-PARTS-PERM-FD63D897-LIFECYCLE','{STOCK}-LIFECYCLE','HERMES-JC-FD63D897-L','Lifecycle Fixture','Bounded lifecycle denial verification',
         'completed',true,'YH','hermes_test','{TASK}','parts-stoppage-completed',jsonb_build_object('bounded_fixture','{TASK}','email_sent',false),1,'{user_id}'::uuid,'{user_id}'::uuid);
      insert into public.vehicle_work_items(vehicle_id,work_key,required,completed)
      values('{VEHICLE_ID}'::uuid,'PARTS',true,false),('{LIFECYCLE_VEHICLE_ID}'::uuid,'PARTS',true,false);
      insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by)
      values('{VEHICLE_ID}'::uuid,true,false,false,false,null,current_date+4,'{user_id}'::uuid),
            ('{LIFECYCLE_VEHICLE_ID}'::uuid,true,false,false,false,null,current_date+4,'{user_id}'::uuid);
      insert into public.pdc_authenticated_email_import_receipts(
        receipt_id,actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,
        source_received_at,stock_number,vehicle_id,identity_source,required_work,response)
      values('{IMPORT_RECEIPT_ID}'::uuid,'{user_id}'::uuid,'{TASK}-parts-stoppage-fixture',repeat('8',64),repeat('7',64),repeat('6',64),
        '{TASK}-parts-stoppage-fixture','no-email@invalid.example',clock_timestamp(),'{STOCK}','{VEHICLE_ID}'::uuid,'email_new',
        '["parts"]'::jsonb,'{{"ok":true,"code":"bounded_fixture","email_sent":false}}'::jsonb);
    """)


def assert_denied(name: str, response: tuple[int, object], evidence: dict[str, object], before: dict[str, object], *, anonymous: bool = False) -> None:
    status, body = response
    after = vehicle_state()
    evidence[name] = {"status": status, "body": body, "before": before, "after": after}
    message = str((body or {}).get("message") or "")
    exact_error = status in ({401, 403} if anonymous else {403}) and (body or {}).get("code") == "42501"
    if anonymous:
        exact_error = exact_error and "permission denied for function set_pdc_parts_stoppage_376" in message
    else:
        exact_error = exact_error and message == "PDC_376_UNAUTHORIZED"
    if not exact_error or after != before:
        raise RuntimeError(f"{name} did not fail closed: {status} {body}")


def cleanup_fixture(user_id: str) -> None:
    management_write(f"""
      begin;
      do $guard$
      begin
        if (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}')<>1
           or to_regclass('public.pdc_production_environment_sentinel') is not null then
          raise exception 'PDC_PARTS_STOPPAGE_CLEANUP_WRONG_ENVIRONMENT';
        end if;
        if (select count(*) from public.vehicles where id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid))<>2
          or exists(select 1 from public.vehicles where id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid)
          and (source_system is distinct from 'hermes_test' or source_batch_id is distinct from '{TASK}'
            or source_payload->>'bounded_fixture' is distinct from '{TASK}' or created_by is distinct from '{user_id}'::uuid)) then
          raise exception 'PDC_PARTS_STOPPAGE_CLEANUP_PROVENANCE_MISMATCH';
        end if;
      end $guard$;
      insert into public.pdc_parts_stoppage_verification_cleanup_20260904(
        task_key,vehicle_id,actor_id,actor_email,before_vehicle,before_parts,receipt_evidence,audit_evidence,cleanup_reason,production_writes)
      select '{TASK}',v.id,v.created_by,'{EMAIL}',to_jsonb(v)||jsonb_build_object('_import_receipt',
        (select to_jsonb(i) from public.pdc_authenticated_email_import_receipts i where i.receipt_id='{IMPORT_RECEIPT_ID}'::uuid)),
        coalesce((select jsonb_agg(to_jsonb(p) order by p.updated_at,p.id) from public.vehicle_parts_updates p where p.vehicle_id=v.id),'[]'::jsonb),
        coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at,r.receipt_id) from public.pdc_parts_stoppage_receipts_376 r where r.vehicle_id=v.id),'[]'::jsonb),
        coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.audit_events a where a.vehicle_id=v.id),'[]'::jsonb),
        'bounded authenticated Parts STOPPAGE verification archived before mutable cleanup',false
      from public.vehicles v where v.id='{VEHICLE_ID}'::uuid
        and exists(select 1 from public.pdc_parts_stoppage_receipts_376 r where r.vehicle_id=v.id)
        and exists(select 1 from public.audit_events a where a.vehicle_id=v.id);
      alter table public.pdc_parts_stoppage_receipts_376 disable trigger pdc_parts_stoppage_receipts_append_only_376;
      delete from public.pdc_parts_stoppage_receipts_376 where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid);
      alter table public.pdc_parts_stoppage_receipts_376 enable trigger pdc_parts_stoppage_receipts_append_only_376;
      delete from public.vehicle_parts_updates where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid);
      alter table public.pdc_authenticated_email_import_receipts disable trigger user;
      delete from public.pdc_authenticated_email_import_receipts where receipt_id='{IMPORT_RECEIPT_ID}'::uuid and vehicle_id='{VEHICLE_ID}'::uuid and actor_id='{user_id}'::uuid;
      alter table public.pdc_authenticated_email_import_receipts enable trigger user;
      alter table public.vehicle_work_items disable trigger user;
      delete from public.vehicle_work_items where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid);
      alter table public.vehicle_work_items enable trigger user;
      delete from public.audit_events where vehicle_id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid);
      delete from public.vehicles where id in ('{VEHICLE_ID}'::uuid,'{LIFECYCLE_VEHICLE_ID}'::uuid);
      commit;
    """)


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    user_id = ""
    service_key = ""
    assignment_applied = False
    fixture_created = False
    cleanup_errors: list[str] = []
    evidence: dict[str, object] = {"task": TASK, "started_at": datetime.now(timezone.utc).isoformat(), "project_ref": STAGING_REF, "pages": PAGES, "production_contacted": False, "email_sent": False, "credentials_redacted": True}
    try:
        before = counts()
        evidence["before"] = before
        if before["head"] != ["20260904011500", "parts_stoppage_runtime_containment_repair"]:
            raise RuntimeError(f"unexpected STAGING head: {before['head']}")
        if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
            raise RuntimeError("STAGING sentinel preflight failed")
        if any(before[key] for key in ("auth_count", "role_count", "vehicle_count", "work_count", "parts_count", "receipt_count", "audit_count", "import_receipt_count")):
            raise RuntimeError("bounded verification namespace is not clean")

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
        status, token = http_json(f"{BASE}/auth/v1/token?grant_type=password", method="POST", headers={"apikey": public_key, "Content-Type": "application/json", "Accept": "application/json"}, payload={"email": EMAIL, "password": password})
        access_token = str((token or {}).get("access_token") or "")
        if status != 200 or not access_token:
            raise RuntimeError(f"temporary login failed: {status}")
        user_headers = {"apikey": public_key, "Authorization": f"Bearer {access_token}", "Content-Type": "application/json", "Accept": "application/json"}
        create_fixtures(user_id)
        fixture_created = True

        untouched = vehicle_state()
        assert_denied("anon_denied", rpc({"apikey": public_key, "Content-Type": "application/json"}, key="fd63d897-0000-5000-8000-000000000010", action="set", reason="anon denied"), evidence, untouched, anonymous=True)
        assert_denied("unapproved_denied", rpc(user_headers, key="fd63d897-0000-5000-8000-000000000011", action="set", reason="unapproved denied"), evidence, untouched)
        set_role(role="viewer", active=True, status="approved")
        assert_denied("viewer_denied", rpc(user_headers, key="fd63d897-0000-5000-8000-000000000012", action="set", reason="viewer denied"), evidence, untouched)
        set_role(role="importer", active=True, status="approved")
        assert_denied("importer_denied", rpc(user_headers, key="fd63d897-0000-5000-8000-000000000013", action="set", reason="importer denied"), evidence, untouched)
        set_role(role="operator", active=False, status="disabled")
        assert_denied("inactive_denied", rpc(user_headers, key="fd63d897-0000-5000-8000-000000000014", action="set", reason="inactive denied"), evidence, untouched)
        set_role(role="operator", active=True, status="approved", email="wrong.identity@example.com")
        assert_denied("identity_mismatch_denied", rpc(user_headers, key="fd63d897-0000-5000-8000-000000000015", action="set", reason="identity denied"), evidence, untouched)
        set_role(role="operator", active=True, status="approved")
        assignment_applied = True

        set_reason = f"{TASK} exact delayed component"
        set_key = "fd63d897-0000-5000-8000-000000000101"
        set_status, set_body = rpc(user_headers, expected_version=1, key=set_key, action="set", reason=set_reason)
        set_readback = vehicle_state()
        evidence["operator_set"] = {"status": set_status, "body": set_body, "readback": set_readback}
        if set_status != 200 or not (set_body or {}).get("ok") or set_readback["vehicle"]["version"] != 2 or not set_readback["parts"]["stoppage"] or set_readback["parts"]["reason"] != set_reason:
            raise RuntimeError(f"approved Operator set failed: {set_status} {set_body} {set_readback}")
        replay_status, replay_body = rpc(user_headers, expected_version=1, key=set_key, action="set", reason=set_reason)
        replay_readback = vehicle_state()
        evidence["exact_replay"] = {"status": replay_status, "body": replay_body, "readback": replay_readback}
        if replay_status != 200 or not (replay_body or {}).get("replay") or replay_body.get("receipt_id") != set_body.get("receipt_id") or replay_readback != set_readback:
            raise RuntimeError("exact replay was not state-equivalent")
        conflict_status, conflict_body = rpc(user_headers, expected_version=1, key=set_key, action="set", reason=set_reason + " conflict")
        conflict_readback = vehicle_state()
        evidence["idempotency_payload_conflict"] = {"status": conflict_status, "body": conflict_body, "readback": conflict_readback}
        if (conflict_status != 400 or (conflict_body or {}).get("code") != "22023"
                or (conflict_body or {}).get("message") != "PDC_376_IDEMPOTENCY_PAYLOAD_MISMATCH"
                or conflict_readback != set_readback):
            raise RuntimeError("idempotency payload conflict did not fail closed")
        stale_status, stale_body = rpc(user_headers, expected_version=1, key="fd63d897-0000-5000-8000-000000000102", action="clear", reason=f"{TASK} stale clear")
        stale_readback = vehicle_state()
        evidence["stale_expected_version"] = {"status": stale_status, "body": stale_body, "readback": stale_readback}
        if stale_status != 200 or (stale_body or {}).get("ok") is not False or stale_body.get("code") != "vehicle_version_conflict" or stale_readback["vehicle"]["version"] != 2 or not stale_readback["parts"]["stoppage"]:
            raise RuntimeError("stale expected-version did not fail closed")
        lifecycle_status, lifecycle_body = rpc(user_headers, vehicle_id=LIFECYCLE_VEHICLE_ID, expected_version=1, key="fd63d897-0000-5000-8000-000000000103", action="set", reason=f"{TASK} lifecycle denial")
        lifecycle_readback = vehicle_state(LIFECYCLE_VEHICLE_ID)
        evidence["lifecycle_denied"] = {"status": lifecycle_status, "body": lifecycle_body, "readback": lifecycle_readback}
        if lifecycle_status != 200 or (lifecycle_body or {}).get("ok") is not False or lifecycle_body.get("code") != "vehicle_inactive_or_issued" or lifecycle_readback["vehicle"]["version"] != 1 or lifecycle_readback["parts"]["stoppage"]:
            raise RuntimeError("lifecycle invalid request did not fail closed")

        clear_reason = f"{TASK} exact recovered component"
        clear_key = "fd63d897-0000-5000-8000-000000000104"
        clear_status, clear_body = rpc(user_headers, expected_version=2, key=clear_key, action="clear", reason=clear_reason)
        clear_readback = vehicle_state()
        evidence["operator_clear"] = {"status": clear_status, "body": clear_body, "readback": clear_readback}
        if clear_status != 200 or not (clear_body or {}).get("ok") or clear_readback["vehicle"]["version"] != 3 or clear_readback["parts"]["stoppage"] or clear_readback["parts"]["reason"] is not None:
            raise RuntimeError("approved Operator clear failed")
        clear_replay_status, clear_replay_body = rpc(user_headers, expected_version=2, key=clear_key, action="clear", reason=clear_reason)
        if clear_replay_status != 200 or not (clear_replay_body or {}).get("replay") or clear_replay_body.get("receipt_id") != clear_body.get("receipt_id") or vehicle_state() != clear_readback:
            raise RuntimeError("clear replay was not state-equivalent")

        set_role(role="administrator", active=True, status="approved")
        admin_set_status, admin_set_body = rpc(user_headers, expected_version=3, key="fd63d897-0000-5000-8000-000000000105", action="set", reason=f"{TASK} administrator set")
        admin_clear_status, admin_clear_body = rpc(user_headers, expected_version=4, key="fd63d897-0000-5000-8000-000000000106", action="clear", reason=f"{TASK} administrator clear")
        evidence["administrator"] = {"set": {"status": admin_set_status, "body": admin_set_body}, "clear": {"status": admin_clear_status, "body": admin_clear_body}, "readback": vehicle_state()}
        if admin_set_status != 200 or admin_clear_status != 200 or not admin_set_body.get("ok") or not admin_clear_body.get("ok") or evidence["administrator"]["readback"]["vehicle"]["version"] != 5:
            raise RuntimeError("approved Administrator set/clear failed")
        set_role(role="operator", active=True, status="approved")

        sql_readback = query_result(f"""
          select jsonb_build_object(
            'vehicle_version',(select version from public.vehicles where id='{VEHICLE_ID}'::uuid),
            'latest_parts',(select jsonb_build_object('stoppage',parts_stoppage,'reason',parts_stoppage_reason) from public.vehicle_parts_updates where vehicle_id='{VEHICLE_ID}'::uuid order by updated_at desc,id desc limit 1),
            'receipts',(select jsonb_agg(jsonb_build_object('action',action,'reason',reason,'response',response) order by created_at) from public.pdc_parts_stoppage_receipts_376 where vehicle_id='{VEHICLE_ID}'::uuid),
            'audits',(select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.audit_events a where a.vehicle_id='{VEHICLE_ID}'::uuid),
            'notification_count',(select count(*) from public.vehicle_notifications),
            'parts_receipts_private',not has_table_privilege('authenticated','public.pdc_parts_stoppage_receipts_376','select')
          ) result
        """)
        evidence["behavior_sql_readback"] = sql_readback
        if sql_readback["vehicle_version"] != 5 or sql_readback["latest_parts"] != {"stoppage": False, "reason": None} or not sql_readback["parts_receipts_private"] or sql_readback["notification_count"] != before["notification_count"]:
            raise RuntimeError("SQL authoritative parity/readback failed")

        snapshot_status, snapshot_body = http_json(f"{BASE}/rest/v1/rpc/get_pdc_email_vehicle_location_snapshot", method="POST", headers=user_headers, payload={})
        snapshot_data = snapshot_body.get("data", {}) if isinstance(snapshot_body, dict) else {}
        snapshot_fixture = next((vehicle for vehicle in snapshot_data.get("vehicles", []) if vehicle.get("id") == VEHICLE_ID), None)
        evidence["pre_ui_snapshot"] = {
            "status": snapshot_status,
            "ok": snapshot_body.get("ok") if isinstance(snapshot_body, dict) else None,
            "code": snapshot_body.get("code") if isinstance(snapshot_body, dict) else None,
            "revision": snapshot_data.get("revision"),
            "fixture": {
                "id": snapshot_fixture.get("id"),
                "stock_number": snapshot_fixture.get("stock_number"),
                "visible_on_board": snapshot_fixture.get("visible_on_board"),
                "parts_stoppage": (snapshot_fixture.get("parts_update") or {}).get("parts_stoppage"),
            } if snapshot_fixture else None,
        }

        browser_events = {"page_errors": [], "http_errors": [], "production_requests": [], "parts_rpc": []}
        evidence["browser_events"] = browser_events
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1440, "height": 1000})
            page = context.new_page()
            page.on("pageerror", lambda error: browser_events["page_errors"].append(str(error)))
            page.on("response", lambda response: browser_events["http_errors"].append({"status": response.status, "url": response.url}) if response.status >= 400 else None)
            page.on("response", lambda response: browser_events["parts_rpc"].append({"status": response.status, "url": response.url}) if "set_pdc_parts_stoppage_376" in response.url else None)
            page.on("request", lambda request: browser_events["production_requests"].append(request.url) if PRODUCTION_REF in request.url else None)
            evidence["browser_stage"] = "navigate"
            page.goto(PAGES + "?parts-stoppage=" + TASK, wait_until="domcontentloaded", timeout=90000)
            evidence["browser_stage"] = "wait_initial_auth_state"
            page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
            evidence["browser_stage"] = "login"
            page.locator("#pdc-login-email").fill(EMAIL)
            page.locator("#pdc-login-password").fill(password)
            page.locator("#pdc-password-login").click()
            page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=30000)
            page.wait_for_function("() => Boolean(app.emailVehicleLocationService)", timeout=30000)
            refresh_attempts = []
            for _ in range(3):
                refresh_attempts.append(page.evaluate("() => refreshEmailVehicleLocations()"))
                if refresh_attempts[-1] is True:
                    break
                page.wait_for_timeout(500)
            evidence["browser_refresh"] = refresh_attempts
            evidence["browser_rows_after_refresh"] = page.evaluate("([vehicleId,lifecycleId,stock]) => ({email:app.emailVehicleLocationRows.filter(v=>[vehicleId,lifecycleId].includes(v.id)).map(v=>({id:v.id,stock_number:v.stock_number,visible:v.visible_on_board})),data:app.data.filter(v=>String(v.stock||'').startsWith(stock)).map(v=>({id:v.id,stock:v.stock,canonical:v.__emailVehicleCanonicalId})),error:app.emailVehicleLocationError})", [VEHICLE_ID, LIFECYCLE_VEHICLE_ID, STOCK])
            evidence["browser_stage"] = "wait_fixture_row"
            page.wait_for_function("stock => (app.data || []).some(v => v.stock === stock)", arg=STOCK, timeout=30000)
            page.locator("[data-view='parts']").click()
            page.wait_for_selector("[data-parts-stoppage]:visible", timeout=30000)
            ui_set_reason = f"{TASK} deployed UI exact reason"
            page.once("dialog", lambda dialog: dialog.accept(ui_set_reason))
            set_button = page.locator(f'[data-parts-stoppage="{STOCK}"]:visible')
            if set_button.count() != 1:
                raise RuntimeError(f"expected one exact fixture STOPPAGE control, got {set_button.count()}")
            set_button.screenshot(path=str(OUT_DIR / "parts-stoppage-ui-clear.png"))
            set_button.click()
            page.wait_for_function("stock => app.data.some(v => v.stock === stock && v.pdcPartsStoppage === true)", arg=STOCK, timeout=30000)
            ui_set_readback = vehicle_state()
            page.locator(f'[data-parts-clear-stoppage="{STOCK}"]:visible').screenshot(path=str(OUT_DIR / "parts-stoppage-ui-set.png"))
            ui_clear_reason = f"{TASK} deployed UI exact recovery"
            page.once("dialog", lambda dialog: dialog.accept(ui_clear_reason))
            clear_button = page.locator(f'[data-parts-clear-stoppage="{STOCK}"]:visible')
            if clear_button.count() != 1:
                raise RuntimeError(f"expected one exact fixture recovery control, got {clear_button.count()}")
            clear_button.click()
            page.wait_for_function("stock => app.data.some(v => v.stock === stock && v.pdcPartsStoppage === false)", arg=STOCK, timeout=30000)
            ui_clear_readback = vehicle_state()
            evidence["deployed_ui"] = {"events": browser_events, "set_reason": ui_set_reason, "set_readback": ui_set_readback, "clear_reason": ui_clear_reason, "clear_readback": ui_clear_readback, "dom": page.evaluate("stock => { const v=app.data.find(x=>x.stock===stock); return {authState:document.body.dataset.authState,role:window.PDC_AUTH_CONTEXT?.role,project:window.PDC_SUPABASE_CONFIG?.projectRef,row:{stock:v?.stock,stoppage:v?.pdcPartsStoppage,reason:v?.pdcPartsStoppageReason,version:v?.__emailVehicleVersion}}; }", STOCK)}
            context.close()
            browser.close()
        ui_dom = evidence["deployed_ui"]["dom"]
        unexpected_http_errors = [item for item in browser_events["http_errors"] if not (
            item["status"] == 403 and item["url"].endswith("/rest/v1/rpc/recover_overdue_planned_workshop_bookings")
        )]
        evidence["deployed_ui"]["unexpected_http_errors"] = unexpected_http_errors
        if (browser_events["production_requests"] or browser_events["page_errors"]
                or unexpected_http_errors
                or [item["status"] for item in browser_events["parts_rpc"]] != [200, 200]
                or ui_set_readback["parts"]["reason"] != ui_set_reason or not ui_set_readback["parts"]["stoppage"]
                or ui_clear_readback["parts"]["stoppage"] or ui_clear_readback["vehicle"]["version"] != 7
                or ui_clear_readback["notification_count"] != before["notification_count"]
                or ui_dom["authState"] != "approved" or ui_dom["role"] != "operator" or ui_dom["project"] != STAGING_REF
                or ui_dom["row"] != {"stock": STOCK, "stoppage": False, "reason": "", "version": 7}):
            raise RuntimeError(f"deployed authenticated UI set/clear failed: {evidence['deployed_ui']}")
        evidence["all_checks_passed"] = True
    except Exception as error:
        evidence["execution_error"] = str(error)
        evidence["all_checks_passed"] = False
    finally:
        if fixture_created:
            try:
                cleanup_fixture(user_id)
            except Exception as error:
                cleanup_errors.append(f"fixture cleanup failed: {error}")
        try:
            if user_id:
                management_write(f"delete from public.pdc_user_roles where auth_user_id='{user_id}'::uuid and lower(email) in ('{EMAIL}','wrong.identity@example.com')")
        except Exception as error:
            cleanup_errors.append(f"role cleanup failed: {error}")
        if user_id and service_key:
            status, body = http_json(f"{BASE}/auth/v1/admin/users/{user_id}", method="DELETE", headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Accept": "application/json"})
            if status not in (200, 204):
                cleanup_errors.append(f"auth cleanup failed: {status} {body}")
        try:
            evidence["cleanup"] = counts()
        except Exception as error:
            cleanup_errors.append(f"cleanup readback failed: {error}")
        evidence["cleanup_errors"] = cleanup_errors
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence["password_retained"] = False
        password = service_key = ""
        OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
        print(json.dumps({"evidence": str(OUT), "all_checks_passed": evidence.get("all_checks_passed"), "execution_error": evidence.get("execution_error"), "cleanup": evidence.get("cleanup"), "cleanup_errors": cleanup_errors}, indent=2, default=str))
    clean = evidence.get("cleanup") or {}
    cleanup_zero = all(clean.get(key) == 0 for key in ("auth_count", "role_count", "vehicle_count", "work_count", "parts_count", "receipt_count", "audit_count", "import_receipt_count"))
    return 0 if evidence.get("all_checks_passed") and cleanup_zero and clean.get("cleanup_evidence_count", 0) >= 1 and not cleanup_errors else 2


if __name__ == "__main__":
    raise SystemExit(main())
