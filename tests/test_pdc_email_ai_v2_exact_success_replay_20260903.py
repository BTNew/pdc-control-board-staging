from __future__ import annotations

import copy
import re
import unittest
from pathlib import Path

from backend.pdc_email_ai_v2_actions import ActionContractError, validate_v2_plan


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902274000_pdc_email_ai_v2_exact_success_replay_20260903.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_v2_exact_success_replay_staging_20260903.py"


def current_schema_plan() -> dict:
    source_digest = "a" * 64
    evidence_digest = "b" * 64
    vehicle_id = "22222222-2222-4222-8222-222222222222"
    versions = {
        "transport_release_version": "test-transport-v1",
        "planner_version": "test-planner-v1",
        "model_version": "test-model-v1",
        "prompt_version": "test-prompt-v1",
        "business_rule_version": "test-business-rules-v1",
        "ruleset_version": "test-ruleset-v1",
        "taxonomy_version": "pdc-operation-taxonomy-proposed/v1",
        "supabase_action_contract_version": "pdc-email-ai-action-request-v1",
        "source_digest": source_digest,
        "evidence_digest": evidence_digest,
    }
    return {
        "schema_version": "pdc-email-ai-plan-v1",
        "plan_id": "11111111-1111-4111-8111-111111111111",
        "environment": "staging",
        "source_receipt_id": "33333333-3333-4333-8333-333333333333",
        "source_digest": source_digest,
        "evidence_digest": evidence_digest,
        "source_thread_id": "test-thread",
        "source_message_id": "test-message",
        "attachment_digests": [],
        "versions": versions,
        "instructions": [{
            "instruction_id": "test-note-1",
            "vehicle_id": vehicle_id,
            "identity": {
                "vehicle_id": vehicle_id,
                "stock_number": "13000001",
                "vin": "JTMAA7BJ204154038",
                "backend_record_id": None,
            },
            "action_type": "note_append",
            "payload": {"text": "Current-schema fixture note", "event_at": "2026-09-03T00:00:00+00:00"},
            "evidence_refs": [{"kind": "message", "ref": "test-message", "required_for_action": True}],
            "required_evidence": ["authoritative_identity"],
            "expected_state": {"vehicle_version": 1, "backend_revision": 0},
            "decision_disposition": "planned",
            "provenance": versions.copy(),
            "audit_event_ref": "test-audit-1",
            "reason": "current-schema regression fixture",
        }],
        "aggregate_disposition": "planned",
        "planner_status": "available",
        "planner_failure_reason": None,
        "created_at": "2026-09-03T00:00:00+00:00",
    }


class CurrentSchemaEvidenceReferenceTests(unittest.TestCase):
    def test_current_schema_object_evidence_reference_is_valid(self):
        self.assertEqual(validate_v2_plan(current_schema_plan())["plan_id"], "11111111-1111-4111-8111-111111111111")

    def test_legacy_string_evidence_reference_is_rejected_for_new_plan(self):
        plan = current_schema_plan()
        plan["instructions"][0]["evidence_refs"] = ["message:test-message"]
        with self.assertRaisesRegex(ActionContractError, "evidence reference shape is invalid"):
            validate_v2_plan(plan)


class ExactSuccessfulReplayMigrationTests(unittest.TestCase):
    def test_migration_resolves_only_exact_successful_replay_before_current_validation(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        for marker in (
            "20260902273000",
            "navision_yh_location_authority_20260903",
            "20260902274000",
            "pdc_email_ai_v2_exact_success_replay_20260903",
            "pdc_email_ai_successor_transaction_receipts",
            "aggregate_disposition::text='SUCCESS'",
            "readback_parity",
            "t.identity_id=v_identity.identity_id",
            "t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid",
            "t.source_digest=lower(p_plan->>'source_digest')",
            "t.evidence_digest=lower(p_plan->>'evidence_digest')",
            "t.plan_hash=public.pdc_email_ai_successor_hash(p_plan)",
            "t.typed_plan=p_plan",
            "exact_successful_replay",
            "pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        patch_block = re.search(r"v_block text:=\$block\$(.*?)\$block\$;", sql, re.S)
        self.assertIsNotNone(patch_block)
        body = patch_block.group(1)
        self.assertIn("pdc_email_ai_successor_exact_success_replay_20260903(p_plan,actor,email)", body)
        self.assertIn("RETURN v_exact_successful_replay", body)
        self.assertIn("v_definition:=replace(v_definition,v_anchor,v_block||v_anchor)", sql)
        self.assertIn("position('successor_runtime_identity_denied' IN v_strict)>position('exact_successful_replay' IN v_strict)", sql)
        self.assertNotIn("UPDATE public.pdc_email_ai_successor_transaction_receipts", sql)
        self.assertNotIn("DELETE FROM public.pdc_email_ai_successor_transaction_receipts", sql)
        self.assertNotIn("UPDATE public.pdc_email_ai_successor_action_receipts", sql)
        self.assertNotIn("DELETE FROM public.pdc_email_ai_successor_action_receipts", sql)

    def test_migration_leaves_unmatched_or_changed_legacy_plans_on_strict_validator_path(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("IF v_matches=0 THEN RETURN NULL", sql)
        self.assertIn("t.typed_plan=p_plan", sql)
        self.assertIn("v_block||v_anchor", sql)
        self.assertIn("pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)", sql)
        self.assertNotIn("jsonb_set", sql)
        self.assertNotIn("jsonb_build_object('kind','legacy'", sql.lower())

    def test_controller_is_hash_approved_staging_only_and_proves_zero_mutation_replay(self):
        self.assertTrue(CONTROLLER.is_file())
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260902274000",
            "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt",
            "exact_successful_replay_before_validator",
            "legacy_new_apply_rejected",
            "changed_legacy_plan_rejected",
            "identity_source_binding_rejected",
            "receipt_counts_before",
            "receipt_counts_after",
            "production_contacted",
            "mailbox_contacted",
            "outbound_email_sent",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)


if __name__ == "__main__":
    unittest.main()
