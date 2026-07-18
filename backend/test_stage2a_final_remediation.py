import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "026_stage2a_final_review_remediation.sql"
SQL = MIGRATION.read_text(encoding="utf-8")


class Stage2AFinalRemediationMigrationTests(unittest.TestCase):
    def test_viewer_direct_select_is_active_only_for_all_four_tables(self):
        expectations = {
            "workshop_technicians": "active",
            "salespeople": "active",
            "sublet_providers": "active",
            "workshop_bays": "is_active",
        }
        for table, active_column in expectations.items():
            with self.subTest(table=table):
                pattern = rf"create policy \w+ on public\.{table}.*?using \(public\.is_pdc_role\('operator'\) or \(public\.current_pdc_user_role\(\) = 'viewer' and {active_column}\)\);"
                self.assertRegex(SQL, re.compile(pattern, re.DOTALL | re.IGNORECASE))

    def test_broad_viewer_policies_are_removed_not_layered(self):
        for policy in (
            "workshop_technicians_select_approved",
            "salespeople_select_approved",
            "sublet_providers_select_approved",
            "workshop_bays_select_approved",
        ):
            self.assertIn(f"drop policy if exists {policy}", SQL.lower())
        self.assertNotRegex(SQL, r"using \(public\.is_pdc_role\('viewer'\)\)")

    def test_exact_iso_and_uuid_validation_precede_casts(self):
        self.assertIn("workshop_is_exact_iso_date", SQL)
        self.assertIn("to_char(v_date, 'YYYY-MM-DD') = p_value", SQL)
        uuid_guard = SQL.index("leave_technician_id_not_valid_uuid")
        uuid_cast = SQL.index("where id = (v_elem->>'technician_id')::uuid")
        self.assertLess(uuid_guard, uuid_cast)
        self.assertIn("closure_date_not_valid_iso_date", SQL)
        self.assertIn("leave_date_not_valid_iso_date", SQL)

    def test_leave_is_enforced_for_create_and_reassign_with_structured_error(self):
        self.assertEqual(SQL.count("'error', 'technician_on_leave'"), 2)
        self.assertIn("workshop_technician_leave_date(p_technician_id, p_scheduled_start_at, v_end)", SQL)
        self.assertIn("workshop_technician_leave_date(p_technician_id, v_booking.scheduled_start_at, v_booking.scheduled_end_at)", SQL)
        self.assertIn("'date', v_leave_date", SQL)
        self.assertIn("'technician_id', p_technician_id", SQL)

    def test_protected_write_grants_remain_rpc_only(self):
        self.assertNotRegex(SQL.lower(), r"grant\s+(insert|update|delete|all)\s+on\s+(table\s+)?public\.(workshop_|salespeople|sublet_providers)")
        self.assertIn("grant execute on function public.update_workshop_configuration", SQL.lower())


if __name__ == "__main__":
    unittest.main()
