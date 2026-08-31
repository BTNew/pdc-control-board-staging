import unittest
from pathlib import Path

from pglast import parse_sql


MIGRATION = Path(__file__).resolve().parent / 'supabase' / 'staging_only' / '20260831330000_pdc_email_ai_successor_inbox_read_projection.sql'


class SuccessorInboxMigrationTests(unittest.TestCase):
    def test_append_only_staging_read_projection_contract(self):
        sql = MIGRATION.read_text(encoding='utf-8')
        self.assertIn("20260831320000", sql)
        self.assertIn("20260831330000", sql)
        self.assertIn("get_pdc_email_ai_transaction_successor_inbox", sql)
        self.assertIn("pdc_email_ai_successor_ui_revision", sql)
        self.assertIn("ALTER TABLE public.pdc_email_ai_successor_transaction_receipts", sql)
        self.assertIn("typed_plan", sql)
        self.assertIn("p_plan,v_aggregate", sql)
        self.assertIn("FORCE ROW LEVEL SECURITY", sql)
        self.assertIn("supabase_realtime", sql)
        self.assertNotIn("raw_body", sql)
        self.assertNotIn("grant select on table public.ai_email_intake", sql.lower())
        self.assertNotRegex(sql, r"(?i)drop\\s+(table|function|policy)")
        self.assertGreaterEqual(len(parse_sql(sql)), 12)

    def test_projection_contains_parent_and_child_readback_fields(self):
        sql = MIGRATION.read_text(encoding='utf-8')
        for marker in (
            'intake_uid', 'attachment_summary', 'vehicle_results', 'retry_state',
            'typed_plan', 'action_receipts', 'readback', 'verification_status',
            'quarantine', 'source_digest', 'plan_hash', 'current_location',
        ):
            self.assertIn(marker, sql)


if __name__ == '__main__':
    unittest.main()
