from __future__ import annotations

import hashlib
import json
import secrets
import string
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
EVIDENCE_ROOT = HERE.parents[1]
ROOT = HERE.parents[3]
OUT = HERE / "aud001-transaction-evidence.json"
SCREENSHOT = EVIDENCE_ROOT / "screenshots" / "transactions" / "aud001-fixture-card.png"
sys.path.insert(0, str(ROOT / "scripts"))
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
URL = "https://btnew.github.io/pdc-control-board-staging/"
PREFIX = "QA-OVERNIGHT-20260904"
ACTOR_EMAIL = "qa.overnight.20260904.aud001@example.com"
VEHICLE_ID = "83f220c9-0000-5000-8000-000000000001"
STOCK = "QA-OVERNIGHT-20260904-AUD001"
JOB_CARD = "QA-OVERNIGHT-20260904-JC001"
VIN = "TEST09049999999AA"
REGISTRATION = "QA001"
EDIT_KEY = "QA-OVERNIGHT-20260904-AUD001-EDIT-1"
STALE_KEY = "QA-OVERNIGHT-20260904-AUD001-STALE-1"
EDIT_REASON = "QA-OVERNIGHT-20260904 AUD-001 deterministic edit"


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def request_json(url: str, method: str = "GET", headers: dict[str, str] | None = None, payload: dict | None = None) -> tuple[int, object]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, data=data, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            body: object = json.loads(raw)
        except json.JSONDecodeError:
            body = {"message": raw[:1000]}
        return error.code, body


def management_write(sql: str) -> list[dict]:
    payload = json.dumps({"query": sql, "read_only": False}).encode("utf-8")
    request = Request(
        f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {supabase_access_token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "SupabaseCLI/2.116.0",
        },
    )
    try:
        with urlopen(request, timeout=300) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else []
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"STAGING management write failed ({error.code}): {detail}") from error


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def scrub(value: object, actor_id: str = "", protected_replacements: dict[str, str] | None = None, credential_values: set[str] | None = None) -> object:
    protected_replacements = protected_replacements or {}
    credential_values = credential_values or set()
    if isinstance(value, dict):
        clean: dict[str, object] = {}
        for key, item in value.items():
            lower = key.lower()
            if any(token in lower for token in ("token", "password", "apikey", "authorization")):
                clean[key] = "[REDACTED_CREDENTIAL]"
            else:
                clean[key] = scrub(item, actor_id, protected_replacements, credential_values)
        return clean
    if isinstance(value, list):
        return [scrub(item, actor_id, protected_replacements, credential_values) for item in value]
    if isinstance(value, str):
        text = value.replace(ACTOR_EMAIL, "[REDACTED_SYNTHETIC_ACTOR_EMAIL]")
        if actor_id:
            text = text.replace(actor_id, "[REDACTED_SYNTHETIC_ACTOR_ID]")
        for source, replacement in protected_replacements.items():
            text = text.replace(source, replacement)
        for credential in credential_values:
            if credential:
                text = text.replace(credential, "[REDACTED_CREDENTIAL]")
        return text
    return value


def control_state() -> dict:
    result = management_query("""
select jsonb_build_object(
  'vehicle_count',(select count(*) from public.vehicles),
  'active_vehicle_count',(select count(*) from public.vehicles where lifecycle_state='active' and deleted_at is null),
  'controls',(select jsonb_agg(jsonb_build_object(
    'stock_number',v.stock_number,
    'id',v.id,
    'version',v.version,
    'updated_at',v.updated_at,
    'current_location',v.current_location,
    'lifecycle_state',v.lifecycle_state,
    'identity_fingerprint',encode(extensions.digest(convert_to(jsonb_build_object(
      'vin',v.vin,'registration',v.registration,'job_card_number',v.job_card_number,
      'customer_name',v.customer_name,'salesperson_reference',v.salesperson_reference
    )::text,'UTF8'),'sha256'),'hex')
  ) order by v.stock_number) from public.vehicles v where v.stock_number in ('13048501','U158318')),
  'notification_count',(select count(*) from public.vehicle_notifications),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
) state
""")[0]["state"]
    return result


