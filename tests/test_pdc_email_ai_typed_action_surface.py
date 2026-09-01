import unittest
from pathlib import Path

from backend.pdc_email_ai_successor_contract import (
    ACTION_CONTRACT_V2_VERSION,
    ACTION_TYPES,
    TAXONOMY_DISPOSITIONS,
    taxonomy_disposition_for_operation,
    validate_plan,
)


MIGRATION = Path(__file__).resolve().parents[1] / "supabase" / "staging_only" / "20260901020000_pdc_email_ai_typed_action_surface.sql"


class TypedActionSurfaceTests(unittest.TestCase):
    def test_contract_exposes_booking_work_and_activation_successors(self):
        self.assertTrue({
            "activate_vehicle", "operation_add", "operation_update", "booking_set",
            "booking_move", "booking_cancel", "work_complete", "required_work_set",
            "note_append", "location_set", "parts_eta_set", "parts_complete",
            "rft_transfer", "rft_collect",
        }.issubset(ACTION_TYPES))
        self.assertEqual(TAXONOMY_DISPOSITIONS, {"classified", "review", "unsupported", "conflict"})
        self.assertEqual(ACTION_CONTRACT_V2_VERSION, "pdc-email-ai-actions-v2")

    def test_taxonomy_blocks_mixed_signage_gvm_decals_from_hoist_or_sublet(self):
        description = "FMG Signage 75mm Safety stripping, FMG Logo's, ID, Tare,GVM,GCM Decals"
        self.assertEqual(taxonomy_disposition_for_operation(description, "HOIST", "pdc-operation-taxonomy-proposed/v1"), "review")
        self.assertEqual(taxonomy_disposition_for_operation(description, "SUBLET", "pdc-operation-taxonomy-proposed/v1"), "review")

    def test_taxonomy_preserves_known_review_conflict_and_unsupported_states(self):
        self.assertEqual(taxonomy_disposition_for_operation("Wheel Nut Indicator Set", "FITTING", "pdc-operation-taxonomy-proposed/v1"), "conflict")
        self.assertEqual(taxonomy_disposition_for_operation("Add a Sublet", "SUBLET", "pdc-operation-taxonomy-proposed/v1"), "unsupported")
        self.assertEqual(taxonomy_disposition_for_operation("Unmapped accessory", "NOT_A_GROUP", "pdc-operation-taxonomy-proposed/v1"), "unsupported")
        self.assertEqual(taxonomy_disposition_for_operation("12V accessory socket", "ELECTRICAL", "pdc-operation-taxonomy-proposed/v1"), "review")
        self.assertEqual(taxonomy_disposition_for_operation("Loose safety triangle", "FITTING", "pdc-operation-taxonomy-proposed/v1"), "review")
        self.assertEqual(taxonomy_disposition_for_operation("Weather shields", "FITTING", "pdc-operation-taxonomy-proposed/v1"), "review")

    def test_sql_is_staging_only_and_contains_fixed_dispatch_and_typed_receipts(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("20260901010000", sql)
        self.assertIn("latest100_attachment_work_receipt_successor", sql)
        self.assertIn("pdc_production_environment_sentinel", sql)
        for action in ("activate_vehicle", "operation_add", "operation_update", "booking_set", "booking_move", "booking_cancel", "required_work_set", "work_complete", "note_append", "location_set", "parts_eta_set", "parts_complete", "rft_transfer", "rft_collect"):
            self.assertIn(action, sql)
        for canonical in ("reconcile_navision_operational_record", "import_pdc_authenticated_email_operations_with_hours", "schedule_vehicle_work", "move_workshop_booking", "cancel_workshop_booking", "set_pdc_vehicle_work_states", "complete_workshop_work", "append_vehicle_timeline_event", "move_vehicle", "update_pdc_parts_eta", "mark_pdc_parts_complete", "rft_transfer_vehicle", "rft_collect_vehicle"):
            self.assertIn(canonical, sql)
        for marker in ("taxonomy_disposition", "review", "unsupported", "conflict", "before_state", "after_state", "readback_parity", "FORCE ROW LEVEL SECURITY", "service_role"):
            self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")


if __name__ == "__main__":
    unittest.main()
