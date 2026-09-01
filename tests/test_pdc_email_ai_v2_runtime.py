import json
import tempfile
import unittest
from pathlib import Path

from backend.pdc_email_ai_v2_actions import (
    ActionContractError,
    ShadowActionClient,
    build_action_request,
    validate_v2_plan,
)
from backend.pdc_email_ai_v2_planner import V2Planner
from backend.pdc_email_ai_v2_readback import project_readback, validate_readback
from backend.pdc_email_ai_v2_rules import CraigRuleStore
from backend.pdc_email_ai_v2_taxonomy import classify_operation
from backend.pdc_email_ai_v2_runtime import V2ShadowRuntime


VEHICLE_A = {
    "vehicle_id": "22222222-2222-4222-8222-222222222222",
    "stock_number": "13000765",
    "vin": None,
    "backend_record_id": None,
    "vehicle_version": 9,
    "backend_revision": 12,
    "location": "PMB",
}
VEHICLE_B = {**VEHICLE_A, "vehicle_id": "44444444-4444-4444-8444-444444444444", "stock_number": "13000766", "vehicle_version": 4}


def receipt():
    return {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "source_digest": "a" * 64,
        "evidence_digest": "b" * 64,
        "thread_id": "thread-v2",
        "message_id": "message-v2",
        "received_at": "2026-09-01T01:00:00+00:00",
        "correspondence": "Stock 13000765 parts ETA 15 September 2026. Please do whatever is needed for Stock 13000766.",
    }


class TaxonomyTests(unittest.TestCase):
    def test_owner_rules_and_negative_precedence(self):
        self.assertEqual(classify_operation("Bull Bar installation").work_key, "FITTING")
        self.assertEqual(classify_operation("Weather shields, matte tint").disposition, "REVIEW")
        self.assertEqual(classify_operation("ARB Long Ranger fuel tank").work_key, "HOIST")
        self.assertEqual(classify_operation("1.0 KG FIRE EXTINGUISHER", mounted=True).work_key, "FABRICATION")
        self.assertEqual(classify_operation("Fire extinguisher decal only").disposition, "REVIEW")
        self.assertEqual(classify_operation("FMG signage GVM GCM Tare decals").disposition, "REVIEW")
        self.assertIsNone(classify_operation("Reflective Stripes - Yellow").work_key)
        self.assertEqual(classify_operation("Reflective Stripes - Yellow", explicit_sublet=True).work_key, "SUBLET")

    def test_rules_are_versioned_and_non_destructive(self):
        store = CraigRuleStore.default()
        result = store.resolve("Bullbar")
        self.assertEqual(result["destination"], "FITTING")
        self.assertTrue(result["version"].startswith("rules-v"))
        self.assertEqual(result["rule_id"], "craig-bullbar-fitting")
        self.assertIn("original_instruction", result)


