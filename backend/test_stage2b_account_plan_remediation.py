"""Offline regression checks for restricted live-pilot account-plan remediation."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
VIEWER_MIGRATION = ROOT / "supabase" / "migrations" / "032_restricted_pilot_viewer_vehicle_contract.sql"
BROAD_RPC_MIGRATION = ROOT / "supabase" / "migrations" / "033_restrict_broad_vehicle_snapshot_rpc.sql"
BOUNDARY_MIGRATION = ROOT / "supabase" / "migrations" / "034_complete_restricted_viewer_vehicle_boundary.sql"
EXHAUSTIVE_MIGRATION = ROOT / "supabase" / "migrations" / "035_exhaustive_viewer_boundary_and_default_privileges.sql"
EXPECTED_COLUMNS = [
    "id uuid",
    "version integer",
    "current_location text",
    "lifecycle_state public.vehicle_lifecycle_state",
    "workshop_status text",
    "active_workshop_booking_id uuid",
]
EXPECTED_SELECT = [
    "v.id",
    "v.version",
    "v.current_location",
    "v.lifecycle_state",
    "v.workshop_status",
    "v.active_workshop_booking_id",
]


class RestrictedPilotAccountPlanMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.viewer_sql = VIEWER_MIGRATION.read_text(encoding="utf-8")
        cls.broad_rpc_sql = BROAD_RPC_MIGRATION.read_text(encoding="utf-8")
        cls.boundary_sql = BOUNDARY_MIGRATION.read_text(encoding="utf-8")
        cls.exhaustive_sql = EXHAUSTIVE_MIGRATION.read_text(encoding="utf-8")
        cls.sql = "\n".join((cls.viewer_sql, cls.broad_rpc_sql, cls.boundary_sql, cls.exhaustive_sql))
        cls.normalized = " ".join(cls.sql.lower().split())
        cls.exhaustive_normalized = " ".join(cls.exhaustive_sql.lower().split())

    def _function(self, name: str) -> str:
        match = re.search(
            rf"create or replace function public\.{name}\(.*?\n\$\$;",
            self.sql,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(match, name)
        return match.group(0)

    def test_migrations_parse_and_are_transactional(self):
        for sql in (self.viewer_sql, self.broad_rpc_sql, self.boundary_sql, self.exhaustive_sql):
            self.assertGreaterEqual(len(parse_sql(sql)), 5)
            normalized = " ".join(sql.lower().split())
            self.assertIn("begin;", normalized)
            self.assertTrue(normalized.endswith("commit;"))

    def test_direct_vehicle_select_is_operator_or_higher_only(self):
        self.assertIn("drop policy if exists vehicles_select_approved on public.vehicles", self.normalized)
        self.assertIn(
            "create policy vehicles_select_operator on public.vehicles for select "
            "to authenticated using (public.is_pdc_role('operator'))",
            self.normalized,
        )
        policy = re.search(
            r"create policy vehicles_select_operator.*?using\s*\((.*?)\);",
            self.normalized,
        )
        self.assertIsNotNone(policy)
        self.assertNotIn("'viewer'", policy.group(1))

    def test_existing_broad_core_snapshot_is_operator_or_higher_only(self):
        body = " ".join(self._function("get_vehicle_core_snapshot").lower().split())
        self.assertIn("security definer", body)
        self.assertIn("stable", body)
        self.assertIn("set search_path = public", body)
        self.assertIn("not public.is_pdc_role('operator')", body)
        self.assertNotIn("is_pdc_role('viewer')", body)
        self.assertIn("return public.vehicle_master_response(false, 'permission_denied'", body)
        self.assertIn(
            "revoke all on function public.get_vehicle_core_snapshot() from public, anon, authenticated",
            self.normalized,
        )
        self.assertIn(
            "grant execute on function public.get_vehicle_core_snapshot() to authenticated",
            self.normalized,
        )

    def test_other_broad_vehicle_surfaces_are_operator_or_higher_only(self):
        workshop = " ".join(self._function("get_workshop_snapshot").lower().split())
        self.assertIn("security definer", workshop)
        self.assertIn("stable", workshop)
        self.assertIn("set search_path = public", workshop)
        self.assertIn("perform public.require_pdc_role('operator')", workshop)
        self.assertNotIn("require_pdc_role('viewer')", workshop)
        self.assertIn(
            "create policy vehicle_aliases_select_operator on public.vehicle_aliases "
            "for select to authenticated using (public.is_pdc_role('operator'))",
            self.normalized,
        )
        alias_policy = re.search(
            r"create policy vehicle_aliases_select_operator.*?using\s*\((.*?)\);",
            self.normalized,
        )
        self.assertIsNotNone(alias_policy)
        self.assertNotIn("'viewer'", alias_policy.group(1))
        self.assertIn(
            "revoke all on function public.get_workshop_snapshot(date, date) "
            "from public, anon, authenticated",
            self.normalized,
        )
        self.assertIn(
            "grant execute on function public.get_workshop_snapshot(date, date) to authenticated",
            self.normalized,
        )
        self.assertIn(
            "revoke all on function public.workshop_booking_snapshot(uuid) "
            "from public, anon, authenticated",
            self.normalized,
        )

    def test_exhaustive_viewer_graph_and_default_privileges_are_hardened(self):
        normalized = self.exhaustive_normalized
        self.assertIn(
            "alter default privileges for role postgres in schema public "
            "revoke execute on functions from public, anon, authenticated",
            normalized,
        )

        policy_pairs = {
            "ai_intake_config": "ai_intake_config_select_approved",
            "ai_mapping_rules": "ai_mapping_rules_select_approved",
            "audit_events": "audit_events_select_approved",
            "deleted_completed_vehicles": "deleted_completed_select_approved",
            "import_runs": "import_runs_select_approved",
            "label_print_events": "label_print_events_select_approved",
            "salespeople": "salespeople_select_by_role",
            "sublet_providers": "sublet_providers_select_by_role",
            "vehicle_intelligence_summaries": "vehicle_intelligence_summaries_select_viewer",
            "vehicle_lifecycle_resolver_revision": "vehicle_lifecycle_resolver_revision_select_approved",
            "vehicle_master_revision": "vehicle_master_revision_select_approved",
            "vehicle_movements": "movements_select_approved",
            "vehicle_parts_updates": "parts_select_approved",
            "vehicle_work_items": "work_items_select_approved",
            "workshop_bays": "workshop_bays_select_by_role",
            "workshop_booking_assignments": "workshop_booking_assignments_select_approved",
            "workshop_booking_history": "workshop_booking_history_select_approved",
            "workshop_bookings": "workshop_bookings_select_approved",
            "workshop_parts_overrides": "workshop_parts_overrides_select_approved",
            "workshop_revision": "workshop_revision_select_approved",
            "workshop_settings": "workshop_settings_select_approved",
            "workshop_stages": "workshop_stages_select_approved",
            "workshop_technicians": "workshop_technicians_select_by_role",
            "ai_workshop_commands": "ai_workshop_commands_select_own_or_importer",
        }
        for table, policy in policy_pairs.items():
            expected = (
                f"create policy {policy} on public.{table} for select to authenticated "
                "using (public.is_pdc_role('operator'::public.pdc_role))"
            )
            self.assertIn(expected, normalized, table)

        for function in (
            "get_vehicle_intelligence_snapshot", "get_workshop_configuration",
            "list_salespeople", "list_sublet_providers", "list_technicians",
            "list_workshop_bays", "resolve_vehicle_lifecycle_identity",
            "workshop_current_revision",
        ):
            start = normalized.rfind(f"create or replace function public.{function}(")
            self.assertGreaterEqual(start, 0, function)
            end = normalized.find("$function$", start)
            end = normalized.find("$function$", end + len("$function$"))
            body = normalized[start:end]
            self.assertTrue(
                "require_pdc_role('operator'" in body or "is_pdc_role('operator'" in body,
                function,
            )
            self.assertNotIn("require_pdc_role('viewer'", body, function)
            self.assertNotIn("is_pdc_role('viewer'", body, function)

        for signature in (
            "apply_vehicle_master_import(text,text,text,jsonb,integer,text)",
            "bump_vehicle_intelligence_revision(uuid)",
            "workshop_conflict_payload(uuid,text)",
            "workshop_find_bay_conflict(uuid,uuid,timestamp with time zone,timestamp with time zone)",
            "workshop_find_technician_conflict(uuid,uuid,timestamp with time zone,timestamp with time zone)",
            "workshop_lock_resources(uuid,uuid)",
            "workshop_normalize_start_date(timestamp with time zone)",
            "workshop_parts_ready(uuid)",
            "workshop_resolve_bay_id(text,integer)",
            "workshop_resolve_stage_id(text)",
            "workshop_upsert_primary_assignment(uuid,uuid,timestamp with time zone,timestamp with time zone,text)",
            "workshop_write_history(uuid,text,jsonb,jsonb,jsonb)",
        ):
            self.assertIn(
                f"revoke all on function public.{signature} from public, anon, authenticated",
                normalized,
                signature,
            )

    def test_narrow_viewer_contract_has_exact_columns_select_and_scope(self):
        function = self._function("get_restricted_pilot_vehicle_snapshot")
        compact = " ".join(function.lower().split())
        declared = re.search(r"returns table\s*\((.*?)\)\s*language", function, re.I | re.S)
        self.assertIsNotNone(declared)
        declared_columns = [" ".join(item.lower().split()) for item in declared.group(1).split(",")]
        self.assertEqual(declared_columns, EXPECTED_COLUMNS)

        selected = re.search(r"return query\s+select\s+(.*?)\s+from public\.vehicles v", function, re.I | re.S)
        self.assertIsNotNone(selected)
        selected_expressions = [" ".join(item.lower().split()) for item in selected.group(1).split(",")]
        self.assertEqual(selected_expressions, EXPECTED_SELECT)

        self.assertIn("language plpgsql", compact)
        self.assertIn("stable", compact)
        self.assertIn("security definer", compact)
        self.assertIn("set search_path = public", compact)
        self.assertIn("perform public.require_pdc_role('viewer')", compact)
        self.assertIn("v.source_system = 'browser_local_c4'", compact)
        self.assertIn("v.source_batch_id = 'c6-real-pilot-7d862abbe37b'", compact)
        for prohibited in (
            "customer_name", "source_payload", "vin", "stock_number",
            "toyota_order_number", "registration", "make", "model",
            "updated_at", "created_at",
        ):
            self.assertNotIn(prohibited, compact)

    def test_narrow_contract_is_authenticated_only(self):
        self.assertIn(
            "revoke all on function public.get_restricted_pilot_vehicle_snapshot(uuid) from public, anon, authenticated",
            self.normalized,
        )
        self.assertIn(
            "grant execute on function public.get_restricted_pilot_vehicle_snapshot(uuid) to authenticated",
            self.normalized,
        )


if __name__ == "__main__":
    unittest.main()
