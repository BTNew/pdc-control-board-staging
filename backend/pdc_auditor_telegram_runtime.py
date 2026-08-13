#!/usr/bin/env python
"""Bounded, signed Telegram ingress for typed AI Auditor operation proposals.

Natural language is deliberately reduced to an allowlisted typed command.  The
migration-253 RPCs own matching, immutable plans, replay/nonce reservation,
authorisation, atomic apply and strict undo.  This module never accepts SQL or
an arbitrary action name.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Mapping
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

STAGING_PROJECT = "cdsmnqxtyyoeoznmbidd"
STAGING_URL = f"https://{STAGING_PROJECT}.supabase.co"
CRAIG_TELEGRAM_ID = 7828138290
PLAN_RPC = "plan_pdc_auditor_typed_instruction_253"
COMPOSE_RPC = "compose_pdc_auditor_typed_plan_253"
APPLY_RPC = "apply_pdc_auditor_typed_plan_253"
RULE_RPC = "rule_pdc_auditor_telegram_227"
UNDO_RPC = "undo_last_pdc_auditor_typed_run_253"
QUERY_RPC = "query_pdc_auditor_typed_253"
MAX_GATEWAY_TTL_SECONDS = 300
MAX_ISSUED_AT_SKEW_SECONDS = 30
GATEWAY_ENVELOPE_KEYS = frozenset({
    "gateway_instance_id", "delivery_uuid", "key_id", "nonce", "issued_at",
    "expires_at", "instruction_sha256", "selected_scope", "telegram_evidence", "signature",
})
TELEGRAM_EVIDENCE_KEYS = frozenset({
    "original_instruction", "telegram_sender_id", "telegram_chat_id",
    "telegram_message_id", "telegram_update_id", "bot_identity", "instruction_sha256",
})
GATEWAY_SIGNING_FIELD_ORDER = (
    "gateway_instance_id", "delivery_uuid", "key_id", "nonce", "issued_at",
    "expires_at", "instruction_sha256", "selected_scope", "telegram_evidence",
)


class AuditorContractError(ValueError):
    pass


def _exact_url(value: str) -> str:
    p = urlsplit(value)
    if (p.scheme != "https" or p.hostname != f"{STAGING_PROJECT}.supabase.co"
            or p.port is not None or p.username or p.password
            or p.path not in ("", "/") or p.query or p.fragment):
        raise AuditorContractError("Supabase URL is not the exact staging origin")
    return STAGING_URL


INTENT_CONTRACT = "pdc-auditor-bounded-intent-253-v1"
COMPOSE_SELECTION_CONTRACT = "pdc-auditor-compose-selection-253-v1"
APPLY_SELECTION_CONTRACT = "pdc-auditor-apply-selection-253-v1"
UNDO_SELECTION_CONTRACT = "pdc-auditor-undo-selection-253-v1"
QUERY_SELECTION_CONTRACT = "pdc-auditor-query-selection-253-v1"
SELECTOR_KEYS = frozenset({"operation_ref", "operation_refs", "vehicle_id", "job_card_number", "category"})
WORK_KEYS = frozenset({"fitting", "tint", "hoist", "electrical", "fabrication", "tyre", "pitInspection"})


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip()).lower()


def _uuid(value: Any, label: str) -> str:
    try:
        parsed = str(uuid.UUID(value))
    except (TypeError, ValueError, AttributeError):
        raise AuditorContractError(f"{label} is invalid") from None
    if not isinstance(value, str) or value.lower() != parsed:
        raise AuditorContractError(f"{label} is invalid")
    return parsed


def _operation_ref(value: Any, label: str = "operation_ref") -> str:
    if not isinstance(value, str) or not re.fullmatch(
            r"(?:source|auditor):[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", value):
        raise AuditorContractError(f"{label} is invalid")
    _uuid(value.split(":", 1)[1], label)
    return value


def _operation_refs(value: Any, label: str = "operation_refs") -> list[str]:
    if not isinstance(value, list) or not 2 <= len(value) <= 100:
        raise AuditorContractError(f"{label} is invalid")
    refs = [_operation_ref(v, label) for v in value]
    if len(refs) != len(set(refs)):
        raise AuditorContractError(f"{label} is invalid")
    return refs


def _job_card(value: Any) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,63}", value):
        raise AuditorContractError("job_card_number is invalid")
    return value


def _category(value: Any) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9_]{1,39}", value):
        raise AuditorContractError("category is invalid")
    return value


def _identifier(value: Any, label: str) -> str:
    """Bounded non-secret gateway identifier (not an operation reference)."""
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", value):
        raise AuditorContractError(f"{label} is invalid")
    return value


def _selector(context: Mapping[str, Any]) -> dict[str, Any]:
    present = [key for key in SELECTOR_KEYS if context.get(key) is not None]
    if len(present) != 1:
        return {}
    key = present[0]
    raw = context[key]
    if key == "operation_ref": value = _operation_ref(raw)
    elif key == "operation_refs": value = _operation_refs(raw)
    elif key == "vehicle_id": value = _uuid(raw, key)
    elif key == "job_card_number": value = _job_card(raw)
    else: value = _category(raw)
    return {key: value}


def _hours(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise AuditorContractError("estimated_hours is invalid")
    result = float(value)
    if result < .25 or result > 999.75 or round(result * 4) != result * 4:
        raise AuditorContractError("estimated_hours must use quarter-hour precision")
    return result


def _new_value(value: Any, *, complete: bool) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise AuditorContractError("trusted new_value is required")
    allowed = {"description", "work_key", "estimated_hours", "operation_code", "ordered_position"}
    if not set(value) <= allowed or not value or (complete and not {"description", "work_key", "estimated_hours"} <= set(value)):
        raise AuditorContractError("new_value fields are invalid")
    result = dict(value)
    if "description" in result and (not isinstance(result["description"], str) or not 1 <= len(result["description"]) <= 180):
        raise AuditorContractError("description is invalid")
    if "work_key" in result and result["work_key"] not in WORK_KEYS:
        raise AuditorContractError("work_key is invalid")
    if "estimated_hours" in result: result["estimated_hours"] = _hours(result["estimated_hours"])
    if "operation_code" in result and (not isinstance(result["operation_code"], str) or not re.fullmatch(r"[A-Za-z0-9._/-]{1,64}", result["operation_code"])):
        raise AuditorContractError("operation_code is invalid")
    if "ordered_position" in result and (isinstance(result["ordered_position"], bool) or not isinstance(result["ordered_position"], int) or not 1 <= result["ordered_position"] <= 10000):
        raise AuditorContractError("ordered_position is invalid")
    return result


def _trusted(context: Mapping[str, Any]) -> dict[str, Any]:
    value = context.get("trusted_intent", {})
    if not isinstance(value, Mapping):
        raise AuditorContractError("trusted_intent is invalid")
    return dict(value)


def _clarify(question: str = "Select exactly one exact operation ref, operation-ref set, vehicle, job card, or category.") -> dict[str, Any]:
    return {"action": "clarification", "question": question}


def _intent(selector: Mapping[str, Any], context: Mapping[str, Any], **desired: Any) -> dict[str, Any]:
    """One exact runtime/SQL typed-intent shape; authoritative state is DB-owned."""
    if not selector:
        return {}
    apply_unambiguous = context.get("apply_unambiguous", False)
    if not isinstance(apply_unambiguous, bool):
        raise AuditorContractError("apply_unambiguous is invalid")
    return {"contract": INTENT_CONTRACT, "action": "", "apply_unambiguous": apply_unambiguous,
            "selector": dict(selector), "desire": dict(desired)}


def _parse_typed_mutation(text: str, context: Mapping[str, Any]) -> tuple[str, dict[str, Any]] | None:
    """Return a SQL action and one exact bounded intent; complex values are trusted-context only."""
    t, selector, trusted = _norm(text), _selector(context), _trusted(context)
    duplicate = "duplicate" in t and (t.startswith("duplicate ") or any(
        v in t for v in ("review", "find", "show", "remove", "delete", "deduplicate")))
    if duplicate:
        if set(selector) != {"operation_refs"}: return ("", {})
        desired: dict[str, Any] = {"duplicate_proof": "database_exact"}
        survivor = trusted.get("survivor_operation_ref")
        if survivor is None: return ("", {})
        desired["survivor_operation_ref"] = _operation_ref(survivor, "survivor_operation_ref")
        if desired["survivor_operation_ref"] not in selector["operation_refs"]:
            raise AuditorContractError("duplicate survivor is not selected")
        return "remove_duplicate", _intent(selector, context, **desired)

    if "gvm" in t and any(v in t for v in ("adjust", "change", "fix", "update", "correct", "review")):
        match = re.search(r"\b(\d+(?:\.\d{1,2})?)\s*(?:hours?|hrs?)\b", t)
        if not match: return ("", {})
        return "edit", _intent({"category": "gvm_upgrade"}, context,
                               new_value={"estimated_hours": _hours(float(match.group(1)))})
    if ("long-range fuel tank" in t or "long range fuel tank" in t) and any(v in t for v in ("move", "change", "fix", "update", "correct", "review")):
        return "edit", _intent({"category": "long_range_fuel_tank"}, context,
                               new_value={"work_key": "hoist"})

    if re.match(r"^add\b", t):
        if set(selector) != {"vehicle_id"}: return ("", {})
        try: new = _new_value(trusted.get("new_value"), complete=True)
        except AuditorContractError: return ("", {})
        return "add", _intent(selector, context, new_value=new)

    edit = re.fullmatch(r"(?:edit|change|set|correct) (?:this operation(?:'s)? |operation )?(description|code|department|hours)(?: to)? (.+)", text, re.I)
    if edit:
        if set(selector) != {"operation_ref"}: return ("", {})
        field, raw = edit.group(1).lower(), edit.group(2).strip()
        departments = {"fitting": "fitting", "tint": "tint", "hoist": "hoist", "hoist/gvm": "hoist",
                       "electrical": "electrical", "fabrication": "fabrication", "tyre": "tyre",
                       "pit": "pitInspection", "pit inspection": "pitInspection"}
        if field == "hours":
            match = re.fullmatch(r"(\d+(?:\.\d{1,2})?)\s*(?:hours?|hrs?)", raw, re.I)
            if not match: return ("", {})
            new = {"estimated_hours": _hours(float(match.group(1)))}
        elif field == "department":
            if raw.lower() not in departments: return ("", {})
            new = {"work_key": departments[raw.lower()]}
        elif field == "code": new = _new_value({"operation_code": raw}, complete=False)
        else: new = _new_value({"description": raw}, complete=False)
        return "edit", _intent(selector, context, new_value=new)

    if re.match(r"^split\b", t):
        if set(selector) != {"operation_ref"}: return ("", {})
        children = trusted.get("children")
        if not isinstance(children, list) or not 2 <= len(children) <= 20: return ("", {})
        try: typed_children = [_new_value(child, complete=True) for child in children]
        except AuditorContractError: return ("", {})
        if any("ordered_position" in child for child in typed_children): return ("", {})
        return "split", _intent(selector, context, children=typed_children)

    if re.match(r"^combine\b", t):
        if set(selector) != {"operation_refs"}: return ("", {})
        survivor = trusted.get("survivor_operation_ref")
        try:
            survivor = _operation_ref(survivor, "survivor_operation_ref")
            new = _new_value(trusted.get("new_value"), complete=True)
        except AuditorContractError: return ("", {})
        if "operation_code" not in new: return ("", {})
        if "ordered_position" in new: return ("", {})
        if survivor not in selector["operation_refs"]: raise AuditorContractError("combine survivor is not selected")
        return "combine", _intent(selector, context, survivor_operation_ref=survivor, new_value=new)

    if re.match(r"^reorder\b", t):
        try: ordered = _operation_refs(trusted.get("ordered_operation_refs"), "ordered_operation_refs")
        except AuditorContractError: return ("", {})
        return "reorder", _intent({"operation_refs": ordered}, context,
                                  complete_effective_set=True)
    return None


def parse_instruction(instruction: str, context: Mapping[str, Any] | None = None) -> dict[str, Any]:
    if not isinstance(instruction, str) or instruction != instruction.strip() or not 3 <= len(instruction) <= 4000:
        raise AuditorContractError("instruction is invalid")
    c, t = dict(context or {}), _norm(instruction)

    if t == "compose these reviewed corrections":
        proposals = c.get("reviewed_proposal_ids")
        try:
            if not isinstance(proposals, list) or len(proposals) != 6:
                raise AuditorContractError("reviewed_proposal_ids")
            proposal_ids = [_uuid(value, "reviewed_proposal_id") for value in proposals]
            if len(set(proposal_ids)) != 6:
                raise AuditorContractError("reviewed_proposal_ids")
        except AuditorContractError:
            return _clarify("Select exactly six distinct reviewed proposals: Add, Edit, Split, Combine, Reorder and Remove Duplicate.")
        selected = {"contract": COMPOSE_SELECTION_CONTRACT, "proposal_ids": proposal_ids}
        return {"action": "compose_reviewed_proposals", "mode": "compose", "selected_scope": selected}

    if t == "apply these corrections":
        try:
            proposal_id = _uuid(c.get("reviewed_proposal_id"), "reviewed_proposal_id")
            proposal_version = c.get("reviewed_proposal_version")
            if isinstance(proposal_version, bool) or not isinstance(proposal_version, int) or proposal_version < 1:
                raise AuditorContractError("proposal version")
            hashes = {}
            for field in ("proposal_hash", "typed_item_set_hash", "final_scope_hash", "expected_row_versions_hash"):
                value = c.get(f"reviewed_{field}")
                if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
                    raise AuditorContractError(field)
                hashes[field] = value
        except AuditorContractError:
            return _clarify("Select the exact final reviewed proposal version and all four binding hashes.")
        selected = {"contract": APPLY_SELECTION_CONTRACT, "proposal_id": proposal_id,
                    "proposal_version": proposal_version, **hashes}
        return {"action": "apply_reviewed_proposal", "mode": "apply_reviewed", "selected_scope": selected}

    if t == "undo the selected auditor run":
        try:
            run_id = _uuid(c.get("selected_run_id"), "selected_run_id")
            revision = c.get("selected_run_revision_after")
            if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{64}", revision):
                raise AuditorContractError("selected_run_revision_after is invalid")
        except AuditorContractError:
            return _clarify("Select the exact Auditor run and its reviewed after-state revision.")
        selected = {"contract": UNDO_SELECTION_CONTRACT, "run_id": run_id,
                    "run_revision_after": revision}
        return {"action": "undo_selected_run", "mode": "undo", "selected_scope": selected}

    if t.startswith("why did you change") or t.startswith("why was this changed"):
        try:
            vehicle_id, job_card = _uuid(c.get("vehicle_id"), "vehicle_id"), _job_card(c.get("job_card_number"))
        except AuditorContractError:
            return _clarify("Which exact vehicle UUID and job-card number should I explain?")
        return {"action": "operation_snapshot", "mode": "query", "selected_scope": {
            "contract": QUERY_SELECTION_CONTRACT, "vehicle_id": vehicle_id,
            "job_card_number": job_card}}

    # Rule RPC 227 is intentionally a separate legacy contract. Keep its baseline
    # grammar and evidence shape; it is not represented as a typed operation plan.
    if t in {"show auditor rules", "show learned rules", "show rules"}:
        return {"action": "show_rules", "mode": "rule", "selected_scope": {}}
    if t in {"undo my last rule", "undo the last rule", "undo last rule"}:
        return {"action": "undo_last_rule", "mode": "rule", "selected_scope": {}}
    if t.startswith("disable the ") and t.endswith(" rule"):
        return {"action": "disable_rule", "mode": "rule", "selected_scope": {"rule_selector": t[12:-5].strip()}}

    explicit_apply = bool(re.match(r"^apply\s+", t))
    body = re.sub(r"^apply\s+", "", instruction, count=1, flags=re.I) if explicit_apply else instruction
    review = bool(re.match(r"^(review|audit|check|find|show)\b", _norm(body)))
    parse_body = re.sub(r"^(?:review|audit|check|find|show)\s+", "", body, count=1, flags=re.I) if review else body
    parsed = _parse_typed_mutation(parse_body, c)
    if parsed is None or not parsed[0] or not parsed[1]:
        return _clarify("Provide one exact selector and all required typed values in trusted structured context.")
    action, selected = parsed
    selected["action"] = action
    return {"action": action, "mode": "review" if review else "apply", "selected_scope": selected}


def bind_telegram(update: Any, *, expected_chat_id: int, bot_identity: str) -> dict[str, Any]:
    if not isinstance(update, Mapping) or not {"update_id", "message"}.issubset(update):
        raise AuditorContractError("Telegram update keys are invalid")
    m = update["message"]
    required_message = {"message_id", "from", "chat", "date", "text"}
    if not isinstance(m, Mapping) or not required_message.issubset(m):
        raise AuditorContractError("Telegram message keys are invalid")
    sender = m["from"]
    if (not isinstance(sender, Mapping) or not {"id", "is_bot", "first_name"}.issubset(sender)
            or sender["is_bot"] is not False or isinstance(sender["id"], bool)
            or not isinstance(sender["id"], int) or sender["id"] < 1
            or not isinstance(sender["first_name"], str) or not sender["first_name"].strip()):
        raise AuditorContractError("Telegram sender shape is invalid")
    chat = m["chat"]
    if (not isinstance(chat, Mapping) or chat.get("id") != expected_chat_id
            or chat.get("type") != "private"):
        raise AuditorContractError("Telegram chat is not the configured private chat")
    text = m["text"]
    if not isinstance(text, str) or text != text.strip() or not 3 <= len(text) <= 4000:
        raise AuditorContractError("Telegram text is invalid")
    for key in ("message_id", "date"):
        if not isinstance(m[key], int) or isinstance(m[key], bool) or m[key] < 1:
            raise AuditorContractError(f"Telegram {key} is invalid")
    if not isinstance(update["update_id"], int) or isinstance(update["update_id"], bool) or update["update_id"] < 1:
        raise AuditorContractError("Telegram update ID is invalid")
    if not isinstance(bot_identity, str) or not bot_identity:
        raise AuditorContractError("bot identity is invalid")
    return {"original_instruction": text, "telegram_sender_id": sender["id"],
            "telegram_chat_id": expected_chat_id, "telegram_message_id": m["message_id"],
            "telegram_update_id": update["update_id"],
            "bot_identity": bot_identity,
            "instruction_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()}


def canonical_json(value: Any) -> bytes:
    """Deterministic UTF-8 JSON; non-JSON values and NaN are rejected."""
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                          allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise AuditorContractError("value is not canonical JSON") from exc


def gateway_signing_bytes(envelope: Mapping[str, Any]) -> bytes:
    if not isinstance(envelope, Mapping) or set(envelope) != GATEWAY_ENVELOPE_KEYS:
        raise AuditorContractError("gateway envelope keys are invalid")
    # Length-prefixing makes delimiters unambiguous.  The SQL verifier uses the
    # same exact field order and compact canonical JSON for the two JSON fields.
    values = []
    for field in GATEWAY_SIGNING_FIELD_ORDER:
        raw = canonical_json(envelope[field]) if field in {"selected_scope", "telegram_evidence"} \
            else str(envelope[field]).encode("utf-8")
        name = field.encode("ascii")
        values.append(name + b":" + str(len(raw)).encode("ascii") + b":" + raw)
    return b"pdc-auditor-envelope-253-v1\n" + b"\n".join(values)


def _utc_timestamp(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", value):
        raise AuditorContractError("gateway timestamps are invalid")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        raise AuditorContractError("gateway timestamps are invalid") from None
    if parsed.tzinfo != timezone.utc:
        raise AuditorContractError(f"{label} is invalid")
    return parsed


def validate_gateway_envelope(envelope: Any, *, instruction: str,
                              selected_scope: Mapping[str, Any],
                              key_resolver: Callable[[str], bytes | None],
                              telegram_evidence: Mapping[str, Any] | None = None,
                              now: int | datetime | None = None) -> dict[str, Any]:
    if not isinstance(envelope, Mapping) or set(envelope) != GATEWAY_ENVELOPE_KEYS:
        raise AuditorContractError("gateway envelope keys are invalid")
    value = dict(envelope)
    for key in ("gateway_instance_id", "key_id", "nonce"):
        _identifier(value[key], key)
    try:
        if str(uuid.UUID(value["delivery_uuid"])) != value["delivery_uuid"].lower():
            raise ValueError
    except (TypeError, ValueError, AttributeError):
        raise AuditorContractError("delivery_uuid is invalid") from None
    if not re.fullmatch(r"[A-Fa-f0-9]{64}", value.get("instruction_sha256", "")):
        raise AuditorContractError("instruction_sha256 is invalid")
    expected_hash = hashlib.sha256(instruction.encode("utf-8")).hexdigest()
    if not hmac.compare_digest(value["instruction_sha256"].lower(), expected_hash):
        raise AuditorContractError("gateway instruction hash does not match")
    if not isinstance(value["selected_scope"], dict) or canonical_json(value["selected_scope"]) != canonical_json(dict(selected_scope)):
        raise AuditorContractError("gateway selected scope does not match")
    nested = value.get("telegram_evidence")
    if not isinstance(nested, dict) or set(nested) != TELEGRAM_EVIDENCE_KEYS:
        raise AuditorContractError("telegram evidence keys are invalid")
    if telegram_evidence is not None and canonical_json(nested) != canonical_json(dict(telegram_evidence)):
        raise AuditorContractError("gateway telegram evidence does not match")
    if nested["original_instruction"] != instruction or nested["instruction_sha256"].lower() != expected_hash:
        raise AuditorContractError("gateway telegram evidence does not match")
    issued, expires = _utc_timestamp(value["issued_at"], "issued_at"), _utc_timestamp(value["expires_at"], "expires_at")
    if now is None:
        current = datetime.now(timezone.utc)
    elif isinstance(now, int) and not isinstance(now, bool):
        current = datetime.fromtimestamp(now, timezone.utc)
    elif isinstance(now, datetime) and now.tzinfo is not None:
        current = now.astimezone(timezone.utc)
    else:
        raise AuditorContractError("current timestamp is invalid")
    if expires <= issued or (expires - issued).total_seconds() > MAX_GATEWAY_TTL_SECONDS:
        raise AuditorContractError("gateway TTL is invalid")
    if issued > current + timedelta(seconds=MAX_ISSUED_AT_SKEW_SECONDS):
        raise AuditorContractError("gateway envelope is not yet valid")
    if expires <= current:
        raise AuditorContractError("gateway envelope has expired")
    signature = value.get("signature")
    if not isinstance(signature, str) or not re.fullmatch(r"[A-Fa-f0-9]{64}", signature):
        raise AuditorContractError("gateway signature is invalid")
    key = key_resolver(value["key_id"])
    if not isinstance(key, bytes) or len(key) < 32:
        raise AuditorContractError("gateway signing key is unavailable")
    expected = hmac.new(key, gateway_signing_bytes(value), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature.lower(), expected):
        raise AuditorContractError("gateway signature is invalid")
    value["instruction_sha256"] = value["instruction_sha256"].lower()
    value["signature"] = value["signature"].lower()
    return value


class RpcClient:
    def __init__(self, url: str, apikey: str, bearer: str):
        self.url = _exact_url(url)
        self.apikey = apikey
        self.bearer = bearer

    def rpc(self, name: str, payload: dict[str, Any]) -> dict[str, Any]:
        if name not in {PLAN_RPC, COMPOSE_RPC, APPLY_RPC, RULE_RPC, UNDO_RPC, QUERY_RPC}:
            raise AuditorContractError("RPC is not allowlisted")
        req = Request(f"{self.url}/rest/v1/rpc/{name}", data=canonical_json(payload), headers={
            "apikey": self.apikey, "Authorization": f"Bearer {self.bearer}",
            "Content-Type": "application/json"}, method="POST")
        with urlopen(req, timeout=30) as response:
            result = json.loads(response.read())
        if not isinstance(result, dict) or set(result) - {"ok", "code", "data"}:
            raise AuditorContractError("RPC response envelope is invalid")
        return result


def execute_bound(client: RpcClient, update: Any, *, expected_chat_id: int,
                  bot_identity: str, gateway_envelope: Mapping[str, Any],
                  key_resolver: Callable[[str], bytes | None],
                  context: Mapping[str, Any] | None = None,
                  now: int | None = None) -> dict[str, Any]:
    evidence = bind_telegram(update, expected_chat_id=expected_chat_id, bot_identity=bot_identity)
    command = parse_instruction(evidence["original_instruction"], context)
    selected_scope = command.get("selected_scope", {})
    envelope = validate_gateway_envelope(gateway_envelope,
        instruction=evidence["original_instruction"], selected_scope=selected_scope,
        telegram_evidence=evidence, key_resolver=key_resolver, now=now)
    if command["action"] == "clarification":
        return {"ok": True, "code": "clarification_required", "data": {"question": command["question"]}}

    if command["mode"] == "query":
        return client.rpc(QUERY_RPC, {"p_action": command["action"], "p_scope": selected_scope,
                                      "p_gateway_envelope": envelope})
    if command["mode"] == "rule":
        action = {"disable_rule": "disable", "undo_last_rule": "undo", "show_rules": "show"}[command["action"]]
        # Deliberately retained migration-227 baseline path: RULE_RPC does not
        # accept the 253 envelope and remains outside typed operation control.
        return client.rpc(RULE_RPC, {"p_action": action, "p_scope": selected_scope, "p_evidence": evidence})
    if command["mode"] == "undo":
        return client.rpc(UNDO_RPC, {"p_gateway_envelope": envelope})
    if command["mode"] == "compose":
        return client.rpc(COMPOSE_RPC, {"p_proposals": selected_scope["proposal_ids"],
                                        "p_gateway_envelope": envelope})
    if command["mode"] == "apply_reviewed":
        return client.rpc(APPLY_RPC, {"p_proposal": selected_scope["proposal_id"],
            "p_proposal_version": selected_scope["proposal_version"],
            "p_proposal_hash": selected_scope["proposal_hash"],
            "p_typed_item_set_hash": selected_scope["typed_item_set_hash"],
            "p_final_scope_hash": selected_scope["final_scope_hash"],
            "p_expected_row_versions_hash": selected_scope["expected_row_versions_hash"],
            "p_gateway_envelope": envelope})

    plan = client.rpc(PLAN_RPC, {"p_action": command["action"], "p_mode": command["mode"],
        "p_selected_scope": selected_scope, "p_gateway_envelope": envelope})
    if not plan.get("ok") or command["mode"] == "review":
        return plan
    data = plan.get("data") or {}
    try:
        proposal_id = _uuid(data.get("proposal_id"), "proposal response proposal_id")
    except AuditorContractError as exc:
        raise AuditorContractError("plan response omitted valid immutable final proposal") from exc
    bindings = {"proposal_id": proposal_id}
    proposal_version = data.get("proposal_version")
    if isinstance(proposal_version, bool) or not isinstance(proposal_version, int) or proposal_version < 1:
        raise AuditorContractError("plan response omitted valid immutable final proposal")
    bindings["proposal_version"] = proposal_version
    for field in ("proposal_hash", "typed_item_set_hash", "final_scope_hash", "expected_row_versions_hash"):
        value = data.get(field)
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
            raise AuditorContractError("plan response omitted valid immutable final proposal")
        bindings[field] = value
    return {"ok": True, "code": "pending_apply_confirmation", "data": {
        **bindings, "selected_scope": selected_scope,
        "apply_selected_scope": {"contract": APPLY_SELECTION_CONTRACT, **bindings},
        "confirmation": "Apply these corrections", "confirmation_required": True}}


def client_from_environment() -> RpcClient:
    return RpcClient(os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_ANON_KEY", ""),
                     os.environ.get("PDC_AUDITOR_ACCESS_TOKEN", ""))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--telegram-update-json", required=True)
    parser.add_argument("--gateway-envelope-json", required=True)
    parser.add_argument("--context-json", default="{}")
    args = parser.parse_args(argv)
    try:
        # CLI key provisioning is intentionally external; the resolver reads one configured
        # key without ever embedding it in source or the signed envelope.
        configured_key_id = os.environ["PDC_AUDITOR_GATEWAY_KEY_ID"]
        configured_key = bytes.fromhex(os.environ["PDC_AUDITOR_GATEWAY_HMAC_KEY_HEX"])
        resolver = lambda key_id: configured_key if key_id == configured_key_id else None
        result = execute_bound(client_from_environment(), json.loads(args.telegram_update_json),
            expected_chat_id=int(os.environ["PDC_AUDITOR_TELEGRAM_CHAT_ID"]),
            bot_identity=os.environ["PDC_AUDITOR_BOT_IDENTITY"],
            gateway_envelope=json.loads(args.gateway_envelope_json), key_resolver=resolver,
            context=json.loads(args.context_json))
        print(json.dumps(result, separators=(",", ":"), sort_keys=True))
        return 0 if result.get("ok") else 1
    except Exception as exc:
        print(json.dumps({"ok": False, "code": "auditor_ingress_error", "error": str(exc)},
                         separators=(",", ":")), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
