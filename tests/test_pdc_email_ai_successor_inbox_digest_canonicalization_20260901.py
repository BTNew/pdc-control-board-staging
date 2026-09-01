import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901140000_pdc_email_ai_successor_inbox_digest_canonicalization_20260901.sql"
VERIFIER = ROOT / "scripts" / "verify_pdc_email_ai_successor_inbox_digest_canonicalization_staging.py"


class SuccessorInboxDigestCanonicalizationTests(unittest.TestCase):
    def test_migration_is_append_only_and_rebinds_the_exact_inbox(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 8)
        for marker in (
            "20260901130000",
            "20260901140000",
            "pdc_email_ai_successor_inbox_digest_canonicalization_20260901",
            "pdc_email_ai_successor_source_evidence_digest_20260901",
            "get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)",
            "source_receipt_id",
            "p_attachment_digests",
            "NOTIFY pgrst",
            "pdc_production_environment_sentinel",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|policy)")
        self.assertNotIn("GRANT SELECT ON TABLE", sql)

    def test_helper_is_source_receipt_bound_and_digest_only(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("p_source_hash", sql)
        self.assertIn("p_message_id", sql)
        self.assertIn("p_thread_id", sql)
        self.assertIn("p_attachment_digests", sql)
        self.assertIn("^[a-f0-9]{64}$", sql)
        self.assertIn("p.raw_body", sql)
        self.assertNotRegex(sql, r"(?i)\b(access_token|refresh_token|password|secret)\b")

    def test_live_verifier_proves_acl_denial_and_zero_mutation(self):
        source = VERIFIER.read_text(encoding="utf-8")
        for marker in (
            "items_with_source_digest",
            "items_with_evidence_digest",
            "authenticated_direct_table_select_denied",
            "inbox_acl_authenticated_public_anon_service_role",
            "successor_receipt_counts",
            "production_sentinel_present",
            "mailbox_contacted",
            "outbound_email",
            "business_mutation",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("cdsmnqxtyyoeoznmbidd", source)
        self.assertIn("vjdtsswhroyguxyfjdkt", source)


if __name__ == "__main__":
    unittest.main()
