from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903125000_pdc_email_ai_final_acceptance_fixture_refresh_20260903.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_final_acceptance_fixture_refresh_staging_20260903.py"
GENERATION_ID = "27c7c81f-0006-4000-8000-000000000014"
FIXTURE_RPC = "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v6"
VALIDATION_RPC = "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v6"


class FinalAcceptanceFixtureRefreshContractTests(unittest.TestCase):
    def test_append_only_generation_six_migration_is_staging_guarded(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertGreater(len(parse_sql(sql)), 0)
        for marker in (
            "20260903124000",
            "20260903125000",
            "cdsmnqxtyyoeoznmbidd",
            "pdc_production_environment_sentinel",
            "PDC_20260903125000_STAGING_PRECONDITION_FAILED",
            "pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5",
            "FAILED_QUEUED_RETRY",
            GENERATION_ID,
            "generation_no=6",
            "fixture_count=14",
        ):
            self.assertIn(marker, sql)

    def test_generation_six_preserves_operation_evidence_and_recomputes_unique_lineage(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "gen_random_uuid()",
            "pdc_email_ai_successor_source_evidence_digest_20260901",
            "old_intake.extracted_data-'pdc_email_ai_evidence_digest'",
            "old_fixture.operation_source",
            "old_fixture.authoritative_snapshot",
            "operation_number_offset=90",
            "PDC_EMAIL_AI_ACCEPTANCE_GENERATION_6_SOURCE_IMMUTABLE",
            "PDC_EMAIL_AI_ACCEPTANCE_GENERATION_6_ATTACHMENT_IMMUTABLE",
            "BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments",
            "BEFORE UPDATE OR DELETE ON public.ai_email_intake",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn("UPDATE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5", sql)
        self.assertNotIn("DELETE FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5", sql)

    def test_generation_and_validation_rpcs_are_scoped_and_tables_remain_private(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            FIXTURE_RPC,
            VALIDATION_RPC,
            "pdc_email_ai_acceptance_runtime_scope_20260903()",
            "REVOKE ALL ON TABLE",
            "REVOKE ALL ON FUNCTION",
            "GRANT EXECUTE ON FUNCTION",
            "TO authenticated",
            "FROM public,anon,service_role",
            "has_table_privilege('authenticated'",
            "x->>'vehicle_id' IS DISTINCT FROM v_fixture.target_vehicle_id::text",
            "x#>>'{identity,stock_number}' IS DISTINCT FROM v_source_data->>'stock_number'",
            "x#>>'{identity,backend_record_id}' IS DISTINCT FROM v_source_data->>'backend_record_id'",
            "x#>>'{provenance,source_digest}' IS DISTINCT FROM v_fixture.source_digest",
            "x#>>'{provenance,evidence_digest}' IS DISTINCT FROM v_fixture.evidence_digest",
        ):
            self.assertIn(marker, sql)

    def test_controller_validates_fresh_current_version_plans_through_real_runtime_jwt(self):
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260903125000",
            "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt",
            "pdc-email-ai-lead/.env",
            "e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8",
            "RUNTIME_IDENTITY_MISMATCH",
            "get_pdc_email_vehicle_location_snapshot",
            '"vehicle_version": int(current_vehicle["version"])',
            "POSTVALIDATION_VEHICLE_VERSION_CHANGED",
            FIXTURE_RPC,
            VALIDATION_RPC,
            "fresh_fixture_count",
            "consumed_fixture_count",
            "validated_current_version_plan_count",
            "cross_target_plan_rejection",
            "protected_table_http_statuses",
            "production_contacted",
            "mailbox_contacted",
            "outbound_email_sent",
        ):
            self.assertIn(marker, source)
        self.assertNotIn('"apply_pdc_email_ai_typed_action_surface_20260901_strict"', source)
        self.assertLess(
            source.index("base, headers, anon_headers = verified_runtime_headers()"),
            source.index("installed = management_query("),
        )

    def test_controller_refreshes_and_rechecks_current_version_per_plan(self):
        source = CONTROLLER.read_text(encoding="utf-8")
        validation_loop = source.split("for fixture in fixtures:", 1)[1]
        self.assertIn("current_vehicles(base, headers)", validation_loop)
        self.assertGreaterEqual(validation_loop.count("current_vehicles(base, headers)"), 2)
        self.assertIn("postvalidation_vehicle", validation_loop)
        self.assertIn("POSTVALIDATION_VEHICLE_VERSION_CHANGED", validation_loop)


if __name__ == "__main__":
    unittest.main(verbosity=2)
