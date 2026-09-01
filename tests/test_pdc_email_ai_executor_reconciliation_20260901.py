import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901220000_pdc_email_ai_successor_executor_reconciliation_20260901.sql"


class ExecutorReconciliationTests(unittest.TestCase):
    def test_append_only_reconciliation_has_staging_guards_and_immutable_history(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 8)
        self.assertNotRegex(sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        for marker in (
            "20260901210000",
            "20260901220000",
            "pdc_email_ai_successor_executor_reconciliation_history_20260901",
            "pdc_email_ai_successor_execute_v2_20260901",
            "pdc_authenticated_email_import_receipts",
            "source_uid",
            "GET STACKED DIAGNOSTICS",
            "RETURNED_SQLSTATE",
            "MESSAGE_TEXT",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)

    def test_operation_binding_uses_server_resolved_receipt_uid(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("SELECT r.source_uid INTO v_source_uid", sql)
        self.assertIn("r.source_hash=v_source_hash_key", sql)
        self.assertIn("import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid", sql)
        self.assertIn("operation_update_20260901(vehicle_id", sql)
        self.assertIn("source_uid_binding", sql)

    def test_canonical_result_and_error_are_retained_per_action(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("actual:=result", sql)
        self.assertIn("'sqlstate',v_sqlstate", sql)
        self.assertIn("'canonical_error',v_message", sql)
        self.assertIn("canonical_rpc", sql)
        self.assertIn("field_scope", sql)

    def test_operation_contract_preserves_zero_hour_and_taxonomy_fields(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("operation_add", sql)
        self.assertIn("operation_update", sql)
        self.assertIn("OP/hour/zero-hour semantics", sql)


if __name__ == "__main__":
    unittest.main()
