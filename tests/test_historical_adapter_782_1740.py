import unittest
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "supabase/staging_only/20260830173000_782_historical_reconciliation_current_head_security_successor.sql"
WRAPPER = ROOT / "supabase/staging_only/20260830174000_782_historical_reconciliation_atomic_wrapper_successor.sql"
CALLER = ROOT / "pdc_historical_778_caller.py"
LEGACY_CALLER = ROOT / "pdc_full_inbox_typed_import.py"


class HistoricalAdapter7821740Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = BASE.read_text(encoding="utf-8").lower()
        cls.wrapper = WRAPPER.read_text(encoding="utf-8").lower()
        cls.caller = CALLER.read_text(encoding="utf-8").lower()
        cls.legacy_caller = LEGACY_CALLER.read_text(encoding="utf-8").lower()

    def test_successor_is_append_only_and_parses(self):
        self.assertEqual(len(parse_sql(WRAPPER.read_text(encoding="utf-8"))), 16)
        for marker in (
            "lock table supabase_migrations.schema_migrations in exclusive mode",
            "20260830173000",
            "782_historical_reconciliation_current_head_security_successor",
            "statements=array[",
            "exists(select 1 from supabase_migrations.schema_migrations where version='20260830174000')",
            "alter function public.submit_pdc_historical_reconciliation_778(jsonb) rename to submit_pdc_historical_reconciliation_782_base",
        ):
            self.assertIn(marker, self.wrapper)

    def test_dependency_and_trigger_contract_is_exactly_pinned(self):
        for marker in (
            "6d091224653234e662601e494bcc7af4aa1f65e659b3798c39b2bcafd1990bbf",
            "6497f2ba7ad244ea414f26d80400a3fa4bff2bf090746fdaa4cad800cbe53cfb",
            "f4f6f14d094afc04c110c72ca6d6d2c642bf6bf2fa8a96f59d3115793a6accd8",
            "f73dd525e5dc6caccde4d5658bea8a2cabd95ec7f55898b792e5984568de5950",
            "9bd5a567213e77dd4fb3ff45fa7031443444707505e576a3c17ace1c7c6699dd",
            "f6a954d162f3b9d7ae53a6fa073f4195b6a1067f51fc8ba7346217a95f518bb8",
            "ff68e5580c8a77701eb5f92ef6a0b6ad99a44f0036185e60900a4292775870f1",
            "aclexplode",
            "pdc_782_1740_dependency_contract_drift",
            "pdc_782_1740_callee_contract_drift",
            "pdc_782_1740_trigger_contract_drift",
            "59f828545fd10c6928ccf38d0e8d8d1e25841fd9af75d591ee96f4219ea82fac",
        ):
            self.assertIn(marker, self.wrapper)

    def test_wrapper_replays_before_expiry_and_derives_flags(self):
        for marker in (
            "verify_pdc_monitor_runtime_binding_authenticated_766",
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "historical_reconciliation_782_base",
            "historical_replay_conflict",
            "pdc_782_1740_protected_boundary_drift",
            "pdc_782_1740_flag_readback_failed",
            "pdc_782_1740_authoritative_state_missing",
            "pdc_782_1740_authoritative_vehicle_failed",
            "pdc_782_1740_authoritative_protected_state_failed",
            "pdc_782_1740_child_receipt_readback_failed",
            "pdc_782_1740_authoritative_work_failed",
            "vehicle_movements",
            "vehicle_aliases",
            "select count(*) into v_booking_count",
            "select count(*) into v_completion_count",
            "select count(*) into v_parts_count",
            "pdc_historical_782_boundary_snapshot",
            "booking_created",
            "completion_created",
            "location_scheduled",
            "parts_changed",
        ):
            self.assertIn(marker, self.wrapper)
        self.assertNotIn("booking_created',false", self.wrapper)
        self.assertNotIn("completion_created',false", self.wrapper)
        self.assertNotIn("location_scheduled',false", self.wrapper)
        self.assertIn("authorized_at+interval '24 hours'", self.base)

    def test_base_contains_exact_attachment_and_atomic_guards(self):
        for marker in (
            "pdc_historical_job_card_attachments_782",
            "attachment_kind",
            "attachment_ordinal",
            "pdc_782_job_card_kind_mismatch",
            "pdc_782_child_occurrence_mismatch",
            "pdc_782_extraction_hash_failed",
            "pdc_782_child_attachment_nonunique",
            "pdc_782_parent_observation_failed",
            "pdc_782_child_import_failed",
            "pdc_782_protected_boundary_drift",
            "pdc_782_unrelated_state_drift",
            "pdc_782_old_mail_completed",
            "historical_authorization_expired",
            "historical_replay_conflict",
        ):
            self.assertIn(marker, self.base)
        self.assertEqual(self.base.count("exception when others"), 1)

    def test_callers_emit_kind_and_ordinal_without_ids(self):
        for caller in (self.caller, self.legacy_caller):
            self.assertIn('"attachment_kind"', caller)
            self.assertIn('"ordinal"', caller)
            self.assertIn('"attachment_ordinal"', caller)
            self.assertNotIn('"attachment_id"', caller)
            self.assertNotIn('"intake_id"', caller)

    def test_scope_and_no_broad_privileges(self):
        for text in (self.base, self.wrapper):
            self.assertIn("production_environment_sentinel", text)
            self.assertIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated", text)
            self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to anon", text)
            self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to service_role", text)


if __name__ == "__main__":
    unittest.main()