def residue() -> dict:
    prefix = sql_literal(f"%{PREFIX}%")
    actor_email = sql_literal(f"%{ACTOR_EMAIL}%")
    vehicle = sql_literal(f"%{VEHICLE_ID}%")
    rows = management_write(f"""
set statement_timeout=0;
create temp table qa_scan(relation text,row_count bigint);
do $scan$ declare r record;c bigint;begin
 for r in select n.nspname schema_name,cl.relname table_name from pg_class cl join pg_namespace n on n.oid=cl.relnamespace where cl.relkind in('r','p') and n.nspname in('public','auth','storage') loop
  begin
   execute format('select count(*) from %I.%I x where row_to_json(x)::text ilike %L or row_to_json(x)::text ilike %L or row_to_json(x)::text ilike %L',r.schema_name,r.table_name,{prefix},{actor_email},{vehicle}) into c;
   if c>0 then insert into qa_scan values(r.schema_name||'.'||r.table_name,c);end if;
  exception when others then null;end;
 end loop;
end $scan$;
select jsonb_build_object('total',coalesce(sum(row_count),0),'relations',coalesce(jsonb_agg(jsonb_build_object('relation',relation,'count',row_count) order by relation),'[]'::jsonb)) residue from qa_scan
""")
    return rows[0]["residue"]


def vehicle_state() -> dict:
    rows = management_query(f"""
select jsonb_build_object(
 'vehicle',(select jsonb_build_object('id',v.id,'stock_number',v.stock_number,'job_card_number',v.job_card_number,'version',v.version,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state,'visible_on_board',v.visible_on_board,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'source_system',v.source_system,'source_batch_id',v.source_batch_id,'source_record_id',v.source_record_id) from public.vehicles v where v.id='{VEHICLE_ID}'::uuid),
 'work_items',(select coalesce(jsonb_agg(jsonb_build_object('work_key',w.work_key,'required',w.required,'completed',w.completed,'updated_at',w.updated_at) order by w.work_key),'[]'::jsonb) from public.vehicle_work_items w where w.vehicle_id='{VEHICLE_ID}'::uuid),
 'master_receipts',(select coalesce(jsonb_agg(jsonb_build_object('operation_kind',r.operation_kind,'idempotency_key',r.idempotency_key,'request_hash',r.request_hash,'response',r.response,'created_at',r.created_at) order by r.created_at),'[]'::jsonb) from public.vehicle_master_operation_receipts r where r.vehicle_id='{VEHICLE_ID}'::uuid),
 'requirement_receipts',(select coalesce(jsonb_agg(jsonb_build_object('receipt_id',r.receipt_id,'idempotency_key',r.idempotency_key,'request_sha256',r.request_sha256,'patched_keys',r.patched_keys,'before_work_states',r.before_work_states,'after_work_states',r.after_work_states,'created_at',r.created_at) order by r.created_at),'[]'::jsonb) from public.pdc_requirement_edit_receipts_772 r where r.vehicle_id='{VEHICLE_ID}'::uuid),
 'audit_events',(select coalesce(jsonb_agg(jsonb_build_object('action',a.action,'table_name',a.table_name,'before_data',a.before_data,'after_data',a.after_data,'metadata',a.metadata,'created_at',a.created_at) order by a.created_at),'[]'::jsonb) from public.audit_events a where a.vehicle_id='{VEHICLE_ID}'::uuid)
) state
""")
    return rows[0]["state"]


