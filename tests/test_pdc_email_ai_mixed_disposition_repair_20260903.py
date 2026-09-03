from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903122000_pdc_email_ai_mixed_disposition_repair_20260903.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_mixed_disposition_repair_staging_20260903.py"
RECOVERY = ROOT / "supabase/staging_only/20260903123000_pdc_email_ai_mixed_apply_fixture_refresh_20260903.sql"
EVIDENCE_BOUND_REFRESH = ROOT / "supabase/staging_only/20260903124000_pdc_email_ai_evidence_bound_fixture_refresh_20260903.sql"
GENERATION_FOUR_ID = "5bf31237-0004-4000-8000-000000000014"
GENERATION_FIVE_ID = "5bf31237-0005-4000-8000-000000000014"


class MixedDispositionRepairContractTests(unittest.TestCase):
    def test_migration_parses_as_postgresql(self):
        self.assertGreater(len(parse_sql(MIGRATION.read_text(encoding="utf-8"))), 0)

    def test_strict_wrapper_routes_only_pure_non_dispatch_away_from_executor(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260903121000",
            "PDC_20260903122000_STAGING_PRECONDITION_FAILED",
            "apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)",
            "predecessor_function_sha256",
            "successor_function_sha256",
            "pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan)",
            "pdc_email_ai_successor_execute_v2_20260901(p_plan)",
            "decision_disposition'='planned'",
            "decision_disposition'<>'planned'",
            "operation_update_mixed_plan_requires_replan",
        ):
            self.assertIn(marker, sql)
        successor = sql.split("v_new text:=$new$", 1)[1].split("$new$;", 1)[0]
        self.assertNotIn(
            "IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'decision_disposition'<>'planned') THEN\n    RETURN public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan);",
            successor,
        )

    def test_generation_three_is_fresh_immutable_and_fourteen_scenarios(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "5bf31237-0003-4000-8000-000000000014",
            "generation_no=3",
            "fixture_count=14",
            "generate_series(1,14)",
            "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903",
            "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903",
            "BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments",
            "BEFORE UPDATE OR DELETE ON public.ai_email_intake",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
        ):
            self.assertIn(marker, sql)

    def test_generation_four_refresh_is_append_only_after_failed_fixture_identity(self):
        sql = RECOVERY.read_text(encoding="utf-8")
        self.assertGreater(len(parse_sql(sql)), 0)
        for marker in (
            "20260903122000", "20260903123000", GENERATION_FOUR_ID, "generation_no=4", "fixture_count=14",
            "OP91", "OP92", "operation_identity_conflict", "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v4",
            "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v4", "PDC_20260903123000_STAGING_PRECONDITION_FAILED",
        ):
            self.assertIn(marker, sql)

    def test_controller_exercises_real_scoped_jwt_and_mixed_apply(self):
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260903124000",
            "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt",
            "pdc-email-ai-lead/.env",
            "validated_fixture_count",
            "mixed_apply",
            "APPLIED_AND_VERIFIED",
            "GENUINELY_AMBIGUOUS",
            "canonical_rpc",
            "protected_table_http_statuses",
            "production_contacted",
            "mailbox_contacted",
            "outbound_email_sent",
        ):
            self.assertIn(marker, source)
        self.assertNotIn('line["operation_no"] =', source)
        self.assertNotIn('line["source_row_no"] =', source)

    def test_generation_five_binds_reserved_operation_ids_into_source_evidence(self):
        sql = EVIDENCE_BOUND_REFRESH.read_text(encoding="utf-8")
        self.assertGreater(len(parse_sql(sql)), 0)
        for marker in (
            "20260903123000", "20260903124000", GENERATION_FIVE_ID, "generation_no=5", "fixture_count=14",
            "'OP 010','OP 091'", "'OP 020','OP 092'", "'OP 030','OP 093'",
            "{operation_lines,0,operation_no}", "{operation_lines,1,operation_no}", "{operation_lines,2,operation_no}",
            "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5",
            "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5",
        ):
            self.assertIn(marker, sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
