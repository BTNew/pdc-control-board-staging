#!/usr/bin/env python3
"""Capture the exact live Parts STOPPAGE failure on STAGING only."""
from __future__ import annotations

import json
import secrets
import string
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

TASK = "t_fd63d897"
EMAIL = "functional.pdc.staging@example.com"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
BASE = f"https://{STAGING_REF}.supabase.co"
VEHICLE_ID = "fd63d897-0000-5000-8000-000000000376"
STOCK = "HERMES-PARTS-STOPPAGE-FD63D897"
OUT = Path(__file__).resolve().parents[1] / "review-evidence" / TASK / "parts-stoppage-live-pre.json"


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


def state() -> dict[str, object]:
    return management_write(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'function_definition',pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'function_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
        'function_owner',(select pg_get_userbyid(p.proowner) from pg_proc p where p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'function_security_definer',(select p.prosecdef from pg_proc p where p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'function_config',(select to_jsonb(p.proconfig) from pg_proc p where p.oid='public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),
        'acl',jsonb_build_object(
          'public',has_function_privilege('public','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute'),
          'anon',has_function_privilege('anon','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute'),
          'authenticated',has_function_privilege('authenticated','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute'),
          'service_role',has_function_privilege('service_role','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','execute')),
        'receipt_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.pdc_parts_stoppage_receipts_376'::regclass),
        'auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),
        'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),
        'vehicle_count',(select count(*) from public.vehicles where id='{VEHICLE_ID}'::uuid),
        'parts_count',(select count(*) from public.vehicle_parts_updates where vehicle_id='{VEHICLE_ID}'::uuid),
        'receipt_count',(select count(*) from public.pdc_parts_stoppage_receipts_376 where vehicle_id='{VEHICLE_ID}'::uuid),
        'audit_count',(select count(*) from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid),
        'notification_count',(select count(*) from public.vehicle_notifications),
        'monitor_staging_guard',public.pdc_monitor_staging_guard(),
        'active_mailbox_count',(select count(*) from public.monitored_mailboxes where active),
        'active_writer_count',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
      ) as result
    """)[0]["result"]


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    evidence: dict[str, object] = {
        "task": TASK,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "project_ref": STAGING_REF,
        "production_contacted": False,
        "email_sent": False,
        "credentials_redacted": True,
    }
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    user_id = ""
    service_key = ""
    assignment_applied = False
    fixture_created = False
    cleanup_errors: list[str] = []
    try:
        before = state()
        evidence["before"] = before
        if before["head"] != ["20260904011400", "pdc14_location_replay_partial_cleanup_identifier_repair"]:
            raise RuntimeError(f"unexpected STAGING head: {before['head']}")
        if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
            raise RuntimeError("STAGING sentinel preflight failed")
        if any(before[key] for key in ("auth_count", "role_count", "vehicle_count", "parts_count", "receipt_count")):
            raise RuntimeError("bounded diagnostic namespace is not clean")

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
        assignment = management_write("select public.apply_pdc14_staging_test_operator_role() as outcome")[0]["outcome"]
        assignment_applied = assignment.get("ok") is True
        evidence["operator_assignment"] = assignment
        if not assignment_applied:
            raise RuntimeError("temporary Operator assignment failed")
        management_write(f"""
          insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,
            lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,version,created_by,updated_by)
          values('{VEHICLE_ID}'::uuid,'HERMES-PARTS-PERM-FD63D897','{STOCK}','HERMES-JC-FD63D897','Parts Stoppage Fixture','Bounded Parts STOPPAGE diagnostic',
            'active',true,'YH','hermes_test','{TASK}','parts-stoppage',jsonb_build_object('bounded_fixture','{TASK}','email_sent',false),1,'{user_id}'::uuid,'{user_id}'::uuid);
          insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values('{VEHICLE_ID}'::uuid,'PARTS',true,false);
          insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by)
          values('{VEHICLE_ID}'::uuid,true,false,false,false,null,current_date+4,'{user_id}'::uuid);
        """)
        fixture_created = True
        idem = "fd63d897-0000-5000-8000-000000000001"
        rpc_status, rpc_body = http_json(
            f"{BASE}/rest/v1/rpc/set_pdc_parts_stoppage_376",
            method="POST",
            headers=user_headers,
            payload={"p_vehicle_id": VEHICLE_ID, "p_expected_version": 1, "p_idempotency_key": idem, "p_action": "set", "p_reason": f"{TASK} bounded delayed component"},
        )
        evidence["postgrest_failure"] = {"status": rpc_status, "body": rpc_body}
        evidence["after_rpc"] = state()
        if rpc_status != 500 or rpc_body != {"code": "55000", "details": None, "hint": None, "message": "PDC_376_RUNTIME_CONTAINMENT_MISMATCH"}:
            raise RuntimeError(f"expected exact live containment HTTP 500 before repair, got {rpc_status}: {rpc_body}")
        evidence["exact_failure_captured"] = True
    except Exception as error:
        evidence["execution_error"] = str(error)
        evidence["exact_failure_captured"] = False
    finally:
        if fixture_created:
            try:
                management_write(f"""
                  begin;
                  do $guard$
                  begin
                    if not exists(select 1 from public.vehicles where id='{VEHICLE_ID}'::uuid
                      and source_system='hermes_test' and source_batch_id='{TASK}'
                      and source_payload->>'bounded_fixture'='{TASK}' and created_by='{user_id}'::uuid) then
                      raise exception 'PDC_PARTS_STOPPAGE_DIAGNOSTIC_CLEANUP_PROVENANCE_MISMATCH';
                    end if;
                  end $guard$;
                  delete from public.vehicle_parts_updates where vehicle_id='{VEHICLE_ID}'::uuid;
                  alter table public.vehicle_work_items disable trigger user;
                  delete from public.vehicle_work_items where vehicle_id='{VEHICLE_ID}'::uuid;
                  alter table public.vehicle_work_items enable trigger user;
                  delete from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid;
                  delete from public.vehicles where id='{VEHICLE_ID}'::uuid;
                  commit;
                """)
            except Exception as error:
                cleanup_errors.append(f"fixture cleanup failed: {error}")
        if assignment_applied:
            try:
                management_write(f"select public.rollback_pdc14_staging_test_operator_role('{TASK} live diagnosis complete')")
            except Exception as error:
                cleanup_errors.append(f"role rollback failed: {error}")
        if user_id and service_key:
            status, body = http_json(f"{BASE}/auth/v1/admin/users/{user_id}", method="DELETE", headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Accept": "application/json"})
            if status not in (200, 204):
                cleanup_errors.append(f"auth cleanup failed: {status} {body}")
        if user_id:
            try:
                management_write(f"delete from public.pdc_user_roles where auth_user_id='{user_id}'::uuid and lower(email)='{EMAIL}'")
            except Exception as error:
                cleanup_errors.append(f"role cleanup failed: {error}")
        try:
            evidence["cleanup"] = state()
        except Exception as error:
            cleanup_errors.append(f"cleanup readback failed: {error}")
        evidence["cleanup_errors"] = cleanup_errors
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence["password_retained"] = False
        password = service_key = ""
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
        print(json.dumps({"evidence": str(OUT), "exact_failure_captured": evidence.get("exact_failure_captured"), "failure": evidence.get("postgrest_failure"), "cleanup_errors": cleanup_errors}, indent=2))
    cleanup = evidence.get("cleanup") or {}
    return 0 if evidence.get("exact_failure_captured") and not cleanup_errors and all(cleanup.get(key) == 0 for key in ("auth_count", "role_count", "vehicle_count", "parts_count", "receipt_count")) else 2


if __name__ == "__main__":
    raise SystemExit(main())
