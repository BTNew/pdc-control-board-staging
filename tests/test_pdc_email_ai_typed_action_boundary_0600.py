import unittest
from pathlib import Path

from backend.pdc_email_ai_v2_actions import ActionContractError, validate_v2_plan
from backend.pdc_email_ai_v2_planner import V2Planner
from backend.pdc_email_ai_v2_rules import CraigRuleStore


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901060000_pdc_email_ai_typed_action_boundary_hardening_20260901.sql"
EXECUTION_MIGRATION = ROOT / "supabase" / "staging_only" / "20260901070000_pdc_email_ai_typed_action_execution_readback_20260901.sql"
FINAL_MIGRATION = ROOT / "supabase" / "staging_only" / "20260901080000_pdc_email_ai_typed_action_identity_contract_20260901.sql"

VEHICLE = {
    "vehicle_id": "22222222-2222-4222-8222-222222222222",
    "stock_number": "13000765",
    "vin": None,
    "backend_record_id": None,
    "vehicle_version": 9,
    "backend_revision": 12,
}


def receipt():
    return {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "source_digest": "a" * 64,
        "evidence_digest": "b" * 64,
        "thread_id": "thread-v2",
        "message_id": "message-v2",
        "correspondence": "",
    }


class TypedActionBoundaryHardeningTests(unittest.TestCase):
    def test_identity_conflict_evidence_is_consistent_across_planner_and_python_validator(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "c" * 64,
                "filename": "conflict.pdf",
                "stock_number": VEHICLE["stock_number"],
                "vin": "JH4TB2H26CC000001",
                "lines": [],
            }],
            [VEHICLE, {
                **VEHICLE,
                "vehicle_id": "33333333-3333-4333-8333-333333333333",
                "stock_number": "13000766",
                "vin": "JH4TB2H26CC000001",
            }],
        )
        self.assertEqual(plan["instructions"][0]["decision_disposition"], "conflict")
        self.assertEqual(plan["instructions"][0]["payload"]["taxonomy_disposition"], "conflict")
        self.assertEqual(validate_v2_plan(plan)["instructions"][0]["decision_disposition"], "conflict")

    def test_authoritative_context_rejects_forged_stock_vin_and_backend_identity(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "c" * 64,
                "filename": "job.pdf",
                "stock_number": VEHICLE["stock_number"],
                "lines": [{"operation_no": "OP1", "description": "Bullbar fitting", "estimated_hours": 1.0}],
            }],
            [VEHICLE],
        )
        for field, forged in (("stock_number", "99999999"), ("vin", "1HGCM82633A004352"), ("backend_record_id", "33333333-3333-4333-8333-333333333333")):
            mutated = __import__("copy").deepcopy(plan)
            mutated["instructions"][0]["identity"][field] = forged
            with self.subTest(field=field), self.assertRaises(ActionContractError):
                validate_v2_plan(mutated, authoritative_contexts=[VEHICLE])

    def test_top_level_schema_values_are_strictly_validated(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(receipt(), [], [VEHICLE])
        for field, value in (("attachment_digests", ["not-a-digest"]), ("aggregate_disposition", "forged"), ("planner_status", "forged"), ("created_at", "not-a-date")):
            mutated = __import__("copy").deepcopy(plan)
            mutated[field] = value
            with self.subTest(field=field), self.assertRaises(ActionContractError):
                validate_v2_plan(mutated)

    def test_review_operation_with_unknown_hours_remains_a_valid_typed_plan(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "c" * 64,
                "filename": "job.pdf",
                "stock_number": VEHICLE["stock_number"],
                "lines": [{"operation_no": "OP1", "description": "Bullbar fitting", "estimated_hours": None}],
            }],
            [VEHICLE],
        )
        validated = validate_v2_plan(plan)
        operation = validated["instructions"][0]
        self.assertEqual(operation["decision_disposition"], "review")
        self.assertIsNone(operation["payload"]["estimated_hours"])

    def test_operation_update_cannot_fabricate_classified_mixed_signage_taxonomy(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "c" * 64,
                "filename": "job.pdf",
                "stock_number": VEHICLE["stock_number"],
                "lines": [{"operation_no": "OP1", "description": "Bullbar fitting", "estimated_hours": 1.0}],
            }],
            [VEHICLE],
        )
        operation = plan["instructions"][0]
        operation["action_type"] = "operation_update"
        operation["payload"]["description"] = "FMG signage GVM tare decals"
        operation["payload"]["work_key"] = "HOIST"
        operation["payload"]["taxonomy_disposition"] = "classified"
        with self.assertRaises(ActionContractError):
            validate_v2_plan(plan)

    def test_staging_migration_contains_protected_update_and_authoritative_readback_contract(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260901050000",
            "pdc_email_ai_successor_operation_update_20260901",
            "correction_origin='ai_auditor'",
            "manual_assignment_locked",
            "operation_update_protected_manual_overlay",
            "pdc_email_ai_successor_taxonomy_disposition_20260901",
            "estimated_hours IS NULL",
            "authoritative_booking_readback",
            "authoritative_timeline_readback",
            "workshop_booking_snapshot",
            "vehicle_timeline_events",
            "source_digest",
            "evidence_digest",
            "provenance",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotIn("correction_origin='pdc_email_ai_v2'", sql)

    def test_staging_migration_rejects_invalid_provenance_before_dispatch(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("pdc_email_ai_successor_validate_v2_plan_20260901", sql)
        self.assertIn("provenance_keys_invalid", sql)
        self.assertIn("identity_value_invalid", sql)
        self.assertIn("source_digest_identity_invalid", sql)
        self.assertIn("evidence_digest_identity_invalid", sql)
        self.assertIn("typed_v2_plan_invalid", sql)


    def test_execution_follow_up_preserves_complete_work_state_and_exact_booking_readback(self):
        self.assertTrue(EXECUTION_MIGRATION.is_file())
        sql = EXECUTION_MIGRATION.read_text(encoding="utf-8")
        self.assertIn("pdc_email_ai_successor_work_state_map_20260901", sql)
        self.assertIn("default_duration_minutes", sql)
        self.assertIn("canonical_" , sql)
        self.assertIn("FAILED_QUEUED_RETRY", sql)

    def test_final_identity_contract_is_append_only_and_review_safe(self):
        self.assertTrue(FINAL_MIGRATION.is_file())
        sql = FINAL_MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260901070000",
            "ALTER TABLE public.pdc_email_ai_successor_action_receipts ALTER COLUMN vehicle_id DROP NOT NULL",
            "unresolved_review_evidence",
            "authoritative_vehicle_identity_mismatch",
            "source_record_id_normalized",
            "attachment_digest_invalid",
            "aggregate_disposition",
            "planner_failure_reason",
            "created_at",
            "identity conflict",
            "vehicle_not_found",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)


if __name__ == "__main__":
    unittest.main()
