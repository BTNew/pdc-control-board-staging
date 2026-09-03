#!/usr/bin/env python3
"""Apply and verify the STAGING current-hours/fixture-generation migration."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from copy import deepcopy
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.pdc_email_ai_v2_actions import validate_v2_plan
from backend.pdc_email_ai_v2_planner import V2Planner
from scripts.diagnose_pdc_email_ai_actual_jwt_replay_staging_20260903 import (
    management_query,
    runtime_values,
)

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
VERSION = "20260903120000"
GENERATION_ID = "9cea2926-0002-4000-8000-000000000014"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260903120000"
MIGRATION = ROOT / "supabase/staging_only/20260903120000_pdc_email_ai_current_hours_fixture_generation_20260903.sql"
EVIDENCE = ROOT / "review-evidence/t_9cea2926/current-hours-fixture-generation-staging-verification.json"


def request_json(method: str, url: str, headers: dict[str, str], payload: Any | None = None) -> tuple[int, Any]:
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = {"redacted_error": raw.decode("utf-8", "replace")[:300]}
        return exc.code, parsed


def require_ok(status: int, body: Any, label: str) -> Any:
    if status < 200 or status >= 300:
        raise RuntimeError(f"{label}_HTTP_{status}: {body}")
    return body


def runtime_headers() -> tuple[str, dict[str, str], dict[str, str]]:
    values = runtime_values()  # profile: pdc-email-ai-lead/.env
    base = values["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    parsed = urllib.parse.urlparse(base)
    if parsed.hostname != f"{STAGING_REF}.supabase.co" or PRODUCTION_REF in base:
        raise RuntimeError("PDC_NON_STAGING_RUNTIME_TARGET_REFUSED")
    anon = values["PDC_STAGING_SUPABASE_ANON_KEY"]
    status, auth = request_json(
        "POST", f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
        {"email": values["PDC_EMAIL_AI_RUNTIME_EMAIL"], "password": values["PDC_EMAIL_AI_RUNTIME_PASSWORD"]},
    )
    auth = require_ok(status, auth, "RUNTIME_AUTH")
    return base, {
        "apikey": anon, "Authorization": f"Bearer {auth['access_token']}", "Content-Type": "application/json",
    }, {"apikey": anon, "Content-Type": "application/json"}


def rpc(base: str, headers: dict[str, str], function: str, payload: dict[str, Any]) -> tuple[int, Any]:
    if PRODUCTION_REF in base or STAGING_REF not in base:
        raise RuntimeError("PDC_NON_STAGING_RPC_TARGET_REFUSED")
    return request_json("POST", f"{base}/rest/v1/rpc/{function}", headers, payload)


def wait_for_generation(base: str, headers: dict[str, str]) -> dict[str, Any]:
    last: tuple[int, Any] = (0, None)
    for _ in range(20):
        last = rpc(base, headers, "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903", {"p_generation_id": GENERATION_ID})
        if last[0] == 200:
            return require_ok(*last, "FIXTURE_GENERATION")
        time.sleep(1)
    raise RuntimeError(f"POSTGREST_SCHEMA_RELOAD_TIMEOUT: {last}")


def make_plan(fixture: dict[str, Any]) -> dict[str, Any]:
    source = fixture["source"]
    extracted = source["extracted_data"]
    vehicle = fixture["authoritative_snapshot"]["vehicle"]
    context = {
        "vehicle_id": fixture["target_vehicle_id"],
        "stock_number": vehicle.get("stock_number"),
        "vin": vehicle.get("vin_normalized") or vehicle.get("vin"),
        "backend_record_id": vehicle.get("backend_record_id"),
        "vehicle_version": vehicle.get("vehicle_version") or 1,
        "backend_revision": vehicle.get("backend_revision") or 0,
    }
    attachments = []
    for attachment in source["attachments"]:
        attachments.append({
            "digest": attachment["source_hash"],
            "filename": attachment["file_name"],
            "extracted_text": attachment["extracted_text"],
            "stock_number": extracted["stock_number"],
            "vin": context["vin"],
            "lines": extracted["operation_lines"],
        })
    receipt = {
        "receipt_id": fixture["source_receipt_id"],
        "source_digest": fixture["source_digest"],
        "evidence_digest": fixture["evidence_digest"],
        "thread_id": fixture["source_thread_id"],
        "message_id": fixture["source_message_id"],
        "source_uid": source["provider_uid"],
        "received_at": source["received_at"],
        "correspondence": source["correspondence"],
    }
    plan = V2Planner().plan(receipt, attachments, [context])
    validate_v2_plan(plan, authoritative_contexts=[context])
    return plan


def main() -> None:
    if os.environ.get(APPROVAL) != "YES":
        raise RuntimeError(f"Set {APPROVAL}=YES for this reversible STAGING-only migration")
    sql = MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("MIGRATION_STAGING_GUARD_MARKERS_INVALID")

    installed = management_query(
        "SELECT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903120000' "
        "AND name='pdc_email_ai_current_hours_fixture_generation_20260903') AS present"
    )[0]["present"]
    if not installed:
        management_query(sql)  # Supabase CLI:supabase management credential; STAGING ref is hard pinned.
    verification = management_query("""
      SELECT
        (SELECT version FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version DESC LIMIT 1) AS ledger_head,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 WHERE generation_id='9cea2926-0002-4000-8000-000000000014'::uuid) AS fresh_fixture_count,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=f.source_receipt_id) AS consumed_fixture_count,
        encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS validator_sha256,
        encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS executor_sha256,
        position('(''job_card'',''ai_estimate'',''business_rule_default'')' IN pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure))>0 AS ai_estimate_installed,
        NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903','select') AS fixture_table_private,
        to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL AS production_sentinel_present
    """)[0]
    if int(str(verification["ledger_head"])) < int(VERSION) or int(verification["fresh_fixture_count"]) != 14:
        raise RuntimeError(f"DEPLOYED_POSTCONDITION_FAILED: {verification}")
    if int(verification["consumed_fixture_count"]) != 0 or not verification["ai_estimate_installed"] or not verification["fixture_table_private"] or verification["production_sentinel_present"]:
        raise RuntimeError(f"DEPLOYED_SAFETY_POSTCONDITION_FAILED: {verification}")

    immutability = management_query("""
      DO $test$
      BEGIN
        BEGIN
          UPDATE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 SET scenario_key=scenario_key WHERE generation_id='9cea2926-0002-4000-8000-000000000014'::uuid;
          RAISE EXCEPTION 'fixture mutation unexpectedly succeeded';
        EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
        BEGIN
          UPDATE public.ai_email_intake SET subject=subject WHERE id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 LIMIT 1);
          RAISE EXCEPTION 'source mutation unexpectedly succeeded';
        EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
        BEGIN
          DELETE FROM public.ai_email_attachments WHERE intake_id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 LIMIT 1);
          RAISE EXCEPTION 'attachment mutation unexpectedly succeeded';
        EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
      END $test$;
      SELECT true AS fixture_source_attachment_immutability_verified;
    """)[0]

    base, headers, anon_headers = runtime_headers()
    generation = wait_for_generation(base, headers)
    fixtures = generation.get("fixtures") or []
    if not generation.get("ok") or generation.get("generation_id") != GENERATION_ID or len(fixtures) != 14:
        raise RuntimeError("RUNTIME_FIXTURE_GENERATION_INVALID")
    if any(bool(row.get("consumed")) for row in fixtures):
        raise RuntimeError("RUNTIME_FIXTURE_GENERATION_NOT_FRESH")

    validation_rows: list[dict[str, Any]] = []
    plans: list[dict[str, Any]] = []
    action_types: set[str] = set()
    dispositions: set[str] = set()
    current_hours_cases: dict[str, int] = {"ai_estimate_1_0": 0, "job_card_2_5": 0, "job_card_0_0": 0}
    for fixture in fixtures:
        plan = make_plan(fixture)
        plans.append(plan)
        for instruction in plan["instructions"]:
            action_types.add(instruction["action_type"])
            dispositions.add(instruction["decision_disposition"])
            if instruction["action_type"] == "operation_add":
                payload = instruction["payload"]
                pair = (payload.get("estimated_hours"), payload.get("estimated_hours_source"))
                if pair == (1.0, "ai_estimate"):
                    current_hours_cases["ai_estimate_1_0"] += 1
                elif pair == (2.5, "job_card"):
                    current_hours_cases["job_card_2_5"] += 1
                elif pair == (0.0, "job_card"):
                    current_hours_cases["job_card_0_0"] += 1
        status, result = rpc(base, headers, "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903", {"p_generation_id": GENERATION_ID, "p_plan": plan})
        require_ok(status, result, f"VALIDATE_SCENARIO_{fixture['scenario_no']}")
        if not result.get("ok") or result.get("code") != "typed_v2_plan_valid":
            raise RuntimeError(f"VALIDATOR_REJECTED_SCENARIO_{fixture['scenario_no']}: {result}")
        validation_rows.append({"scenario_no": fixture["scenario_no"], "scenario_key": fixture["scenario_key"], "code": result["code"], "instruction_count": result["instruction_count"]})
    if not all(value == 14 for value in current_hours_cases.values()):
        raise RuntimeError(f"CURRENT_HOURS_CASE_COUNTS_INVALID: {current_hours_cases}")

    hostile = deepcopy(plans[0])
    hostile["instructions"][0]["action_type"] = "sql"
    hostile_status, hostile_result = rpc(base, headers, "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903", {"p_generation_id": GENERATION_ID, "p_plan": hostile})
    changed = deepcopy(plans[0])
    changed["source_message_id"] = "changed-source-message@invalid"
    changed_status, changed_result = rpc(base, headers, "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903", {"p_generation_id": GENERATION_ID, "p_plan": changed})
    strict_status, strict_hostile = rpc(base, headers, "apply_pdc_email_ai_typed_action_surface_20260901_strict", {"p_plan": {"environment": "production", "instructions": [{"action_type": "sql", "payload": "DROP TABLE vehicles"}]}})
    if hostile_status != 200 or hostile_result.get("ok") or hostile_result.get("code") != "typed_v2_plan_invalid":
        raise RuntimeError(f"HOSTILE_VALIDATOR_REJECTION_FAILED: {hostile_status} {hostile_result}")
    if changed_status != 200 or changed_result.get("ok") or changed_result.get("code") != "acceptance_fixture_plan_binding_invalid":
        raise RuntimeError(f"CHANGED_PLAN_REJECTION_FAILED: {changed_status} {changed_result}")
    if strict_status != 200 or strict_hostile.get("ok") or strict_hostile.get("code") != "typed_v2_plan_invalid":
        raise RuntimeError(f"STRICT_HOSTILE_REJECTION_FAILED: {strict_status} {strict_hostile}")

    protected_tables = (
        "pdc_email_ai_v2_acceptance_fixture_generations_20260903",
        "pdc_email_ai_v2_acceptance_fixtures_generation_20260903",
        "pdc_email_ai_current_hours_repairs_20260903",
    )
    protected_table_http_statuses: dict[str, dict[str, int]] = {}
    for table in protected_tables:
        auth_status, _ = request_json("GET", f"{base}/rest/v1/{table}?select=*&limit=1", headers)
        anon_status, _ = request_json("GET", f"{base}/rest/v1/{table}?select=*&limit=1", anon_headers)
        if 200 <= auth_status < 300 or 200 <= anon_status < 300:
            raise RuntimeError(f"PROTECTED_TABLE_HTTP_EXPOSURE: {table} auth={auth_status} anon={anon_status}")
        protected_table_http_statuses[table] = {"runtime": auth_status, "anon": anon_status}

    final_fresh = management_query("""
      SELECT count(*) AS fresh_fixture_count,
        count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.source_receipt_id=f.source_receipt_id)) AS consumed_fixture_count
      FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903 f
      WHERE f.generation_id='9cea2926-0002-4000-8000-000000000014'::uuid
    """)[0]
    if int(final_fresh["fresh_fixture_count"]) != 14 or int(final_fresh["consumed_fixture_count"]) != 0:
        raise RuntimeError(f"FINAL_FRESHNESS_CHECK_FAILED: {final_fresh}")

    report = {
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration": VERSION,
        "generation_id": GENERATION_ID,
        "fixture_rpc": "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903",
        "validation_rpc": "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903",
        "fresh_fixture_count": int(final_fresh["fresh_fixture_count"]),
        "consumed_fixture_count": int(final_fresh["consumed_fixture_count"]),
        "runtime_jwt_validation": validation_rows,
        "all_fixture_plans_validated": len(validation_rows) == 14,
        "observed_action_types": sorted(action_types),
        "observed_dispositions": sorted(dispositions),
        "current_hours_case_counts": current_hours_cases,
        "hostile_plan_rejection": {"http_status": hostile_status, "code": hostile_result.get("code")},
        "changed_plan_rejection": {"http_status": changed_status, "code": changed_result.get("code")},
        "strict_surface_hostile_rejection": {"http_status": strict_status, "code": strict_hostile.get("code")},
        "protected_table_http_statuses": protected_table_http_statuses,
        "deployed_contract": verification,
        "fixture_source_attachment_immutability_verified": bool(immutability["fixture_source_attachment_immutability_verified"]),
        "production_contacted": False,
        "production_writes": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "migration": VERSION, "generation_id": GENERATION_ID, "fresh_fixture_count": 14, "validated_fixture_count": 14, "proof": str(EVIDENCE)}, sort_keys=True))


if __name__ == "__main__":
    main()
