import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "027_stage2a_assignment_interval_enforcement.sql"
SQL = MIGRATION.read_text(encoding="utf-8")


def function_sql(name):
    match = re.search(
        rf"create or replace function public\.{re.escape(name)}\(.*?\n\$\$;",
        SQL,
        re.DOTALL | re.IGNORECASE,
    )
    if not match:
        raise AssertionError(f"missing function replacement: {name}")
    return match.group(0)


class Stage2AAssignmentIntervalEnforcementTests(unittest.TestCase):
    def test_applied_026_is_not_replaced_or_edited(self):
        previous = ROOT / "supabase" / "migrations" / "026_stage2a_final_review_remediation.sql"
        self.assertTrue(previous.exists())
        self.assertIn("Applied migration 026 remains unchanged", SQL)

    def test_every_interval_mutation_checks_leave_before_mutation(self):
        expectations = {
            "workshop_move_booking": (
                "workshop_technician_leave_date(v_technician_id, p_scheduled_start_at, v_end)",
                "update public.workshop_bookings",
                "workshop_upsert_primary_assignment(p_booking_id, v_technician_id, p_scheduled_start_at, v_end",
            ),
            "workshop_resize_booking": (
                "workshop_technician_leave_date(v_technician_id, v_booking.scheduled_start_at, v_end)",
                "update public.workshop_bookings",
                "workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_booking.scheduled_start_at, v_end",
            ),
            "resume_workshop_work": (
                "workshop_technician_leave_date(v_technician_id, v_new_start, v_new_end)",
                "update public.workshop_bookings",
                "workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_new_start, v_new_end",
            ),
        }
        for name, (leave_call, booking_update, assignment_update) in expectations.items():
            with self.subTest(function=name):
                body = function_sql(name)
                leave_index = body.index(leave_call)
                self.assertLess(leave_index, body.index(booking_update))
                self.assertLess(leave_index, body.index(assignment_update))
                self.assertIn("'error', 'technician_on_leave'", body)
                self.assertIn("'date', v_leave_date", body)
                self.assertIn("'technician_id', v_technician_id", body)

    def test_all_changed_interval_upserts_from_prior_migrations_are_covered(self):
        prior_sql = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
            if not path.name.startswith("027_")
        )
        changed_interval_notes = {"'moved'", "'resized'", "'resume_rescheduled'"}
        for note in changed_interval_notes:
            self.assertIn(note, prior_sql)
            self.assertIn(note, SQL)
        self.assertEqual(SQL.count("'error', 'technician_on_leave'"), 3)

    def test_window_date_scope_and_day_validation_is_structured(self):
        body = function_sql("update_workshop_configuration")
        for reason in (
            "window_date_not_valid_iso_date",
            "window_scope_must_be_string",
            "window_scope_unknown",
            "window_day_must_be_string",
            "window_day_unknown",
            "window_scope_day_conflict",
            "window_time_not_hhmm",
            "window_start_not_before_end",
        ):
            self.assertIn(f"'reason', '{reason}'", body)
        self.assertIn("workshop_is_exact_iso_date(v_elem->>'date')", body)
        self.assertIn("'global', 'working_day'", body)
        for weekday in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"):
            self.assertIn(weekday, body)

    def test_protected_grants_are_explicit_and_public_anon_stay_revoked(self):
        signatures = (
            "update_workshop_configuration(text, integer, jsonb)",
            "workshop_move_booking(uuid, integer, text, integer, timestamptz, integer, jsonb)",
            "workshop_resize_booking(uuid, integer, integer, jsonb)",
            "resume_workshop_work(uuid, integer, jsonb)",
        )
        lowered = SQL.lower()
        for signature in signatures:
            with self.subTest(signature=signature):
                self.assertIn(f"revoke all on function public.{signature} from public, anon;", lowered)
                self.assertIn(f"grant execute on function public.{signature} to authenticated;", lowered)
        self.assertNotRegex(lowered, r"grant\s+execute\s+on\s+function\s+public\..*\s+to\s+(anon|public)")

    def test_historical_rows_are_not_rewritten(self):
        self.assertNotIn("delete from public.workshop_", SQL.lower())
        self.assertNotIn("update public.workshop_booking_history", SQL.lower())
        self.assertNotIn("update public.workshop_booking_assignments\n  set scheduled", SQL.lower())


if __name__ == "__main__":
    unittest.main()
