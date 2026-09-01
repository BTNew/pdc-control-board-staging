"""AI interpretation boundary for the isolated PDC Email AI v2 runtime.

This planner consumes immutable evidence and a read-only current-state snapshot.
It emits a typed plan and a disposition for every body clause and attachment
line; it never emits SQL, RPC names, credentials or generic database writes.
"""
from __future__ import annotations

import hashlib
import re
import uuid
from datetime import date
from typing import Any, Mapping, Sequence

from .pdc_email_ai_v2_rules import CraigRuleStore
from .pdc_email_ai_v2_taxonomy import Classification, classify_operation


PLAN_VERSION = "pdc-email-ai-plan-v1"
PLANNER_VERSION = "pdc-email-ai-v2-planner-v1"
MODEL_VERSION = "pdc-email-ai-v2-model-boundary-v1"
PROMPT_VERSION = "pdc-email-ai-v2-prompt-v1"
TAXONOMY_VERSION = "pdc-operation-taxonomy-proposed/v1"
ACTION_VERSION = "pdc-email-ai-action-request-v1"


def _date(text: str) -> str | None:
    patterns = (
        r"\b(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(20\d{2})\b",
        r"\b(20\d{2})-(\d{2})-(\d{2})\b",
    )
    months = {name: index for index, name in enumerate(("", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")) if name}
    found: set[str] = set()
    for index, pattern in enumerate(patterns):
        for match in re.finditer(pattern, text, re.I):
            try:
                if index == 0:
                    day, month, year = int(match.group(1)), months[match.group(2).title()], int(match.group(3))
                else:
                    year, month, day = (int(value) for value in match.groups())
                found.add(date(year, month, day).isoformat())
            except (ValueError, KeyError):
                continue
    return next(iter(found)) if len(found) == 1 else None


def _stock(text: str) -> set[str]:
    return {value.upper() for value in re.findall(r"\b(?:stock(?:\s*(?:no\.?|number))?|batch)\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,79})\b", text, re.I)}


def _clauses(text: str) -> list[str]:
    return [item.strip() for item in re.split(r"(?<=[.!?])\s+|\r?\n+", text or "") if item.strip()]


def _estimated_hours(line: Mapping[str, Any]) -> Any:
    value = line.get("estimated_hours")
    if value is not None:
        return value
    description = str(line.get("description") or "")
    match = re.search(r"\[\s*EST(?:IMATED)?\s*HRS?\s*\]\s*[:=\-]?\s*(\d+(?:\.\d+)?)", description, re.I)
    return float(match.group(1)) if match else None


def _context_index(contexts: Sequence[Mapping[str, Any]]) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    by_stock: dict[str, dict[str, Any]] = {}
    by_vin: dict[str, dict[str, Any]] = {}
    for raw in contexts:
        row = dict(raw)
        stock = str(row.get("stock_number") or (row.get("identity") or {}).get("stock_number") or "").strip().upper()
        if not row.get("vehicle_id") or not stock:
            continue
        row["stock_number"] = stock
        row["vin"] = row.get("vin") or (row.get("identity") or {}).get("vin")
        row["backend_record_id"] = row.get("backend_record_id") or (row.get("identity") or {}).get("backend_record_id")
        if stock in by_stock:
            raise ValueError("duplicate authoritative Stock context")
        by_stock[stock] = row
        if row.get("vin"):
            by_vin[str(row["vin"]).upper()] = row
    return by_stock, by_vin


def _identity(row: Mapping[str, Any]) -> dict[str, Any]:
    return {"vehicle_id": str(row["vehicle_id"]), "stock_number": row.get("stock_number"), "vin": row.get("vin"), "backend_record_id": row.get("backend_record_id")}


class V2Planner:
    def __init__(self, *, rules: CraigRuleStore | None = None) -> None:
        self.rules = rules or CraigRuleStore.default()

    def _provenance(self, source: Mapping[str, Any]) -> dict[str, str]:
        return {
            "transport_release_version": "pdc-email-ai-v2-transport-v1",
            "planner_version": PLANNER_VERSION,
            "model_version": MODEL_VERSION,
            "prompt_version": PROMPT_VERSION,
            "business_rule_version": self.rules.ruleset_version,
            "ruleset_version": self.rules.ruleset_version,
            "taxonomy_version": TAXONOMY_VERSION,
            "supabase_action_contract_version": ACTION_VERSION,
            "source_digest": str(source["source_digest"]),
            "evidence_digest": str(source["evidence_digest"]),
        }

    def _refs(self, source: Mapping[str, Any], attachment_digest: str | None = None) -> list[dict[str, Any]]:
        refs = [{"kind": "message", "ref": str(source["message_id"] or source["receipt_id"]), "required_for_action": True}]
        if attachment_digest:
            refs.append({"kind": "attachment", "ref": f"attachment:{attachment_digest}", "required_for_action": True})
        return refs

    def _instruction(self, *, source: Mapping[str, Any], row: Mapping[str, Any], action_type: str, payload: Mapping[str, Any], refs: list[dict[str, Any]], decision: str = "planned", reason: str = "") -> dict[str, Any]:
        expected = {"vehicle_version": int(row.get("vehicle_version") or 1), "backend_revision": int(row.get("backend_revision") or 0)}
        return {
            "instruction_id": "", "vehicle_id": str(row["vehicle_id"]), "identity": _identity(row), "action_type": action_type,
            "payload": dict(payload), "evidence_refs": refs, "required_evidence": ["authoritative_identity"],
            "expected_state": expected, "decision_disposition": decision,
            "provenance": self._provenance(source), "audit_event_ref": "audit-plan-pending", "reason": reason,
        }

    def plan(self, receipt: Mapping[str, Any], attachments: Sequence[Mapping[str, Any]], contexts: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
        source = {key: receipt.get(key) for key in ("receipt_id", "source_digest", "evidence_digest", "thread_id", "message_id")}
        if not all(isinstance(source[key], str) and source[key] for key in source):
            raise ValueError("immutable receipt identity is incomplete")
        by_stock, by_vin = _context_index(contexts)
        instructions: list[dict[str, Any]] = []

        def add(row: Mapping[str, Any], action: str, payload: Mapping[str, Any], refs: list[dict[str, Any]], decision: str, reason: str) -> None:
            instructions.append(self._instruction(source=source, row=row, action_type=action, payload=payload, refs=refs, decision=decision, reason=reason))

        body = str(receipt.get("correspondence") or "")
        for clause in _clauses(body):
            stocks = _stock(clause)
            row = by_stock[next(iter(stocks))] if len(stocks) == 1 and next(iter(stocks)) in by_stock else None
            if row is None and not stocks and len(by_stock) == 1:
                row = next(iter(by_stock.values()))
            if row is None:
                # Keep an unbound instruction as review evidence without assigning
                # it to a different sibling vehicle.
                row = next(iter(by_stock.values()), {"vehicle_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-unresolved:" + str(source["source_digest"]))), "stock_number": None, "vin": None, "backend_record_id": None, "vehicle_version": 1, "backend_revision": 0})
                add(row, "note_append", {"text": clause[:2000], "event_at": "2026-09-01T00:00:00+00:00"}, self._refs(source), "review", "unresolved_vehicle_or_instruction")
                continue
            refs = self._refs(source)
            lowered = clause.casefold()
            if "activate" in lowered:
                if row.get("backend_record_id"):
                    add(row, "activate_vehicle", {"backend_record_id": row["backend_record_id"], "stock_number": row["stock_number"], "vin": row.get("vin"), "job_card_number": None}, refs, "planned", "authoritative_backend_activation")
                else:
                    add(row, "activate_vehicle", {}, refs, "review", "activation_requires_authoritative_backend")
            elif re.search(r"\bparts?\s+eta\b", lowered) and _date(clause):
                add(row, "parts_eta_set", {"eta": _date(clause)}, refs, "planned", "explicit_parts_eta")
            elif re.search(r"\bparts?\s+(?:are\s+)?(?:now\s+)?(?:complete|completed|received)\b", lowered):
                add(row, "parts_complete", {"confirmed": True}, refs, "planned", "explicit_parts_complete")
            elif re.search(r"\bparts?\s+ordered\b", lowered):
                add(row, "parts_ordered", {"confirmed": True}, refs, "planned", "explicit_parts_ordered")
            elif re.search(r"\badd\s+note\b", lowered):
                text = re.split(r"\badd\s+note\s*[:#-]?\s*", clause, flags=re.I, maxsplit=1)[-1].strip().rstrip(".")
                add(row, "note_append", {"text": text[:2000], "event_at": "2026-09-01T00:00:00+00:00"}, refs, "planned", "explicit_note")
            else:
                add(row, "note_append", {"text": clause[:2000], "event_at": "2026-09-01T00:00:00+00:00"}, refs, "review", "unclassified_instruction_preserved")

        for attachment in attachments:
            digest = str(attachment.get("digest") or "")
            if len(digest) != 64:
                raise ValueError("attachment digest is required")
            stock = str(attachment.get("stock_number") or attachment.get("stock") or "").strip().upper()
            vin = str(attachment.get("vin") or "").strip().upper() or None
            row = by_stock.get(stock) if stock else by_vin.get(vin or "")
            if row is None:
                placeholder = next(iter(by_stock.values()), {"vehicle_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-attachment:" + digest)), "stock_number": stock or None, "vin": vin, "backend_record_id": None, "vehicle_version": 1, "backend_revision": 0})
                add(placeholder, "operation_upsert", {"operation_no": "OP1", "source_row_no": 1, "work_key": "PARTS", "description": "unresolved attachment identity", "estimated_hours": None}, self._refs(source, digest), "review", "identity_not_resolved")
                continue
            if vin and row.get("vin") and vin != str(row["vin"]).upper():
                add(row, "operation_upsert", {"operation_no": "OP1", "source_row_no": 1, "work_key": "PARTS", "description": "identity conflict retained as evidence", "estimated_hours": None}, self._refs(source, digest), "conflict", "identity_stock_vin_conflict")
                continue
            if vin and by_vin.get(vin) and str(by_vin[vin]["vehicle_id"]) != str(row["vehicle_id"]):
                add(row, "operation_upsert", {"operation_no": "OP1", "source_row_no": 1, "work_key": "PARTS", "description": "identity conflict retained as evidence", "estimated_hours": None}, self._refs(source, digest), "conflict", "identity_stock_vin_conflict")
                continue
            explicit_sublet = bool(attachment.get("explicit_sublet") or attachment.get("authorized_provider") or attachment.get("authorized_booking"))
            lines = attachment.get("lines") or []
            if not lines:
                add(row, "operation_upsert", {"operation_no": "OP1", "source_row_no": 1, "work_key": "PARTS", "description": "attachment received; no operation rows extracted", "estimated_hours": None}, self._refs(source, digest), "review", "no_operation_rows_extracted")
                continue
            for index, raw_line in enumerate(lines, 1):
                line = dict(raw_line)
                description = str(line.get("description") or "").strip()
                classification: Classification = classify_operation(description, rules=self.rules, explicit_sublet=explicit_sublet, mounted=bool(line.get("mounted")), loose=bool(line.get("loose")))
                payload = {"operation_no": str(line.get("operation_no") or f"OP{index}").upper(), "source_row_no": int(line.get("source_row_no") or index), "work_key": classification.work_key or "PARTS", "description": description or "unclassified source operation", "estimated_hours": _estimated_hours(line), "taxonomy_version": TAXONOMY_VERSION, "taxonomy_disposition": "classified" if classification.disposition == "PLANNED" else classification.disposition.casefold(), "source_uid": str(source["message_id"]) + ":" + digest}
                add(row, "operation_upsert", payload, self._refs(source, digest), classification.disposition.casefold(), classification.reason)

        for index, row in enumerate(instructions, 1):
            row["instruction_id"] = f"instruction-{index:04d}"
            row["audit_event_ref"] = f"audit-plan-{index:04d}"
        dispositions = [row["decision_disposition"] for row in instructions]
        aggregate = "no_actions" if not instructions else ("planned" if "planned" in dispositions else "review")
        plan_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-plan:" + str(source["source_digest"])))
        return {
            "schema_version": PLAN_VERSION, "plan_id": plan_id, "environment": "staging", "source_receipt_id": source["receipt_id"], "source_digest": source["source_digest"], "evidence_digest": source["evidence_digest"],
            "versions": {"transport_release_version": "pdc-email-ai-v2-transport-v1", "planner_version": PLANNER_VERSION, "model_version": MODEL_VERSION, "prompt_version": PROMPT_VERSION, "business_rule_version": self.rules.ruleset_version, "ruleset_version": self.rules.ruleset_version, "taxonomy_version": TAXONOMY_VERSION, "supabase_action_contract_version": ACTION_VERSION, "source_digest": source["source_digest"], "evidence_digest": source["evidence_digest"]},
            "instructions": instructions, "aggregate_disposition": aggregate, "planner_status": "available", "planner_failure_reason": None, "created_at": "2026-09-01T00:00:00+00:00",
        }


__all__ = ["V2Planner"]
