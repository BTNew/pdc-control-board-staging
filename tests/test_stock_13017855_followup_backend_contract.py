from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / 'supabase/staging_only/20260830080000_stock_13017855_integrity_and_lifecycle_guards.sql').read_text(encoding='utf-8')


class Stock13017855FollowupBackendContract(unittest.TestCase):
    def test_exact_staging_predecessor_and_target(self):
        for marker in (
            "20260830073000",
            "771_monitor_compatibility_after_770",
            "b02645d9-f411-5de0-97d1-905966b5feae",
            "f8e932e2-0699-46a5-81e7-0cc3f071eaac",
            "13017855",
            "J139125422",

            "20260829_101700_3c31d6",
            "8660fc9e-09cd-5fb5-9bf9-cbc577a013bb",
        ):
            self.assertIn(marker, SQL)
        self.assertIn("expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version=19)", SQL)

    def test_requirement_patch_is_non_destructive(self):
        body = SQL[SQL.index('CREATE OR REPLACE FUNCTION public.set_pdc_vehicle_work_states'):SQL.index('-- Exact, recoverable single-line removal')]
        self.assertIn("IF NOT(p_work_states ? key) THEN CONTINUE", body)
        self.assertIn("ON CONFLICT(vehicle_id,work_key) DO UPDATE", body)
        self.assertNotRegex(body, r"DELETE\s+FROM\s+public\.pdc_authenticated_email_operation_lines")
        self.assertNotRegex(body, r"DELETE\s+FROM\s+public\.vehicle_work_items")
        self.assertIn('pdc_requirement_edit_receipts_772', body)
        self.assertIn('source_operation_count', body)
        self.assertIn('source_zero_hour_count', SQL)

    def test_class_level_guards_and_exact_delete(self):
        for marker in (
            'PDC_772_SOURCE_OPERATION_DELETE_BLOCKED',
            'PDC_772_SOURCE_OPERATION_IMMUTABLE',
            'PDC_772_WORK_ITEM_DELETE_BLOCKED',
            'PDC_772_PROJECTION_DELETE_BLOCKED',
            'pdc.772.explicit_operation_delete',
            'delete_pdc_authenticated_operation_line_772',
            'p_operation_line_id uuid',
            'p_stock_number text',
            'p_job_card_number text',
            'p_operation_no text',
            'p_confirmation text',
            'p_request_hash text',
            'operation_line_already_removed',
            'undo_pdc_authenticated_operation_line_772',
            'undo_later_change_preserved',
        ):
            self.assertIn(marker, SQL)
        self.assertNotRegex(SQL, r"DELETE\s+FROM\s+public\.pdc_authenticated_email_operation_lines")

    def test_parts_booking_completion_and_restore_receipts(self):
        for marker in (
            'complete_pdc_vehicle_department_772',
            'booking_removed_from_occupancy',
            'preserve_actual_elapsed_work',
            'pdc_stock_13017855_restore_receipts_772',
            'source_operation_hours numeric(8,2) NOT NULL CHECK(source_operation_hours=17.29)',
            'source_zero_hour_count integer NOT NULL CHECK(source_zero_hour_count=6)',
            'bookings_reactivated',
            'booking_date_hash',
            'fabrication_adjustment_id',
            'parts_receipt_id',
        ):
            self.assertIn(marker, SQL)

    def test_security_and_append_only_controls(self):
        self.assertGreaterEqual(SQL.count('FORCE ROW LEVEL SECURITY'), 4)
        self.assertIn('REVOKE ALL ON FUNCTION public.set_pdc_vehicle_work_states', SQL)
        self.assertIn('GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_work_states', SQL)
        self.assertIn("INSERT INTO supabase_migrations.schema_migrations(version,name", SQL)
        self.assertIn("production sentinel and production data remain untouched", SQL.lower())


if __name__ == '__main__':
    unittest.main()
