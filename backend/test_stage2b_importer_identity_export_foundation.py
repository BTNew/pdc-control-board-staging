from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "031_stage2b_importer_identity_export.sql"
IMPORTER = ROOT / "scripts" / "workshop_legacy_import.py"


class Stage2BImporterIdentityExportFoundationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8") if MIGRATION.exists() else ""
        cls.lower = cls.sql.lower()
        cls.importer = IMPORTER.read_text(encoding="utf-8")

    def function_sql(self) -> str:
        match = re.search(
            r"create\s+or\s+replace\s+function\s+public\.export_workshop_legacy_vehicle_identities\b.*?\$export\$;",
            self.sql,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(match, "missing importer identity-export RPC")
        return match.group(0).lower()

    def test_narrow_security_definer_importer_admin_rpc(self):
        body = self.function_sql()
        self.assertIn("security definer", body)
        self.assertIn("set search_path = public", body)
        self.assertIn("current_pdc_user_role", body)
        self.assertRegex(body, r"not\s+in\s*\(\s*'importer'\s*,\s*'administrator'\s*\)")
        self.assertIn("'unauthorized'", body)
        self.assertIn("revoke all on function public.export_workshop_legacy_vehicle_identities", self.lower)
        self.assertIn("grant execute on function public.export_workshop_legacy_vehicle_identities", self.lower)
        self.assertNotIn("grant execute on all functions", self.lower)

    def test_contract_uses_028_normalizers_and_complete_candidate_sets(self):
        body = self.function_sql()
        for helper in (
            "normalize_vehicle_stock_number", "is_real_vehicle_stock_number",
            "normalize_vehicle_vin", "is_valid_vehicle_vin",
            "normalize_vehicle_source_identifier", "normalize_vehicle_source_system",
        ):
            self.assertIn(helper, body)
        for source in ("public.vehicles", "public.vehicle_aliases"):
            self.assertIn(source, body)
        self.assertIn("count(distinct vehicle_id)", body)
        self.assertIn("canonical_alias_conflict", body)
        self.assertIn("ambiguous_normalized_identity", body)
        self.assertNotIn("limit 1", body)

    def test_projection_is_identity_only(self):
        body = self.function_sql()
        for allowed in (
            "'vehicle_id'", "'version'", "'is_archived'", "'identifiers'",
            "'identifier_type'", "'normalized_value'", "'source_system'",
            "'origin'", "'export_revision'", "'conflicts'",
        ):
            self.assertIn(allowed, body)
        for forbidden in (
            "customer_name", "parts_required", "notes", "ai_", "workshop_status",
            "current_location", "pmb_stage", "salesperson_id", "source_payload",
        ):
            self.assertNotIn(forbidden, body)

    def test_pagination_is_bounded_revision_pinned_and_deterministic(self):
        body = self.function_sql()
        self.assertIn("p_after_vehicle_id text", body)
        self.assertIn("p_page_size integer", body)
        self.assertIn("p_expected_revision bigint", body)
        self.assertIn("greatest(1, least", body)
        self.assertIn("vehicle_lifecycle_resolver_revision", body)
        self.assertIn("'stale_export'", body)
        self.assertRegex(body, r"order\s+by\s+v\.id")
        self.assertIn("'next_cursor'", body)
        self.assertIn("'has_more'", body)

    def test_importer_default_path_is_rpc_and_rollback_is_explicit_staging_only(self):
        self.assertIn("export_workshop_legacy_vehicle_identities", self.importer)
        self.assertIn("vehicle_export_rollback=False", self.importer)
        self.assertIn("STAGING_PROJECT_REF", self.importer)
        self.assertIn("rollback", self.importer.lower())
        direct = re.findall(r"select id, stock_number, permanent_vehicle_id from vehicles", self.importer.lower())
        self.assertEqual(len(direct), 1, "historical vehicle read must exist only in rollback helper")

    def test_transitional_broad_select_is_not_retired(self):
        self.assertNotIn("revoke select on table public.vehicles", self.lower)
        self.assertNotIn("drop policy vehicles_select_approved", self.lower)


if __name__ == "__main__":
    unittest.main()
