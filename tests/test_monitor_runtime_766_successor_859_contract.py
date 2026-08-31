from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "staging_only"
TARGET = "verify_pdc_monitor_runtime_binding_authenticated_766"


class MonitorRuntime766Successor859ContractTests(unittest.TestCase):
    def setUp(self):
        self.sql = (MIGRATIONS / "20260831250000_859_runtime_766_compatibility_and_attachment_path_successor.sql").read_text(encoding="utf-8")

    def test_is_append_only_after_858_and_preserves_legacy_projection(self):
        for marker in (
            "20260831240000",
            "858_runtime_authority_839_scope_compatibility_successor",
            "20260831250000",
            "859_runtime_766_compatibility_and_attachment_path_successor",
            "pdc_monitor_authenticated_active_scope_839()",
            "migration_head',766",
            "compatibility_successor_head',766",
            "current_staging_migration_head",
            "current_head_compatibility_successor',859",
            "active_mailbox_count"):
            self.assertIn(marker, self.sql)
        self.assertNotIn("pdc_monitor_authenticated_active_scope_672", self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.pdc_monitor_authenticated_active_scope_839", self.sql)

    def test_exact_safety_tuple_and_attachment_quarantine_are_present(self):
        for marker in (
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348",
            "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
            "c.jwt_role<>'authenticated'",
            "c.server_application_role<>'importer'",
            "c.task_enabled",
            "c.mailbox_contacted",
            "c.uid514_processed",
            "c.production_writes",
            "path_quarantined",
            "board_mutated',false",
            "mailbox_flags_changed',false",
            "pdc-email-intake-private/[a-f0-9]{64}/[^/]+"):
            self.assertIn(marker, self.sql)

    def test_no_later_active_successor_overwrites_766_projection(self):
        later = []
        for path in MIGRATIONS.glob("*.sql"):
            if path.name > "20260831250000_859_runtime_766_compatibility_and_attachment_path_successor.sql":
                text = path.read_text(encoding="utf-8")
                if TARGET in text and re.search(r"CREATE\s+OR\s+REPLACE\s+FUNCTION[^$]*" + TARGET, text, re.I):
                    later.append(path.name)
        self.assertEqual(later, [], f"later successor overwrites protected projection: {later}")

    def test_protected_672_source_is_not_modified_by_successor(self):
        protected = next(MIGRATIONS.glob("*672_authenticated_active_email_monitor_identity_successor.sql"), None)
        self.assertIsNotNone(protected)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.pdc_monitor_authenticated_active_scope_672", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
