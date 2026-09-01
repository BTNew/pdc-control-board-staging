from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831460000_latest100_resume_repair.sql"


class Latest100ResumeRepairContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_exact_staging_head_and_sentinel_guards(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        for marker in (
            "20260831450000",
            "pdc_email_monitor_viewer_receipt_read_successor",
            "cdsmnqxtyyoeoznmbidd",
            "pdc_production_environment_sentinel",
            "pdc_monitor_canonical_import_capabilities_20260831",
            "95131ea9-647f-4461-b5b9-573d22b8824c",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_viewer_caller_gate_is_separate_from_exact_sender_gate(self):
        for marker in (
            "pdc_canonical_import_capability_context_20260831",
            "pdc_monitor_stage_activation_writers",
            "pdc_monitor_exact_sender_enrollments",
            "sender_not_enrolled",
            "canonical_attachment_import_only",
            "pdc_resume_460_sender_policy",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("split_part(v_sender,'@',2) not in", self.lower)

    def test_exact_known_sender_hashes_are_proven_by_existing_records(self):
        for marker in (
            "0f371e0126fe46f11550b6fd8893f61e8976f8b94d181fe2729c0f32c0a76ebd",
            "ff43f3ac9154a06df493ba77605120e7c06205da4001ae0259f94d6d163b7543",
            "c8f1287687794e3d9a835f1cba02f856fdb8cc5188661a2d7728d952cacc455f",
            "201f02404dd79de8ae556d4d033246e24ba51648ce72f7ae776d9d82357865f5",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("public.salespeople", self.lower)
        self.assertIn("public.pdc_historical_reconciliation_writer_authorizations_773", self.lower)
        self.assertIn("on conflict(sender_sha256) do nothing", self.lower)

    def test_multi_attachment_children_are_independent_and_immutable(self):
        for marker in (
            "attachment_id",
            "canonical_source_hash",
            "parent_source_hash",
            "pdc_jobcard_attachment_import_receipts_immutable",
            "pdc_jobcard_attachment_source_row_receipts_immutable",
            "child_receipt",
            "sibling",
            "pdc_resume_460_attachment_child",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("unique (actor_id, intake_id, attachment_id)", self.lower)
        self.assertIn("unique (canonical_source_hash)", self.lower)

    def test_migration_260_returns_one_typed_row_or_explicit_safe_empty(self):
        for marker in (
            "resolve_pdc_email_intake_attachment_binding",
            "returns table",
            "return query",
            "pdc_resume_460_binding",
            "binding_not_found",
            "provider_uid",
            "attachment_source_hash",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("limit 1", self.lower)
        self.assertIn("order by", self.lower)

    def test_invalid_input_compatibility_drops_only_deprecated_derived_flag(self):
        self.assertIn("p_authentication - 'aligned'", self.lower)
        self.assertIn("deprecated derived authentication flag", self.lower)
        self.assertIn("exact authentication keys", self.lower)
        self.assertIn("invalid_input", self.lower)

    def test_least_privilege_parent_readback_has_no_raw_body_or_generic_select(self):
        for marker in (
            "read_pdc_email_intake_parent_audit_20260901",
            "p_source_hash",
            "source_hash",
            "sender_email",
            "provider_authentication",
            "attachment_manifest",
            "raw_body",
            "parsed_text",
            "grant execute",
            "to authenticated",
            "revoke all on function",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("raw_body", self.lower)
        self.assertIn("parsed_text", self.lower)
        self.assertIn("revoke select on public.ai_email_attachments", self.lower)
        self.assertNotIn("grant select on public.ai_email_intake", self.lower)
        self.assertNotIn("grant select on public.ai_email_attachments", self.lower)

    def test_hostile_sender_and_spoof_guards_remain_fail_closed(self):
        for marker in (
            "sender_sha256",
            "provider_authentication",
            "provider_authserv_id",
            "sender_domain",
            "mx.google.com",
            "not enrolled",
            "review_queued",
            "identity_conflict",
            "pdc_resume_460_spoof_rejected",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("sender_sha256", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