def rpc(name: str, payload: dict, anon_key: str, bearer: str) -> dict:
    status, body = request_json(
        f"https://{STAGING_REF}.supabase.co/rest/v1/rpc/{name}",
        "POST",
        {"apikey": anon_key, "Authorization": f"Bearer {bearer}", "Content-Type": "application/json", "Accept": "application/json"},
        payload,
    )
    return {"http_status": status, "body": body}


def cleanup() -> dict:
    rows = management_write(f"""
begin;
set local statement_timeout=0;
set local session_replication_role=replica;
create temp table qa_deleted(relation text primary key,row_count bigint,max_expected bigint);
with d as (delete from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.audit_events',count(*),1 from d;
with d as (delete from public.pdc_authenticated_email_import_receipts where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.pdc_authenticated_email_import_receipts',count(*),1 from d;
with d as (delete from public.pdc_requirement_edit_receipts_772 where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.pdc_requirement_edit_receipts_772',count(*),1 from d;
with d as (delete from public.vehicle_master_history where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.vehicle_master_history',count(*),3 from d;
with d as (delete from public.vehicle_master_operation_receipts where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.vehicle_master_operation_receipts',count(*),1 from d;
with d as (delete from public.vehicle_master_source_records where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.vehicle_master_source_records',count(*),1 from d;
with d as (delete from public.vehicle_work_items where vehicle_id='{VEHICLE_ID}'::uuid returning 1)
insert into qa_deleted select 'public.vehicle_work_items',count(*),1 from d;
with d as (delete from public.vehicles where id='{VEHICLE_ID}'::uuid and stock_number={sql_literal(STOCK)} and source_batch_id={sql_literal(PREFIX + '-AUD001-CORRECTION')} returning 1)
insert into qa_deleted select 'public.vehicles',count(*),1 from d;
with d as (delete from public.pdc_user_roles where lower(email)={sql_literal(ACTOR_EMAIL)} returning auth_user_id)
insert into qa_deleted select 'public.pdc_user_roles',count(*),1 from d;
with d as (delete from auth.identities where user_id in(select id from auth.users where lower(email)={sql_literal(ACTOR_EMAIL)}) returning 1)
insert into qa_deleted select 'auth.identities',count(*),1 from d;
with d as (delete from auth.users where lower(email)={sql_literal(ACTOR_EMAIL)} returning 1)
insert into qa_deleted select 'auth.users',count(*),1 from d;
do $bounds$ begin
 if exists(select 1 from qa_deleted where row_count>max_expected) then
  raise exception 'AUD001 cleanup exceeded manifest bounds';
 end if;
end $bounds$;
set local session_replication_role=origin;
commit;
select jsonb_build_object('deleted_total',coalesce(sum(row_count),0),'relations',coalesce(jsonb_agg(jsonb_build_object('relation',relation,'count',row_count,'max_expected',max_expected) order by relation),'[]'::jsonb)) cleanup from qa_deleted where row_count>0
""")
    return rows[0]["cleanup"]


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("refusing non-STAGING target")
    manifest = HERE / "aud001-remediation-fixture-manifest.json"
    if not manifest.is_file() or not json.loads(manifest.read_text(encoding="utf-8")).get("created_before_mutation"):
        raise RuntimeError("manifest-before-mutation requirement not met")

    initial_residue = residue()
    baseline = control_state()
    if initial_residue["total"] != 0 or baseline["production_sentinel_present"] or baseline["staging_sentinel_count"] != 1:
        raise RuntimeError(f"STAGING preflight failed: residue={initial_residue} state={baseline}")

    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    actor_id = ""
    service_key = ""
    anon_key = ""
    access_token = ""
    evidence: dict[str, object] = {
        "schema_version": 1,
        "task_id": "t_83f220c9",
        "generated_at": now(),
        "project_ref": STAGING_REF,
        "deployed_url": URL,
        "manifest_before_mutation": "lanes/transactions/aud001-remediation-fixture-manifest.json",
        "before_run": {"residue": initial_residue, "authoritative_controls": baseline},
        "transactions": {},
        "ui_readback": {},
        "cleanup": {},
        "containment": {"production_contacted": False, "production_mutated": False, "outbound_email_sent": False},
    }
    events: list[dict[str, object]] = []
    try:
        status, keys = request_json(
            f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys",
            headers={"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"},
        )
        if status != 200 or not isinstance(keys, list):
            raise RuntimeError("could not retrieve STAGING API key metadata")
        service_key = str(next((item.get("api_key") for item in keys if item.get("name") == "service_role"), ""))
        anon_key = str(next((item.get("api_key") for item in keys if item.get("name") in {"anon", "legacy_anon"}), ""))
        if not service_key or not anon_key:
            raise RuntimeError("required STAGING API keys unavailable")

        status, created = request_json(
            f"https://{STAGING_REF}.supabase.co/auth/v1/admin/users",
            "POST",
            {"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json", "Accept": "application/json"},
            {"email": ACTOR_EMAIL, "password": password, "email_confirm": True},
        )
        if status not in {200, 201} or not isinstance(created, dict) or not created.get("id"):
            raise RuntimeError(f"temporary actor creation failed with HTTP {status}")
        actor_id = str(created["id"])
        for _ in range(20):
            count = management_query(f"select count(*)::int count from public.pdc_user_roles where lower(email)={sql_literal(ACTOR_EMAIL)}")[0]["count"]
            if count == 1:
                break
            time.sleep(0.25)
        management_write(f"""
update public.pdc_user_roles set display_name='QA Overnight AUD-001 Verifier',role='administrator',active=true,account_status='approved',auth_user_id='{actor_id}'::uuid,approved_at=coalesce(approved_at,clock_timestamp()),updated_at=clock_timestamp() where lower(email)={sql_literal(ACTOR_EMAIL)};
insert into public.vehicles(id,permanent_vehicle_id,stock_number,vin,job_card_number,customer_name,vehicle_description,make,model,registration,lifecycle_state,visible_on_board,current_location,source_payload,source_system,source_batch_id,source_record_id,created_by,updated_by)
values('{VEHICLE_ID}'::uuid,{sql_literal('QA-OVERNIGHT-20260904-AUD001-PERM')},{sql_literal(STOCK)},{sql_literal(VIN)},{sql_literal(JOB_CARD)},{sql_literal(PREFIX + ' AUD001 CUSTOMER')},{sql_literal(PREFIX + ' AUD001 SYNTHETIC VEHICLE')},'TEST','SYNTHETIC',{sql_literal(REGISTRATION)},'active',true,'PMB',jsonb_build_object('contract','QA-OVERNIGHT-20260904-AUD001','synthetic',true),'qa_overnight_synthetic',{sql_literal(PREFIX + '-AUD001-CORRECTION')},{sql_literal(PREFIX + '-AUD001')},'{actor_id}'::uuid,'{actor_id}'::uuid);
insert into public.pdc_authenticated_email_import_receipts(
  actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,
  sender_address,source_received_at,stock_number,vin,vehicle_id,identity_source,
  required_work,response
)
values(
  '{actor_id}'::uuid,{sql_literal(PREFIX + '-EMAIL-RECEIPT')},repeat(md5({sql_literal(PREFIX + '-REQUEST')}),2),
  repeat(md5({sql_literal(PREFIX + '-SOURCE')}),2),repeat(md5({sql_literal(PREFIX + '-EVIDENCE')}),2),
  {sql_literal(PREFIX + '-SOURCE-UID')},'qa.aud001.20260904@example.invalid',clock_timestamp(),
  {sql_literal(STOCK)},{sql_literal(VIN)},'{VEHICLE_ID}'::uuid,'email_new','[]'::jsonb,
  jsonb_build_object('ok',true,'code','created','tag',{sql_literal(PREFIX)})
);
select true ok
""")
        seeded = vehicle_state()
        if seeded["vehicle"]["version"] != 1:
            raise RuntimeError("fixture seed did not produce version 1")

        status, auth_body = request_json(
            f"https://{STAGING_REF}.supabase.co/auth/v1/token?grant_type=password",
            "POST",
            {"apikey": anon_key, "Content-Type": "application/json", "Accept": "application/json"},
            {"email": ACTOR_EMAIL, "password": password},
        )
        if status != 200 or not isinstance(auth_body, dict) or not auth_body.get("access_token"):
            raise RuntimeError(f"temporary actor sign-in failed with HTTP {status}")
        access_token = str(auth_body["access_token"])

        edit_payload = {
            "p_vehicle_id": VEHICLE_ID,
            "p_expected_version": 1,
            "p_changes": {"customer_name": PREFIX + " AUD001 UPDATED"},
            "p_reason": EDIT_REASON,
            "p_idempotency_key": EDIT_KEY,
        }
        edit_success = rpc("edit_vehicle_master", edit_payload, anon_key, access_token)
        after_edit = vehicle_state()
        if edit_success["http_status"] != 200 or not isinstance(edit_success["body"], dict) or edit_success["body"].get("ok") is not True or after_edit["vehicle"]["version"] != 2:
            raise RuntimeError(f"edit success invariant failed: {edit_success}")

        stale_payload = {**edit_payload, "p_changes": {"customer_name": PREFIX + " AUD001 STALE"}, "p_idempotency_key": STALE_KEY}
        stale = rpc("edit_vehicle_master", stale_payload, anon_key, access_token)
        after_stale = vehicle_state()
        stale_body = stale["body"] if isinstance(stale["body"], dict) else {}
        stale_rejected = stale["http_status"] >= 400 or (stale_body.get("ok") is False and stale_body.get("code") == "stale_version")
        if not stale_rejected or after_stale["vehicle"]["version"] != 2 or after_stale["vehicle"]["customer_name"] != PREFIX + " AUD001 UPDATED":
            raise RuntimeError(f"stale-version denial invariant failed: {stale}")

        replay = rpc("edit_vehicle_master", edit_payload, anon_key, access_token)
        after_replay = vehicle_state()
        if replay["http_status"] != 200 or not isinstance(replay["body"], dict) or replay["body"].get("ok") is not True or after_replay["vehicle"]["version"] != 2:
            raise RuntimeError(f"idempotent replay invariant failed: {replay}")

        work_payload = {"p_vehicle_id": VEHICLE_ID, "p_expected_version": 2, "p_work_states": {"fabrication": "required"}}
        anonymous = rpc("set_pdc_vehicle_work_states", work_payload, anon_key, anon_key)
        after_anonymous = vehicle_state()
        anonymous_body = anonymous["body"] if isinstance(anonymous["body"], dict) else {}
        if anonymous["http_status"] != 401 or anonymous_body.get("code") != "42501" or "permission denied for function set_pdc_vehicle_work_states" not in str(anonymous_body.get("message", "")) or after_anonymous["vehicle"]["version"] != 2:
            raise RuntimeError(f"anonymous denial invariant failed: {anonymous}")

        authenticated = rpc("set_pdc_vehicle_work_states", work_payload, anon_key, access_token)
        after_authenticated = vehicle_state()
        fabrication = next((item for item in after_authenticated["work_items"] if item["work_key"] == "fabrication"), None)
        if authenticated["http_status"] != 200 or not isinstance(authenticated["body"], dict) or authenticated["body"].get("ok") is not True or after_authenticated["vehicle"]["version"] != 3 or not fabrication or not fabrication["required"] or fabrication["completed"]:
            raise RuntimeError(f"authenticated work-state invariant failed: {authenticated}")

        ready_payload = {"p_vehicle_id": VEHICLE_ID, "p_expected_version": 3}
        ready_denial = rpc("mark_vehicle_ready_for_qc", ready_payload, anon_key, access_token)
        after_ready = vehicle_state()
        ready_body = ready_denial["body"] if isinstance(ready_denial["body"], dict) else {}
        if ready_denial["http_status"] != 200 or ready_body.get("ok") is not False or ready_body.get("error") != "qc_gate_blocked" or "outstanding_required_work:FABRICATION" not in (ready_body.get("issues") or []) or after_ready["vehicle"]["version"] != 3 or after_ready["vehicle"]["current_location"] != "PMB":
            raise RuntimeError(f"QC negative gate invariant failed: {ready_denial}")

        evidence["transactions"] = {
            "A04": {"before_state": seeded, "request_payload_redacted": edit_payload, "response": replay, "authoritative_db_readback": after_replay, "audit_history_or_typed_action_receipt": after_replay["master_receipts"]},
            "A16": {"before_state": after_authenticated, "request_payload_redacted": ready_payload, "response": ready_denial, "authoritative_db_readback": after_ready, "audit_history_or_typed_action_receipt": {"typed_negative_action": "mark_vehicle_ready_for_qc", "audit_count_before": len(after_authenticated["audit_events"]), "audit_count_after": len(after_ready["audit_events"])}},
            "A21": {"before_state": after_replay, "request_payload_redacted": work_payload, "response": {"anonymous": anonymous, "authenticated": authenticated}, "authoritative_db_readback": {"after_anonymous": after_anonymous, "after_authenticated": after_authenticated}, "audit_history_or_typed_action_receipt": {"requirement_receipts": after_authenticated["requirement_receipts"], "audit_events": after_authenticated["audit_events"]}},
            "A22": {"before_state": seeded, "request_payload_redacted": {"valid": edit_payload, "stale": stale_payload}, "response": {"valid": edit_success, "stale": stale}, "authoritative_db_readback": after_stale, "audit_history_or_typed_action_receipt": after_stale["master_receipts"]},
            "A23": {"before_state": after_edit, "request_payload_redacted": edit_payload, "response": replay, "authoritative_db_readback": after_replay, "audit_history_or_typed_action_receipt": after_replay["master_receipts"]},
        }

        snapshot_readback = rpc("get_pdc_email_vehicle_location_snapshot", {}, anon_key, access_token)
        snapshot_vehicles = snapshot_readback.get("body", {}).get("data", {}).get("vehicles", []) if isinstance(snapshot_readback.get("body"), dict) else []
        snapshot_stocks = [item.get("stock_number") for item in snapshot_vehicles if isinstance(item, dict)]
        evidence["ui_readback"]["snapshot_rpc"] = {"http_status": snapshot_readback["http_status"], "fixture_present": STOCK in snapshot_stocks, "vehicle_count": len(snapshot_vehicles)}
        if snapshot_readback["http_status"] != 200 or STOCK not in snapshot_stocks:
            raise RuntimeError(f"fixture missing from authenticated snapshot: {evidence['ui_readback']['snapshot_rpc']}")

        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1280, "height": 900})
            page = context.new_page()
            page.set_default_timeout(10000)
            page.on("response", lambda response: events.append({"kind": "http_error", "status": response.status, "url": response.url}) if response.status >= 400 else None)
            page.on("request", lambda request: events.append({"kind": "production_request", "url": request.url}) if PRODUCTION_REF in request.url else None)
            page.on("pageerror", lambda error: events.append({"kind": "pageerror", "message": str(error)}))
            page.goto(URL + f"?aud001={int(time.time())}", wait_until="domcontentloaded", timeout=90000)
            page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
            if page.evaluate("() => document.body.dataset.authState") == "signed-out":
                page.locator("#pdc-login-email").fill(ACTOR_EMAIL)
                page.locator("#pdc-login-password").fill(password)
                page.locator("#pdc-password-login").click()
                page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=90000)
            page.locator('[data-view="dashboard"]').click()
            page.wait_for_function("stock => document.body.textContent.includes(stock)", arg=STOCK, timeout=90000)
            search = page.locator("#incoming-search")
            search.fill(STOCK)
            page.wait_for_timeout(1000)
            bucket = page.locator("details.incoming-pmb")
            if bucket.get_attribute("open") is None:
                bucket.locator(":scope > summary").click()
            card = page.locator(f".incoming-vehicle-card:has-text('{STOCK}')").first
            card.wait_for(state="visible", timeout=30000)
            card_text = card.inner_text()
            card_dom_text = card.text_content() or ""
            SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
            card.screenshot(path=str(SCREENSHOT))
            evidence["ui_readback"].update({
                "authenticated_role": "administrator",
                "fixture_visible": card.is_visible() and STOCK in card_dom_text,
                "exact_fixture_locator": f".incoming-vehicle-card:has-text('{STOCK}')",
                "fixture_card_text": card_text,
                "screenshot": str(SCREENSHOT.relative_to(EVIDENCE_ROOT)).replace("\\", "/"),
                "events": events,
            })
            context.close()
            browser.close()
        if not evidence["ui_readback"]["fixture_visible"] or any(event["kind"] in {"production_request", "pageerror"} for event in events):
            raise RuntimeError(f"fixture-specific UI read-back failed: {evidence['ui_readback']}")

    finally:
        pre_cleanup = residue()
        cleanup_result = cleanup() if pre_cleanup["total"] else {"deleted_total": 0, "relations": []}
        post_cleanup = residue()
        after_controls = control_state()
        evidence["cleanup"] = {
            "started_at": now(),
            "pre_cleanup": pre_cleanup,
            "bounded_delete": cleanup_result,
            "post_cleanup": post_cleanup,
            "authoritative_controls_after": after_controls,
            "real_vehicle_cardinality_unchanged": after_controls["vehicle_count"] == baseline["vehicle_count"],
            "active_vehicle_cardinality_unchanged": after_controls["active_vehicle_count"] == baseline["active_vehicle_count"],
            "protected_controls_unchanged": after_controls["controls"] == baseline["controls"],
            "notification_count_unchanged": after_controls["notification_count"] == baseline["notification_count"],
            "temporary_actor_removed": post_cleanup["total"] == 0,
        }
        credential_values = {password, service_key, anon_key, access_token}
        protected_replacements = {}
        for index, control in enumerate(baseline.get("controls") or []):
            suffix = chr(ord("A") + index)
            protected_replacements[str(control.get("stock_number"))] = f"[REDACTED_STOCK_{suffix}]"
            protected_replacements[str(control.get("id"))] = f"[REDACTED_PROTECTED_UUID_{suffix}]"
        evidence = scrub(evidence, actor_id, protected_replacements, credential_values)
        password = service_key = anon_key = access_token = ""
        OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")

    cleanup_evidence = evidence["cleanup"]
    ok = (
        cleanup_evidence["post_cleanup"]["total"] == 0
        and cleanup_evidence["real_vehicle_cardinality_unchanged"]
        and cleanup_evidence["active_vehicle_cardinality_unchanged"]
        and cleanup_evidence["protected_controls_unchanged"]
        and cleanup_evidence["notification_count_unchanged"]
        and set(evidence["transactions"]) == {"A04", "A16", "A21", "A22", "A23"}
        and evidence["ui_readback"].get("fixture_visible") is True
    )
    print(json.dumps({"ok": ok, "transactions": sorted(evidence["transactions"]), "ui_fixture_visible": evidence["ui_readback"].get("fixture_visible"), "cleanup_remaining": cleanup_evidence["post_cleanup"]["total"], "controls_unchanged": cleanup_evidence["protected_controls_unchanged"], "vehicle_cardinality": cleanup_evidence["authoritative_controls_after"]["vehicle_count"], "production_contacted": False, "outbound_email_sent": False}, indent=2))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
