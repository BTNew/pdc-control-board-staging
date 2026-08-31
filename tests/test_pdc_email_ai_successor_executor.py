import copy
import unittest

from backend.pdc_email_ai_successor_executor import (
    ExecutorContractError,
    execute_typed_plan,
)


PLAN = {
    "schema_version": "pdc-email-ai-plan-v1",
    "source": {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "source_digest": "a" * 64,
        "evidence_digest": "b" * 64,
        "thread_id": "thread-1",
        "message_id": "message-1",
        "attachment_digests": [],
    },
    "versions": {
        "model": "model-1",
        "prompt": "prompt-1",
        "taxonomy": "taxonomy-1",
        "rules": "rules-1",
        "action_contract": "pdc-email-ai-actions-v1",
        "supabase_actions": "staging-actions-1",
    },
    "instructions": [
        {
            "instruction_id": "instruction-0001",
            "vehicle_id": "22222222-2222-4222-8222-222222222222",
            "identity": {"stock_number": "13000765", "vin": None, "backend_record_id": None},
            "expected_vehicle_version": 9,
            "action_type": "parts_eta_set",
            "payload": {"eta": "2026-09-15"},
            "evidence_refs": ["body:1"],
        }
    ],
}


class FakeClient:
    def __init__(self, command_result, readback_result):
        self.command_result = command_result
        self.readback_result = readback_result
        self.calls = []

    def rpc(self, name, payload):
        self.calls.append((name, copy.deepcopy(payload)))
        if name == "apply_pdc_email_ai_transaction_successor":
            return self.command_result
        if name == "get_pdc_email_vehicle_location_snapshot":
            return self.readback_result
        raise AssertionError(f"unexpected RPC {name}")


class ExecutorTests(unittest.TestCase):
    def result(self, disposition="SUCCESS"):
        action = PLAN["instructions"][0]
        return {
            "ok": disposition == "SUCCESS",
            "code": "pdc_email_ai_transaction_completed",
            "disposition": disposition,
            "actions": [{
                "instruction_id": action["instruction_id"],
                "disposition": "APPLIED_AND_VERIFIED" if disposition == "SUCCESS" else "BLOCKED_EXACT_REASON",
                "expected": {"parts.eta": "2026-09-15"},
                "actual": {"parts.eta": "2026-09-15" if disposition == "SUCCESS" else None},
            }],
            "state": {"vehicles": []},
        }

    def test_executor_uses_only_typed_command_then_independent_authoritative_readback(self):
        client = FakeClient(
            self.result(),
            {"ok": True, "code": "ok", "data": {"vehicles": [{"id": PLAN["instructions"][0]["vehicle_id"], "version": 10, "parts_update": {"worst_eta": "2026-09-15"}}]}},
        )
        outcome = execute_typed_plan(client, PLAN)
        self.assertTrue(outcome["ok"])
        self.assertEqual([call[0] for call in client.calls], [
            "apply_pdc_email_ai_transaction_successor",
            "get_pdc_email_vehicle_location_snapshot",
        ])
        self.assertTrue(outcome["readback"]["parity"])

    def test_partial_failure_is_not_reported_as_success(self):
        client = FakeClient(
            self.result("PARTIAL_FAILURE"),
            {"ok": True, "code": "ok", "data": {"vehicles": [{"id": PLAN["instructions"][0]["vehicle_id"], "version": 9, "parts_update": {}}]}},
        )
        outcome = execute_typed_plan(client, PLAN)
        self.assertFalse(outcome["ok"])
        self.assertEqual(outcome["disposition"], "PARTIAL_FAILURE")

    def test_http_success_with_wrong_authoritative_value_fails_readback(self):
        client = FakeClient(
            self.result(),
            {"ok": True, "code": "ok", "data": {"vehicles": [{"id": PLAN["instructions"][0]["vehicle_id"], "version": 10, "parts_update": {"worst_eta": "2026-09-16"}}]}},
        )
        outcome = execute_typed_plan(client, PLAN)
        self.assertFalse(outcome["ok"])
        self.assertEqual(outcome["code"], "readback_mismatch")

    def test_malformed_command_response_fails_closed(self):
        client = FakeClient({"ok": True}, {"ok": True, "data": {"vehicles": []}})
        with self.assertRaises(ExecutorContractError):
            execute_typed_plan(client, PLAN)
        self.assertEqual([call[0] for call in client.calls], ["apply_pdc_email_ai_transaction_successor"])


if __name__ == "__main__":
    unittest.main()
