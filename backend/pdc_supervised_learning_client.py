#!/usr/bin/env python
"""Strict staging-only Telegram/Hermes client for supervised PDC lessons.

Hermes is responsible for interpreting natural language.  This module accepts
only the resulting canonical command, preserves Telegram evidence verbatim and
passes it to database RPCs.  The database is the sole store of lesson state.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any, Mapping

STAGING_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
STAGING_HOST = f"{STAGING_PROJECT_REF}.supabase.co"
STAGING_URL = f"https://{STAGING_HOST}"
COMMAND_RPC = "execute_pdc_supervised_learning_command"
MONITOR_READ_RPC = "read_pdc_supervised_learning_rule"
MONITOR_APPLY_RPC = "apply_pdc_supervised_learning_rule"
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_RPC_NAME = re.compile(r"[a-z][a-z0-9_]{0,127}")
_OPERATION_CODE = re.compile(r"[A-Z0-9][A-Z0-9._/-]{0,79}")

ACTIONS = frozenset({
    "propose_lesson", "activate_future", "review_apply_existing_scope",
    "list_active", "explain_why", "create_corrected_version", "disable",
    "undo_last_lesson", "review_uncertain",
})
_MUTATING_ACTIONS = frozenset({
    "propose_lesson", "activate_future", "review_apply_existing_scope",
    "create_corrected_version", "disable", "undo_last_lesson",
})
_LESSON_ID_ACTIONS = frozenset({
    "activate_future", "review_apply_existing_scope", "explain_why", "disable",
})
_ALLOWED_CODES = frozenset({
    "lesson_proposed", "lesson_activated", "existing_scope_reviewed",
    "active_lessons", "lesson_explained", "corrected_version_created",
    "lesson_disabled", "last_lesson_undone", "uncertain_lessons",
    "clarification_required", "unauthorized", "forbidden", "not_found",
    "conflict", "invalid_request", "no_lesson_to_undo", "rpc_error",
})


class SupervisedLearningContractError(RuntimeError):
    """A bounded local or remote contract failure safe to show to an operator."""


def _strict_url(value: Any) -> str:
    if not isinstance(value, str) or value != value.strip():
        raise SupervisedLearningContractError("staging Supabase URL is invalid")
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise SupervisedLearningContractError("staging Supabase URL is invalid") from exc
    if (parsed.scheme != "https" or parsed.hostname != STAGING_HOST or port is not None
            or parsed.username is not None or parsed.password is not None
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise SupervisedLearningContractError("refusing non-staging Supabase URL")
    return STAGING_URL


def _text(value: Any, label: str, minimum: int = 1, maximum: int = 4000) -> str:
    if (not isinstance(value, str) or value != value.strip()
            or not minimum <= len(value) <= maximum or _CONTROL.search(value)):
        raise SupervisedLearningContractError(f"{label} is invalid")
    return value


def _exact(value: Any, keys: set[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != keys:
        raise SupervisedLearningContractError(f"{label} keys do not match the contract")
    return value


def _uuid(value: Any, label: str) -> str:
    text = _text(value, label, 36, 36)
    try:
        parsed = uuid.UUID(text)
    except ValueError as exc:
        raise SupervisedLearningContractError(f"{label} is not a canonical UUID") from exc
    if parsed.int == 0 or str(parsed) != text.lower():
        raise SupervisedLearningContractError(f"{label} is not a canonical UUID")
    return str(parsed)


def _telegram_id(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not -(2**63) < value < 2**63:
        raise SupervisedLearningContractError(f"{label} is invalid")
    return value


def validate_evidence(value: Any) -> dict[str, Any]:
    evidence = dict(_exact(value, {
        "original_instruction", "telegram_sender_id", "telegram_chat_id",
        "telegram_message_id",
    }, "Telegram evidence"))
    _text(evidence["original_instruction"], "original Telegram instruction", 1, 8000)
    _telegram_id(evidence["telegram_sender_id"], "Telegram sender ID")
    _telegram_id(evidence["telegram_chat_id"], "Telegram chat ID")
    message_id = evidence["telegram_message_id"]
    if isinstance(message_id, bool) or not isinstance(message_id, int) or not 1 <= message_id < 2**63:
        raise SupervisedLearningContractError("Telegram message ID is invalid")
    return evidence


def _money(value: Any, label: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"(?:0|[1-9]\d{0,7})\.\d{2}", value) is None:
        raise SupervisedLearningContractError(f"{label} must be a supplied decimal string with two places")
    try:
        amount = Decimal(value)
    except InvalidOperation as exc:
        raise SupervisedLearningContractError(f"{label} is invalid") from exc
    if amount < 0:
        raise SupervisedLearningContractError(f"{label} is invalid")
    return value


def validate_pricing(value: Any) -> dict[str, str] | None:
    if value is None:
        return None
    pricing = dict(_exact(value, {"cost_ex_gst", "sell_ex_gst", "gst_percent", "currency"}, "pricing"))
    _money(pricing["cost_ex_gst"], "pricing cost_ex_gst")
    _money(pricing["sell_ex_gst"], "pricing sell_ex_gst")
    if pricing["gst_percent"] not in {"0.00", "10.00"}:
        raise SupervisedLearningContractError("pricing gst_percent must be explicitly supplied as 0.00 or 10.00")
    if pricing["currency"] != "AUD":
        raise SupervisedLearningContractError("pricing currency must be AUD")
    return pricing


def _scope(value: Any, label: str = "scope") -> dict[str, Any]:
    scope = dict(_exact(value, {"operation_code", "operation_description", "current_mapping"}, label))
    code = scope["operation_code"]
    if code is not None:
        code = _text(code, f"{label} operation_code", 1, 80)
        if _OPERATION_CODE.fullmatch(code) is None:
            raise SupervisedLearningContractError(f"{label} operation_code is invalid")
    _text(scope["operation_description"], f"{label} operation_description", 1, 500)
    if scope["current_mapping"] is not None:
        _text(scope["current_mapping"], f"{label} current_mapping", 1, 120)
    return scope


def _proposal(value: Any, label: str = "proposal") -> dict[str, Any]:
    proposal = dict(_exact(value, {"scope", "target_mapping", "estimated_hours", "pricing", "reason"}, label))
    proposal["scope"] = _scope(proposal["scope"], f"{label}.scope")
    _text(proposal["target_mapping"], f"{label} target_mapping", 1, 120)
    hours = proposal["estimated_hours"]
    if hours is not None and (isinstance(hours, bool) or not isinstance(hours, (int, float)) or not 0 < hours <= 999.99):
        raise SupervisedLearningContractError(f"{label} estimated_hours is invalid")
    proposal["pricing"] = validate_pricing(proposal["pricing"])
    _text(proposal["reason"], f"{label} reason", 1, 1000)
    return proposal


def validate_command(value: Any) -> dict[str, Any]:
    command = dict(_exact(value, {"action", "parameters", "telegram_evidence"}, "command"))
    action = command["action"]
    if action not in ACTIONS:
        raise SupervisedLearningContractError("command action is invalid")
    parameters = command["parameters"]
    if action == "propose_lesson":
        parameters = _proposal(parameters)
    elif action == "create_corrected_version":
        parameters = dict(_exact(parameters, {"lesson_id", "replacement"}, "parameters"))
        parameters["lesson_id"] = _uuid(parameters["lesson_id"], "lesson_id")
        parameters["replacement"] = _proposal(parameters["replacement"], "replacement")
    elif action in _LESSON_ID_ACTIONS:
        parameters = dict(_exact(parameters, {"lesson_id"}, "parameters"))
        parameters["lesson_id"] = _uuid(parameters["lesson_id"], "lesson_id")
    elif action in {"list_active", "undo_last_lesson", "review_uncertain"}:
        _exact(parameters, set(), "parameters")
        parameters = {}
    command["parameters"] = parameters
    command["telegram_evidence"] = validate_evidence(command["telegram_evidence"])
    # Reads also retain who asked and the exact question; mutations can therefore
    # never lose the evidence required by the database audit contract.
    return command


@dataclass(frozen=True)
class RpcClient:
    url: str
    apikey: str
    bearer: str
    authority: str
    timeout: int = 60

    def __post_init__(self) -> None:
        object.__setattr__(self, "url", _strict_url(self.url))
        for credential, label in ((self.apikey, "apikey"), (self.bearer, "bearer")):
            if not isinstance(credential, str) or not 8 <= len(credential) <= 16384 or _CONTROL.search(credential):
                raise SupervisedLearningContractError(f"{label} credential is invalid")
        if self.authority not in {"actor", "scoped_monitor"}:
            raise SupervisedLearningContractError("RPC authority is invalid")
        if isinstance(self.timeout, bool) or not isinstance(self.timeout, int) or not 1 <= self.timeout <= 180:
            raise SupervisedLearningContractError("RPC timeout is invalid")

    def rpc(self, name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        if not isinstance(name, str) or _RPC_NAME.fullmatch(name) is None:
            raise SupervisedLearningContractError("RPC name is invalid")
        try:
            body = json.dumps(dict(payload), separators=(",", ":"), allow_nan=False).encode()
        except (TypeError, ValueError) as exc:
            raise SupervisedLearningContractError("RPC payload is not canonical JSON") from exc
        request = urllib.request.Request(
            f"{self.url}/rest/v1/rpc/{name}", data=body, method="POST",
            headers={"apikey": self.apikey, "Authorization": f"Bearer {self.bearer}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                if getattr(response, "status", response.getcode()) != 200:
                    raise SupervisedLearningContractError(f"{self.authority} RPC returned unexpected HTTP status")
                raw = response.read(1_048_577)
                if len(raw) > 1_048_576:
                    raise SupervisedLearningContractError(f"{self.authority} RPC returned an oversized result")
        except urllib.error.HTTPError as exc:
            exc.read(4096)  # discard potentially secret-bearing remote diagnostics
            code = "unauthorized" if exc.code == 401 else "forbidden" if exc.code == 403 else "rpc_error"
            raise SupervisedLearningContractError(f"{self.authority} RPC failed: {code}") from exc
        except (urllib.error.URLError, OSError) as exc:
            raise SupervisedLearningContractError(f"{self.authority} RPC transport failed") from exc
        try:
            result = json.loads(raw.decode("utf-8", errors="strict"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise SupervisedLearningContractError(f"{self.authority} RPC returned invalid JSON") from exc
        if not isinstance(result, dict):
            raise SupervisedLearningContractError(f"{self.authority} RPC returned an invalid result")
        return result


def _result(value: Any, label: str) -> dict[str, Any]:
    result = dict(_exact(value, {"ok", "code", "data"}, label))
    if type(result["ok"]) is not bool or result["code"] not in _ALLOWED_CODES or not isinstance(result["data"], Mapping):
        raise SupervisedLearningContractError(f"{label} returned an invalid envelope")
    result["data"] = dict(result["data"])
    if result["ok"] is not (result["code"] not in {"unauthorized", "forbidden", "not_found", "conflict", "invalid_request", "no_lesson_to_undo", "rpc_error"}):
        raise SupervisedLearningContractError(f"{label} success flag and code disagree")
    return result


def execute_command(client: RpcClient, command: Mapping[str, Any]) -> dict[str, Any]:
    if getattr(client, "authority", None) != "actor":
        raise SupervisedLearningContractError("Craig/Admin actor JWT authority is required")
    _strict_url(getattr(client, "url", None))
    checked = validate_command(command)
    result = _result(client.rpc(COMMAND_RPC, {
        "p_action": checked["action"],
        "p_parameters": checked["parameters"],
        "p_telegram_evidence": checked["telegram_evidence"],
    }), "supervised-learning command")
    # clarification_required is a terminal proposal outcome.  In particular no
    # activation RPC is chained here (or anywhere else in this client).
    if result["code"] == "clarification_required" and checked["action"] != "propose_lesson":
        raise SupervisedLearningContractError("clarification is only valid for a proposal")
    return result


def strip_jc_prefix(description: str) -> tuple[str, dict[str, Any]]:
    original = _text(description, "operation description", 1, 500)
    display = re.sub(
        r"^\s*(?:JC|JOB\s*CARD)(?:\s*(?:NO\.?|NUMBER))?\s*[-:#/]?\s*[A-Z]?\d{3,}(?:\s*[·:|\-/]\s*|\s+)",
        "", original, count=1, flags=re.IGNORECASE,
    )
    display = display.strip()
    if not display:
        display = original
    return display, {"original_operation_description": original, "jc_prefix_stripped": display != original}


def resolve_active_rule(client: RpcClient, operation_code: str, operation_description: str,
                        current_mapping: str | None) -> dict[str, Any]:
    """Read and, only when explicitly matched, apply one active monitor rule."""
    if getattr(client, "authority", None) != "scoped_monitor":
        raise SupervisedLearningContractError("scoped monitor token authority is required")
    _strict_url(getattr(client, "url", None))
    scope = _scope({"operation_code": operation_code, "operation_description": operation_description,
                    "current_mapping": current_mapping}, "monitor scope")
    display, jc_metadata = strip_jc_prefix(operation_description)
    read = _result(client.rpc(MONITOR_READ_RPC, {"p_scope": scope}), "monitor rule read")
    if not read["ok"] or read["code"] != "active_lessons":
        return read
    data = read["data"]
    if set(data) != {"matched", "rule"} or type(data["matched"]) is not bool:
        raise SupervisedLearningContractError("monitor rule readback is invalid")
    if not data["matched"]:
        if data["rule"] is not None:
            raise SupervisedLearningContractError("unmatched monitor read returned a rule")
        return {"ok": True, "code": "active_lessons", "data": {"matched": False, "rule": None}}
    rule = dict(_exact(data["rule"], {"lesson_id", "version", "target_mapping", "pricing"}, "active rule"))
    _uuid(rule["lesson_id"], "active rule lesson_id")
    if isinstance(rule["version"], bool) or not isinstance(rule["version"], int) or rule["version"] < 1:
        raise SupervisedLearningContractError("active rule version is invalid")
    _text(rule["target_mapping"], "active rule target_mapping", 1, 120)
    rule["pricing"] = validate_pricing(rule["pricing"])
    applied = _result(client.rpc(MONITOR_APPLY_RPC, {
        "p_scope": scope, "p_lesson_id": rule["lesson_id"], "p_expected_version": rule["version"],
        "p_resolution": {"target_mapping": rule["target_mapping"], "pricing": rule["pricing"],
                         "display_description": display, "jc_metadata": jc_metadata},
    }), "monitor rule apply")
    return applied


def client_from_environment(*, monitor: bool = False) -> RpcClient:
    url = os.environ.get("SUPABASE_URL", "")
    apikey = os.environ.get("SUPABASE_ANON_KEY", "")
    bearer_name = "PDC_SUPERVISED_MONITOR_JWT" if monitor else "PDC_SUPERVISED_ACTOR_JWT"
    return RpcClient(url, apikey, os.environ.get(bearer_name, ""), "scoped_monitor" if monitor else "actor")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Execute one strict staging supervised-learning command")
    parser.add_argument("--command-json", help="canonical command JSON; defaults to stdin")
    args = parser.parse_args(argv)
    try:
        command = json.loads(args.command_json if args.command_json is not None else sys.stdin.read())
        result = execute_command(client_from_environment(), command)
        print(json.dumps(result, separators=(",", ":"), sort_keys=True))
        return 0 if result["ok"] else 1
    except (json.JSONDecodeError, SupervisedLearningContractError) as exc:
        print(json.dumps({"ok": False, "code": "client_error", "error": str(exc)}, separators=(",", ":")), file=sys.stderr)
        return 2


__all__ = [
    "ACTIONS", "COMMAND_RPC", "MONITOR_APPLY_RPC", "MONITOR_READ_RPC", "RpcClient",
    "STAGING_URL", "SupervisedLearningContractError", "client_from_environment",
    "execute_command", "resolve_active_rule", "strip_jc_prefix", "validate_command",
    "validate_evidence", "validate_pricing",
]

if __name__ == "__main__":
    raise SystemExit(main())
