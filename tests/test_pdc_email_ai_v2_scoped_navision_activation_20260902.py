from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902263000_pdc_email_ai_v2_scoped_navision_activation_20260902.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_v2_scoped_navision_activation_staging.py"


class ScopedNavisionActivationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(MIGRATION.is_file(), "scoped activation migration is required")
        self.sql = MIGRATION.read_text(encoding="utf-8")

    def test_migration_is_staging_guarded_append_only_and_hashed(self):
        self.assertGreaterEqual(len(parse_sql(self.sql)), 10)
        self.assertNotRegex(self.sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        for marker in (
            "20260902262000",
            "20260902263000",
            "cdsmnqxtyyoeoznmbidd",
            "pdc_production_environment_sentinel",
            "PDC_20260902263000_STAGING_PRECONDITION_FAILED",
            "predecessor_hash",
            "successor_hash",
            "FORCE ROW LEVEL SECURITY",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.sql)

    def test_activation_is_exact_source_authenticated_writer_and_identity_bound(self):
        for marker in (
            "pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902",
            "pdc_email_ai_successor_runtime_identities",
            "pdc_monitor_stage_activation_writers",
            "auth.role()<>'authenticated'",
            "auth.uid()",
            "source_hash",
            "source_uid",
            "pdc_monitor_exact_sender_enrollments",
            "backend_stock_ambiguous",
            "operational_identity_conflict",
            "activation_identity_conflict",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.sql)

    def test_activation_uses_existing_canonical_reconciliation_and_preserves_scope(self):
        helper = self.sql.split("CREATE FUNCTION public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902", 1)[1]
        helper = helper.split("REVOKE ALL ON FUNCTION", 1)[0]
        for forbidden in (
            "vehicle_work_items",
            "vehicle_parts_updates",
            "workshop_bookings",
            "schedule_vehicle_work",
            "complete_workshop_work",
            "pdc_email_ai_successor_execute_v2",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, helper)
        for marker in (
            "navision_board_activations",
            "trigger_reconcile_navision_operational_record",
            "navision_backend_audit",
            "audit_events",
            "activation_only",
            "work_mutated',false",
            "parts_mutated',false",
            "booking_created',false",
            "completion_created',false",
            "status_mutated',false",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, helper)

    def test_prepare_rpc_calls_activation_before_source_receipt_and_replays(self):
        for marker in (
            "pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(p_request)",
            "scoped_navision_activation_prepared",
            "scoped_navision_activation_replayed",
            "source_reuse_conflict",
            "source_hash",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.sql)
        self.assertIn("source-bound canonical Navision activation", self.sql)

    def test_authenticated_acl_and_controller_prove_first_replay_negative_readback(self):
        self.assertRegex(
            self.sql,
            r"REVOKE ALL ON FUNCTION public\.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902\(jsonb\) FROM public,anon,authenticated,service_role,pdc_email_monitor",
        )
        self.assertRegex(
            self.sql,
            r"GRANT EXECUTE ON FUNCTION public\.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902\(jsonb\) TO authenticated",
        )
        self.assertTrue(CONTROLLER.is_file(), "staging controller is required")
        controller = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260902263200",
            "PDC_SCOPED_NAVISION_ACTIVATION_NON_STAGING_TARGET",
            "first_activation",
            "replay_activation",
            "negative_identity",
            "negative_authentication",
            "authoritative_readback",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, controller)


if __name__ == "__main__":
    unittest.main()
