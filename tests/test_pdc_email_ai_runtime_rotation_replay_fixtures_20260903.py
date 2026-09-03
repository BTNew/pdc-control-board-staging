from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903020000_pdc_email_ai_runtime_rotation_replay_fixtures_20260903.sql"
HARDENING = ROOT / "supabase/staging_only/20260903030000_pdc_email_ai_runtime_rotation_fixture_hardening_20260903.sql"
EVIDENCE_HARDENING = ROOT / "supabase/staging_only/20260903040000_pdc_email_ai_legacy_success_evidence_immutability_20260903.sql"
ATTESTATION = ROOT / "supabase/staging_only/20260903050000_pdc_email_ai_legacy_attachment_attestation_20260903.sql"
FINAL_BINDING = ROOT / "supabase/staging_only/20260903060000_pdc_email_ai_final_replay_binding_20260903.sql"
FINAL_GUARD = ROOT / "supabase/staging_only/20260903070000_pdc_email_ai_final_replay_input_guard_20260903.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_runtime_rotation_replay_fixtures_staging_20260903.py"


class RuntimeRotationReplayMigrationTests(unittest.TestCase):
    def sql(self) -> str:
        self.assertTrue(MIGRATION.is_file())
        return MIGRATION.read_text(encoding="utf-8")

    def hardening_sql(self) -> str:
        self.assertTrue(HARDENING.is_file())
        return HARDENING.read_text(encoding="utf-8")

    def test_successor_may_read_only_exact_predecessor_success_receipt(self):
        sql = self.sql()
        for marker in (
            "20260903010000",
            "workshop_eta_plus_seven_authority_20260903",
            "20260903020000",
            "pdc_email_ai_runtime_rotation_replay_fixtures_20260903",
            "predecessor.environment=v_successor.environment",
            "predecessor.identity_purpose=v_successor.identity_purpose",
            "predecessor.created_at<v_successor.created_at",
            "predecessor.revoked_at IS NOT NULL",
            "NOT predecessor.active",
            "t.identity_id=predecessor.identity_id",
            "t.typed_plan=p_plan",
            "t.plan_hash=public.pdc_email_ai_successor_hash(p_plan)",
            "t.aggregate_disposition::text='SUCCESS'",
            "t.readback_parity",
            "runtime_rotation_replay",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertIn("predecessor.identity_id=v_successor.identity_id", sql)
        self.assertNotRegex(sql, r"(?i)update\s+public\.pdc_email_ai_successor_(transaction|action)_receipts")
        self.assertNotRegex(sql, r"(?i)delete\s+from\s+public\.pdc_email_ai_successor_(transaction|action)_receipts")

        hardening = self.hardening_sql()
        for marker in (
            "pdc_email_ai_successor_runtime_rotations_20260903",
            "rotation.predecessor_identity_id=predecessor.identity_id",
            "rotation.successor_identity_id=v_successor.identity_id",
            "predecessor.revoked_at=rotation.predecessor_revoked_at",
            "attachment_hashes.hashes",
        ):
            with self.subTest(hardening_marker=marker):
                self.assertIn(marker, hardening)

    def test_changed_cross_source_and_hostile_plans_remain_closed(self):
        sql = self.sql()
        for marker in (
            "t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid",
            "t.source_digest=lower(p_plan->>'source_digest')",
            "t.evidence_digest=lower(p_plan->>'evidence_digest')",
            "i.id=t.source_receipt_id",
            "i.duplicate_of IS NULL",
            "source_message_id",
            "source_thread_id",
            "pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotIn("jsonb_set", sql)
        self.assertNotIn("GRANT SELECT", sql.upper())
        self.assertNotIn("GRANT INSERT", sql.upper())
        self.assertNotIn("GRANT UPDATE", sql.upper())
        self.assertNotIn("GRANT DELETE", sql.upper())

    def test_fourteen_immutable_complete_evidence_fixtures_are_exposed_by_rpc_only(self):
        sql = self.sql()
        self.assertIn("pdc_email_ai_v2_acceptance_fixtures_20260903", sql)
        self.assertIn("get_pdc_email_ai_v2_acceptance_fixtures_20260903", sql)
        self.assertIn("FORCE ROW LEVEL SECURITY", sql)
        self.assertIn("BEFORE UPDATE OR DELETE", sql)
        self.assertIn("jsonb_array_length(v_fixtures)=14", sql)
        self.assertIn("generate_series(1,14)", sql)
        for scenario in (
            "exact_vehicle_identity",
            "job_card_activation",
            "parts_eta_state_update",
            "parts_complete_update",
            "multi_action_email",
            "all_operation_lines_accounted",
            "explicit_hours_preserved",
            "missing_hours_estimated_with_provenance",
            "ambiguous_identity_review",
            "revised_superseding_evidence",
            "replay_idempotency",
            "taxonomy_review",
            "typed_write_readback_board_intake_parity",
            "restart_recovery_no_duplicate_effect",
        ):
            with self.subTest(scenario=scenario):
                self.assertIn(scenario, sql)
        for marker in (
            "source_receipt_id",
            "source_digest",
            "evidence_digest",
            "attachment_digests",
            "source_message_id",
            "source_thread_id",
            "authoritative_snapshot",
            "operation_source",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertRegex(sql, r"GRANT EXECUTE ON FUNCTION public\.get_pdc_email_ai_v2_acceptance_fixtures_20260903\(\) TO authenticated")
        self.assertIn("REVOKE ALL ON TABLE public.pdc_email_ai_v2_acceptance_fixtures_20260903 FROM public,anon,authenticated,service_role", sql)
        hardening = self.hardening_sql()
        self.assertIn("BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments", hardening)
        self.assertIn("f.source_receipt_id=NEW.intake_id", hardening)
        self.assertIn("f.source_receipt_id=OLD.intake_id", hardening)
        evidence_hardening = EVIDENCE_HARDENING.read_text(encoding="utf-8")
        self.assertIn("pdc_email_ai_success_evidence_intake_immutable_20260903", evidence_hardening)
        self.assertIn("pdc_email_ai_success_evidence_attachment_immutable_20260903", evidence_hardening)
        self.assertIn("coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)=attachment_hashes.hashes", evidence_hardening)
        attestation = ATTESTATION.read_text(encoding="utf-8")
        self.assertIn("coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes", attestation)
        # This detector is deliberately red-capable against the installed 050000 body.
        self.assertNotIn("t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid", attestation)
        self.assertNotIn("t.source_digest=lower(p_plan->>'source_digest')", attestation)
        self.assertNotIn("t.evidence_digest=lower(p_plan->>'evidence_digest')", attestation)
        final_binding = FINAL_BINDING.read_text(encoding="utf-8")
        self.assertIn("t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid", final_binding)
        self.assertIn("t.source_digest=lower(p_plan->>'source_digest')", final_binding)
        self.assertIn("t.evidence_digest=lower(p_plan->>'evidence_digest')", final_binding)
        self.assertIn("position('t.source_receipt_id=(p_plan->>''source_receipt_id'')::uuid' IN v_def)=0", final_binding)
        self.assertIn("position('t.source_digest=lower(p_plan->>''source_digest'')' IN v_def)=0", final_binding)
        self.assertIn("position('t.evidence_digest=lower(p_plan->>''evidence_digest'')' IN v_def)=0", final_binding)
        final_guard = FINAL_GUARD.read_text(encoding="utf-8")
        self.assertIn("coalesce(p_plan->>'source_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'", final_guard)
        self.assertIn("coalesce(p_plan->>'source_digest','') !~ '^[a-f0-9]{64}$'", final_guard)
        self.assertIn("coalesce(p_plan->>'evidence_digest','') !~ '^[a-f0-9]{64}$'", final_guard)

    def test_controller_applies_only_to_linked_staging_and_verifies_runtime_behavior(self):
        self.assertTrue(CONTROLLER.is_file())
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt",
            "PDC_APPROVE_STAGING_MIGRATION_20260903020000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903030000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903040000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903050000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903060000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903070000",
            "Supabase CLI:supabase",
            "/v1/projects/{STAGING_REF}/database/query",
            "migration_ledger",
            "final_function_definition",
            "final_function_sha256",
            "predecessor_successor_exact_replay",
            "stable_transaction_id",
            "stable_action_receipt_ids",
            "zero_mutations",
            "changed_plan_rejected",
            "malformed_source_receipt_rejected",
            "hostile_plan_rejected",
            "fixture_count",
            "protected_table_access_denied",
            "generic_dml_denied",
            "production_contacted",
            "mailbox_contacted",
            "outbound_email_sent",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("PRODUCTION_REF in path or STAGING_REF not in path", source)
        self.assertNotIn('values.get("SUPABASE_URL")', source)


if __name__ == "__main__":
    unittest.main()
