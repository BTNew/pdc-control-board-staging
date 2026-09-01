"""Isolated v2 shadow runtime composition and durable queue integration."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Mapping, Sequence

from .pdc_email_ai_v2_actions import ShadowActionClient, build_action_request
from .pdc_email_ai_v2_queue import DurableQueue
from .pdc_email_ai_v2_planner import V2Planner
from .pdc_email_ai_v2_rules import CraigRuleStore


class V2ShadowRuntime:
    """Run the complete evidence -> state -> plan -> typed shadow action chain."""

    def __init__(self, *, rules: CraigRuleStore | None = None) -> None:
        self.rules = rules or CraigRuleStore.default()
        self.planner = V2Planner(rules=self.rules)
        self.actions = ShadowActionClient()

    def run(
        self,
        receipt: Mapping[str, Any],
        attachments: Sequence[Mapping[str, Any]],
        authoritative_contexts: Sequence[Mapping[str, Any]],
        *,
        incumbent_instructions: Sequence[Mapping[str, Any]] = (),
    ) -> dict[str, Any]:
        plan = self.planner.plan(receipt, attachments, authoritative_contexts)
        action_results: list[dict[str, Any]] = []
        for instruction in plan["instructions"]:
            if instruction["decision_disposition"] != "planned":
                action_results.append({"instruction_id": instruction["instruction_id"], "disposition": instruction["decision_disposition"], "operational_write_attempted": False, "reason": instruction["reason"]})
                continue
            request = build_action_request(plan_id=plan["plan_id"], source_receipt_id=plan["source_receipt_id"], source_digest=plan["source_digest"], evidence_digest=plan["evidence_digest"], instruction=instruction)
            action_results.append(self.actions.submit(request))
        incumbent = {str(item.get("instruction_id")): item for item in incumbent_instructions}
        comparison = []
        for instruction in plan["instructions"]:
            old = incumbent.get(instruction["instruction_id"])
            comparison.append({"instruction_id": instruction["instruction_id"], "changed_from_incumbent": bool(old and old.get("work_key") != instruction.get("payload", {}).get("work_key")), "incumbent_present": old is not None})
        return {
            "schema_version": "pdc-email-ai-v2-shadow-receipt-v1", "mode": "SHADOW_ZERO_WRITE", "source_digest": plan["source_digest"], "evidence_digest": plan["evidence_digest"], "plan_id": plan["plan_id"], "plan": plan,
            "action_results": action_results, "comparison": comparison, "instruction_count": len(plan["instructions"]), "all_instructions_accounted": len(action_results) == len(plan["instructions"]), "operational_writes_attempted": False, "mailbox_mutated": False, "production_touched": False, "legacy_runtime_touched": False,
        }

    def process_one_queued(
        self,
        queue: DurableQueue,
        *,
        owner: str,
        receipt_loader: Any,
        attachments_loader: Any,
        contexts_loader: Any,
    ) -> dict[str, Any] | None:
        """Claim one durable evidence reference and finish it with a shadow receipt.

        Loaders are injected so this coordinator never reaches a mailbox,
        database, filesystem convention, or legacy queue implicitly.
        """
        claim = queue.claim(owner)
        if claim is None:
            return None
        try:
            receipt = receipt_loader(claim["receipt_path"])
            result = self.run(receipt, attachments_loader(receipt), contexts_loader(receipt))
            queue.finish(claim["item_key"], owner, {"shadow_receipt": result["plan_id"], "instruction_count": result["instruction_count"], "operational_writes_attempted": False})
            return result
        except Exception as exc:
            queue.fail(claim["item_key"], owner, f"v2_shadow_failure:{type(exc).__name__}", retryable=True)
            raise


def write_shadow_receipt(path: Path, receipt: Mapping[str, Any]) -> str:
    payload = json.dumps(dict(receipt), sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n"
    destination = Path(path).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(payload, encoding="utf-8")
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


__all__ = ["V2ShadowRuntime", "write_shadow_receipt"]
