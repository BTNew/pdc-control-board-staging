from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828070000_686_authenticated_acceptance_campaign_fixtures.sql"
EXPECTED = "dd349b6c5e6ab2226e3fb720463f5bcdd4b7829edaf8667c99c7bc83db584458"


class AuthenticatedAcceptanceCampaign686ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_append_only_guarded_staging_migration(self):
        self.assertEqual(hashlib.sha256(self.sql.encode()).hexdigest(), EXPECTED)
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        self.assertNotRegex(self.lower, r"\b(drop|truncate)\s+(table|function|schema)")
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.lower)
        for marker in (
            "20260828060000", "686_authenticated_email_ai_final_functional_remediation",
            "pdc_authenticated_email_acceptance_campaign_runs_686",
            "pdc_authenticated_email_acceptance_campaign_fixtures_686",
            "pdc_authenticated_email_acceptance_plans_686",
            "pdc_authenticated_email_acceptance_action_receipts_686",
            "pdc_authenticated_email_acceptance_final_receipts_686",
            "pdc_monitor_authenticated_acceptance_scope_686",
            "create_pdc_authenticated_acceptance_campaign_686",
            "record_pdc_authenticated_email_acceptance_plan_686",
            "execute_pdc_authenticated_email_acceptance_action_686",
            "finalize_pdc_authenticated_email_acceptance_plan_686",
            "cleanup_pdc_authenticated_acceptance_campaign_686",
            "read_pdc_authenticated_email_acceptance_context_686",
            "read_pdc_authenticated_acceptance_campaign_686",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_exact_actor_binding_and_production_guards(self):
        for marker in (
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "sales@broometoyota.com.au", "authenticated", "importer",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348",
            "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
            "pdc_production_environment_sentinel", "production_writes", "task_enabled",
            "mailbox_contacted", "uid514_processed", "pdc_monitor_authenticated_active_scope_674",
            "pdc_686_exact_685_head_or_uid514_prestate_mismatch",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("auth.role()<>'authenticated'", self.lower)
        self.assertIn("auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid", self.lower)

    def test_date_and_action_contract_is_fail_closed_and_ordered(self):
        for marker in (
            "pdc_email_resolve_business_date_686",
            "next non-past", "existing_date",
            "parts_eta", "parts_complete", "sublet_booking_date", "unparsed",
            "parts_eta_required", "sublet_existing_booking_required",
            "applied_and_verified", "already_correct", "blocked_with_exact_reason",
            "genuinely_ambiguous", "dependency_order",
            "2027-06-12", "2026-09-15", "2026-09-10",
            "booking_created',false", "provider_created',false", "location_changed',false",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertRegex(self.lower, r"array\['parts_eta','parts_complete','sublet_booking_date'\]")

    def test_synthetic_source_and_uid514_are_separate(self):
        self.assertIn("provider_uid ~ '^imap_uid:[0-9]+$'", self.lower)
        self.assertIn("substring(provider_uid from 10)::bigint>=515", self.lower)
        self.assertIn("pdc-acceptance-686:", self.lower)
        self.assertIn("synthetic fixture", self.lower)
        self.assertIn("imap_uid:514", self.lower)
        self.assertIn("uid514 is never reprocessed", self.lower)
        self.assertIn("manual_booking_date','2026-09-10'", self.lower)

    def test_immutable_receipts_narrow_grants_and_projection_repair(self):
        for marker in (
            "pdc_686_acceptance_receipt_immutable",
            "pdc_email_vehicle_location_snapshot_pre_686",
            "navision_board_activations",
            "normalized_data->>'batch'",
            "source_batch_id in('14450','37047')",
            "supabase_realtime",
            "pdc_email_vehicle_revision",
            "realtime revision publication preserved",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("execute format('revoke all on table public.%i", self.lower)
        self.assertNotRegex(self.lower, r"grant\s+(select|insert|update|delete|all)\s+on\s+(table\s+)?public\.pdc_authenticated_email_acceptance_campaign")
        self.assertNotRegex(self.lower, r"grant execute on function public\.[^;]+ to (anon|service_role|pdc_email_monitor)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
