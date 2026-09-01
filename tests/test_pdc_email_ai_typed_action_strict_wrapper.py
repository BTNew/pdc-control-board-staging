import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901100000_pdc_email_ai_typed_action_strict_wrapper_20260901.sql"
CORRECTION_MIGRATION = ROOT / "supabase" / "staging_only" / "20260901110000_pdc_email_ai_typed_action_review_receipts_20260901.sql"
CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_typed_action_strict_wrapper_staging.py"
CORRECTION_CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_typed_action_review_receipts_staging.py"
EXECUTION_MIGRATION = ROOT / "supabase" / "staging_only" / "20260901120000_pdc_email_ai_typed_action_field_executor_identity_20260901.sql"
EXECUTION_CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_typed_action_field_executor_identity_staging.py"


class StrictWrapperMigrationTests(unittest.TestCase):
    def test_append_only_migration_rebinds_strict_entrypoint_to_full_plan_validator(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 5)
        self.assertIn("20260901090000", sql)
        self.assertIn("20260901100000", sql)
        self.assertIn("pdc_email_ai_typed_action_strict_wrapper_20260901", sql)
        self.assertIn("CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)", sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        wrapper = re.search(r"CREATE OR REPLACE FUNCTION public\.apply_pdc_email_ai_typed_action_surface_20260901_strict\(p_plan jsonb\).*?\$strict\$(.*?)END \$strict\$;", sql, re.S)
        self.assertIsNotNone(wrapper)
        body = wrapper.group(1)
        self.assertIn("pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)", body)
        self.assertNotIn("pdc_email_ai_successor_validate_v2_instruction_20260901(p_plan)", body)
        self.assertLess(body.index("pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)"), body.index("apply_pdc_email_ai_operation_update_transaction_20260901"))

    def test_replay_guard_and_ledger_record_bind_the_exact_source_identity(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901100000')", sql)
        self.assertIn("version='20260901090000'", sql)
        self.assertRegex(sql, r"INSERT INTO supabase_migrations\.schema_migrations\(version,name,statements\) VALUES\('20260901100000','pdc_email_ai_typed_action_strict_wrapper_20260901'")
        self.assertIn("Full pdc_email_ai_successor_validate_v2_plan_20260901 is called by the strict authenticated entrypoint before source lookup or canonical dispatch", sql)

    def test_staging_controller_is_hash_and_target_bound_without_service_role(self):
        self.assertTrue(CONTROLLER.is_file())
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "20260901090000",
            "20260901100000",
            "PDC_APPROVE_STAGING_MIGRATION_20260901100000",
            "pg_get_functiondef",
            "strict_wrapper_full_validator_bound",
            "PDC_TYPED_ACTION_STRICT_WRAPPER_POST_APPLY_READBACK_FAILED",
        ):
            self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("vjdtsswhroyguxyfjdkt", source)

    def test_review_correction_preserves_disposition_and_never_projects_to_dispatch(self):
        self.assertTrue(CORRECTION_MIGRATION.is_file())
        sql = CORRECTION_MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 5)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        for marker in (
            "20260901100000",
            "20260901110000",
            "pdc_email_ai_successor_record_non_dispatch_v2_20260901",
            "decision_disposition",
            "GENUINELY_AMBIGUOUS",
            "unresolved_review_evidence",
            "canonical_rpc",
            "action_rpc_invoked",
            "REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        wrapper = re.search(r"CREATE OR REPLACE FUNCTION public\.apply_pdc_email_ai_typed_action_surface_20260901_strict\(p_plan jsonb\).*?\$strict\$(.*?)END \$strict\$;", sql, re.S)
        self.assertIsNotNone(wrapper)
        body = wrapper.group(1)
        self.assertIn("pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan)", body)
        self.assertLess(body.index("decision_disposition'<>\'planned\'"), body.index("SELECT coalesce(jsonb_agg"))
        self.assertLess(body.index("record_non_dispatch_v2_20260901"), body.index("apply_pdc_email_ai_typed_action_surface_20260901(normalized)"))

    def test_review_correction_controller_has_read_only_known_and_unresolved_probes(self):
        self.assertTrue(CORRECTION_CONTROLLER.is_file())
        source = CORRECTION_CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "20260901100000",
            "20260901110000",
            "known_review_plan",
            "unresolved_review_plan",
            "pdc_email_ai_successor_validate_v2_plan_20260901",
            "strict_has_non_dispatch_guard",
            "receipt_counts_before",
            "action_rpc_invoked",
            "PDC_TYPED_ACTION_REVIEW_RECEIPTS_POST_APPLY_READBACK_FAILED",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("vjdtsswhroyguxyfjdkt", source)

    def test_field_executor_correction_routes_strict_plans_to_affected_row_readback(self):
        self.assertTrue(EXECUTION_MIGRATION.is_file())
        sql = EXECUTION_MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 5)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        for marker in (
            "20260901110000",
            "20260901120000",
            "pdc_email_ai_successor_execute_v2_20260901(p_plan)",
            "field-level affected-row executor",
            "unbound review identity",
            "duplicate VIN",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        wrapper = re.search(r"CREATE OR REPLACE FUNCTION public\.apply_pdc_email_ai_typed_action_surface_20260901_strict\(p_plan jsonb\).*?\$strict\$(.*?)END \$strict\$;", sql, re.S)
        self.assertIsNotNone(wrapper)
        body = wrapper.group(1)
        self.assertIn("pdc_email_ai_successor_execute_v2_20260901(p_plan)", body)
        self.assertNotIn("apply_pdc_email_ai_typed_action_surface_20260901(normalized)", body)

    def test_field_executor_controller_proves_route_and_identity_rejections_read_only(self):
        self.assertTrue(EXECUTION_CONTROLLER.is_file())
        source = EXECUTION_CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "20260901110000",
            "20260901120000",
            "head_route_calls_execute_v2",
            "unknown_identity_plan",
            "duplicate_vin_plan",
            "booking_set",
            "work_complete",
            "note_append",
            "receipt_counts_before",
            "action_rpc_invoked",
            "PDC_TYPED_ACTION_FIELD_EXECUTOR_IDENTITY_POST_APPLY_READBACK_FAILED",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("vjdtsswhroyguxyfjdkt", source)


if __name__ == "__main__":
    unittest.main()
