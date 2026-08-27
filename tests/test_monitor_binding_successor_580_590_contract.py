from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = {
    "504": ROOT / "supabase/staging_only/20260827054000_504_forward_reconcile_contained_email_runtime.sql",
    "505_guard": ROOT / "supabase/staging_only/20260827055000_505_repair_contained_email_runtime_reconcile_guard.sql",
    "506": ROOT / "supabase/staging_only/20260827056000_506_repair_contained_email_runtime_reconcile_head.sql",
    "507": ROOT / "supabase/staging_only/20260827057000_507_stabilize_contained_email_runtime_reconcile_lineage.sql",
    "580": ROOT / "supabase/staging_only/20260827058000_505_forward_project_504_reconciliation_into_m503_singleton.sql",
    "590": ROOT / "supabase/staging_only/20260827059000_505_repair_contained_email_runtime_rollback_path.sql",
    "600": ROOT / "supabase/staging_only/20260827060000_600_repair_contained_email_runtime_reconcile_replay_after_projection.sql",
    "610": ROOT / "supabase/staging_only/20260827061000_610_repair_contained_email_runtime_reconcile_replay_head.sql",
    "630": ROOT / "supabase/staging_only/20260827063000_630_repair_contained_email_runtime_reconcile_forward_head_floor.sql",
}
PAIR = (
    "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
    "pdc-monitor-staging-sales-uid509-v1",
    "pdc-monitor-staging-m502-2026.08.44",
    "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
    "8981540501bc629e189c39c9ea8a9adf3165d397",
    "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
    "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
)


def body(sql: str) -> str:
    starts = re.findall(r"(?im)^\s*BEGIN;\s*$", sql)
    commits = re.findall(r"(?im)^\s*COMMIT;\s*$", sql)
    if len(starts) != 1 or len(commits) != 1:
        raise AssertionError("migration must have exactly one outer transaction")
    return sql.split("BEGIN;", 1)[1].rsplit("COMMIT;", 1)[0]


class ContainedEmailForwardSuccessorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = {name: path.read_text(encoding="utf-8") for name, path in MIGRATIONS.items()}
        cls.lower = {name: text.lower() for name, text in cls.sql.items()}

    def test_all_successors_are_single_append_only_transactions(self):
        for name, sql in self.sql.items():
            with self.subTest(migration=name):
                self.assertEqual(sql.count("BEGIN;"), 1)
                self.assertEqual(sql.count("COMMIT;"), 1)
                self.assertNotRegex(body(sql), r"(?im)^\s*(?:BEGIN|COMMIT|ROLLBACK)\s*;")
                self.assertNotIn("DROP TABLE", sql.upper())
                self.assertNotIn("DELETE FROM", sql.upper())
                self.assertIn("LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE", sql)
                self.assertIn("pdc_staging_environment_sentinel", self.lower[name])
                self.assertIn("pdc_production_environment_sentinel", self.lower[name])

    def test_exact_reviewed_44_pair_is_present_in_both_forward_and_repair_paths(self):
        for name in ("504", "580", "590", "600"):
            with self.subTest(migration=name):
                for value in PAIR:
                    self.assertIn(value, self.sql[name])
                self.assertIn("operational", self.lower[name])
                self.assertIn("activation_ready", self.lower[name])
                self.assertIn("writer_active", self.lower[name])
                self.assertIn("planner_commissioned", self.lower[name])
                self.assertIn("production_writes", self.lower[name])
                self.assertIn("pdc-monitor-staging-m502-2026.08.44", self.sql[name])

    def test_580_projects_only_through_admin_rpc_and_preserves_old_snapshot(self):
        sql = self.lower["580"]
        for marker in (
            "20260827053000",
            "20260827054000",
            "20260827055000",
            "20260827056000",
            "20260827057000",
            "0c53cb93-bda2-4d02-90db-4c1b96cc7896",
            "admin_forward_project_pdc_monitor_contained_binding_505",
            "before_binding",
            "after_binding",
            "pdc_monitor_runtime_binding_compatibility_history_505",
            "force row level security",
            "pdc_505_compatibility_history_immutable",
            "forward migration only; exact old singleton snapshot retained",
        ):
            self.assertIn(marker.lower(), sql)
        self.assertIn("update public.pdc_monitor_runtime_bindings_255", sql)
        self.assertIn("insert into public.audit_events", sql)
        self.assertNotRegex(sql, r"insert\s+into\s+public\.(monitored_mailboxes|pdc_email_monitor_pilot|pdc_monitor_stage_activation_writers)")
        self.assertNotIn("send_email", sql)

    def test_590_repairs_only_guarded_rollback_control_flow(self):
        sql = self.lower["590"]
        for marker in (
            "20260827058000",
            "505_forward_project_504_reconciliation_into_m503_singleton",
            "pdc_505_rollback_repair_predecessor_or_collision_mismatch",
            "pdc_505_rollback_repair_postcondition_failed",
            "pdc_505_compatibility_rollback_proof_required",
            "pdc_505_compatibility_rollback_precondition",
            "pdc_505_compatibility_rollback_canonical_drift",
            "insert into public.audit_events",
            "values('20260827059000','505_repair_contained_email_runtime_rollback_path'",
        ):
            self.assertIn(marker.lower(), sql)
        self.assertNotIn("pdc_monitor_contained_binding_reconciliations_504", sql.replace("select *", ""))
        self.assertNotIn("send_email", sql)

    def test_600_repairs_replay_without_reinvoking_503_provision(self):
        sql = self.lower["600"]
        for marker in (
            "20260827059000",
            "600_repair_contained_email_runtime_reconcile_replay_after_projection",
            "pdc_600_reconcile_replay_predecessor_or_collision_mismatch",
            "pdc_600_canonical_binding_mismatch",
            "pdc_600_compatibility_projection_proof_required",
            "pdc_600_reconciliation_history_missing",
            "pdc_monitor_runtime_binding_compatibility_history_505",
            "'idempotent',true",
            "pdc_600_reconcile_replay_postcondition_failed",
        ):
            self.assertIn(marker.lower(), sql)
        self.assertNotIn("provision_pdc_monitor_contained_binding_503", sql)
        self.assertIn("pdc_monitor_contained_binding_reconciliations_504", sql)
        self.assertNotIn("send_email", sql)

    def test_610_repairs_600_post_apply_head_without_rewriting_history(self):
        sql = self.lower["610"]
        for marker in (
            "20260827060000",
            "610_repair_contained_email_runtime_reconcile_replay_head",
            "pdc_610_reconcile_replay_head_predecessor_or_collision_mismatch",
            "pdc_610_reconcile_replay_source_drift",
            "pdc_610_reconcile_replay_head_postcondition_failed",
            "pg_get_functiondef",
            "has_function_privilege",
            "reconcile_pdc_monitor_contained_binding_504",
        ):
            self.assertIn(marker.lower(), sql)
        self.assertNotIn("provision_pdc_monitor_contained_binding_503", sql)
        self.assertNotIn("send_email", sql)

    def test_forward_repairs_keep_least_privilege_and_fail_closed_flags(self):
        for name in ("580", "590", "600"):
            sql = self.lower[name]
            self.assertIn("revoke all on function", sql)
            self.assertIn("grant execute on function", sql)
            self.assertIn("to authenticated", sql)
            self.assertNotIn(" to anon", sql)
            self.assertNotIn(" to service_role", sql)
            self.assertNotIn(" to public", sql)
            for flag in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
                self.assertRegex(sql, rf"{flag}['\"]?\s*,\s*false")

    def test_630_removes_the_self_head_loop_without_rewriting_history(self):
        sql = self.lower["630"]
        for marker in (
            "20260827061000",
            "630_repair_contained_email_runtime_reconcile_forward_head_floor",
            "pdc_630_reconcile_forward_head_floor_predecessor_or_collision_mismatch",
            "pdc_630_reconcile_forward_source_drift",
            "pdc_630_reconcile_forward_head_floor_postcondition_failed",
            "pg_get_functiondef",
            "reconcile_pdc_monitor_contained_binding_504",
            "installed-lineage floor",
        ):
            self.assertIn(marker.lower(), sql)
        self.assertNotIn("provision_pdc_monitor_contained_binding_503", sql)
        self.assertNotIn("send_email", sql)

    def test_migration_580_source_is_deterministically_hashable(self):
        digest = hashlib.sha256(MIGRATIONS["580"].read_bytes()).hexdigest()
        self.assertRegex(digest, r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
