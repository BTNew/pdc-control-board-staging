from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903080000_pdc_email_ai_actual_jwt_replay_parity_20260903.sql"
FINAL_MIGRATION = ROOT / "supabase/staging_only/20260903090000_pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903.sql"
LOCKDOWN_MIGRATION = ROOT / "supabase/staging_only/20260903100000_pdc_email_ai_actual_jwt_replay_lockdown_20260903.sql"
PROJECTION_MIGRATION = ROOT / "supabase/staging_only/20260903110000_pdc_email_ai_safe_projection_freeze_20260903.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_actual_jwt_replay_parity_staging_20260903.py"
REPRO = ROOT / "scripts/reproduce_pdc_email_ai_actual_jwt_replay_staging_20260903.py"
DIAGNOSTIC = ROOT / "scripts/diagnose_pdc_email_ai_actual_jwt_replay_staging_20260903.py"


class ActualJwtReplayParityTests(unittest.TestCase):
    def test_migration_accepts_only_exact_safe_inbox_projection_of_canonical_success(self):
        self.assertTrue(MIGRATION.is_file())
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260903070000",
            "pdc_email_ai_final_replay_input_guard_20260903",
            "20260903080000",
            "pdc_email_ai_actual_jwt_replay_parity_20260903",
            "public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan",
            "t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,'UTF8'),'sha256'),'hex')",
            "t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid",
            "t.source_digest=lower(p_plan->>'source_digest')",
            "t.evidence_digest=lower(p_plan->>'evidence_digest')",
            "attachment_hashes.hashes",
            "pdc_email_ai_successor_runtime_rotations_20260903",
            "exact_successful_replay",
            "runtime_rotation_replay",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotIn("t.plan_hash=encode(extensions.digest(convert_to(p_plan::text", sql)
        self.assertNotRegex(sql, r"(?i)grant\s+(select|insert|update|delete)")
        self.assertNotRegex(sql, r"(?i)(update|delete\s+from)\s+public\.pdc_email_ai_successor_(transaction|action)_receipts")
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_safe_plan", sql)

    def test_migration_is_append_only_staging_guarded_and_preserves_helper_acl(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "current_user<>'postgres'",
            "session_user<>'postgres'",
            "current_setting('app.environment',true)='production'",
            "pdc_production_environment_sentinel",
            "cdsmnqxtyyoeoznmbidd",
            "REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text) FROM public,anon,authenticated,service_role",
            "has_function_privilege('authenticated'",
            "has_function_privilege('service_role'",
            "has_function_privilege('anon'",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)drop\s+(table|function|schema)")

    def test_final_migration_explicitly_binds_older_identity_and_legacy_attachment_set(self):
        self.assertTrue(FINAL_MIGRATION.is_file())
        sql = FINAL_MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260903080000",
            "pdc_email_ai_actual_jwt_replay_parity_20260903",
            "20260903090000",
            "pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903",
            "a5be6642-a175-4abc-a7e2-45185b87d790",
            "173c0d7f-8c36-4f73-a670-ee7fcf835af1",
            "explicit-predecessor-successor-rotation/20260903",
            "public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan",
            "t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,'UTF8'),'sha256'),'hex')",
            "coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes",
            "attachment_hashes.hashes@>coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)",
            "value#>>'{}' !~ '^[a-f0-9]{64}$'",
            "coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)grant\s+(select|insert|update|delete)")
        self.assertNotRegex(sql, r"(?i)(update|delete\s+from)\s+public\.pdc_email_ai_successor_(transaction|action)_receipts")
        self.assertNotRegex(sql, r"(?i)(update|delete\s+from)\s+public\.ai_email_(intake|attachments)")

    def test_lockdown_pins_safe_projection_and_allowlists_only_approved_receipts(self):
        self.assertTrue(LOCKDOWN_MIGRATION.is_file())
        sql = LOCKDOWN_MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260903090000",
            "pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903",
            "20260903100000",
            "pdc_email_ai_actual_jwt_replay_lockdown_20260903",
            "9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086",
            "pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure)",
            "t.transaction_id IN(",
            "541657d7-ef0b-4323-884c-2a1edc29aa2f",
            "35726910-42d6-4c7a-aa54-71e75dd67083",
            "0fec3e2a-bd49-4d98-a83d-42770edd9b23",
            "public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan",
            "t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,'UTF8'),'sha256'),'hex')",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)grant\s+(select|insert|update|delete)")
        self.assertNotRegex(sql, r"(?i)(update|delete\s+from)\s+public\.(pdc_email_ai_successor_(transaction|action)_receipts|ai_email_(intake|attachments)|vehicles|audit_events)")

    def test_final_projection_migration_defines_and_freezes_safe_plan_dependency(self):
        self.assertTrue(PROJECTION_MIGRATION.is_file())
        sql = PROJECTION_MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260903100000",
            "pdc_email_ai_actual_jwt_replay_lockdown_20260903",
            "20260903110000",
            "pdc_email_ai_safe_projection_freeze_20260903",
            "CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_safe_plan(p_plan jsonb)",
            "legacy-evidence-reference",
            "9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086",
            "REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_safe_plan(jsonb) FROM public,anon,authenticated,service_role",
            "t.transaction_id IN(",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, sql)
        self.assertNotRegex(sql, r"(?i)grant\s+(select|insert|update|delete)")

    def test_controller_requires_hash_approval_and_real_runtime_rest_proof(self):
        self.assertTrue(CONTROLLER.is_file())
        source = CONTROLLER.read_text(encoding="utf-8")
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260903080000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903090000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903100000",
            "PDC_APPROVE_STAGING_MIGRATION_20260903110000",
            "cdsmnqxtyyoeoznmbidd",
            "vjdtsswhroyguxyfjdkt",
            "e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8",
            "get_pdc_email_ai_transaction_successor_inbox_v2",
            "apply_pdc_email_ai_typed_action_surface_20260901_strict",
            "get_pdc_email_ai_v2_acceptance_fixtures_20260903",
            "get_pdc_email_ai_successor_action_contract_20260901",
            "get_pdc_email_vehicle_location_snapshot",
            "protected_table_http_statuses",
            "arbitrary_sql_http_status",
            "changed_plan_rejected",
            "altered_evidence_rejected",
            "stable_transaction_ids",
            "stable_action_receipt_ids",
            "zero_mutations",
            "all_transactions_sha256",
            "all_actions_sha256",
            "all_audit_events_sha256",
            "all_vehicles_sha256",
            "all_intakes_sha256",
            "all_attachments_sha256",
            "production_contacted",
            "mailbox_contacted",
            "outbound_email_sent",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("PRODUCTION_REF in path or STAGING_REF not in path", source)
        self.assertIn('row["http_status"] == 200', source)
        self.assertIn('row["code"] == "pdc_email_ai_typed_action_surface_verified"', source)
        self.assertIn('row["runtime_rotation_replay"] is True', source)
        self.assertIn('readbacks[label]["code"] != expected_codes[label]', source)
        self.assertIn('row["http_status"] == 200 and row["ok"] is False', source)

    def test_repro_is_pinned_to_three_reported_transactions_and_real_jwt(self):
        self.assertTrue(REPRO.is_file())
        source = REPRO.read_text(encoding="utf-8")
        for transaction_id in (
            "541657d7-ef0b-4323-884c-2a1edc29aa2f",
            "35726910-42d6-4c7a-aa54-71e75dd67083",
            "0fec3e2a-bd49-4d98-a83d-42770edd9b23",
        ):
            self.assertIn(transaction_id, source)
        self.assertIn("/auth/v1/token?grant_type=password", source)
        self.assertIn("/rest/v1/rpc/apply_pdc_email_ai_typed_action_surface_20260901_strict", source)
        self.assertIn('row["http_status"] == 200', source)
        self.assertIn('row["code"] == "pdc_email_ai_typed_action_surface_verified"', source)
        self.assertIn("PDC_ACTUAL_JWT_REPLAY_VERIFICATION_FAILED", source)

    def test_diagnostic_refuses_any_non_staging_runtime_url(self):
        source = DIAGNOSTIC.read_text(encoding="utf-8")
        self.assertIn("urllib.parse.urlparse", source)
        self.assertIn('parsed.hostname != f"{STAGING_REF}.supabase.co"', source)
        self.assertIn("PDC_RUNTIME_PROFILE_NON_STAGING_URL_REFUSED", source)


if __name__ == "__main__":
    unittest.main()
