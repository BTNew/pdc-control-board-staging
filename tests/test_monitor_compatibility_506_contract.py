from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260827064000_506_allow_contained_sales_uid514_receipt_read.sql"


class MonitorCompatibility506ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_timestamped_successor_transaction_and_ledger(self):
        self.assertRegex(self.sql, r"(?is)^\s*--.*?\nBEGIN;.*LOCK TABLE supabase_migrations\.schema_migrations IN EXCLUSIVE MODE;")
        self.assertIn("VALUES('20260827064000','506_allow_contained_sales_uid514_receipt_read'", self.sql)
        self.assertRegex(self.sql, r"(?is)NOTIFY pgrst,'reload schema';\s*COMMIT;\s*$")
        body = re.split(r"(?im)^BEGIN;\s*$", self.sql, maxsplit=1)[1]
        body = re.split(r"(?im)^COMMIT;\s*$", body, maxsplit=1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;")
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())

    def test_frozen_signature_and_exact_scope_are_preserved(self):
        for marker in (
            "read_pdc_uid514_transaction_receipt_257(integer)",
            "PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED",
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "pmbcontroller@gmail.com",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "8981540501bc629e189c39c9ea8a9adf3165d397",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
            "25751401",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("pdc_monitor_runtime_binding_compatibility_history_505", self.lower)
        self.assertIn("0c53cb93-bda2-4d02-90db-4c1b96cc7896", self.sql)

    def test_reader_compatibility_is_narrow_and_preserves_generic_scope(self):
        for marker in (
            "pdc_monitor_uid514_reader_compatibility_controls_506",
            "pdc_monitor_uid514_reader_compatibility_history_506",
            "pdc_monitor_actor_scope()",
            "PDC_506_CONTAINED_SALES_READER_SCOPE",
            "PDC_506_RECONCILIATION_OR_BINDING_DRIFT",
            "PDC_506_READER_COMPATIBILITY_DISABLED",
            "PDC_506_COMPATIBILITY_HISTORY_IMMUTABLE",
            "PDC_506_ADMIN_AUTHORITY_REQUIRED",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("create or replace function public.read_pdc_uid514_transaction_receipt_257", self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("send_email", self.lower)
        self.assertNotIn("monitored_mailboxes", self.lower)
        self.assertNotIn("pdc_monitor_stage_activation_writers set", self.lower)

    def test_least_privilege_flags_and_rollback(self):
        for flag in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertGreaterEqual(self.lower.count(f"'{flag}',false"), 1)
        self.assertIn("force row level security", self.lower)
        self.assertIn("revoke all on public.pdc_monitor_uid514_reader_compatibility_history_506", self.lower)
        self.assertIn("revoke all on public.pdc_monitor_uid514_reader_compatibility_controls_506", self.lower)
        self.assertIn("admin_rollback_pdc_uid514_reader_compatibility_506", self.lower)
        self.assertIn("'rollback'", self.lower)
        self.assertIn("forward migration only", self.lower)

    def test_predecessor_source_owner_and_grant_guards(self):
        for marker in (
            "35fa1d94ac0bba312b7d3ac1523ca581f54b155a3e79df6bc1694d98db2788f9",
            "55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485",
            "postgres",
            "security definer",
            "stable",
            "20260827063000",
            "630_repair_contained_email_runtime_reconcile_forward_head_floor",
            "PDC_506_PREDECESSOR_OR_COLLISION_MISMATCH",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_source_digest_is_deterministic(self):
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
