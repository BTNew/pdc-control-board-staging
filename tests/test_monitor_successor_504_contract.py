from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260827054000_504_forward_reconcile_contained_email_runtime.sql"


class MonitorSuccessor504ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_reviewed_inputs_are_bound_including_source_tree_hash(self):
        for value in (
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "8981540501bc629e189c39c9ea8a9adf3165d397",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
        ):
            self.assertIn(value, self.sql)
        self.assertIn("source_tree_sha", self.sql)

    def test_transaction_and_timestamped_successor_ledger(self):
        self.assertRegex(self.sql, r"(?is)^\s*--.*?\nBEGIN;.*LOCK TABLE supabase_migrations\.schema_migrations IN EXCLUSIVE MODE;")
        self.assertRegex(self.sql, r"(?is)INSERT INTO supabase_migrations\.schema_migrations\s*\(version,name,statements\)\s*VALUES\('20260827054000',")
        self.assertRegex(self.sql, r"(?is)NOTIFY pgrst,'reload schema';\s*COMMIT;\s*$")
        body = re.split(r"(?im)^BEGIN;\s*$", self.sql, maxsplit=1)[1]
        body = re.split(r"(?im)^COMMIT;\s*$", body, maxsplit=1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;")

    def test_predecessor_head_sentinel_and_function_markers_are_guarded(self):
        for marker in (
            "PDC_504_EXACT_LEDGER_HEAD_REQUIRED",
            "PDC_504_PREDECESSOR_FUNCTION_MARKER_MISMATCH",
            "PDC_504_STAGING_PREDECESSOR_OR_COLLISION_MISMATCH",
            "pdc_staging_environment_sentinel",
            "pdc_production_environment_sentinel",
            "PDC_503_ALREADY_TRANSITIONED_INPUT_DRIFT",
            "runtime_binding_mismatch",
            "predecessor_ledger_sha256",
            "predecessor_provision_function_sha256",
            "predecessor_verify_function_sha256",
            "predecessor_markers",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_fail_closed_flags_and_containment_are_structural(self):
        for field in (
            "operational",
            "activation_ready",
            "writer_active",
            "planner_commissioned",
            "production_writes",
        ):
            self.assertGreaterEqual(self.lower.count(f"check(not {field})"), 1)
        self.assertIn("pdc_504_containment_required", self.lower)
        self.assertIn("transaction rollback only; predecessor 503 remains unchanged", self.lower)
        self.assertNotRegex(self.lower, r"\b(create|start|enable)\s+(?:a\s+)?(?:monitor|planner|scheduler)")
        self.assertNotIn("send_email", self.lower)
        self.assertNotIn("pg_sleep", self.lower)

    def test_one_time_idempotency_and_mutation_rejection_contract(self):
        self.assertIn("event_key text not null unique", self.lower)
        self.assertIn("singleton boolean not null default true unique", self.lower)
        self.assertIn("if found then", self.lower)
        self.assertIn("'idempotent',true", self.lower)
        self.assertIn("'idempotent',false", self.lower)
        self.assertIn("pdc_504_reviewed_pair_mismatch", self.lower)
        self.assertIn("pdc_504_predecessor_drift_on_replay", self.lower)
        self.assertIn("pdc_504_reconciliation_history_immutable", self.lower)

    def test_only_authenticated_rpc_execution_and_private_table(self):
        self.assertIn("force row level security", self.lower)
        self.assertIn("revoke all on public.pdc_monitor_contained_binding_reconciliations_504 from public,anon,authenticated,service_role", self.lower)
        self.assertEqual(self.lower.count("grant execute on function public.reconcile_pdc_monitor_contained_binding_504"), 1)
        self.assertEqual(self.lower.count("grant execute on function public.verify_pdc_monitor_contained_binding_504"), 1)
        self.assertEqual(self.lower.count("grant execute on function public.get_pdc_monitor_contained_binding_504"), 1)
        self.assertNotIn("grant select", self.lower)

    def test_migration_source_digest_is_deterministic_for_release_evidence(self):
        digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        self.assertEqual(
            digest,
            "ac0b3fcd09d467fceb38d37c07fe1263cdfa1327926b1e413cd976c25409ae7f",
        )

    def test_controller_is_staging_only_and_requires_transactional_apply(self):
        controller = (ROOT / "scripts" / "manage_migration_504_staging.py").read_text(encoding="utf-8")
        self.assertIn('EXPECTED_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"', controller)
        self.assertIn('PRODUCTION_PROJECT_REF = "vjdtsswhroyguxyfjdkt"', controller)
        self.assertIn('choices=("rehearse-504", "apply-504")', controller)
        self.assertIn("conn.rollback()", controller)
        self.assertIn("APPLY_APPROVAL_MISSING", controller)
        self.assertNotIn("PDC_STAGING_SERVICE_ROLE_KEY", controller)


if __name__ == "__main__":
    unittest.main(verbosity=2)
