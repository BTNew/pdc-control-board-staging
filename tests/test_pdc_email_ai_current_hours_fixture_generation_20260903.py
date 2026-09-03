from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903120000_pdc_email_ai_current_hours_fixture_generation_20260903.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_current_hours_fixture_generation_staging_20260903.py"
ALIGNMENT = ROOT / "supabase/staging_only/20260903121000_pdc_email_ai_v2_contract_alignment_20260903.sql"
ALIGNMENT_CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_v2_contract_alignment_staging_20260903.py"
GENERATION_ID = "9cea2926-0002-4000-8000-000000000014"


class CurrentHoursMigrationContractTests(unittest.TestCase):
    def test_append_only_validator_repair_is_narrow_and_hash_guarded(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("20260903110000", sql)
        self.assertIn("PDC_20260903120000_STAGING_PRECONDITION_FAILED", sql)
        self.assertIn("pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)", sql)
        self.assertIn("('job_card','business_rule_default')", sql)
        self.assertIn("('job_card','ai_estimate','business_rule_default')", sql)
        self.assertIn("estimated_hours_source", sql)
        self.assertIn("predecessor_function_sha256", sql)
        self.assertIn("successor_function_sha256", sql)
        self.assertIn("pdc_email_ai_successor_execute_v2_20260901(jsonb)", sql)
        self.assertIn("import_pdc_authenticated_email_operations_with_hours", sql)

    def test_generation_two_is_immutable_scoped_and_complete(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            GENERATION_ID,
            "pdc_email_ai_v2_acceptance_fixture_generations_20260903",
            "pdc_email_ai_v2_acceptance_fixtures_generation_20260903",
            "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903",
            "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903",
            "scenario_no BETWEEN 1 AND 14",
            "generate_series(1,14)",
            "Pre-Delivery",
            "2.50",
            "0.00",
            "AI ESTIMATE",
            "BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments",
            "BEFORE UPDATE OR DELETE ON public.ai_email_intake",
            "acceptance_fixture_scope_denied",
            "typed_v2_plan_invalid",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn(
            "GRANT SELECT ON public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903",
            sql,
        )
        self.assertNotIn("service_role TO authenticated", sql)

    def test_controller_uses_management_staging_and_real_runtime_jwt(self):
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt",
            "PDC_APPROVE_STAGING_MIGRATION_20260903120000",
            "Supabase CLI:supabase",
            "pdc-email-ai-lead/.env",
            "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903",
            "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903",
            "apply_pdc_email_ai_typed_action_surface_20260901_strict",
            "fresh_fixture_count",
            "protected_table_http_statuses",
            "production_contacted",
            "mailbox_contacted",
            "outbound_email_sent",
        ):
            self.assertIn(marker, source)

    def test_followup_aligns_python_and_installed_first_apply_contract(self):
        sql = ALIGNMENT.read_text(encoding="utf-8")
        controller = ALIGNMENT_CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "20260903120000", "20260903121000", "68c06ccced246a3eb63f3b460f372da3b7421dd728705863544c447dc129f8c0",
            "operation_update_first_apply_disabled", "operation_number_fully_anchored",
            "^(OP[1-9][0-9]{0,2}|PD[0-9]{3}-[A-F0-9]{8})$",
            "('job_card','ai_estimate','business_rule_default')", "PDC_20260903121000_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker, sql)
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260903121000", "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt", "operation_update_fail_closed", "fresh_fixture_count",
        ):
            self.assertIn(marker, controller)


if __name__ == "__main__":
    unittest.main(verbosity=2)
