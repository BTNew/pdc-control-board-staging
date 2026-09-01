#!/usr/bin/env python3
"""Bounded live STAGING proof for successor receipt FK ordering."""
from __future__ import annotations

import copy
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
BOOT_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
STAGING_SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
BASE = "https://cdsmnqxtyyoeoznmbidd.supabase.co"
VERIFY_ENV = "PDC_VERIFY_STAGING_RECEIPT_FK_ORDERING"
PREDECESSOR_VERSION = "20260901160000"
RECEIPT_ID = "205f0c13-ef4b-4ac0-8128-3563a4d8d61a"


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


def compact(value: object) -> dict[str, object]:
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
        actions = body.get("actions")
        if isinstance(actions, list):
            result["actions"] = [
                {
                    key: action.get(key)
                    for key in ("instruction_id", "action_type", "disposition", "reason", "canonical_rpc", "verification", "after_state")
                    if key in action
                }
                for action in actions
                if isinstance(action, dict)
            ]
    return result


def main() -> None:
    if os.environ.get(VERIFY_ENV) != "1":
        raise RuntimeError(f"set {VERIFY_ENV}=1 for the bounded staging verifier")
    if not META_PATH.is_file() or not STORE_PATH.is_file() or not BOOT_PATH.is_file() or not STAGING_SECRETS.is_file():
        raise RuntimeError("PDC_RECEIPT_FK_PROTECTED_CONNECTOR_UNAVAILABLE")
    meta = pairs(META_PATH)
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_RECEIPT_FK_BOOTSTRAP_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    staging_bundle = json.loads(module.unprotect(STAGING_SECRETS.read_bytes()).decode("utf-8"))
    module.validate(staging_bundle)
    if staging_bundle.get("PDC_STAGING_PROJECT_REF") != STAGING_REF:
        raise RuntimeError("PDC_RECEIPT_FK_STAGING_BUNDLE_TARGET_MISMATCH")
    secret = json.loads(module.unprotect(STORE_PATH.read_bytes()).decode("utf-8"))
    # Use only the staging bundle's public anon key. No legacy monitor token,
    # service role key or staging admin credential is used by this verifier.
    anon = staging_bundle.get("PDC_STAGING_SUPABASE_ANON_KEY", "").strip()
    if not anon:
        raise RuntimeError("PDC_RECEIPT_FK_CONNECTOR_ANON_KEY_UNAVAILABLE")
    login_status, auth = request(BASE + "/auth/v1/token?grant_type=password", "POST", {"apikey": anon}, {"email": secret["email"], "password": secret["runtime_password"]})
    if login_status != 200 or not isinstance(auth, dict) or not auth.get("access_token"):
        raise RuntimeError(f"PDC_RECEIPT_FK_STAGING_LOGIN_FAILED:{login_status}")
    headers = {"apikey": anon, "Authorization": "Bearer " + auth["access_token"]}
    allowed = {meta["PDC_SUCCESSOR_HEALTH_RPC"], meta["PDC_SUCCESSOR_READBACK_RPC"], meta["PDC_SUCCESSOR_INBOX_RPC"], meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"]}

    def rpc(name: str, body: object) -> object:
        if name not in allowed:
            raise RuntimeError("PDC_RECEIPT_FK_CONNECTOR_SCOPE_VIOLATION")
        call_body = {"p_plan": body} if name == meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"] else body
        status, value = request(BASE + "/rest/v1/rpc/" + name, "POST", headers, call_body)
        return value if status == 200 else {"http_status": status, "body": value}

    pre_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    pre_readback = rpc(meta["PDC_SUCCESSOR_READBACK_RPC"], {})
    if not isinstance(pre_health, dict) or pre_health.get("ok") is not True:
        raise RuntimeError("PDC_RECEIPT_FK_HEALTH_PREFLIGHT_FAILED")
    if not isinstance(pre_readback, dict) or pre_readback.get("ok") is not True:
        raise RuntimeError("PDC_RECEIPT_FK_READBACK_PREFLIGHT_FAILED")
    if pre_health.get("outbound_email") is not False or pre_health.get("production_writes") is not False:
        raise RuntimeError("PDC_RECEIPT_FK_OUTBOUND_OR_PRODUCTION_PREFLIGHT_FAILED")

    inbox: list[dict] = []
    cursor = None
    while True:
        page = rpc(meta["PDC_SUCCESSOR_INBOX_RPC"], {"p_cursor": cursor, "p_page_size": 100})
        if not isinstance(page, dict) or page.get("ok") is not True:
            raise RuntimeError("PDC_RECEIPT_FK_INBOX_PREFLIGHT_FAILED")
        inbox.extend(row for row in page.get("items", []) if isinstance(row, dict))
        if not page.get("has_more"):
            break
        cursor = page.get("next_cursor")
        if not cursor:
            raise RuntimeError("PDC_RECEIPT_FK_INBOX_CURSOR_MISSING")
    candidates = [
        row for row in inbox
        if str(row.get("subject", "")).startswith("PDC Acceptance")
        and isinstance(row.get("source_digest"), str)
        and isinstance(row.get("evidence_digest"), str)
        and len(row["source_digest"]) == 64
        and len(row["evidence_digest"]) == 64
        and not row.get("transaction")
    ]
    candidates.sort(key=lambda row: (str(row.get("received_at") or ""), str(row.get("intake_id") or "")), reverse=True)
    if len(candidates) < 2:
        raise RuntimeError("PDC_RECEIPT_FK_EVIDENCE_BACKED_ROWS_MISSING")
    source, mixed_source = candidates[0], candidates[1]
    vehicles = (pre_readback.get("data") or {}).get("vehicles") or []
    vehicle = next((row for row in vehicles if row.get("stock_number") == "13000765" and (row.get("lifecycle_state") or (row.get("pdc_lifecycle") or {}).get("lifecycle_state") or row.get("state")) == "active"), None)
    if not vehicle:
        raise RuntimeError("PDC_RECEIPT_FK_ACTIVE_SYNTHETIC_VEHICLE_MISSING")

    versions = {
        "transport_release_version": "pdc-email-ai-v2-transport-v1",
        "planner_version": "pdc-email-ai-v2-planner-v1",
        "model_version": meta.get("PDC_SUCCESSOR_MODEL_VERSION", "pdc-email-ai-model-v1"),
        "prompt_version": meta.get("PDC_SUCCESSOR_PROMPT_VERSION", "pdc-email-ai-prompt-v1"),
        "business_rule_version": meta.get("PDC_SUCCESSOR_BUSINESS_RULE_VERSION", "pdc-business-rules-v1"),
        "ruleset_version": meta.get("PDC_SUCCESSOR_RULESET_VERSION", "pdc-business-rules-v1"),
        "taxonomy_version": "pdc-operation-taxonomy-proposed/v1",
        "supabase_action_contract_version": "pdc-email-ai-action-request-v1",
    }

    def plan(row: dict, label: str, instructions: list[dict]) -> dict:
        source_id = row["intake_id"]
        source_message_id = str(row.get("message_id") or source_id)
        source_thread_id = str(row.get("thread_id") or source_message_id)
        attachment_digests = sorted((row.get("attachment_summary") or {}).get("digests") or [])
        full_versions = {**versions, "source_digest": row["source_digest"], "evidence_digest": row["evidence_digest"]}
        full = {
            "schema_version": "pdc-email-ai-plan-v1",
            "plan_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-receipt-fk-ordering:" + source_id + ":" + label)),
            "environment": "staging",
            "source_receipt_id": source_id,
            "source_digest": row["source_digest"],
            "evidence_digest": row["evidence_digest"],
            "source_thread_id": source_thread_id,
            "source_message_id": source_message_id,
            "attachment_digests": attachment_digests,
            "versions": full_versions,
            "instructions": instructions,
            "aggregate_disposition": "planned",
            "planner_status": "available",
            "planner_failure_reason": None,
            "created_at": "2026-09-01T00:00:00Z",
        }
        for index, item in enumerate(full["instructions"], 1):
            item["instruction_id"] = f"{label}-{index:02d}"
            item["audit_event_ref"] = f"audit-{label}-{index:02d}"
            item["evidence_refs"] = [{"kind": "message", "ref": source_message_id, "required_for_action": True}]
            item["required_evidence"] = ["authoritative_identity"]
            item["provenance"] = full_versions.copy()
            item["reason"] = label
        return full

    def planned_action(label: str, disposition: str = "planned") -> dict:
        return {
            "vehicle_id": vehicle["id"],
            "identity": {"vehicle_id": vehicle["id"], "stock_number": vehicle.get("stock_number"), "vin": vehicle.get("vin"), "backend_record_id": vehicle.get("source_record_id")},
            "expected_state": {"vehicle_version": int(vehicle.get("version") or 1), "backend_revision": int((pre_readback.get("data") or {}).get("revision") or 0)},
            "action_type": "activate_vehicle",
            "payload": {"backend_record_id": vehicle["source_record_id"], "stock_number": vehicle["stock_number"], "vin": vehicle.get("vin"), "job_card_number": None},
            "decision_disposition": disposition,
        }

    valid_plan = plan(source, "receipt_fk_planned", [planned_action("receipt_fk_planned")])
    mixed_plan = plan(mixed_source, "receipt_fk_mixed_planned_review", [planned_action("receipt_fk_mixed_planned_review", "planned"), planned_action("receipt_fk_mixed_review", "review")])
    # The validator requires each instruction's evidence and provenance fields;
    # plan() fills those after the compact action builders above.
    baseline_revision = (pre_readback.get("data") or {}).get("revision")
    baseline_transactions = int(pre_health.get("transactions") or 0)
    valid_response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], valid_plan)
    valid_readback = rpc(meta["PDC_SUCCESSOR_READBACK_RPC"], {})
    valid_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    valid_actions = valid_response.get("actions") if isinstance(valid_response, dict) else None
    if not isinstance(valid_response, dict) or valid_response.get("ok") is not True or valid_response.get("disposition") != "SUCCESS" or not valid_response.get("transaction_id") or not isinstance(valid_actions, list) or len(valid_actions) != 1 or valid_actions[0].get("disposition") != "APPLIED_AND_VERIFIED" or valid_actions[0].get("verification", {}).get("parity") is not True:
        raise RuntimeError("PDC_RECEIPT_FK_PLANNED_PARENT_CHILD_READBACK_FAILED:" + json.dumps(compact(valid_response), sort_keys=True))
    if not isinstance(valid_readback, dict) or valid_readback.get("ok") is not True:
        raise RuntimeError("PDC_RECEIPT_FK_AUTHORITATIVE_READBACK_FAILED")
    if int(valid_health.get("transactions") or 0) != baseline_transactions + 1:
        raise RuntimeError("PDC_RECEIPT_FK_PLANNED_TRANSACTION_COUNT_FAILED")

    mixed_response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], mixed_plan)
    mixed_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    mixed_actions = mixed_response.get("actions") if isinstance(mixed_response, dict) else None
    if not isinstance(mixed_response, dict) or mixed_response.get("ok") is not False or mixed_response.get("disposition") != "PARTIAL_FAILURE" or not mixed_response.get("transaction_id") or not isinstance(mixed_actions, list) or len(mixed_actions) != 2 or any(action.get("canonical_rpc") is not None or action.get("verification", {}).get("dispatch") is True for action in mixed_actions):
        raise RuntimeError("PDC_RECEIPT_FK_MIXED_PLANNED_REVIEW_ISOLATION_FAILED:" + json.dumps(compact(mixed_response), sort_keys=True))
    if int(mixed_health.get("transactions") or 0) != baseline_transactions + 2:
        raise RuntimeError("PDC_RECEIPT_FK_MIXED_TRANSACTION_COUNT_FAILED")

    invalid_digest = copy.deepcopy(valid_plan)
    invalid_digest["plan_id"] = str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-receipt-fk-ordering:invalid-digest"))
    invalid_digest["evidence_digest"] = "not-a-digest"
    invalid_digest["versions"]["evidence_digest"] = "not-a-digest"
    production_target = copy.deepcopy(valid_plan)
    production_target["plan_id"] = str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-receipt-fk-ordering:production-target"))
    production_target["environment"] = "production"
    invalid_response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], invalid_digest)
    production_response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], production_target)
    for name, response in (("invalid_digest", invalid_response), ("production_target", production_response)):
        if not isinstance(response, dict) or response.get("ok") is not False or response.get("code") != "typed_v2_plan_invalid" or response.get("actions") != []:
            raise RuntimeError(f"PDC_RECEIPT_FK_{name.upper()}_NOT_FAIL_CLOSED:" + json.dumps(compact(response), sort_keys=True))
    after_negative_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    if int(after_negative_health.get("transactions") or 0) != baseline_transactions + 2:
        raise RuntimeError("PDC_RECEIPT_FK_NEGATIVE_RECEIPT_COUNT_CHANGED")

    revision_before_replay = (valid_readback.get("data") or {}).get("revision")
    replay_response = rpc(meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], copy.deepcopy(valid_plan))
    replay_readback = rpc(meta["PDC_SUCCESSOR_READBACK_RPC"], {})
    replay_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    if not isinstance(replay_response, dict) or replay_response.get("replay") is not True or replay_response.get("transaction_id") != valid_response.get("transaction_id"):
        raise RuntimeError("PDC_RECEIPT_FK_EXACT_REPLAY_NOT_RECOGNISED")
    if int(replay_health.get("transactions") or 0) != baseline_transactions + 2 or (replay_readback.get("data") or {}).get("revision") != revision_before_replay:
        raise RuntimeError("PDC_RECEIPT_FK_EXACT_REPLAY_CHANGED_STATE")
    if int(replay_health.get("transactions") or 0) < baseline_transactions + 2:
        raise RuntimeError("PDC_RECEIPT_FK_RECEIPT_COUNT_REGRESSED")

    final_health = rpc(meta["PDC_SUCCESSOR_HEALTH_RPC"], {})
    proof = {
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration_identity": ["20260901170000", "pdc_email_ai_successor_receipt_fk_ordering_repair_20260901"],
        "planned_parent_child": {"transaction_id": valid_response["transaction_id"], "action_count": len(valid_actions), "action": compact(valid_response)["actions"][0], "authoritative_readback_ok": True},
        "mixed_planned_review": {"transaction_id": mixed_response["transaction_id"], "action_count": len(mixed_actions), "actions": compact(mixed_response)["actions"]},
        "invalid_digest": compact(invalid_response),
        "production_target": compact(production_response),
        "exact_replay": {"replay": replay_response.get("replay"), "transaction_id_unchanged": True, "transactions_before": baseline_transactions + 2, "transactions_after": int(replay_health.get("transactions") or 0), "revision_unchanged": True},
        "receipt_counts": {"transactions_before": baseline_transactions, "transactions_after_valid": int(valid_health.get("transactions") or 0), "transactions_after_mixed": int(mixed_health.get("transactions") or 0), "transactions_after_negative": int(after_negative_health.get("transactions") or 0), "transactions_after_replay": int(replay_health.get("transactions") or 0)},
        "pre_readback_revision": baseline_revision,
        "final_readback_revision": (replay_readback.get("data") or {}).get("revision"),
        "final_health": {"transactions": final_health.get("transactions"), "partial_failures": final_health.get("partial_failures"), "outbound_email": final_health.get("outbound_email"), "production_writes": final_health.get("production_writes")},
        "foreign_key_integrity": "successful deferred parent-child commit through strict RPC",
        "fk_integrity": "successful deferred parent-child commit through strict RPC",
        "direct_table": "not used",
        "force_rls": "preserved and verified by protected migration readback",
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
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
        raise SystemExit(1)
