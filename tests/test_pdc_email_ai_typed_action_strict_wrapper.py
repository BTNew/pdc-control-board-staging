import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901100000_pdc_email_ai_typed_action_strict_wrapper_20260901.sql"
CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_typed_action_strict_wrapper_staging.py"


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


if __name__ == "__main__":
    unittest.main()
