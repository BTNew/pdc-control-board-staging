import copy
import unittest

from backend.pdc_email_ai_successor_contract import (
    ACTION_TYPES,
    TERMINAL_DISPOSITIONS,
    aggregate_disposition,
    action_idempotency_key,
    validate_plan,
)


SOURCE = {
    "receipt_id": "11111111-1111-4111-8111-111111111111",
    "source_digest": "a" * 64,
    "evidence_digest": "b" * 64,
    "thread_id": "thread-1",
}
VERSIONS = {
    "model": "model-test-1",
    "prompt": "prompt-test-1",
    "taxonomy": "taxonomy-test-1",
    "rules": "rules-test-1",
    "action_contract": "pdc-email-ai-actions-v1",
    "supabase_actions": "staging-canonical-2026-08-31",
}


def valid_plan():
    return {
        "schema_version": "pdc-email-ai-plan-v1",
        "source": SOURCE,
        "versions": VERSIONS,
        "instructions": [
            {
                "instruction_id": "instruction-1",
                "vehicle_id": "22222222-2222-4222-8222-222222222222",
                "identity": {
                    "stock_number": "13000765",
                    "vin": "JTFLAAB1234567890",
                    "backend_record_id": "33333333-3333-4333-8333-333333333333",
                },
                "expected_vehicle_version": 9,
                "action_type": "parts_eta_set",
                "payload": {"eta": "2026-09-15"},
                "evidence_refs": ["body:1-2"],
            },
            {
                "instruction_id": "instruction-2",
                "vehicle_id": "22222222-2222-4222-8222-222222222222",
                "identity": {
                    "stock_number": "13000765",
                    "vin": "JTFLAAB1234567890",
                    "backend_record_id": "33333333-3333-4333-8333-333333333333",
                },
                "expected_vehicle_version": 9,
                "action_type": "job_card_upsert",
                "payload": {
                    "job_card_number": "J139125482",
                    "lines": [
                        {
                            "operation_no": "OP1",
                            "source_row_no": 1,
                            "work_key": "HOIST",
                            "description": "GVM upgrade",
                            "estimated_hours": 0,
                        }
                    ],
                },
                "evidence_refs": ["attachment:job-card.pdf#page=1"],
            },
            {
                "instruction_id": "instruction-3",
                "vehicle_id": "44444444-4444-4444-8444-444444444444",
                "identity": {
                    "stock_number": "13000766",
                    "vin": None,
                    "backend_record_id": "55555555-5555-4555-8555-555555555555",
                },
                "expected_vehicle_version": 4,
                "action_type": "notes_append",
                "payload": {"text": "Dealer confirmed revised delivery date."},
                "evidence_refs": ["body:8-9"],
            },
        ],
    }


class ContractTests(unittest.TestCase):
    def test_valid_multi_vehicle_plan_preserves_zero_hours_and_derives_stable_keys(self):
        plan = validate_plan(valid_plan())
        self.assertEqual(plan["schema_version"], "pdc-email-ai-plan-v1")
        self.assertEqual(len(plan["instructions"]), 3)
        self.assertEqual(plan["instructions"][1]["payload"]["lines"][0]["estimated_hours"], 0)
        first = action_idempotency_key(plan, plan["instructions"][0])
        second = action_idempotency_key(plan, plan["instructions"][0])
        self.assertEqual(first, second)
        self.assertEqual(len(first), 64)

    def test_unknown_action_is_rejected_before_any_executor_boundary(self):
        plan = valid_plan()
        plan["instructions"][0]["action_type"] = "drop_table"
        with self.assertRaisesRegex(ValueError, "action_type"):
            validate_plan(plan)

    def test_sql_and_table_control_fields_are_rejected(self):
        plan = valid_plan()
        plan["instructions"][0]["payload"]["sql"] = "update vehicles set current_location='RFT'"
        with self.assertRaisesRegex(ValueError, "forbidden"):
            validate_plan(plan)

    def test_action_types_and_terminal_dispositions_are_closed_sets(self):
        self.assertIn("parts_complete", ACTION_TYPES)
        self.assertIn("APPLIED_AND_VERIFIED", TERMINAL_DISPOSITIONS)
        self.assertEqual(aggregate_disposition(["APPLIED_AND_VERIFIED", "ALREADY_CORRECT"]), "SUCCESS")
        self.assertEqual(aggregate_disposition(["APPLIED_AND_VERIFIED", "BLOCKED_EXACT_REASON"]), "PARTIAL_FAILURE")
        self.assertEqual(aggregate_disposition([]), "NO_ACTIONS")

    def test_mutating_a_nested_plan_changes_the_action_key(self):
        original = valid_plan()
        changed = copy.deepcopy(original)
        changed["instructions"][0]["payload"]["eta"] = "2026-09-16"
        self.assertNotEqual(
            action_idempotency_key(original, original["instructions"][0]),
            action_idempotency_key(changed, changed["instructions"][0]),
        )


if __name__ == "__main__":
    unittest.main()
