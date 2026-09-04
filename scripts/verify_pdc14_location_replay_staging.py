#!/usr/bin/env python3
"""Authenticated PDC-14 location replay verification on STAGING only."""
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

EMAIL = "functional.pdc.staging@example.com"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
BASE = f"https://{STAGING_REF}.supabase.co"
VEHICLE_ID = "67594974-0000-5000-8000-000000000014"
STOCK = "HERMES-PDC14-67594974"
OUT = Path(__file__).resolve().parents[1] / "review-evidence/t_67594974/location-authenticated-replay.json"


def http_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: dict | None = None, allow_error: bool = False):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, data=body, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        if not allow_error:
            raise RuntimeError(f"HTTP {error.code}: {raw[:500]}") from error
        try:
            return error.code, json.loads(raw) if raw else None
        except json.JSONDecodeError:
            return error.code, {"error_present": bool(raw)}


def counts() -> dict[str, object]:
    return management_query(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),
        'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),
        'vehicle_count',(select count(*) from public.vehicles where id='{VEHICLE_ID}'::uuid),
        'movement_count',(select count(*) from public.vehicle_movements where vehicle_id='{VEHICLE_ID}'::uuid),
        'receipt_count',(select count(*) from public.pdc_vehicle_location_receipts_20260904 where vehicle_id='{VEHICLE_ID}'::uuid),
        'audit_count',(select count(*) from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid and action='move')
      ) as result
    """)[0]["result"]


def rpc(headers: dict[str, str], *, vehicle_id: str | None, expected_version: int, location: str, request_key: str):
    return http_json(
        f"{BASE}/rest/v1/rpc/set_pdc_vehicle_location_1500",
        method="POST",
        headers=headers,
        payload={
            "p_vehicle_id": vehicle_id,
            "p_expected_version": expected_version,
            "p_location": location,
            "p_request_key": request_key,
        },
        allow_error=True,
    )


def insert_fixture(user_id: str) -> None:
    management_write(f"""
      insert into public.vehicles(
        id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,
        lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,
        source_payload,version,created_by,updated_by
      ) values(
        '{VEHICLE_ID}'::uuid,'HERMES-PDC14-PERM-67594974','{STOCK}','HERMES-JC-PDC14','PDC-14 Fixture','PDC-14 Replay Fixture',
        'active',true,'YH','hermes_test','t_67594974','location-replay',
        '{{"bounded_fixture":"t_67594974","email_sent":false}}'::jsonb,1,'{user_id}'::uuid,'{user_id}'::uuid
      )
    """)


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    evidence: dict[str, object] = {
        "task": "t_67594974",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "project_ref": STAGING_REF,
        "email_sent": False,
        "production_contacted": False,
        "credentials_redacted": True,
    }
    user_id = ""
    service_key = ""
    assignment_applied = False
    cleanup_errors: list[str] = []
    try:
        before = counts()
        evidence["before"] = before
        if before["head"] != ["20260904011400", "pdc14_location_replay_partial_cleanup_identifier_repair"]:
            raise RuntimeError(f"unexpected STAGING head {before['head']}")
        if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
            raise RuntimeError("STAGING sentinel preflight failed")
        if before["auth_count"] or before["role_count"] or before["vehicle_count"]:
            raise RuntimeError("bounded fixture namespace is not clean")

        management_headers = {"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"}
        _, keys = http_json(f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys", headers=management_headers)
        service_entry = next((item for item in keys or [] if item.get("name") == "service_role"), None)
        public_entry = next((item for item in keys or [] if item.get("name") in {"anon", "publishable"}), None)
        service_key = str((service_entry or {}).get("api_key") or "")
        public_key = str((public_entry or {}).get("api_key") or "")
        if not service_key or not public_key:
            raise RuntimeError("STAGING API keys unavailable")

        admin_headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json", "Accept": "application/json"}
        status, created = http_json(f"{BASE}/auth/v1/admin/users", method="POST", headers=admin_headers, payload={"email": EMAIL, "password": password, "email_confirm": True})
        user_id = str((created or {}).get("id") or "")
        if status != 200 or not user_id:
            raise RuntimeError("temporary Auth Admin createUser failed")

        status, token = http_json(f"{BASE}/auth/v1/token?grant_type=password", method="POST", headers={"apikey": public_key, "Content-Type": "application/json", "Accept": "application/json"}, payload={"email": EMAIL, "password": password})
        access_token = str((token or {}).get("access_token") or "")
        if status != 200 or not access_token:
            raise RuntimeError("temporary user password login failed")
        user_headers = {"apikey": public_key, "Authorization": f"Bearer {access_token}", "Accept": "application/json", "Content-Type": "application/json"}

        denied_status, denied_body = rpc(user_headers, vehicle_id=None, expected_version=1, location="PMB", request_key="pdc14-pending-role-denied-67594974")
        evidence["pending_role_denied"] = {"status": denied_status, "body": denied_body}
        denied_error = str((denied_body or {}).get("message") or (denied_body or {}).get("error") or "")
        if denied_status != 403 or denied_error != "PDC role operator required":
            raise RuntimeError(f"pending/lower-role caller did not fail at the role gate: {denied_status}, {denied_body}")

        assignment = management_write("select public.apply_pdc14_staging_test_operator_role() as outcome")[0]["outcome"]
        assignment_applied = assignment.get("ok") is True
        evidence["operator_assignment"] = assignment
        if not assignment_applied:
            raise RuntimeError("temporary Operator assignment failed")

        insert_fixture(user_id)
        partial_cleanup = management_write("select public.cleanup_pdc14_location_replay_fixture_20260904() as outcome")[0]["outcome"]
        partial_readback = counts()
        evidence["partial_fixture_cleanup_probe"] = {"outcome": partial_cleanup, "readback": partial_readback}
        if partial_cleanup.get("ok") is not True or partial_cleanup.get("code") != "bounded_fixture_cleaned" or partial_readback["vehicle_count"] != 0:
            raise RuntimeError(f"partial fixture cleanup probe failed: {partial_cleanup}, {partial_readback}")
        insert_fixture(user_id)

        key = "pdc14-location-replay-67594974"
        valid_status, valid = rpc(user_headers, vehicle_id=VEHICLE_ID, expected_version=1, location="PMB", request_key=key)
        replay_status, replay = rpc(user_headers, vehicle_id=VEHICLE_ID, expected_version=1, location="PMB", request_key=key)
        conflict_status, conflict = rpc(user_headers, vehicle_id=VEHICLE_ID, expected_version=1, location="PIT", request_key=key)
        stale_status, stale = rpc(user_headers, vehicle_id=VEHICLE_ID, expected_version=1, location="PIT", request_key="pdc14-location-stale-67594974")
        invalid_status, invalid = rpc(user_headers, vehicle_id=VEHICLE_ID, expected_version=2, location="YH", request_key="pdc14-location-lifecycle-67594974")
        evidence["rpc_matrix"] = {
            "valid": {"status": valid_status, "body": valid},
            "exact_replay": {"status": replay_status, "body": replay},
            "request_reuse_conflict": {"status": conflict_status, "body": conflict},
            "stale_version": {"status": stale_status, "body": stale},
            "disallowed_transition": {"status": invalid_status, "body": invalid},
        }
        if valid_status != 200 or (valid or {}).get("code") != "pdc_location_updated":
            raise RuntimeError("valid YH to PMB mutation failed")
        if replay_status != 200 or replay != valid:
            raise RuntimeError("exact replay did not return the immutable original response")
        if (conflict or {}).get("error") != "idempotency_conflict":
            raise RuntimeError("request-key payload conflict did not fail closed")
        if (stale or {}).get("error") != "vehicle_version_conflict":
            raise RuntimeError("stale expected version did not fail closed")
        if (invalid or {}).get("error") != "invalid_pdc_location_transition":
            raise RuntimeError("disallowed lifecycle transition did not fail closed")

        readback = management_query(f"""
          select jsonb_build_object(
            'vehicle',(select jsonb_build_object('id',id,'location',current_location,'version',version,'date_to_pmb',date_to_pmb,'rule_version',source_payload->>'location_rule_version') from public.vehicles where id='{VEHICLE_ID}'::uuid),
            'movement_count',(select count(*) from public.vehicle_movements where vehicle_id='{VEHICLE_ID}'::uuid),
            'audit_count',(select count(*) from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid and action='move'),
            'receipt_count',(select count(*) from public.pdc_vehicle_location_receipts_20260904 where vehicle_id='{VEHICLE_ID}'::uuid and actor_id='{user_id}'::uuid),
            'valid_receipt',(select jsonb_build_object('request_key',request_key,'response',response,'before',vehicle_version_before,'after',vehicle_version_after) from public.pdc_vehicle_location_receipts_20260904 where actor_id='{user_id}'::uuid and request_key='{key}'),
            'private_to_authenticated',not has_table_privilege('authenticated','public.pdc_vehicle_location_receipts_20260904','select')
          ) as result
        """)[0]["result"]
        evidence["authoritative_readback"] = readback
        if readback["vehicle"]["location"] != "PMB" or readback["vehicle"]["version"] != 2 or readback["movement_count"] != 1 or readback["audit_count"] != 1 or readback["receipt_count"] != 3 or not readback["private_to_authenticated"]:
            raise RuntimeError(f"authoritative receipt/movement/audit readback failed: {readback}")
        evidence["all_checks_passed"] = True
    except Exception as error:
        evidence["execution_error"] = str(error)
        evidence["all_checks_passed"] = False
    finally:
        try:
            cleanup_result = management_write("select public.cleanup_pdc14_location_replay_fixture_20260904() as outcome")[0]["outcome"]
            evidence["bounded_fixture_cleanup"] = cleanup_result
            if cleanup_result.get("ok") is not True:
                raise RuntimeError(f"bounded fixture cleanup failed closed: {cleanup_result}")
        except Exception as error:
            cleanup_errors.append(f"vehicle cleanup failed: {error}")
        if assignment_applied:
            try:
                management_write("select public.rollback_pdc14_staging_test_operator_role('t_67594974 location replay verification complete')")
            except Exception as error:
                cleanup_errors.append(f"role rollback failed: {error}")
        if user_id and service_key:
            try:
                http_json(f"{BASE}/auth/v1/admin/users/{user_id}", method="DELETE", headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Accept": "application/json"})
            except Exception as error:
                cleanup_errors.append(f"auth cleanup failed: {error}")
        try:
            management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
        except Exception as error:
            cleanup_errors.append(f"role cleanup failed: {error}")
        try:
            evidence["cleanup"] = counts()
        except Exception as error:
            cleanup_errors.append(f"cleanup readback failed: {error}")
        evidence["cleanup_errors"] = cleanup_errors
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence["password_retained"] = False
        password = service_key = ""
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
        print(json.dumps({
            "evidence": str(OUT),
            "all_checks_passed": evidence.get("all_checks_passed", False),
            "cleanup_auth_count": (evidence.get("cleanup") or {}).get("auth_count"),
            "cleanup_role_count": (evidence.get("cleanup") or {}).get("role_count"),
            "cleanup_vehicle_count": (evidence.get("cleanup") or {}).get("vehicle_count"),
            "cleanup_errors": cleanup_errors,
            "credentials_redacted": True,
        }, indent=2))
    clean = evidence.get("cleanup") or {}
    return 0 if evidence.get("all_checks_passed") and not cleanup_errors and clean.get("auth_count") == 0 and clean.get("role_count") == 0 and clean.get("vehicle_count") == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
