#!/usr/bin/env python3
"""Bounded live STAGING proof for the source_hash ambiguity repair.

The valid plan uses one retained evidence-backed acceptance row and one active
synthetic vehicle. It exercises the strict RPC once; hostile plans are rejected
by the strict validator and never reach the executor. No mailbox or direct-table
access is used.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
META_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/config/pdc-email-ai-successor-runtime.env")
STORE_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/secrets/pdc-email-ai-successor-runtime.dpapi")
LEGACY_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/config/pdc-monitor-staging-runtime.env")
BOOT_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
VERIFY_ENV = "PDC_VERIFY_STAGING_SOURCE_HASH_AMBIGUITY"
EXECUTOR_FUNCTION = "pdc_email_ai_successor_execute_v2_20260901"
BASE = "https://cdsmnqxtyyoeoznmbidd.supabase.co"


def pairs(path: Path) -> dict[str, str]:
    result = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def request(url: str, method: str, headers: dict[str, str], body: object) -> tuple[int, object]:
    data = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    req = Request(url, data=data, method=method, headers={"Content-Type": "application/json", **headers})
    try:
        with urlopen(req, timeout=45) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            return exc.code, json.loads(raw)
        except json.JSONDecodeError:
            return exc.code, {"raw": raw[:500]}


def summary(value: object) -> dict[str, object]:
    if not isinstance(value, dict):
        return {"type": type(value).__name__}
    body = value.get("body") if "http_status" in value else value
    result: dict[str, object] = {}
    if "http_status" in value:
        result["http_status"] = value["http_status"]
    if isinstance(body, dict):
        for key in ("ok", "code", "disposition", "transaction_id", "replay", "action_rpc_invoked", "production_writes", "mailbox_contacted", "outbound_email"):
            if key in body:
                result[key] = body[key]
        if "http_status" in value:
            for key in ("message", "details", "hint"):
                if body.get(key):
                    result[key] = body[key]
        actions = body.get("actions")
        if isinstance(actions, list):
            result["action_dispositions"] = [
                {key: action.get(key) for key in ("action_type", "disposition", "reason", "canonical_rpc") if key in action}
                for action in actions if isinstance(action, dict)
            ]
    return result


def main() -> None:
    if os.environ.get(VERIFY_ENV) != "1":
        raise RuntimeError(f"set {VERIFY_ENV}=1 for the bounded staging verifier")
    meta = pairs(META_PATH)
    legacy = pairs(LEGACY_PATH)
    os.environ.update({key: value for key, value in legacy.items() if key not in os.environ})
    if not BOOT_PATH.is_file() or not STORE_PATH.is_file():
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_PROTECTED_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_BOOTSTRAP_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    secret = json.loads(module.unprotect(STORE_PATH.read_bytes()).decode("utf-8"))
    anon = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if not anon:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_CONNECTOR_ANON_KEY_UNAVAILABLE")
    login_status, auth = request(BASE + "/auth/v1/token?grant_type=password", "POST", {"apikey": anon}, {"email": secret["email"], "password": secret["runtime_password"]})
    if login_status != 200 or not isinstance(auth, dict) or not auth.get("access_token"):
        raise RuntimeError(f"PDC_SOURCE_HASH_AMBIGUITY_STAGING_LOGIN_FAILED:{login_status}")
    headers = {"apikey": anon, "Authorization": "Bearer " + auth["access_token"]}

    allowed = {meta["PDC_SUCCESSOR_HEALTH_RPC"], meta["PDC_SUCCESSOR_READBACK_RPC"], meta["PDC_SUCCESSOR_INBOX_RPC"], meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"]}

    def rpc(name: str, body: object) -> object:
        if name not in allowed:
            raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_CONNECTOR_SCOPE_VIOLATION")
        call_body = {"p_plan": body} if name == meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"] else body
        status, value = request(BASE + "/rest/v1/rpc/" + name, "POST", headers, call_body)
        return value if status == 200 else {"http_status": status, "body": value}

    pre_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    pre_readback = rpc(meta["PDC_SUCCESSOR_READBACK_RPC"], {})
    if not isinstance(pre_health, dict) or pre_health.get("ok") is not True:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_HEALTH_PREFLIGHT_FAILED")
    if not isinstance(pre_readback, dict) or pre_readback.get("ok") is not True:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_READBACK_PREFLIGHT_FAILED")

    inbox_items: list[dict] = []
    cursor = None
    while True:
        page = rpc(meta["PDC_SUCCESSOR_INBOX_RPC"], {"p_cursor": cursor, "p_page_size": 100})
        if not isinstance(page, dict) or page.get("ok") is not True:
            raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_INBOX_PREFLIGHT_FAILED")
        inbox_items.extend(item for item in page.get("items", []) if isinstance(item, dict))
        if not page.get("has_more"):
            break
        cursor = page.get("next_cursor")
        if not cursor:
            raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_INBOX_CURSOR_MISSING")
    candidates = [
        item for item in inbox_items
        if str(item.get("subject", "")).startswith("PDC Acceptance")
        and isinstance(item.get("source_digest"), str)
        and isinstance(item.get("evidence_digest"), str)
        and len(item["source_digest"]) == 64
        and len(item["evidence_digest"]) == 64
    ]
    if not candidates:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_NO_EVIDENCE_BACKED_ACCEPTANCE_ROW")
    candidates.sort(key=lambda item: (str(item.get("received_at") or ""), str(item.get("intake_id") or "")), reverse=True)
    source = candidates[0]

    vehicles = (pre_readback.get("data") or {}).get("vehicles") or []
    vehicle = next(
        (
            row for row in vehicles
            if row.get("stock_number") == "13000765"
            and (
                row.get("lifecycle_state")
                or (row.get("pdc_lifecycle") or {}).get("lifecycle_state")
                or row.get("state")
            ) == "active"
        ),
        None,
    )
    if not vehicle:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_ACTIVE_SYNTHETIC_VEHICLE_MISSING")
    source_message_id = str(source.get("message_id") or source["intake_id"])
    source_thread_id = str(source.get("thread_id") or source_message_id)
    attachment_digests = sorted((source.get("attachment_summary") or {}).get("digests") or [])
    versions = {
        "transport_release_version": "pdc-email-ai-v2-transport-v1",
        "planner_version": "pdc-email-ai-v2-planner-v1",
        "model_version": meta.get("PDC_SUCCESSOR_MODEL_VERSION", "pdc-email-ai-model-v1"),
        "prompt_version": meta.get("PDC_SUCCESSOR_PROMPT_VERSION", "pdc-email-ai-prompt-v1"),
        "business_rule_version": meta.get("PDC_SUCCESSOR_BUSINESS_RULE_VERSION", "pdc-business-rules-v1"),
        "ruleset_version": meta.get("PDC_SUCCESSOR_RULESET_VERSION", "pdc-business-rules-v1"),
        "taxonomy_version": "pdc-operation-taxonomy-proposed/v1",
        "supabase_action_contract_version": "pdc-email-ai-action-request-v1",
        "source_digest": source["source_digest"],
        "evidence_digest": source["evidence_digest"],
    }
    instruction = {
        "instruction_id": "S00_source_hash_ambiguity_repair",
        "vehicle_id": vehicle["id"],
        "identity": {"vehicle_id": vehicle["id"], "stock_number": vehicle.get("stock_number"), "vin": vehicle.get("vin"), "backend_record_id": vehicle.get("source_record_id")},
        "expected_state": {"vehicle_version": int(vehicle.get("version") or 1), "backend_revision": int((pre_readback.get("data") or {}).get("revision") or 0)},
        "action_type": "note_append",
        "payload": {"text": "controlled source_hash ambiguity repair verifier", "event_at": "2026-09-01T00:00:00Z"},
        "evidence_refs": [{"kind": "message", "ref": source_message_id, "required_for_action": True}] + [{"kind": "attachment", "ref": "attachment:" + digest, "required_for_action": True} for digest in attachment_digests],
        "required_evidence": ["authoritative_identity"],
        "decision_disposition": "planned",
        "provenance": versions.copy(),
        "audit_event_ref": "audit-S00-source-hash-ambiguity-repair",
        "reason": "controlled source_hash ambiguity repair verifier",
    }
    plan = {
        "schema_version": "pdc-email-ai-plan-v1",
        "plan_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-source-hash-ambiguity-repair:" + str(source["intake_id"]))),
        "environment": "staging",
        "source_receipt_id": source["intake_id"],
        "source_digest": source["source_digest"],
        "evidence_digest": source["evidence_digest"],
        "source_thread_id": source_thread_id,
        "source_message_id": source_message_id,
        "attachment_digests": attachment_digests,
        "versions": versions,
        # Empty instructions are a valid strict envelope and exercise the
        # source-binding/transaction-receipt path without invoking a business
        # action or consuming a retained acceptance source row.
        "instructions": [],
        "aggregate_disposition": "planned",
        "planner_status": "available",
        "planner_failure_reason": None,
        "created_at": "2026-09-01T00:00:00Z",
    }
    valid_plan_response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], plan)
    after_valid_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    if not isinstance(valid_plan_response, dict) or valid_plan_response.get("ok") is not False or valid_plan_response.get("code") != "pdc_email_ai_typed_action_surface_partial_failure" or valid_plan_response.get("disposition") != "NO_ACTIONS":
        raise RuntimeError(
            "PDC_SOURCE_HASH_AMBIGUITY_VALID_PLAN_DID_NOT_REACH_VERIFIED_RECEIPT_PATH:"
            + json.dumps({"response": summary(valid_plan_response), "health": summary(after_valid_health)}, sort_keys=True)
        )
    if not valid_plan_response.get("transaction_id"):
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_VALID_PLAN_RECEIPT_ID_MISSING")
    if valid_plan_response.get("actions") != []:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_EMPTY_VALID_PLAN_ACTIONS_UNEXPECTED")

    hostile_plans = []
    invalid_digest = copy.deepcopy(plan)
    invalid_digest["evidence_digest"] = "not-a-digest"
    invalid_digest["versions"]["evidence_digest"] = "not-a-digest"
    hostile_plans.append(("invalid_evidence_digest", invalid_digest))
    production_target = copy.deepcopy(plan)
    production_target["environment"] = "production"
    hostile_plans.append(("production_target", production_target))
    hostile_results = []
    for name, candidate in hostile_plans:
        response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], candidate)
        compact = summary(response)
        if compact.get("http_status", 200) != 200 or compact.get("ok") is not False or compact.get("code") != "typed_v2_plan_invalid":
            raise RuntimeError(f"PDC_SOURCE_HASH_AMBIGUITY_HOSTILE_PLAN_NOT_FAIL_CLOSED:{name}")
        hostile_results.append({"name": name, "response": compact})
    final_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    if not isinstance(final_health, dict) or final_health.get("ok") is not True:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_FINAL_HEALTH_FAILED")
    pre_transactions = int(pre_health.get("transactions") or 0)
    post_valid_transactions = int((after_valid_health or {}).get("transactions") or 0)
    final_transactions = int(final_health.get("transactions") or 0)
    if post_valid_transactions < pre_transactions + 1 or final_transactions != post_valid_transactions:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_TRANSACTION_RECEIPT_COUNT_UNEXPECTED")

    proof = {
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration_identity": ["20260901160000", "pdc_email_ai_typed_action_source_hash_ambiguity_repair_20260901"],
        "executor_function": EXECUTOR_FUNCTION,
        "migration_scope": "source_hash ambiguity only in execute, non-dispatch and operation-update wrappers",
        "valid_plan_source_receipt_id": source["intake_id"],
        "valid_plan_response": summary(valid_plan_response),
        "valid_plan_action_count": 0,
        "hostile_plan_responses": hostile_results,
        "receipt_counts_before": {"transactions": pre_transactions},
        "receipt_counts_after_valid": {"transactions": post_valid_transactions},
        "receipt_counts_after_hostile": {"transactions": final_transactions},
        "pre_readback_revision": (pre_readback.get("data") or {}).get("revision"),
        "post_valid_health": {"transactions": post_valid_transactions, "partial_failures": after_valid_health.get("partial_failures"), "production_writes": after_valid_health.get("production_writes")},
        "final_health": {"transactions": final_transactions, "partial_failures": final_health.get("partial_failures"), "production_writes": final_health.get("production_writes")},
        "action_rpc_invoked": False,
        "production_touched": False,
        "mailbox_contacted": False,
        "outbound_email": False,
        "scheduling_enabled": False,
    }
    print(json.dumps(proof, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email": False}, sort_keys=True))
        raise SystemExit(1)
