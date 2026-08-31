"""Composition boundary for one successor transaction cycle.

The runtime is intentionally a thin coordinator: evidence capture, typed
interpretation, one command RPC, and independent readback remain separate.
"""
from __future__ import annotations

import time
from typing import Any, Mapping, Sequence

from .pdc_email_ai_successor_executor import execute_typed_plan
from .pdc_email_ai_successor_planner import interpret_correspondence


def process_evidence(
    receipt: Mapping[str, Any],
    attachments: Sequence[Mapping[str, Any]],
    authoritative_vehicle_contexts: Sequence[Mapping[str, Any]],
    client: Any,
) -> dict[str, Any]:
    started = time.monotonic()
    if receipt.get("status") not in {"RECEIVED", "REPLAYED"}:
        return {"ok": False, "code": "evidence_not_ready", "disposition": "FAILED_QUEUED_RETRY"}
    plan = interpret_correspondence(receipt, attachments, authoritative_vehicle_contexts)
    if not plan["instructions"]:
        return {
            "ok": False,
            "code": "no_typed_actions",
            "disposition": "NO_ACTIONS",
            "plan": plan,
            "duration_ms": round((time.monotonic() - started) * 1000, 3),
        }
    outcome = execute_typed_plan(client, plan)
    return {
        **outcome,
        "plan": plan,
        "duration_ms": round((time.monotonic() - started) * 1000, 3),
    }


__all__ = ["process_evidence"]
