from __future__ import annotations

import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828050000_684_authenticated_provider_import_agentic_compatibility.sql"
EXPECTED = "567b756d2b1742e9aa5d1d02451af0c512caa5bd5b3bb54be13bd1af4997fa29"


class AuthenticatedProviderImportAgentic684ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_source_is_exact_append_only_staging_transaction(self):
        self.assertEqual(hashlib.sha256(self.sql.encode()).hexdigest(), EXPECTED)
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        self.assertNotRegex(self.lower, r"\b(drop|delete|truncate)\s+(table|from|function|schema)")
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.lower)
        for marker in (
            "20260828010000", "20260828020000", "20260828030000", "20260828040000",
            "20260828050000", "683_uid514_capability_mint_replay_repair",
            "pdc_authenticated_provider_import_agentic_compatibility_controls_684",
            "pdc_authenticated_provider_import_agentic_compatibility_history_684",
            "pdc_monitor_authenticated_uid514_claim_scope_684",
            "pdc_monitor_authenticated_uid514_source_scope_684",
            "attest_pdc_monitor_provider_email_observation_684",
            "import_pdc_monitor_jobcard_attachment_authenticated_684",
            "read_pdc_monitor_jobcard_attachment_receipt_authenticated_684",
            "read_pdc_agentic_email_context_authenticated_684",
            "record_pdc_agentic_email_plan_authenticated_684",
            "execute_pdc_agentic_email_action_authenticated_684",
            "pdc_agentic_apply_action_authenticated_684",
            "finalize_pdc_agentic_email_plan_authenticated_684",
            "force row level security", "immutable", "administrator-only disable",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_exact_identity_provider_and_retained_inventory_are_server_bound(self):
        for marker in (
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b", "sales@broometoyota.com.au",
            "authenticated", "importer", "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44", "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348",
            "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
            "12fe383d-5c1e-5801-96e4-f67cf3e3bb57", "pdc_pmb_email", "pmbcontroller@gmail.com",
            "imap_uid:514", "25751401", "102e286d-1799-4c97-8e45-e0da9fb31c63",
            "440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280",
            "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4",
            "66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff",
            "b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1",
            "ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae",
            "source_total_hours", "7.46", "stale_expected_hours", "13.10",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("jsonb_build_object('dkim_aligned',false,'dmarc_aligned',true", self.lower)
        self.assertIn("'gmail_authentication_results',true", self.lower)
        self.assertIn("'spf_aligned',true", self.lower)

    def test_layout_preserves_zeroes_and_tow_bar_mapping(self):
        expected = [
            (1, "OP1", "owner_supplied_document", "Fill Fuel", "0"),
            (2, "OP2", "owner_supplied_document", "PDI", "0.70"),
            (3, "OP3", "fabrication", "HDA Tray", "0"),
            (4, "OP4", "fitting", "Steel Bull Bar", "5.18"),
            (5, "OP5", "fitting", "Tow Bar long tongue", "1.58"),
        ]
        for row, (no, operation, work, description, hours) in enumerate(expected, 1):
            self.assertIn(f'"source_row_no":{no}', self.lower)
            self.assertIn(f'"operation_no":"{operation.lower()}"', self.lower)
            self.assertIn(f'"work_key":"{work.lower()}"', self.lower)
            self.assertIn(f'"description":"{description.lower()}"', self.lower)
            self.assertIn(f'"estimated_hours":{hours}', self.lower)
        self.assertIn("p_required_work is distinct from '[\"fabrication\",\"fitting\"]'::jsonb", self.lower)
        self.assertIn("source_layout_or_hours_mismatch", self.lower)
        self.assertIn("tow_bar_work_key','fitting", self.lower)
        self.assertIn("zero_hours_preserved", self.lower)

    def test_acl_is_authenticated_only_and_legacy_surfaces_are_closed(self):
        self.assertNotRegex(self.lower, r"grant execute[\s\S]{0,180}\bto\s+(anon|service_role|pdc_email_monitor)\b")
        for signature in (
            "attest_pdc_monitor_provider_email_observation_684", "import_pdc_monitor_jobcard_attachment_authenticated_684",
            "read_pdc_monitor_jobcard_attachment_receipt_authenticated_684", "read_pdc_agentic_email_context_authenticated_684",
            "record_pdc_agentic_email_plan_authenticated_684", "execute_pdc_agentic_email_action_authenticated_684",
            "pdc_agentic_apply_action_authenticated_684", "finalize_pdc_agentic_email_plan_authenticated_684",
        ):
            self.assertRegex(self.lower, rf"grant execute on function[\s\S]*{re.escape(signature)}[\s\S]*to authenticated")
        for legacy in (
            "attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)",
            "import_pdc_monitor_jobcard_attachment_279(text,uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)",
            "read_pdc_monitor_jobcard_attachment_receipt_279(text,uuid)",
            "import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)",
        ):
            self.assertIn(f"revoke all on function public.{legacy}", self.lower)

    def test_rollback_and_rehearsal_markers_are_fail_closed(self):
        for marker in (
            "admin_rollback_pdc_authenticated_provider_import_agentic_compatibility_684",
            "compatibility_rollback_applied", "compatibility_rollback_replayed",
            "pdc_684_compatibility_history_immutable", "pdc_684_forward_postcondition_failed",
            "uid514_processed',false", "mailbox_contacted',false", "production_writes',false",
            "pdc_provider_email_observations where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid)<>0",
            "queue_attempts',8", "status','failed",
        ):
            self.assertIn(marker.lower(), self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
