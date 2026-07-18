from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "030_stage2b_lifecycle_identity_resolver.sql"
BACKUP_SCRIPT = ROOT / "scripts" / "pdc_backup.py"
APP = ROOT / "app.js"
STAGING_CONFIG = ROOT / "pdc-supabase-config.staging.js"


class Stage2BLifecycleIdentityResolverFoundationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def function_sql(self, name: str) -> str:
        match = re.search(
            rf"create\s+or\s+replace\s+function\s+public\.{re.escape(name)}\b.*?\$\$;",
            self.sql,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(match, f"missing function {name}")
        return match.group(0).lower()

    def test_resolver_is_narrow_authenticated_security_definer_rpc(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        self.assertIn("security definer", body)
        self.assertIn("set search_path = public", body)
        self.assertIn("grant execute on function public.resolve_vehicle_lifecycle_identity", self.lower)
        self.assertIn("revoke all on function public.resolve_vehicle_lifecycle_identity", self.lower)
        self.assertNotIn("grant execute on all functions", self.lower)

    def test_resolver_accepts_text_uuid_and_all_approved_identity_inputs(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        for parameter in (
            "p_vehicle_id text", "p_stock_number text", "p_vin text",
            "p_job_card_number text", "p_permanent_vehicle_id text",
            "p_toyota_order_number text", "p_source_system text",
            "p_source_record_id text",
        ):
            self.assertIn(parameter, body)

    def test_public_outcome_vocabulary_is_complete(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        for outcome in (
            "resolved", "not_found", "ambiguous", "conflict",
            "invalid_input", "unauthorized",
        ):
            self.assertIn(f"'{outcome}'", body)
        self.assertNotIn("limit 1", body)

    def test_normalization_matches_028_and_029(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        for helper in (
            "normalize_vehicle_stock_number", "is_real_vehicle_stock_number",
            "normalize_vehicle_vin", "is_valid_vehicle_vin",
            "normalize_vehicle_source_system", "normalize_vehicle_source_identifier",
        ):
            self.assertIn(helper, body)
        self.assertIn("alias_type_normalized", body)
        self.assertIn("normalized_alias_value", body)
        self.assertIn("vehicle_master_source_records", body)

    def test_ambiguity_and_conflict_use_all_candidates_and_origins(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        self.assertIn("candidate_count", body)
        self.assertIn("canonical", body)
        self.assertIn("alias", body)
        self.assertIn("source_evidence", body)
        self.assertIn("canonical_alias_conflict", body)
        self.assertIn("conflicting_identifiers", body)
        self.assertNotIn("rows[0]", body)

    def test_resolved_projection_is_lifecycle_only(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        for allowed in (
            "'vehicle_id'", "'version'", "'qc_completed_at'",
            "'lifecycle_state'", "'is_archived'", "'resolver_revision'",
        ):
            self.assertIn(allowed, body)
        for forbidden in (
            "'customer_name'", "'source_payload'", "'current_location'",
            "'pmb_stage'", "'workshop_status'", "'parts_required'",
            "'salesperson_id'", "'deleted_reason'",
        ):
            self.assertNotIn(forbidden, body)

    def test_viewer_hierarchy_is_required_and_unauthorized_has_no_data(self):
        body = self.function_sql("resolve_vehicle_lifecycle_identity")
        self.assertIn("current_pdc_user_role", body)
        self.assertIn("is_pdc_role('viewer')", body)
        unauthorized = re.search(
            r"return\s+jsonb_build_object\s*\(\s*'outcome'\s*,\s*'unauthorized'\s*\)",
            body,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(unauthorized)

    def test_lifecycle_revision_is_private_except_viewer_read_and_realtime(self):
        self.assertIn("create table if not exists public.vehicle_lifecycle_resolver_revision", self.lower)
        self.assertIn("alter table public.vehicle_lifecycle_resolver_revision enable row level security", self.lower)
        self.assertRegex(
            self.lower,
            r"revoke all on function public\.bump_vehicle_lifecycle_resolver_revision\(\)\s+from public, anon, authenticated",
        )
        self.assertIn("grant select on table public.vehicle_lifecycle_resolver_revision to authenticated", self.lower)
        self.assertIn("revoke all on table public.vehicle_lifecycle_resolver_revision from public, anon, authenticated", self.lower)
        self.assertIn("alter publication supabase_realtime add table public.vehicle_lifecycle_resolver_revision", self.lower)
        self.assertIn("replica identity full", self.lower)
        self.assertIn("vehicles_bump_lifecycle_resolver_revision", self.lower)
        self.assertIn("vehicle_aliases_bump_lifecycle_resolver_revision", self.lower)
        self.assertIn("vehicle_source_records_bump_lifecycle_resolver_revision", self.lower)

    def test_existing_direct_select_and_publication_are_not_retired(self):
        self.assertNotIn("revoke select on table public.vehicles", self.lower)
        self.assertNotIn("drop policy vehicles_select_approved", self.lower)
        self.assertNotIn("alter publication supabase_realtime drop table public.vehicles", self.lower)

    def test_browser_direct_first_match_is_removed_and_rollback_is_staging_only(self):
        app = APP.read_text(encoding="utf-8")
        config = STAGING_CONFIG.read_text(encoding="utf-8")
        self.assertNotIn("&limit=1", app)
        self.assertIn("resolverRollbackDirectRead", config)
        self.assertIn("resolverRollbackDirectRead: false", config)
        self.assertIn("vehicleLifecycleResolverRollbackEnabled", app)
        self.assertIn("__vehicleLifecycleResolverDiagnostics", app)

    def test_backup_inventory_includes_resolver_revision(self):
        backup = BACKUP_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('"vehicle_lifecycle_resolver_revision"', backup)
        restore_test = (ROOT / "_staging_test_tools" / "test_stage2a_backup_restore_staging.py").read_text(encoding="utf-8")
        self.assertIn('(\"vehicle_lifecycle_resolver_revision\", [\"singleton\", \"revision\", \"updated_at\"])', restore_test)

    def test_placeholder_stock_and_origin_sets_fail_closed_deterministically(self):
        self.assertIn("public.is_real_vehicle_stock_number(v.stock_number)", self.lower)
        self.assertIn("public.is_real_vehicle_stock_number(a.alias_value)", self.lower)
        self.assertIn("v_stock_canonical <@ v_stock_alias", self.lower)
        self.assertIn("v_source_alias <@ v_source_evidence", self.lower)
        self.assertRegex(self.lower, r"'candidate_count',\s*cardinality\(v_all_candidates\)")


if __name__ == "__main__":
    unittest.main()
