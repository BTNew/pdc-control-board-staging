from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260827065000_507_uid514_staging_commissioning_terminal_receipt.sql"


class MonitorCompatibility507ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_timestamped_append_only_transaction(self):
        self.assertRegex(self.sql, r"(?is)^\s*--.*?\nBEGIN;.*LOCK TABLE supabase_migrations\.schema_migrations IN EXCLUSIVE MODE;")
        self.assertIn("VALUES('20260827065000','507_uid514_staging_commissioning_terminal_receipt'", self.sql)
        self.assertRegex(self.sql, r"(?is)NOTIFY pgrst,'reload schema';\s*COMMIT;\s*$")
        body = re.split(r"(?im)^BEGIN;\s*$", self.sql, maxsplit=1)[1]
        body = re.split(r"(?im)^COMMIT;\s*$", body, maxsplit=1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;")
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())

    def test_exact_reviewed_scope_and_no_physical_work(self):
        for marker in (
            "25751401",
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "8981540501bc629e189c39c9ea8a9adf3165d397",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
            "synthetic_staging_commissioning",
            "physical_mailbox_fetch",
            "mailbox_flags_changed",
            "vehicle_operations",
            "operation_lines",
            "mailbox_folder",
            "inbox",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("pdc_monitor_runtime_binding_compatibility_history_505", self.lower)

    def test_frozen_reader_signature_is_replaced_narrowly(self):
        self.assertIn("create or replace function public.read_pdc_uid514_transaction_receipt_257(", self.lower)
        self.assertIn("pdc_uid514_staging_commissioning_terminal_receipts_507", self.lower)
        self.assertIn("uid514_staging_commissioned_terminal", self.lower)
        self.assertIn("pdc_506_reconciliation_or_binding_drift", self.lower)
        self.assertIn("pdc_monitor_actor_scope()", self.lower)
        self.assertIn("PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED".lower(), self.lower)

    def test_immutable_rls_and_admin_only_rollback(self):
        for marker in (
            "pdc_uid514_staging_commissioning_history_507",
            "pdc_uid514_staging_commissioning_controls_507",
            "PDC_507_COMMISSIONING_HISTORY_IMMUTABLE",
            "PDC_507_ADMIN_AUTHORITY_REQUIRED",
            "admin_rollback_pdc_uid514_staging_commissioning_507",
            "force row level security",
            "revoke all on public.pdc_uid514_staging_commissioning_history_507",
            "revoke all on public.pdc_uid514_staging_commissioning_controls_507",
            "'rollback'",
            "idempotent",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("send_email", self.lower)
        self.assertNotIn("monitored_mailboxes", self.lower)
        self.assertNotIn("pdc_monitor_stage_activation_writers set", self.lower)

    def test_fail_closed_operational_flags_and_predecessor_guards(self):
        for flag in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertGreaterEqual(self.lower.count(f"'{flag}',false"), 1)
        for marker in (
            "20260827064000",
            "506_allow_contained_sales_uid514_receipt_read",
            "fb326a1b0f01bc66fcee0228d138c14c74fd29ba16d2d46c79f50b09e8fbb366",
            "55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485",
            "PDC_507_PREDECESSOR_OR_COLLISION_MISMATCH",
            "PDC_507_TERMINAL_RECEIPT_SCOPE_MISMATCH",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_source_digest_is_deterministic(self):
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
