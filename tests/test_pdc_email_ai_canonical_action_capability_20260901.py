import unittest
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901230000_pdc_email_ai_v2_canonical_action_capability_20260901.sql"
CORRECTION = ROOT / "supabase/staging_only/20260901231000_pdc_email_ai_v2_canonical_action_guc_repair_20260901.sql"


class CanonicalActionCapabilityTests(unittest.TestCase):
    def test_append_only_staging_guard_and_immutable_history(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 10)
        self.assertNotRegex(sql, r"(?i)\\b(drop|truncate)\\s+(table|function|policy)")
        for marker in (
            "20260901220000",
            "20260901230000",
            "pdc_email_ai_v2_canonical_action_capability_20260902",
            "pdc_email_ai_v2_canonical_action_capability_history_20260901",
            "FORCE ROW LEVEL SECURITY",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)

    def test_capability_is_actor_bound_and_transaction_scoped(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "auth.role()='authenticated'",
            "auth.uid()",
            "pdc_email_ai_successor_runtime_identities",
            "pdc_monitor_stage_activation_writers",
            "role::text='administrator'",
            "set_config(",
            "true)",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)

    def test_only_canonical_paths_gain_capability_and_direct_operator_path_stays_guarded(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "update_pdc_parts_eta",
            "set_pdc_vehicle_work_states",
            "append_vehicle_timeline_event",
            "move_vehicle",
            "require_pdc_role('operator')",
            "workshop_is_planner_operator()",
            "workshop_require_planner_operator()",
            "pdc-email-ai-v2|",
            "canonical result/error evidence",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertIn("current_setting('pdc_email_ai_v2_canonical_capability_20260902',true)", sql)
        self.assertIn("pdc_authenticated_email_import_operations_with_hours(source_hash,v_source_uid", sql)

    def test_security_and_receipt_boundaries_are_preserved(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_canonical_action_capability_20260902",
            "REVOKE ALL ON public.pdc_email_ai_v2_canonical_action_capability_history_20260901",
            "CREATE TRIGGER",
            "source_hash",
            "source_uid",
            "action_rpc_invoked",
            "pdc_production_environment_sentinel",
            "NOTIFY pgrst",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)

    def test_custom_guc_uses_postgresql_dotted_namespace(self):
        self.assertTrue(CORRECTION.is_file())
        sql = CORRECTION.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(parse_sql(sql)), 8)
        self.assertIn("20260901230000", sql)
        self.assertIn("pdc.monitor.v2_canonical_action_capability_20260902", sql)
        self.assertIn("PDC_20260901231000_POSTCONDITION_FAILED", sql)
        self.assertNotIn("DROP TABLE", sql.upper())


if __name__ == "__main__":
    unittest.main()
