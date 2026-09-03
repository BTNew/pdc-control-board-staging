from __future__ import annotations

import unittest

from backend.pdc_email_ai_v2_actions import ActionContractError, validate_v2_plan
from backend.pdc_email_ai_v2_planner import V2Planner
from backend.pdc_email_ai_v2_rules import CraigRuleStore


VEHICLE = {
    "vehicle_id": "22222222-2222-4222-8222-222222222222",
    "stock_number": "13059806",
    "vin": "JTMAA7BJ204154038",
    "backend_record_id": "33333333-3333-4333-8333-333333333333",
    "vehicle_version": 4,
    "backend_revision": 12,
}


def receipt() -> dict:
    return {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "source_digest": "a" * 64,
        "evidence_digest": "b" * 64,
        "thread_id": "thread-acceptance",
        "message_id": "message-acceptance",
        "received_at": "2026-09-03T00:00:00+00:00",
        "correspondence": "",
    }


class CurrentHoursAuthorityTests(unittest.TestCase):
    def test_missing_pre_delivery_hours_use_one_hour_ai_estimate(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "c" * 64,
                "filename": "J139125567_RepairOrder.pdf",
                "stock_number": VEHICLE["stock_number"],
                "vin": VEHICLE["vin"],
                "lines": [{"operation_no": "OP1", "description": "Pre-Delivery (Commercial)"}],
            }],
            [VEHICLE],
        )
        operation = next(row for row in plan["instructions"] if row["action_type"] == "operation_add")
        self.assertEqual(operation["decision_disposition"], "planned")
        self.assertEqual(operation["payload"]["estimated_hours"], 1.0)
        self.assertEqual(operation["payload"]["estimated_hours_source"], "ai_estimate")
        validate_v2_plan(plan, authoritative_contexts=[VEHICLE])

    def test_explicit_zero_hours_remain_source_hours(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "d" * 64,
                "filename": "J139125568_RepairOrder.pdf",
                "stock_number": VEHICLE["stock_number"],
                "vin": VEHICLE["vin"],
                "lines": [{"operation_no": "OP1", "description": "Pre-Delivery (Commercial)", "estimated_hours": 0.0}],
            }],
            [VEHICLE],
        )
        operation = next(row for row in plan["instructions"] if row["action_type"] == "operation_add")
        self.assertEqual(operation["payload"]["estimated_hours"], 0.0)
        self.assertEqual(operation["payload"]["estimated_hours_source"], "job_card")
        validate_v2_plan(plan, authoritative_contexts=[VEHICLE])

    def test_explicit_fractional_hours_remain_source_hours(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "f" * 64,
                "filename": "J139125570_RepairOrder.pdf",
                "stock_number": VEHICLE["stock_number"],
                "vin": VEHICLE["vin"],
                "lines": [{"operation_no": "OP1", "description": "Pre-Delivery (Commercial)", "estimated_hours": 2.5}],
            }],
            [VEHICLE],
        )
        operation = next(row for row in plan["instructions"] if row["action_type"] == "operation_add")
        self.assertEqual(operation["payload"]["estimated_hours"], 2.5)
        self.assertEqual(operation["payload"]["estimated_hours_source"], "job_card")
        validate_v2_plan(plan, authoritative_contexts=[VEHICLE])

    def test_hours_source_rejects_unknown_provenance(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "e" * 64,
                "filename": "J139125569_RepairOrder.pdf",
                "stock_number": VEHICLE["stock_number"],
                "vin": VEHICLE["vin"],
                "lines": [{"operation_no": "OP1", "description": "Pre-Delivery (Commercial)"}],
            }],
            [VEHICLE],
        )
        operation = next(row for row in plan["instructions"] if row["action_type"] == "operation_add")
        operation["payload"]["estimated_hours_source"] = "invented"
        with self.assertRaises(ActionContractError):
            validate_v2_plan(plan, authoritative_contexts=[VEHICLE])

    def test_fallback_operation_rows_carry_explicit_hours_provenance(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "1" * 64,
                "filename": "evidence.txt",
                "stock_number": VEHICLE["stock_number"],
                "vin": VEHICLE["vin"],
                "lines": [],
            }],
            [VEHICLE],
        )
        operation = next(row for row in plan["instructions"] if row["action_type"] == "operation_add")
        self.assertEqual(operation["payload"]["estimated_hours_source"], "job_card")
        validate_v2_plan(plan, authoritative_contexts=[VEHICLE])

    def test_parts_ordered_is_review_not_an_unsupported_planned_action(self):
        row = receipt()
        row["correspondence"] = "Stock 13059806 parts ordered."
        plan = V2Planner(rules=CraigRuleStore.default()).plan(row, [], [VEHICLE])
        self.assertNotIn("parts_ordered", {item["action_type"] for item in plan["instructions"]})
        self.assertEqual(plan["instructions"][0]["decision_disposition"], "review")
        validate_v2_plan(plan, authoritative_contexts=[VEHICLE])


if __name__ == "__main__":
    unittest.main(verbosity=2)
