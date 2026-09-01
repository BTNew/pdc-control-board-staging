import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260901170000_pdc_email_ai_successor_receipt_fk_ordering_repair_20260901.sql"
CONTROLLER = ROOT / "scripts" / "apply_pdc_email_ai_successor_receipt_fk_ordering_repair_staging.py"
VERIFIER = ROOT / "scripts" / "verify_pdc_email_ai_successor_receipt_fk_ordering_staging.py"
SOURCE_BINDING_MIGRATION = ROOT / "supabase" / "staging_only" / "20260901200000_pdc_email_ai_successor_canonical_source_binding_20260901.sql"
PROJECTION_CORRECTION_MIGRATION = ROOT / "supabase" / "staging_only" / "20260901210000_pdc_email_ai_successor_source_binding_projection_correction_20260901.sql"


class ReceiptFkOrderingRepairTests(unittest.TestCase):
    def test_append_only_staging_migration_defers_receipt_fk(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 7)
        self.assertNotRegex(sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        for marker in (
            "20260901160000",
            "20260901170000",
            "pdc_email_ai_successor_action_receipts",
            "DEFERRABLE INITIALLY DEFERRED",
            "pdc_email_ai_successor_receipt_fk_ordering_repair_20260901",
            "205f0c13-ef4b-4ac0-8128-3563a4d8d61a",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)

    def test_repair_changes_only_the_transaction_receipt_fk(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("ALTER TABLE public.pdc_email_ai_successor_action_receipts", sql)
        self.assertIn("DROP CONSTRAINT", sql)
        self.assertIn("ADD CONSTRAINT pdc_email_ai_successor_action_receipts_transaction_id_fkey", sql)
        self.assertIn("FOREIGN KEY(transaction_id)", sql)
        self.assertIn("REFERENCES public.pdc_email_ai_successor_transaction_receipts(transaction_id)", sql)
        self.assertEqual(len(re.findall(r"(?i)\bALTER\s+TABLE\b", sql)), 2)
        self.assertNotIn("CREATE OR REPLACE FUNCTION", sql)

    def test_mixed_source_binding_uses_canonical_projection_digest(self):
        self.assertTrue(SOURCE_BINDING_MIGRATION.is_file())
        sql = SOURCE_BINDING_MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 8)
        self.assertNotRegex(sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        for marker in (
            "20260901190000",
            "20260901200000",
            "pdc_email_ai_successor_record_non_dispatch_v2_20260901",
            "pdc_email_ai_successor_source_evidence_digest_20260901",
            "pdc_email_ai_successor_source_binding_history_20260901",
            "PDC_20260901200000_SOURCE_BINDING_ANCHOR_FAILED",
            "production_writes",
            "mailbox_contacted",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertIn("i.duplicate_of IS NULL", sql)
        self.assertIn("i.graph_thread_id", sql)
        self.assertIn("i.raw_body", sql)
        self.assertIn("i.attachment_summary->'digests'", sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_execute_v2_20260901", sql)

    def test_controller_and_verifier_are_protected_staging_only(self):
        for path in (CONTROLLER, VERIFIER):
            self.assertTrue(path.is_file())
            source = path.read_text(encoding="utf-8")
            for marker in (
                "cdsmnqxtyyoeoznmbidd",
                "vjdtsswhroyguxyfjdkt",
                "20260901160000",
                "20260901170000",
                "205f0c13-ef4b-4ac0-8128-3563a4d8d61a",
                "action_rpc_invoked",
                "production",
                "outbound_email",
            ):
                with self.subTest(path=path.name, marker=marker):
                    self.assertIn(marker, source)
            self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
            self.assertNotIn("pdc-monitor-staging-runtime", source)

        verifier = VERIFIER.read_text(encoding="utf-8")
        for marker in (
            "mixed_planned_review",
            "invalid_digest",
            "production_target",
            "replay",
            "foreign_key",
            "direct_table",
            "force_rls",
        ):
            self.assertIn(marker, verifier)

    def test_projection_correction_uses_protected_attachment_projection(self):
        self.assertTrue(PROJECTION_CORRECTION_MIGRATION.is_file())
        sql = PROJECTION_CORRECTION_MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 8)
        self.assertNotRegex(sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        for marker in (
            "20260901200000",
            "20260901210000",
            "pdc_email_ai_successor_source_binding_projection_history_20260901",
            "pdc_email_ai_successor_source_evidence_digest_20260901",
            "public.ai_email_attachments",
            "jsonb_agg(lower(a.source_hash)",
            "PDC_20260901210000_SOURCE_BINDING_PROJECTION_ANCHOR_FAILED",
            "production_writes",
            "mailbox_contacted",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertIn("i.attachment_summary", sql)


if __name__ == "__main__":
    unittest.main()
