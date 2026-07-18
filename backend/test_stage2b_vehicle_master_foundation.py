import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "028_stage2b_vehicle_master_foundation.sql"
SQL = MIGRATION.read_text(encoding="utf-8") if MIGRATION.exists() else ""
LOWER_SQL = SQL.lower()
BACKUP_SCRIPT = (ROOT / "scripts" / "pdc_backup.py").read_text(encoding="utf-8")
RESTORE_SCRIPT = (ROOT / "scripts" / "pdc_restore.py").read_text(encoding="utf-8")


def function_sql(name):
    match = re.search(
        rf"create or replace function public\.{re.escape(name)}\(.*?\n\$\$;",
        SQL,
        re.DOTALL | re.IGNORECASE,
    )
    if not match:
        raise AssertionError(f"missing function: {name}")
    return match.group(0)


class Stage2BVehicleMasterFoundationTests(unittest.TestCase):
    def test_migration_exists_and_is_transactional(self):
        self.assertTrue(MIGRATION.exists(), "migration 028 is missing")
        self.assertRegex(LOWER_SQL, r"\bbegin\s*;")
        self.assertRegex(LOWER_SQL, r"\bcommit\s*;")

    def test_immutable_normalizers_and_validators_are_safe(self):
        stock = function_sql("normalize_vehicle_stock_number").lower()
        vin = function_sql("normalize_vehicle_vin").lower()
        source = function_sql("normalize_vehicle_source_identifier").lower()
        for body in (stock, vin, source):
            self.assertIn("immutable", body)
            self.assertIn("returns null on null input", body)
        self.assertIn("regexp_replace(upper(btrim(p_value)), '[[:space:]-]+', '', 'g')", stock)
        self.assertIn("regexp_replace(upper(btrim(p_value)), '[[:space:]-]+', '', 'g')", vin)
        self.assertIn("upper(btrim(p_value))", source)
        self.assertIn("function public.is_real_vehicle_stock_number", LOWER_SQL)
        self.assertIn("function public.is_valid_vehicle_vin", LOWER_SQL)
        for placeholder in ("'0'", "'tba'", "'new-%'", "'pd-%'", "'pending-%'"):
            self.assertIn(placeholder, LOWER_SQL)
        self.assertIn("^[a-hj-npr-z0-9]{17}$", LOWER_SQL)

    def test_core_columns_generated_identity_and_nonbreaking_checks(self):
        for column in (
            "key_number",
            "vehicle_description",
            "salesperson_reference",
            "arrival_reference_date",
            "source_system",
            "source_batch_id",
            "source_record_id",
            "stock_number_normalized",
            "vin_normalized",
        ):
            self.assertRegex(LOWER_SQL, rf"add column if not exists {column}\b")
        self.assertIn("generated always as (public.normalize_vehicle_stock_number(stock_number)) stored", LOWER_SQL)
        self.assertIn("case when public.is_valid_vehicle_vin(vin)", LOWER_SQL)
        self.assertIn("then public.normalize_vehicle_vin(vin)", LOWER_SQL)
        self.assertIn("else null", LOWER_SQL)
        self.assertIn("drop constraint if exists vehicles_master_vin_valid", LOWER_SQL)
        vin_guard = function_sql("enforce_vehicle_master_identity_uniqueness").lower()
        self.assertIn("old.vin is distinct from new.vin", vin_guard)
        self.assertIn("raise exception 'invalid vin'", vin_guard)
        self.assertIn("errcode = '23514'", vin_guard)
        self.assertIn("constraint vehicles_master_version_positive", LOWER_SQL)
        self.assertGreaterEqual(LOWER_SQL.count("not valid"), 2)

    def test_existing_duplicates_are_surfaced_before_indexes_and_do_not_abort_migration(self):
        conflict_pos = LOWER_SQL.index("create table if not exists public.vehicle_master_identity_conflicts")
        capture_pos = LOWER_SQL.index("insert into public.vehicle_master_identity_conflicts")
        indexes_pos = LOWER_SQL.index("create unique index vehicles_master_vin_unique_idx")
        self.assertLess(conflict_pos, capture_pos)
        self.assertLess(capture_pos, indexes_pos)
        self.assertIn("on conflict (conflict_kind, scope_key, normalized_value) do update", LOWER_SQL)
        self.assertIn("if not exists (", LOWER_SQL[indexes_pos - 500 :])
        self.assertIn("duplicate_vehicle_vin", LOWER_SQL)
        self.assertIn("duplicate_vehicle_stock", LOWER_SQL)
        self.assertIn("duplicate_vehicle_source_record", LOWER_SQL)
        self.assertIn("cross_vehicle_alias_vin", LOWER_SQL)
        self.assertIn("cross_vehicle_alias_stock", LOWER_SQL)
        pre_guard_sql = LOWER_SQL[: LOWER_SQL.index("function public.enforce_vehicle_master_identity_uniqueness")]
        self.assertNotIn("raise exception", pre_guard_sql)

    def test_deterministic_uniqueness_excludes_placeholders_and_invalid_vins(self):
        self.assertIn("where public.is_valid_vehicle_vin(vin)", LOWER_SQL)
        self.assertIn("where public.is_real_vehicle_stock_number(stock_number)", LOWER_SQL)
        self.assertIn("(source_system_normalized, source_record_id_normalized)", LOWER_SQL)
        self.assertIn("where source_system_normalized is not null and source_record_id_normalized is not null", LOWER_SQL)
        self.assertIn("vehicle_aliases_master_global_unique_idx", LOWER_SQL)
        self.assertIn("alias_type_normalized in ('vin', 'stock_number')", LOWER_SQL)
        self.assertIn("vehicle_aliases_master_source_unique_idx", LOWER_SQL)
        self.assertIn("alias_type_normalized in ('source_record_id', 'toyota_order_number', 'job_card_number')", LOWER_SQL)
        self.assertIn("trigger vehicles_enforce_master_identity_uniqueness", LOWER_SQL)
        self.assertIn("trigger vehicle_aliases_enforce_master_identity_uniqueness", LOWER_SQL)
        self.assertIn("pg_advisory_xact_lock", LOWER_SQL)
        vehicle_guard = function_sql("enforce_vehicle_master_identity_uniqueness").lower()
        alias_guard = function_sql("enforce_vehicle_alias_identity_uniqueness").lower()
        self.assertIn("from public.vehicle_aliases a", vehicle_guard)
        self.assertIn("from public.vehicles v", alias_guard)

    def test_alias_metadata_revision_and_audit_support(self):
        for column in (
            "normalized_alias_value",
            "alias_type_normalized",
            "source_system",
            "source_batch_id",
            "version",
            "created_by",
            "updated_by",
            "updated_at",
        ):
            self.assertRegex(
                LOWER_SQL,
                re.compile(
                    rf"alter table public\.vehicle_aliases.*?add column if not exists {column}\b",
                    re.DOTALL,
                ),
            )
        self.assertIn("create table if not exists public.vehicle_master_revision", LOWER_SQL)
        self.assertIn("create table if not exists public.vehicle_master_history", LOWER_SQL)
        self.assertIn("create table if not exists public.vehicle_master_source_records", LOWER_SQL)
        self.assertIn("vehicle_id uuid references public.vehicles(id) on delete set null", LOWER_SQL)
        self.assertIn("source_metadata jsonb not null default '{}'::jsonb", LOWER_SQL)
        self.assertNotRegex(
            LOWER_SQL,
            re.compile(
                r"alter table public\.(vehicles|vehicle_aliases).*?add column if not exists source_metadata",
                re.DOTALL,
            ),
        )
        self.assertIn("before_data jsonb", LOWER_SQL)
        self.assertIn("after_data jsonb", LOWER_SQL)
        self.assertIn("expected_version integer", LOWER_SQL)
        self.assertIn("resulting_version integer", LOWER_SQL)
        self.assertIn("function public.bump_vehicle_master_revision", LOWER_SQL)
        self.assertIn("trigger vehicles_bump_master_revision", LOWER_SQL)
        self.assertIn("trigger vehicle_aliases_bump_master_revision", LOWER_SQL)
        self.assertIn("function public.record_vehicle_master_history", LOWER_SQL)
        self.assertIn("trigger vehicles_record_master_history", LOWER_SQL)
        self.assertIn("trigger vehicle_aliases_record_master_history", LOWER_SQL)

    def test_history_trigger_records_core_changes_but_not_workflow_payloads(self):
        body = function_sql("record_vehicle_master_history").lower()
        self.assertIn("insert into public.vehicle_master_history", body)
        self.assertIn("public.vehicle_master_core_audit_json", body)
        self.assertIn("public.vehicle_alias_audit_json", body)
        self.assertIn("public.current_actor_email()", body)
        for operational_column in (
            "parts_stoppage",
            "visible_on_board",
            "current_location",
            "pmb_stage",
            "lifecycle_state",
            "active_workshop_booking_id",
            "workshop_status",
        ):
            self.assertNotIn(operational_column, body)

    def test_vehicle_revision_trigger_does_not_treat_operational_updates_as_master_changes(self):
        body = function_sql("bump_vehicle_master_revision").lower()
        for core_column in (
            "stock_number",
            "vin",
            "toyota_order_number",
            "job_card_number",
            "customer_name",
            "salesperson_id",
            "make",
            "model",
            "key_number",
            "vehicle_description",
            "source_system",
            "source_record_id",
        ):
            self.assertIn(core_column, body)
        for operational_column in (
            "parts_stoppage",
            "visible_on_board",
            "current_location",
            "pmb_stage",
            "lifecycle_state",
            "rft_collected_at",
        ):
            self.assertNotIn(operational_column, body)

    def test_sanitized_snapshot_has_explicit_core_allowlist(self):
        snapshot = function_sql("get_vehicle_core_snapshot").lower()
        for field in (
            "'id'",
            "'stock_number'",
            "'vin'",
            "'job_card_number'",
            "'key_number'",
            "'customer_name'",
            "'vehicle_description'",
            "'salesperson_id'",
            "'eta_to_kewdale'",
            "'arrival_reference_date'",
            "'version'",
            "'created_at'",
            "'updated_at'",
            "'is_archived'",
        ):
            self.assertIn(field, snapshot)
        for forbidden in (
            "source_metadata",
            "source_payload",
            "parts_stoppage",
            "visible_on_board",
            "current_location",
            "pmb_stage",
            "lifecycle_state",
            "active_workshop_booking_id",
            "workshop_status",
            "rft_collected_at",
        ):
            self.assertNotIn(forbidden, snapshot)
        self.assertIn("public.current_pdc_user_role()", snapshot)
        self.assertIn("public.is_pdc_role('viewer')", snapshot)
        self.assertIn("'can_edit'", snapshot)
        self.assertIn("public.is_pdc_role('operator')", snapshot)
        self.assertIn("'can_import'", snapshot)
        self.assertIn("public.is_pdc_role('importer')", snapshot)
        self.assertIn("'can_administer'", snapshot)
        self.assertIn("public.is_pdc_role('administrator')", snapshot)

    def test_viewer_reads_rpc_only_writes_and_least_privilege(self):
        for table in (
            "vehicles",
            "vehicle_aliases",
            "vehicle_master_revision",
            "vehicle_master_history",
            "vehicle_master_identity_conflicts",
        ):
            self.assertIn(f"alter table public.{table} enable row level security", LOWER_SQL)
        self.assertIn("using (public.is_pdc_role('viewer'))", LOWER_SQL)
        self.assertIn("revoke insert, update, delete, truncate on table", LOWER_SQL)
        self.assertIn("from public, anon, authenticated", LOWER_SQL)
        self.assertIn("grant select on table public.vehicles, public.vehicle_aliases to authenticated", LOWER_SQL)
        self.assertIn("grant select on table public.vehicle_master_revision to authenticated", LOWER_SQL)
        self.assertIn("create policy vehicle_master_revision_select_approved", LOWER_SQL)
        self.assertNotRegex(
            LOWER_SQL,
            r"grant select on table\s+public\.vehicle_master_(history|identity_conflicts|source_records)",
        )
        self.assertIn("grant execute on function public.get_vehicle_core_snapshot() to authenticated", LOWER_SQL)
        self.assertIn("revoke all on function public.get_vehicle_core_snapshot() from public, anon", LOWER_SQL)
        self.assertNotRegex(LOWER_SQL, r"create policy .*? for (insert|update|delete|all)")
        self.assertNotRegex(LOWER_SQL, r"grant\s+(insert|update|delete|all)\s+on")

    def test_realtime_and_replica_identity_are_explicit_and_idempotent(self):
        self.assertIn("alter table public.vehicles replica identity full", LOWER_SQL)
        self.assertIn("alter table public.vehicle_aliases replica identity full", LOWER_SQL)
        self.assertIn("alter table public.vehicle_master_revision replica identity full", LOWER_SQL)
        self.assertIn("pg_publication_tables", LOWER_SQL)
        self.assertIn("alter publication supabase_realtime add table public.vehicles", LOWER_SQL)
        self.assertIn("alter publication supabase_realtime add table public.vehicle_aliases", LOWER_SQL)
        self.assertIn("alter publication supabase_realtime add table public.vehicle_master_revision", LOWER_SQL)

    def test_snapshot_exists_but_mutation_rpcs_are_deferred(self):
        response = function_sql("vehicle_master_response").lower()
        self.assertIn("returns jsonb", response)
        self.assertIn("jsonb_build_object", response)
        for key in ("'ok'", "'code'", "'data'"):
            self.assertIn(key, response)
        for rpc in (
            "preview_vehicle_master_import",
            "apply_vehicle_master_import",
            "upsert_vehicle_master_from_source",
            "create_manual_vehicle",
            "edit_vehicle_master",
            "activate_vehicle_master",
        ):
            self.assertNotIn(f"function public.{rpc}", LOWER_SQL)

    def test_restore_order_is_fk_safe_and_history_preserves_audit(self):
        vehicles_pos = LOWER_SQL.index("alter table public.vehicles")
        aliases_pos = LOWER_SQL.index("alter table public.vehicle_aliases")
        history_pos = LOWER_SQL.index("create table if not exists public.vehicle_master_history")
        conflicts_pos = LOWER_SQL.index("create table if not exists public.vehicle_master_identity_conflicts")
        self.assertLess(vehicles_pos, aliases_pos)
        self.assertLess(aliases_pos, history_pos)
        self.assertLess(history_pos, conflicts_pos)
        self.assertIn("vehicle_id uuid references public.vehicles(id) on delete set null", LOWER_SQL)
        self.assertIn("restore order: vehicles before vehicle_aliases", LOWER_SQL)

    def test_backup_covers_foundation_and_restore_regenerates_normalized_columns(self):
        table_positions = [
            BACKUP_SCRIPT.index(f'"{table}"')
            for table in (
                "vehicles",
                "vehicle_aliases",
                "vehicle_master_revision",
                "vehicle_master_source_records",
                "vehicle_master_history",
                "vehicle_master_identity_conflicts",
            )
        ]
        self.assertEqual(table_positions, sorted(table_positions))
        self.assertIn("def get_generated_columns", RESTORE_SCRIPT)
        self.assertIn("is_generated='ALWAYS'", RESTORE_SCRIPT)
        self.assertIn(
            "insert_columns = [column for column in columns if column not in generated_cols]",
            RESTORE_SCRIPT,
        )
        self.assertIn("payload_tables = set(data[\"tables\"])", RESTORE_SCRIPT)
        self.assertIn("discover_foreign_keys(cur, payload_tables)", RESTORE_SCRIPT)

    def test_no_operational_data_rewrite_or_stage2b_import_evidence_table(self):
        self.assertNotRegex(LOWER_SQL, r"update\s+public\.vehicles\s+set")
        self.assertNotRegex(LOWER_SQL, r"delete\s+from\s+public\.vehicles")
        self.assertNotIn("vehicle_master_import_items", LOWER_SQL)


if __name__ == "__main__":
    unittest.main()