class PlannerTests(unittest.TestCase):
    def test_planner_output_is_strictly_validated_and_builds_planned_requests(self):
        planner = V2Planner(rules=CraigRuleStore.default())
        plan = planner.plan(
            {**receipt(), "correspondence": "Stock 13000765 parts ETA 15 September 2026."},
            [{"digest": "c" * 64, "filename": "job.pdf", "stock_number": "13000765", "lines": [{"operation_no": "OP1", "description": "Bullbar fitting", "estimated_hours": 2.0}]}],
            [VEHICLE_A],
        )
        validated = validate_v2_plan(plan)
        self.assertEqual(validated["schema_version"], "pdc-email-ai-plan-v1")
        self.assertEqual(next(row for row in validated["instructions"] if row.get("payload", {}).get("description") == "Bullbar fitting")["action_type"], "operation_add")
        planned = [row for row in validated["instructions"] if row["decision_disposition"] == "planned"]
        requests = [build_action_request(plan_id=validated["plan_id"], source_receipt_id=validated["source_receipt_id"], source_digest=validated["source_digest"], evidence_digest=validated["evidence_digest"], instruction=row) for row in planned]
        self.assertEqual({row["action_type"] for row in requests}, {"parts_eta_set", "operation_add"})

    def test_v2_validator_rejects_extra_payload_keys_before_request_building(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(
            {**receipt(), "correspondence": "Stock 13000765 parts ETA 15 September 2026."}, [], [VEHICLE_A]
        )
        plan["instructions"][0]["payload"]["unexpected"] = True
        with self.assertRaises(ActionContractError):
            validate_v2_plan(plan)

    def test_v2_validator_rejects_legacy_action_contract_identity(self):
        plan = V2Planner(rules=CraigRuleStore.default()).plan(receipt(), [], [VEHICLE_A])
        plan["versions"]["supabase_action_contract_version"] = "pdc-email-ai-actions-v1"
        with self.assertRaises(ActionContractError):
            validate_v2_plan(plan)

    def test_attachment_scope_and_unknown_instruction_are_preserved(self):
        planner = V2Planner(rules=CraigRuleStore.default())
        plan = planner.plan(
            receipt(),
            [
                {"digest": "c" * 64, "filename": "a.pdf", "stock_number": "13000765", "lines": [
                    {"operation_no": "OP1", "description": "Bullbar fitting", "estimated_hours": 2.0}
                ]},
                {"digest": "d" * 64, "filename": "b.pdf", "stock_number": "13000766", "vin": "JH4TB2H26CC000001", "lines": [
                    {"operation_no": "OP1", "description": "Reflective Stripes - Yellow", "estimated_hours": None}
                ]},
            ],
            [VEHICLE_A, VEHICLE_B],
        )
        self.assertEqual(plan["environment"], "staging")
        self.assertEqual(len(plan["instructions"]), 4)
        self.assertEqual(plan["instructions"][0]["action_type"], "parts_eta_set")
        fitting = next(row for row in plan["instructions"] if row["payload"].get("description") == "Bullbar fitting")
        self.assertEqual(fitting["payload"]["work_key"], "FITTING")
        self.assertEqual(plan["instructions"][1]["decision_disposition"], "review")
        self.assertEqual(plan["instructions"][2]["decision_disposition"], "planned")
        self.assertEqual(len(plan["instructions"]), 4)
        self.assertEqual(plan["instructions"][3]["evidence_refs"][1]["ref"], "attachment:" + "d" * 64)

    def test_bracketed_estimated_hours_are_parsed_and_zero_is_preserved(self):
        planner = V2Planner(rules=CraigRuleStore.default())
        plan = planner.plan({**receipt(), "correspondence": ""}, [{"digest": "c" * 64, "filename": "job.pdf", "stock_number": "13000765", "lines": [{"operation_no": "OP1", "description": "Bullbar [EST HRS] 2.50", "estimated_hours": None}, {"operation_no": "OP2", "description": "Bullbar [EST HRS] 0.00", "estimated_hours": None}]}], [VEHICLE_A])
        self.assertEqual([row["payload"]["estimated_hours"] for row in plan["instructions"]], [2.5, 0.0])

    def test_unknown_hours_are_review_only_and_not_coerced_to_zero(self):
        planner = V2Planner(rules=CraigRuleStore.default())
        plan = planner.plan(
            {**receipt(), "correspondence": ""},
            [{"digest": "c" * 64, "filename": "job.pdf", "stock_number": "13000765", "lines": [{"operation_no": "OP1", "description": "Bullbar fitting", "estimated_hours": None}]}],
            [VEHICLE_A],
        )
        operation = plan["instructions"][0]
        self.assertEqual(operation["decision_disposition"], "review")
        self.assertIsNone(operation["payload"]["estimated_hours"])
        self.assertIn("hours", operation["reason"])

    def test_conflicting_identity_is_isolated(self):
        planner = V2Planner(rules=CraigRuleStore.default())
        plan = planner.plan(
            {**receipt(), "correspondence": ""},
            [{"digest": "c" * 64, "filename": "conflict.pdf", "stock_number": "13000765", "vin": "JH4TB2H26CC000001", "lines": []}],
            [VEHICLE_A, {**VEHICLE_B, "vin": "JH4TB2H26CC000001"}],
        )
        self.assertEqual(len(plan["instructions"]), 1)
        self.assertEqual(plan["instructions"][0]["decision_disposition"], "conflict")
        self.assertIn("identity", plan["instructions"][0]["reason"])


class ActionAndReadbackTests(unittest.TestCase):
    def test_shadow_action_client_never_calls_transport_and_rejects_production(self):
        request = build_action_request(
            plan_id="11111111-1111-4111-8111-111111111111",
            source_receipt_id=receipt()["receipt_id"],
            source_digest="a" * 64,
            evidence_digest="b" * 64,
            instruction={
                "instruction_id": "instruction-0001",
                "vehicle_id": VEHICLE_A["vehicle_id"],
                "expected_state": {"vehicle_version": 9, "backend_revision": 12},
                "action_type": "parts_eta_set",
                "payload": {"eta": "2026-09-15"},
                "evidence_refs": [{"kind": "message", "ref": "message-v2", "required_for_action": True}],
                "provenance": {"transport_release_version": "v2", "planner_version": "v2", "model_version": "model", "prompt_version": "prompt", "business_rule_version": "rules-v2", "ruleset_version": "rules-v2", "taxonomy_version": "taxonomy-v2", "supabase_action_contract_version": "action-v1", "source_digest": "a" * 64, "evidence_digest": "b" * 64},
            },
        )
        client = ShadowActionClient()
        result = client.submit(request)
        self.assertEqual(result["disposition"], "planned")
        self.assertFalse(result["operational_write_attempted"])
        with self.assertRaises(ActionContractError):
            build_action_request(environment="production", plan_id="11111111-1111-4111-8111-111111111111", source_receipt_id=receipt()["receipt_id"], source_digest="a" * 64, evidence_digest="b" * 64, instruction=request)

    def test_readback_projection_is_deterministic_and_staging_bound(self):
        state = {**VEHICLE_A, "operations": [{"operation_line_id": "55555555-5555-4555-8555-555555555555", "operation_no": "OP1", "description": "Bullbar", "work_key": "FITTING", "estimated_hours": 2.0, "hours_provenance": "job_card", "completed": False}], "required_work": {"FITTING": True}, "parts": {"required": True, "ordered": False, "complete": False, "eta": None}, "bookings": [], "lifecycle": {"status": "active", "qc_complete": False, "rft_ready": False, "collected": False}}
        projected = project_readback(state, source_revision=12)
        self.assertEqual(validate_readback(projected)["projection_digest"], projected["projection_digest"])
        self.assertEqual(projected["identity"]["stock_number"], "13000765")
        self.assertEqual(projected["operations"][0]["work_key"], "FITTING")
        with self.assertRaises(ActionContractError):
            validate_readback({**projected, "environment": "production"})


class RuntimeTests(unittest.TestCase):
    def test_shadow_runtime_has_zero_writes_and_preserves_receipt(self):
        runtime = V2ShadowRuntime(rules=CraigRuleStore.default())
        result = runtime.run(receipt(), [{"digest": "c" * 64, "filename": "a.pdf", "stock_number": "13000765", "lines": []}], [VEHICLE_A])
        self.assertTrue(result["all_instructions_accounted"])
        self.assertFalse(result["operational_writes_attempted"])
        self.assertEqual(result["mode"], "SHADOW_ZERO_WRITE")
        self.assertEqual(result["source_digest"], "a" * 64)
        self.assertEqual(result["action_results"][0]["disposition"], "planned")

    def test_queued_shadow_cycle_finishes_durable_reference_without_operational_write(self):
        from backend.pdc_email_ai_v2_queue import DurableQueue
        with tempfile.TemporaryDirectory() as temp:
            queue = DurableQueue(Path(temp) / "queue.sqlite")
            queue.enqueue(source_digest="e" * 64, receipt_path="receipt.json", mailbox="pdc@example.test", folder="Inbox", uidvalidity=1, uid=1)
            result = V2ShadowRuntime(rules=CraigRuleStore.default()).process_one_queued(
                queue,
                owner="shadow-worker",
                receipt_loader=lambda _: {**receipt(), "source_digest": "e" * 64},
                attachments_loader=lambda _: [],
                contexts_loader=lambda _: [VEHICLE_A],
            )
            self.assertFalse(result["operational_writes_attempted"])
            self.assertEqual(queue.counts()["COMPLETED"], 1)


class FixtureAndRecoveryTests(unittest.TestCase):
    def test_fixture_catalog_and_v2_recovery_pack_are_complete_and_secretless(self):
        root = Path(__file__).resolve().parents[1]
        catalog = json.loads((root / "fixtures" / "v2-scenario-catalog-v1.json").read_text(encoding="utf-8"))
        self.assertEqual(len(catalog["owner_scenarios"]), 14)
        self.assertEqual(len(catalog["hostile_negatives"]), 10)
        fixtures = json.loads((root / "fixtures" / "v2-safe-fixtures-v1.json").read_text(encoding="utf-8"))
        self.assertEqual(len(fixtures["scenarios"]), 14)
        self.assertEqual(len(fixtures["hostile_negatives"]), 10)
        self.assertEqual({row["scenario_id"] for row in fixtures["scenarios"]}, {row["scenario_id"] for row in catalog["owner_scenarios"]})
        self.assertEqual({row["negative_id"] for row in fixtures["hostile_negatives"]}, {row["negative_id"] for row in catalog["hostile_negatives"]})
        pack = root / "recovery-pack" / "v2"
        manifest = json.loads((pack / "RECOVERY-PACK-MANIFEST.json").read_text(encoding="utf-8"))
        self.assertFalse(manifest["secret_policy"]["plaintext_secrets"])
        self.assertIn("PDC_V2_MAILBOX_SECRET", (pack / "ENVIRONMENT-REQUIREMENTS.md").read_text(encoding="utf-8"))
        self.assertFalse(list(pack.rglob(".env")))


if __name__ == "__main__":
    unittest.main()
