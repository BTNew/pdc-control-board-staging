from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260831430000_pdc_email_canonical_import_nested_context.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


class PdcEmailCanonicalNestedContextTests(unittest.TestCase):
    def test_exact_staging_successor_and_transaction_shape(self):
        self.assertEqual(SQL.count("BEGIN;"), 1)
        self.assertEqual(SQL.count("COMMIT;"), 1)
        self.assertIn("20260831420000", SQL)
        self.assertIn("pdc_email_canonical_import_capability", LOWER)
        self.assertIn("cdsmnqxtyyoeoznmbidd", LOWER)
        self.assertIn("pdc_production_environment_sentinel", LOWER)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", LOWER)

    def test_nested_context_is_transaction_local_and_not_api_callable(self):
        self.assertIn("pdc_canonical_import_capability_context_20260831", LOWER)
        self.assertIn("set_config('pdc.canonical_import_capability_20260831'", LOWER)
        self.assertIn("revoke all on function public.pdc_canonical_import_capability_context_20260831()", LOWER)
        self.assertIn("pdc_monitor_stage_activation_writers", LOWER)
        self.assertIn("if not found and not public.pdc_canonical_import_capability_context_20260831()", LOWER)
        self.assertEqual(LOWER.count("pdc_canonical_import_capability_context_20260831()"), 12)

    def test_nested_functions_are_exact_and_business_semantics_stay_narrow(self):
        for signature in (
            "pdc_submit_generic_current_navision_enrichment_312",
            "import_pdc_authenticated_vehicle_email",
            "import_pdc_authenticated_email_operations_with_hours",
        ):
            self.assertIn(signature, LOWER)
        for marker in (
            "stock identity",
            "recognised work",
            "ambiguity",
            "idempotency",
            "no-booking/no-completion/no-location",
        ):
            self.assertIn(marker, LOWER)
        self.assertNotIn("grant execute on function public.pdc_canonical_import_capability_context_20260831", LOWER)
        self.assertEqual(LOWER.count("insert into supabase_migrations.schema_migrations"), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
