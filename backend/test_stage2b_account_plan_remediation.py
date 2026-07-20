"""Offline regression checks for restricted live-pilot account-plan remediation."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "032_restricted_pilot_viewer_vehicle_contract.sql"
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
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.normalized = " ".join(cls.sql.lower().split())

    def _function(self, name: str) -> str:
        match = re.search(
            rf"create or replace function public\.{name}\(.*?\n\$\$;",
            self.sql,
            flags=re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(match, name)
        return match.group(0)

    def test_migration_parses_and_is_transactional(self):
        statements = parse_sql(self.sql)
        self.assertGreaterEqual(len(statements), 12)
        self.assertIn("\nbegin;\n", self.sql.lower())
        self.assertTrue(self.normalized.endswith("commit;"))

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
