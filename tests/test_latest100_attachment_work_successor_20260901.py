from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901010000_latest100_attachment_work_receipt_successor.sql"


class Latest100AttachmentWorkSuccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_staging_guard_and_schema_reload_are_bounded(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        for marker in (
            "20260831461000",
            "latest100_force_rls_successor",
            "cdsmnqxtyyoeoznmbidd",
            "pdc_production_environment_sentinel",
            "pdc_email_intake_work_receipts_20260901",
            "pdc_monitor_canonical_import_capabilities_20260831",
            "notify pgrst,'reload schema'",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)
        self.assertNotIn("grant execute on function public.pdc_latest100", self.lower)

    def test_old_receipt_audit_is_read_only_and_digest_guarded(self):
        for marker in (
            "pg_temp.pdc_latest100_old_work_receipt_digest",
            "pdc.latest100.old_work_before",
            "pdc_email_intake_work_receipts_immutable",
            "old_work_after",
            "old_work_before",
            "historical receipt",
            "preserve",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("update public.pdc_email_intake_work_receipts", self.lower)
        self.assertNotIn("delete from public.pdc_email_intake_work_receipts", self.lower)

    def test_attachment_scoped_lookup_allows_only_genuine_identity_difference(self):
        for marker in (
            "attachment_id uuid not null",
            "unique(actor_id,intake_id,attachment_id)",
            "where actor_id=v_actor and intake_id=p_intake_id and attachment_id=v_attachment_id",
            "where r.intake_id=p_intake_id and r.attachment_id=v_attachment_id",
            "work_receipt_duplicate_zero_add",
            "work_receipt_replay_conflict",
            "work_receipt_identity_conflict",
            "pdc-email-intake-work-20260901:",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("unique(source_hash)", self.lower)
        self.assertNotIn("unique(intake_id)", self.lower)

    def test_true_duplicate_is_zero_add_and_conflicting_identity_fails_closed(self):
        for marker in (
            "if v_existing.request_sha256=v_request",
            "pdc_latest100_work_receipt_response_20260901(v_existing.work_receipt_id,'work_receipt_duplicate_zero_add')",
            "if v_existing.source_hash<>v_source",
            "or v_existing.extraction_hash<>v_extraction_hash",
            "return public.navision_backend_response(false,'work_receipt_replay_conflict'",
            "on conflict (actor_id,intake_id,attachment_id) do nothing",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("old work receipt", self.lower)
        self.assertIn("a different actor is a genuinely distinct old work receipt identity", self.lower)

    def test_no_runtime_broadening_or_production_path(self):
        for marker in (
            "security definer",
            "set search_path=pg_catalog,public,extensions",
            "authenticated",
            "canonical_attachment_import_only",
            "service_role",
            "mailbox",
            "outbound",
            "production",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("grant all", self.lower)
        self.assertNotIn("grant insert", self.lower)
        self.assertNotIn("grant update", self.lower)
        self.assertNotIn("grant delete", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
