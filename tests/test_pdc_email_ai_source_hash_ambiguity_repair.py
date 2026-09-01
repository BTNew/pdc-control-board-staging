import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901160000_pdc_email_ai_typed_action_source_hash_ambiguity_repair_20260901.sql"
CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_typed_action_source_hash_ambiguity_repair_staging.py"
VERIFIER = ROOT / "scripts" / "verify_pdc_email_ai_typed_action_source_hash_ambiguity_staging.py"


class SourceHashAmbiguityRepairTests(unittest.TestCase):
    def test_append_only_migration_qualifies_source_binding_variables(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 7)
        self.assertNotRegex(sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        for marker in (
            "20260901140000",
            "20260901160000",
            "pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901",
            "pdc_email_ai_successor_execute_v2_20260901(jsonb)",
            "pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)",
            "apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)",
            "lower(coalesce(i.source_hash,''))=v_source_hash_key",
            "source_hash_ambiguity_repair",
            "production_writes",
            "mailbox_contacted",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)

    def test_each_repaired_function_keeps_the_exact_source_hash_binding(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for function in (
            "pdc_email_ai_successor_execute_v2_20260901",
            "pdc_email_ai_successor_record_non_dispatch_v2_20260901",
            "apply_pdc_email_ai_operation_update_transaction_20260901",
        ):
            self.assertIn(f"pg_get_functiondef('public.{function}", sql)
        self.assertEqual(sql.count("old_pred:=$old$lower(coalesce(i.source_hash,''))=source_hash$old$;"), 1)
        self.assertEqual(sql.count("new_pred:=$new$lower(coalesce(i.source_hash,''))=v_source_hash_key$new$;"), 1)
        self.assertIn("d:=replace(replace(d,old_decl,new_decl),old_pred,new_pred);", sql)
        self.assertIn("predecessor_function_sha256", sql)
        self.assertIn("successor_function_sha256", sql)

    def test_controller_and_live_verifier_are_staging_only_and_cover_receipt_path(self):
        for path in (CONTROLLER, VERIFIER):
            self.assertTrue(path.is_file())
            source = path.read_text(encoding="utf-8")
            for marker in (
                "cdsmnqxtyyoeoznmbidd",
                "vjdtsswhroyguxyfjdkt",
                "20260901160000",
                "receipt_counts_before",
                "action_rpc_invoked",
            ):
                with self.subTest(path=path.name, marker=marker):
                    self.assertIn(marker, source)
            self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)

        self.assertIn("production_sentinel_present", CONTROLLER.read_text(encoding="utf-8"))

        verifier = VERIFIER.read_text(encoding="utf-8")
        self.assertIn("pdc_email_ai_successor_execute_v2_20260901", verifier)
        self.assertIn("valid_plan_response", verifier)
        self.assertIn("hostile_plan_response", verifier)
        self.assertIn("typed_v2_plan_invalid", verifier)
        self.assertIn("pdc_email_ai_typed_action_surface_partial_failure", verifier)


if __name__ == "__main__":
    unittest.main()
