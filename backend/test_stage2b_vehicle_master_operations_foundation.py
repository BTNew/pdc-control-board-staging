from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "029_stage2b_vehicle_master_operations.sql"
BACKUP_SCRIPT = ROOT / "scripts" / "pdc_backup.py"


class Stage2BVehicleMasterOperationsFoundationTests(unittest.TestCase):
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

    def test_protected_operation_surface_exists(self):
        for name in (
            "preview_vehicle_master_import",
            "upsert_vehicle_master_import",
            "apply_vehicle_master_import",
            "edit_vehicle_master",
        ):
            body = self.function_sql(name)
            self.assertIn("security definer", body)
            self.assertIn("set search_path = public", body)

    def test_preview_and_apply_share_one_matcher_and_normalizer(self):
        preview = self.function_sql("preview_vehicle_master_import")
        upsert = self.function_sql("upsert_vehicle_master_import")
        self.assertIn("vehicle_master_import_match", preview)
        self.assertIn("preview_vehicle_master_import", upsert)
        matcher = self.function_sql("vehicle_master_import_match")
        for helper in (
            "normalize_vehicle_vin",
            "normalize_vehicle_stock_number",
            "normalize_vehicle_source_system",
            "normalize_vehicle_source_identifier",
        ):
            self.assertIn(helper, matcher)
        self.assertIn("ambiguous_match", matcher)
        self.assertIn("conflicting_match", matcher)
        self.assertIn("unlinked_source_evidence", matcher)
        self.assertNotIn("limit 1", matcher)

    def test_idempotency_receipts_are_private_and_request_bound(self):
        self.assertIn("create table if not exists public.vehicle_master_operation_receipts", self.lower)
        self.assertIn("unique (operation_kind, scope_key, idempotency_key)", self.lower)
        self.assertIn("request_hash", self.lower)
        self.assertIn("idempotency_conflict", self.function_sql("upsert_vehicle_master_import"))
        self.assertIn("idempotency_conflict", self.function_sql("edit_vehicle_master"))
        self.assertIn("revoke all on table public.vehicle_master_operation_receipts", self.lower)

    def test_version_checks_and_fail_closed_conflicts(self):
        upsert = self.function_sql("upsert_vehicle_master_import")
        edit = self.function_sql("edit_vehicle_master")
        self.assertIn("stale_version", upsert)
        self.assertIn("where id = v_vehicle_id and version = p_expected_version", upsert)
        self.assertIn("stale_version", edit)
        self.assertIn("where id = p_vehicle_id and version = p_expected_version", edit)

    def test_source_evidence_aliases_and_audit_are_retained(self):
        upsert = self.function_sql("upsert_vehicle_master_import")
        edit = self.function_sql("edit_vehicle_master")
        self.assertIn("retain_vehicle_master_source_record", upsert)
        self.assertIn("retain_vehicle_master_source_record", edit)
        self.assertIn("ensure_vehicle_master_alias", upsert)
        self.assertIn("ensure_vehicle_master_alias", edit)
        self.assertIn("audit_pdc_event", upsert)
        self.assertIn("audit_pdc_event", edit)

    def test_allowlist_excludes_operational_and_raw_fields(self):
        sanitizer = self.function_sql("sanitize_vehicle_master_changes")
        for field in (
            "stock_number", "vin", "job_card_number", "customer_name",
            "vehicle_description", "salesperson_reference", "make", "model",
            "registration", "eta_to_kewdale", "arrival_reference_date",
        ):
            self.assertIn(field, sanitizer)
        for forbidden in (
            "source_payload", "lifecycle_state", "current_location", "pmb_stage",
            "workshop_status", "qc_completed_at", "deleted_at", "version",
        ):
            self.assertNotIn(f"'{forbidden}'", sanitizer)

    def test_role_grants_are_narrow(self):
        self.assertIn("perform public.require_pdc_role('importer')", self.function_sql("preview_vehicle_master_import"))
        self.assertIn("perform public.require_pdc_role('importer')", self.function_sql("upsert_vehicle_master_import"))
        self.assertIn("perform public.require_pdc_role('operator')", self.function_sql("edit_vehicle_master"))
        self.assertIn("grant execute on function public.preview_vehicle_master_import", self.lower)
        self.assertIn("grant execute on function public.apply_vehicle_master_import", self.lower)
        self.assertIn("grant execute on function public.edit_vehicle_master", self.lower)
        self.assertNotIn("grant execute on all functions", self.lower)

    def test_existing_direct_select_is_not_retired(self):
        self.assertNotIn("revoke select on table public.vehicles", self.lower)
        self.assertNotIn("drop policy vehicles_select_approved", self.lower)
        self.assertNotIn("alter publication supabase_realtime drop table public.vehicles", self.lower)

    def test_migration_cannot_touch_browser_local_data(self):
        self.assertNotIn("localstorage", self.lower)
        self.assertNotIn("vehicletrackingcorenavisiononly", self.lower)
        self.assertNotIn("window.vehicle_tracking_data", self.lower)

    def test_backup_inventory_is_pre_migration_safe(self):
        backup = BACKUP_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('"vehicle_master_operation_receipts"', backup)
        self.assertLess(
            backup.index('"vehicle_master_operation_receipts"'),
            backup.index('"vehicle_master_history"'),
        )
        self.assertIn("existing_tables", backup)
        self.assertIn("not_present_tables", backup)
        self.assertIn("payload_tables = [table for table in TABLES if table in existing_tables]", backup)


if __name__ == "__main__":
    unittest.main()
