import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901130000_pdc_email_ai_successor_inbox_digest_projection_20260901.sql"
CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_successor_inbox_digest_projection_staging.py"


class SuccessorInboxDigestProjectionTests(unittest.TestCase):
    def test_append_only_migration_projects_canonical_source_receipt_digests(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 6)
        for marker in (
            "20260901120000",
            "20260901130000",
            "pdc_email_ai_typed_action_field_executor_identity_20260901",
            "get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)",
            "source_digest",
            "evidence_digest",
            "p.source_hash",
            "p.extracted_data->>'pdc_email_ai_evidence_digest'",
            "source_receipt_id",
            "REVOKE ALL ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)",
            "GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)",
            "pdc_production_environment_sentinel",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        self.assertEqual(sql.count("'source_digest',CASE\n"), 1)
        self.assertEqual(sql.count("'evidence_digest',CASE\n"), 1)

    def test_projection_is_digest_only_and_keeps_direct_table_access_closed(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("^[a-f0-9]{64}$", sql)
        self.assertIn("successor-inbox-digest-projection", sql)
        self.assertIn("direct table access remains denied", sql.lower())
        self.assertNotRegex(sql, r"(?i)raw[_-]?body|parsed[_-]?text|storage[_-]?path|access[_-]?token|password|secret")

    def test_controller_is_hash_bound_and_proves_runtime_denial(self):
        self.assertTrue(CONTROLLER.is_file())
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "20260901120000",
            "20260901130000",
            "PDC_APPROVE_STAGING_MIGRATION_20260901130000",
            "source_digest_present",
            "evidence_digest_present",
            "projection_readback",
            "direct_table_select_denied",
            "has_function_privilege",
            "production_sentinel_present",
            "mailbox_contacted",
            "outbound_email",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("cdsmnqxtyyoeoznmbidd", source)
        self.assertIn("vjdtsswhroyguxyfjdkt", source)


if __name__ == "__main__":
    unittest.main()
