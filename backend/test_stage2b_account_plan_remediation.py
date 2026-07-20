"""Offline regression checks for restricted live-pilot account-plan remediation."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "032_restricted_pilot_viewer_vehicle_contract.sql"


class RestrictedPilotAccountPlanMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.normalized = " ".join(cls.sql.lower().split())

    def test_migration_parses_and_is_transactional(self):
        statements = parse_sql(self.sql)
        self.assertGreaterEqual(len(statements), 8)
        self.assertIn("\nbegin;\n", self.sql.lower())
        self.assertTrue(self.normalized.endswith("commit;"))

    def test_direct_vehicle_select_is_operator_or_higher_only(self):
        self.assertIn("drop policy if exists vehicles_select_approved on public.vehicles", self.normalized)
        self.assertIn("create policy vehicles_select_operator on public.vehicles for select to authenticated using (public.is_pdc_role('operator'))", self.normalized)
        policy = re.search(
            r"create policy vehicles_select_operator.*?using\s*\((.*?)\);",
            self.normalized,
        )
        self.assertIsNotNone(policy)
        self.assertNotIn("'viewer'", policy.group(1))

    def test_narrow_viewer_contract_has_only_approved_fields_and_exact_scope(self):
        function = re.search(
            r"create or replace function public.get_restricted_pilot_vehicle_snapshot\(.*?\$\$;(?:\s*revoke)",
            self.normalized,
        )
        self.assertIsNotNone(function)
        body = function.group(0)
        for field in (
            "id", "version", "current_location", "lifecycle_state",
            "workshop_status", "active_workshop_booking_id",
        ):
            self.assertIn(field, body)
        for prohibited in ("customer_name", "source_payload", "vin", "stock_number", "toyota_order_number"):
            self.assertNotIn(prohibited, body)
        self.assertIn("perform public.require_pdc_role('viewer')", body)
        self.assertIn("v.source_system = 'browser_local_c4'", body)
        self.assertIn("v.source_batch_id = 'c6-real-pilot-7d862abbe37b'", body)

    def test_contract_is_authenticated_only(self):
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
