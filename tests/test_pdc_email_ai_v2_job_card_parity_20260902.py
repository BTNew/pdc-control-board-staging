from __future__ import annotations

import unittest
from pathlib import Path

from backend.pdc_email_ai_v2_actions import ActionContractError, validate_v2_plan
from backend.pdc_email_ai_v2_planner import V2Planner
from backend.pdc_email_ai_v2_runtime import V2ShadowRuntime
from backend.pdc_email_ai_v2_rules import CraigRuleStore


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902264000_pdc_email_ai_v2_job_card_parity_correction_20260902.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_v2_job_card_parity_correction_staging.py"
DEPLOYED_REPAIR = ROOT / "supabase/staging_only/20260902265000_pdc_email_ai_v2_job_card_deployed_function_repair_20260902.sql"
REPLAY_REPAIR = ROOT / "supabase/staging_only/20260902266000_pdc_email_ai_v2_job_card_replay_validation_order_20260902.sql"

VEHICLE = {
    "vehicle_id": "22222222-2222-4222-8222-222222222222",
    "stock_number": "13059806",
    "vin": "JTMAA7BJ204154038",
    "backend_record_id": "33333333-3333-4333-8333-333333333333",
    "vehicle_version": 4,
    "backend_revision": 12,
}


def receipt():
    return {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "source_digest": "a" * 64,
        "evidence_digest": "b" * 64,
        "thread_id": "thread-709",
        "message_id": "message-709",
        "received_at": "2026-09-01T03:13:15+00:00",
        "correspondence": "",
    }


class JobCardPlannerTests(unittest.TestCase):
    def test_exact_attachment_job_card_becomes_source_bound_typed_action(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{
                "digest": "c" * 64,
                "filename": "J139125567_RepairOrder.pdf",
                "stock_number": "13059806",
                "vin": "JTMAA7BJ204154038",
                "lines": [{"operation_no": "OP1", "description": "Pre-Delivery (Commercial)", "estimated_hours": 0.0}],
            }],
            [VEHICLE],
        )
        job_cards = [item for item in plan["instructions"] if item["action_type"] == "job_card_set"]
        self.assertEqual(len(job_cards), 1)
        self.assertEqual(job_cards[0]["payload"], {
            "attachment_digest": "c" * 64,
            "job_card_number": "J139125567",
            "source_uid": "message-709:" + "c" * 64,
            "stock_number": "13059806",
            "vin": "JTMAA7BJ204154038",
        })
        self.assertEqual(job_cards[0]["decision_disposition"], "planned")
        validate_v2_plan(plan)

    def test_no_job_card_attachment_does_not_invent_a_job_card_action(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [{"digest": "d" * 64, "filename": "GP10516664_PurchaseOrder.pdf", "stock_number": "13059806", "lines": []}],
            [VEHICLE],
        )
        self.assertFalse(any(item["action_type"] == "job_card_set" for item in plan["instructions"]))
        self.assertFalse(any(item["action_type"] == "job_card_set" for item in plan["instructions"]))

    def test_conflicting_attachment_job_cards_are_not_planned(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            receipt(),
            [
                {"digest": "e" * 64, "filename": "J139125567_RepairOrder.pdf", "stock_number": "13059806", "lines": []},
                {"digest": "f" * 64, "filename": "J139125568_RepairOrder.pdf", "stock_number": "13059806", "lines": []},
            ],
            [VEHICLE],
        )
        self.assertFalse(any(item["action_type"] == "job_card_set" for item in plan["instructions"]))
        self.assertTrue(any(item["decision_disposition"] == "review" for item in plan["instructions"]))

    def test_job_card_payload_rejects_wrong_shape_or_digest(self):
        planner = V2Planner(rules=CraigRuleStore.default())
        plan = planner.plan(
            receipt(),
            [{"digest": "c" * 64, "filename": "J139125567_RepairOrder.pdf", "stock_number": "13059806", "lines": []}],
            [VEHICLE],
        )
        item = next(item for item in plan["instructions"] if item["action_type"] == "job_card_set")
        item["payload"]["attachment_digest"] = "not-a-digest"
        with self.assertRaises(ActionContractError):
            validate_v2_plan(plan)


class JobCardMigrationContractTests(unittest.TestCase):
    def test_migration_and_controller_are_present_and_fail_closed(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        controller = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "PDC_20260902264000_STAGING_PRECONDITION_FAILED",
            "pdc_email_ai_v2_job_card_parity_corrections_20260902",
            "reconcile_pdc_email_ai_v2_job_card_parity_20260902",
            "pdc_email_ai_successor_runtime_identities",
            "pdc_monitor_stage_activation_writers",
            "pdc_authenticated_email_import_receipts",
            "ai_email_attachments",
            "pdc_provider_email_observations",
            "job_card_conflict_protected",
            "source_reuse_conflict",
            "vehicle_identity_conflict",
            "attachment_source_mismatch",
            "booking_created',false",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
            "action_rpc_invoked",
        ):
            self.assertIn(marker, sql)
        self.assertIn("PDC_APPROVE_STAGING_MIGRATION_20260902264000", controller)
        self.assertIn("cdsmnqxtyyoeoznmbidd", controller)
        self.assertIn("production_writes", controller)
        self.assertNotIn("GRANT EXECUTE ON FUNCTION public.reconcile_pdc_email_ai_v2_job_card_parity_20260902(uuid) TO service_role", sql)

    def test_follow_up_repairs_preserve_real_staging_schema_and_replay_guards(self):
        deployed = DEPLOYED_REPAIR.read_text(encoding="utf-8")
        replay = REPLAY_REPAIR.read_text(encoding="utf-8")
        self.assertIn("workshop_booking_status enum", deployed)
        self.assertIn("v_vehicle.vin IS NOT NULL", deployed)
        self.assertIn("conflicting retries fail closed", replay)
        self.assertIn("v_existing.request_hash<>v_request_hash", replay)
        self.assertIn("pdc_email_ai_v2_job_card_replay_validation_history_20260902", replay)


if __name__ == "__main__":
    unittest.main()
