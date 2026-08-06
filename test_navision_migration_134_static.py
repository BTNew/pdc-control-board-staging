from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent
MIGRATION = ROOT / "supabase" / "staging_only" / "134_navision_preserve_deleted_canonical_identity.sql"


class NavisionMigration134StaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_staging_guard_and_ledger_identity(self):
        self.assertIn("project_ref='cdsmnqxtyyoeoznmbidd'", self.sql)
        self.assertIn("pdc_production_environment_sentinel", self.sql)
        self.assertIn("version='133' and name='close_email_receipt_table_direct_authority'", self.sql)
        self.assertIn("values('134','navision_preserve_deleted_canonical_identity'", self.sql)

    def test_existing_reconciler_is_retained_and_delegated(self):
        self.assertIn("rename to reconcile_navision_operational_record_pre134", self.lower)
        self.assertGreaterEqual(
            self.lower.count("reconcile_navision_operational_record_pre134("),
            4,
        )
        self.assertIn("from public.vehicles v", self.lower)
        self.assertIn("v.deleted_at is not null", self.lower)
        self.assertIn("v.id=v_record.canonical_vehicle_id", self.lower)
        self.assertIn("v.stock_number_normalized=v_stock", self.lower)
        self.assertIn("v.vin_normalized=v_vin", self.lower)

    def test_historical_identity_is_non_operational_success(self):
        self.assertIn("'historical_vehicle_retained'", self.sql)
        self.assertIn("'operational_change',false", self.sql)
        executable = re.sub(r"--.*", "", self.lower)
        self.assertNotIn("insert into public.vehicles", executable)
        self.assertNotIn("update public.vehicles", executable)
        self.assertNotIn("delete from public.vehicles", executable)

    def test_triggers_are_rebound_to_the_new_wrapper(self):
        self.assertIn(
            "create or replace function public.trigger_reconcile_navision_operational_record()",
            self.lower,
        )
        self.assertIn(
            "perform public.reconcile_navision_operational_record(",
            self.lower,
        )
        self.assertIn(
            "revoke all on function public.trigger_reconcile_navision_operational_record()",
            self.lower,
        )
        self.assertIn("drop trigger if exists navision_record_operational_reconcile", self.lower)
        self.assertIn("drop trigger if exists navision_activation_operational_reconcile", self.lower)
        self.assertEqual(
            self.lower.count("execute function public.trigger_reconcile_navision_operational_record()"),
            2,
        )

    def test_reconcilers_remain_internal_only(self):
        self.assertIn(
            "revoke all on function public.reconcile_navision_operational_record_pre134(uuid,uuid,text)",
            self.lower,
        )
        self.assertIn(
            "revoke all on function public.reconcile_navision_operational_record(uuid,uuid,text)",
            self.lower,
        )
        self.assertNotRegex(
            self.lower,
            r"grant\s+execute\s+on\s+function\s+public\.reconcile_navision_operational_record",
        )


if __name__ == "__main__":
    unittest.main()
