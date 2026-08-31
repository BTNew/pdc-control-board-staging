import re
import unittest
from pathlib import Path

from pglast import parse_sql


MIGRATION = Path(__file__).resolve().parents[1] / "supabase" / "staging_only" / "20260831300000_pdc_email_ai_transaction_successor.sql"
REPAIR_MIGRATION = Path(__file__).resolve().parents[1] / "supabase" / "staging_only" / "20260831320000_pdc_email_ai_transaction_successor_contract_repair.sql"


class MigrationContractTests(unittest.TestCase):
    def test_successor_migration_is_staging_only_and_append_only(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("pdc_staging_environment_sentinel", sql)
        self.assertIn("cdsmnqxtyyoeoznmbidd", sql)
        self.assertIn("pdc_production_environment_sentinel", sql)
        self.assertIn("20260831290000", sql)
        self.assertIn("20260831300000", sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        self.assertIn("apply_pdc_email_ai_transaction_successor", sql)
        self.assertGreaterEqual(len(parse_sql(sql)), 30)

    def test_runtime_has_no_direct_table_authority_and_immutable_receipts(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(sql.count("FORCE ROW LEVEL SECURITY"), 3)
        self.assertIn("REVOKE ALL ON TABLE", sql)
        self.assertIn("service_role", sql)
        self.assertIn("BEFORE UPDATE OR DELETE", sql)
        self.assertIn("PDC_EMAIL_AI_SUCCESSOR_RECEIPT_IMMUTABLE", sql)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor(jsonb) TO authenticated", sql)

    def test_dispatch_is_fixed_and_never_uses_caller_supplied_sql_rpc_or_table(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("update_pdc_parts_eta", sql)
        self.assertIn("mark_pdc_parts_complete", sql)
        self.assertIn("update_pdc_sublet_booking", sql)
        self.assertIn("canonical_location_rpc_requires_operator_or_reviewed_monitor_capability", sql)
        self.assertIn("action_key", sql)
        self.assertIn("source_reuse_conflict", sql)
        self.assertNotIn("EXECUTE p_plan", sql)
        self.assertNotIn("p_plan->>'rpc'", sql)
        self.assertNotIn("p_plan->>'sql'", sql)

    def test_sql_response_contains_expected_and_actual_parity_fields(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("'expected',", sql)
        self.assertIn("'actual',", sql)
        self.assertIn("v_expected", sql)
        self.assertIn("v_actual", sql)

    def test_sql_binds_message_thread_evidence_and_attachment_graph(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("message_id", sql)
        self.assertIn("attachment_digests", sql)
        self.assertIn("graph_thread_id", sql)
        self.assertIn("ai_email_attachments", sql)
        self.assertIn("evidence_digest", sql)

    def test_sql_preflights_each_vehicle_once_before_multi_action_apply(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("v_initial_vehicle_versions", sql)
        self.assertIn("before the first canonical call", sql)

    def test_forward_repair_is_append_only_and_parses(self):
        sql = REPAIR_MIGRATION.read_text(encoding="utf-8")
        self.assertIn("20260831300000", sql)
        self.assertIn("20260831320000", sql)
        self.assertIn("CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor", sql)
        self.assertIn("'expected',", sql)
        self.assertIn("'actual',", sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        self.assertGreaterEqual(len(parse_sql(sql)), 8)

    def test_all_terminal_dispositions_and_partial_failure_are_server_contract(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for disposition in (
            "APPLIED_AND_VERIFIED", "ALREADY_CORRECT", "SUPERSEDED", "NOT_APPLICABLE",
            "BLOCKED_EXACT_REASON", "GENUINELY_AMBIGUOUS", "FAILED_QUEUED_RETRY", "PARTIAL_FAILURE",
        ):
            self.assertIn(disposition, sql)
        self.assertRegex(sql, r"count\(\*\).*BLOCKED_EXACT_REASON|PARTIAL_FAILURE")

    def test_no_service_or_admin_runtime_identity(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("identity_purpose='pdc_email_ai_transaction_successor'", sql)
        self.assertIn("r.role::text='administrator'", sql)
        self.assertIn("auth.role()<>'authenticated'", sql)
        self.assertIn("environment='staging'", sql)


if __name__ == "__main__":
    unittest.main()
