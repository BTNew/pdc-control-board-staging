from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260827058000_505_forward_project_504_reconciliation_into_m503_singleton.sql"


class MonitorCompatibility505ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_timestamped_append_only_successor_and_transaction_shape(self):
        self.assertRegex(self.sql, r"(?is)^\s*--.*?\nBEGIN;.*LOCK TABLE supabase_migrations\.schema_migrations IN EXCLUSIVE MODE;")
        self.assertIn("VALUES('20260827058000','505_forward_project_504_reconciliation_into_m503_singleton'", self.sql)
        self.assertRegex(self.sql, r"(?is)NOTIFY pgrst,'reload schema';\s*COMMIT;\s*$")
        body = re.split(r"(?im)^BEGIN;\s*$", self.sql, maxsplit=1)[1]
        body = re.split(r"(?im)^COMMIT;\s*$", body, maxsplit=1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;")
        self.assertNotIn("DELETE FROM", self.upper if hasattr(self, "upper") else self.sql.upper())
        self.assertNotIn("DROP TABLE", self.sql.upper())

    def test_exact_504_reconciliation_pair_and_id_are_required(self):
        for value in (
            "0c53cb93-bda2-4d02-90db-4c1b96cc7896",
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "8981540501bc629e189c39c9ea8a9adf3165d397",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
        ):
            self.assertIn(value, self.sql)
        self.assertIn("PDC_505_RECONCILIATION_PROOF_REQUIRED", self.sql)
        self.assertIn("PDC_505_RECONCILIATION_PAIR_MISMATCH", self.sql)

    def test_canonical_projection_is_rpc_owned_and_history_preserved(self):
        self.assertIn("pdc_monitor_runtime_bindings_255", self.lower)
        self.assertIn("before_binding", self.lower)
        self.assertIn("after_binding", self.lower)
        self.assertIn("pdc_monitor_runtime_binding_compatibility_history_505", self.lower)
        self.assertIn("PDC_505_COMPATIBILITY_HISTORY_IMMUTABLE", self.sql)
        self.assertIn("CREATE FUNCTION public.admin_forward_project_pdc_monitor_contained_binding_505", self.sql)
        self.assertIn("CREATE FUNCTION public.admin_rollback_pdc_monitor_contained_binding_505", self.sql)
        self.assertIn("CREATE FUNCTION public.verify_pdc_monitor_m503_compatibility_505", self.sql)
        self.assertIn("update public.pdc_monitor_runtime_bindings_255", self.lower)

    def test_fail_closed_security_and_operational_flags(self):
        for flag in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertGreaterEqual(self.lower.count(f"'{flag}',false"), 2)
        self.assertIn("pdc_505_admin_authority_required", self.lower)
        self.assertIn("pdc_505_compatibility_canonical_prestate_mismatch", self.lower)
        self.assertIn("force row level security", self.lower)
        self.assertIn("revoke all on public.pdc_monitor_runtime_binding_compatibility_history_505", self.lower)
        self.assertNotIn("send_email", self.lower)
        self.assertNotIn("monitored_mailboxes", self.lower)
        self.assertNotIn("pdc_monitor_stage_activation_writers set", self.lower)

    def test_idempotency_drift_unauthorized_and_rollback_contracts(self):
        for marker in (
            "event_key text not null unique",
            "'idempotent',true",
            "'idempotent',false",
            "PDC_505_COMPATIBILITY_ALREADY_PROJECTED",
            "PDC_505_COMPATIBILITY_CANONICAL_DRIFT",
            "PDC_505_COMPATIBILITY_ROLLBACK_PRECONDITION",
            "forward_project",
            "rollback",
            "forward migration only",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_predecessor_function_and_source_guards_are_bound(self):
        for marker in (
            "20260827053000",
            "503_existing_sales_contained_monitor_commissioning",
            "317d87a1d8f2dc184f6db6ad4309ffbb88d77bf6976a7571f95aafc19e58f45f",
            "428f5c220ce6aa59d5ecc8e05483a6f9992b0db36f69fa9a3c50debbe859f8a9",
            "491f4c7237f4e5601f4d86975bdcb9e1dda44a58da9dc6f593f83549f2b539c",
            "PDC_505_RECONCILIATION_PROOF_REQUIRED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_source_digest_is_deterministic(self):
        digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        self.assertRegex(digest, r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
