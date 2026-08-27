from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828030000_715_remove_leaked_navision_714_test_probes.sql"


class NavisionDelivery715ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_is_append_only_exactly_guarded_after_714(self):
        for marker in (
            "20260828020000",
            "714_fail_closed_navision_family_catalog_hardening",
            "pdc_715_exact_live_head_required",
            "pdc_715_probe_identity_guard_failed",
            "pdc_715_staging_sentinel_or_role_failed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("truncate", self.lower)

    def test_only_recorded_hermes_test_public_probes_can_be_removed(self):
        for marker in (
            "pdc_navision_function_security_inventory_714",
            "phase='post'",
            "not i.is_canonical",
            "i.function_sha256=encode",
            "drop function %s",
            "pdc_715_synthetic_probe_remains",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("reconcile_navision_delivery_700", self.lower)
        self.assertIn("p_backend_record_id uuid, p_probe text", self.lower)

    def test_canonical_call_is_unambiguous_and_noncanonical_acl_stays_closed(self):
        for marker in (
            "pdc_715_delivery_overload_remains",
            "pdc_715_canonical_signature_missing",
            "pdc_715_noncanonical_execute_drift",
            "to_regprocedure('public.reconcile_navision_delivery_700(uuid)')",
            "has_function_privilege('public'",
            "has_function_privilege('anon'",
            "has_function_privilege('service_role'",
            "has_function_privilege('pdc_email_monitor'",
            "perforM public.reconcile_navision_delivery_700",
            "notify pgrst",
        ):
            self.assertIn(marker.lower(), self.lower)


if __name__ == "__main__":
    unittest.main()
