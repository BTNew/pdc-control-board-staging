from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260829163000_exact_stock_reset_13080534_13017855_phase1.sql").read_text(encoding="utf-8")
CONTROLLER = (ROOT / "scripts/apply_exact_stock_reset_20260828.py").read_text(encoding="utf-8")
ROLLBACK = (ROOT / "scripts/rollback_exact_stock_reset_20260828.py").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/verify_exact_stock_reset_20260828.py").read_text(encoding="utf-8")


class ExactStockResetContractTests(unittest.TestCase):
    def test_exact_stock_and_identity_binding(self):
        for value in (
            "13080534", "13017855", "5721cafa-2b60-4d45-b69c-ab907eaf178e",
            "e39eb741-cf03-44f2-8a75-54362ecc8a26", "7fe33693-f519-5152-bbe0-9cc799c4ae33",
            "J139125422", "MR0MABAV902402464", "cdsmnqxtyyoeoznmbidd",
            "20260829151000", "752_reactivate_exact_email_monitor_after_751",
        ):
            self.assertIn(value, SQL)
        self.assertIn("stock_number_normalized='13080534'", SQL)
        self.assertIn("stock_number_normalized='13017855'", SQL)
        self.assertIn("PDC_EXACT_RESET_20260828_PREFLIGHT_BINDING_FAILED", SQL)

    def test_wrong_message_sender_and_attachment_are_fail_closed(self):
        for value in (
            "craig.watson@broometoyota.com.au", "imap_uid:680", "imap_uid:681",
            "f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916",
            "d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493",
            "0f190df5-09df-4df6-a111-66f658318d57", "842405e4-5209-45f5-9729-0d22327daeaa",
        ):
            self.assertIn(value, SQL)
        self.assertIn("array_agg(id ORDER BY received_at DESC NULLS LAST,id DESC)", SQL)
        self.assertIn("count(*) FROM public.ai_email_attachments", SQL)

    def test_replay_scope_is_exactly_two_and_does_not_reenable_uid514(self):
        self.assertIn("CREATE TABLE public.pdc_exact_email_reimport_authorizations_20260828", SQL)
        self.assertIn("status text NOT NULL CHECK(status='authorized')", SQL)
        self.assertIn("one_time boolean NOT NULL CHECK(one_time)", SQL)
        self.assertIn("consumed boolean NOT NULL DEFAULT false CHECK(NOT consumed)", SQL)
        self.assertIn("count(*) FROM public.pdc_exact_email_reimport_authorizations_20260828 WHERE status='authorized'", SQL)
        self.assertNotIn("UPDATE public.pdc_email_monitor_pilot", SQL)
        self.assertNotIn("UPDATE public.monitored_mailboxes", SQL)
        self.assertNotIn("minimum_uid=", SQL)
        self.assertNotIn("uid514", SQL.lower())
        self.assertNotRegex(SQL, r"(?is)delete\s+from[^;]*13000769")

    def test_forced_rls_receipt_and_postconditions(self):
        self.assertIn("FORCE ROW LEVEL SECURITY", SQL)
        self.assertIn("PDC_EXACT_RESET_IDENTITY_OR_POSTCONDITION_FAILED", SQL)
        self.assertIn("PDC_EXACT_RESET_13000769_CHANGED", SQL)
        self.assertIn("production_untouched boolean NOT NULL CHECK(production_untouched)", SQL)
        self.assertIn("trigger_reset_restored boolean NOT NULL CHECK(trigger_reset_restored)", SQL)
        self.assertIn("NOTIFY pgrst", SQL)

    def test_snapshot_and_head_are_bound_by_controller(self):
        for value in (
            "7f1c3315-ac42-46fb-99ed-70b43ef89f80",
            "6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518",
            "8de3b4cb413006d6850838a83ca1648215e0e589f1f61f7e01cb9339fc4bb018",
        ):
            self.assertIn(value, SQL)
            self.assertIn(value, CONTROLLER)
        self.assertIn("head_before != HEAD", CONTROLLER)
        self.assertIn("PDC_APPROVE_EXACT_STOCK_RESET_20260828", CONTROLLER)

    def test_rollback_is_staging_only_and_fail_closed(self):
        self.assertIn("verify-only", ROLLBACK)
        self.assertIn("PDC_EXACT_RESET_ROLLBACK_REQUIRES_SEPARATE_EXPLICIT_RESTORE_APPROVAL", ROLLBACK)
        self.assertIn("PDC_EXACT_RESET_ROLLBACK_NON_STAGING_TARGET", ROLLBACK)
        self.assertIn("PDC_EXACT_RESET_ROLLBACK_ARTIFACT_HASH_MISMATCH", ROLLBACK)
        self.assertIn("transaction rollback on any mismatch", SQL.lower())

    def test_13000769_exclusion_and_runtime_entrypoint(self):
        self.assertIn("d777b071-a2b0-5367-893b-aa83a07fcfce", CONTROLLER)
        self.assertIn("untouched_13000769", VERIFY)
        self.assertIn("C:/ProgramData/PDCMonitor/Staging/CURRENT", VERIFY)
        self.assertIn("runtime_launcher.py --mode monitor", VERIFY)
        self.assertIn("2026.08.65", VERIFY)


if __name__ == "__main__":
    unittest.main()
