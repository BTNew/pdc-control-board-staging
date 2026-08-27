from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260827066000_508_uid514_receipt_code_compatibility.sql"


class MonitorCompatibility508ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_timestamped_append_only_successor(self):
        self.assertRegex(self.sql, r"(?is)^\s*--.*?\nBEGIN;.*LOCK TABLE supabase_migrations\.schema_migrations IN EXCLUSIVE MODE;")
        self.assertIn("VALUES('20260827066000','508_uid514_receipt_code_compatibility'", self.sql)
        self.assertRegex(self.sql, r"(?is)NOTIFY pgrst,'reload schema';\s*COMMIT;\s*$")
        body = re.split(r"(?im)^BEGIN;\s*$", self.sql, maxsplit=1)[1]
        body = re.split(r"(?im)^COMMIT;\s*$", body, maxsplit=1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;")
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())

    def test_exact_507_scope_and_legacy_response_schema(self):
        for marker in (
            "20260827065000",
            "507_uid514_staging_commissioning_terminal_receipt",
            "25751401",
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "8981540501bc629e189c39c9ea8a9adf3165d397",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
            "pdc_uid514_staging_commissioning_terminal_receipts_507",
            "uid514_receipt_terminal",
            "receipt_kind",
            "staging_commissioning",
            "receipt_source",
            "logical_507_exact_terminal_receipt",
            "synthetic_staging_commissioning",
            "physical_mailbox_fetch",
            "mailbox_flags_changed",
            "vehicle_operations",
            "operation_lines",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_reader_signature_and_dedicated_fallback_are_preserved(self):
        self.assertIn("create or replace function public.read_pdc_uid514_transaction_receipt_257(", self.lower)
        self.assertIn("pdc_314_monitor_dedicated_identity_required", self.lower)
        self.assertIn("pdc_monitor_actor_scope()", self.lower)
        self.assertIn("uid514_staging_commissioned_terminal", self.lower)
        self.assertIn("uid514_receipt_terminal", self.lower)
        self.assertIn("pdc_506_reader_compatibility_disabled", self.lower)

    def test_forced_rls_immutable_history_and_admin_rollback(self):
        for marker in (
            "pdc_uid514_receipt_code_compatibility_controls_508",
            "pdc_uid514_receipt_code_compatibility_history_508",
            "pdc_uid514_receipt_code_compatibility_history_immutable_508",
            "pdc_508_admin_authority_required",
            "admin_rollback_pdc_uid514_receipt_code_compatibility_508",
            "force row level security",
            "revoke all on public.pdc_uid514_receipt_code_compatibility_controls_508",
            "revoke all on public.pdc_uid514_receipt_code_compatibility_history_508",
            "event_kind in ('forward_code_compatibility','rollback')",
            "idempotent",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("send_email", self.lower)
        self.assertNotIn("monitored_mailboxes", self.lower)
        self.assertNotIn("pdc_monitor_stage_activation_writers set", self.lower)

    def test_predecessor_hash_owner_head_and_fail_closed_guards(self):
        for marker in (
            "20260827065000",
            "3568a203c2c03c1c6515fa3c13959c7ae66f025ad4fdc49fdfd922952065bea5",
            "postgres",
            "stable",
            "security definer",
            "55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485",
            "pdc_508_predecessor_or_collision_mismatch",
            "pdc_508_scope_mismatch",
            "not h.operational",
            "not h.production_writes",
        ):
            self.assertIn(marker.lower(), self.lower)
        for flag in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertGreaterEqual(self.lower.count(f"'{flag}',false"), 1)

    def test_source_digest_is_deterministic(self):
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
