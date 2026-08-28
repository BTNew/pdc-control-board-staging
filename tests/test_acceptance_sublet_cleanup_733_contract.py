import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260828550000_733_acceptance_sublet_cleanup.sql'


class AcceptanceSubletCleanup733ContractTests(unittest.TestCase):
    def test_cleanup_is_exact_one_shot_canonical_and_fail_closed(self):
        sql = MIGRATION.read_text(encoding='utf-8').lower()
        for marker in (
            "'cdsmnqxtyyoeoznmbidd'",
            "'47dde42b-f768-4a3f-a680-28b6ae8f36f7'::uuid",
            "'2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid",
            "'4cbd486c-78c2-42ce-987a-99d45d1eeaf4'::uuid",
            "'hermes bounded staging acceptance fixture'",
            "'2026-08-27 16:42:03.887085+00'::timestamptz",
            "'microsoft_navision'",
            "'13000765'",
            "'6ddb2053-3ca2-41aa-8ef5-0418582bcde0'",
            'create_pdc_email_ai_acceptance_693',
            'pdc_sublet_booking_instance_history',
            'cancel_pdc_sublet_booking',
            "b_after.status<>'cancelled'",
            'b_after.returned_at is not null',
            "required=false",
            'immutable',
            'force row level security',
            'enabled=false',
            'used_at',
            'revoke all on function public.run_pdc_acceptance_sublet_cleanup_733',
            'grant execute on function public.run_pdc_acceptance_sublet_cleanup_733(uuid,text) to authenticated',
            'production',
        ):
            self.assertIn(marker, sql)
        self.assertNotIn('delete from public.pdc_sublet_booking_instances', sql)
        self.assertNotIn('returned_at=clock_timestamp()', sql)
        self.assertNotIn('grant update on public.vehicle_work_items', sql)

    def test_cleanup_records_before_after_and_does_not_touch_vehicle_identity(self):
        sql = MIGRATION.read_text(encoding='utf-8').lower()
        self.assertIn('before_vehicle', sql)
        self.assertIn('after_vehicle', sql)
        self.assertIn('target_vehicle_preserved', sql)
        self.assertIn('cleanup_history', sql)
        self.assertIn('source_kind', sql)
        self.assertIn('created_by', sql)
        self.assertIn('created_at', sql)


if __name__ == '__main__':
    unittest.main(verbosity=2)
