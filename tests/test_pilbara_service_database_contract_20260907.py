from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260907100000_pilbara_service_open_jobcards_v1.sql"
RUNTIME_REPAIR = ROOT / "supabase/staging_only/20260907101000_pilbara_service_runtime_actor_gate.sql"
ACTIVATION_REPAIR = ROOT / "supabase/staging_only/20260907102000_pilbara_service_scoped_activation_gate.sql"
DELIVERY_INTERCEPT_REPAIR = ROOT / "supabase/staging_only/20260907103000_pilbara_service_delivery_intercept_gate.sql"
DELIVERY_BYPASS_REPAIR = ROOT / "supabase/staging_only/20260907104000_pilbara_service_pre_delivery_link_gate.sql"
ACTIVATION_SECURITY_REPAIR = ROOT / "supabase/staging_only/20260907105000_pilbara_service_activation_security_repair.sql"
ATOMIC_HEAD_REPAIR = ROOT / "supabase/staging_only/20260907106000_pilbara_service_atomic_head_guard.sql"
NULL_SAFE_HEAD_REPAIR = ROOT / "supabase/staging_only/20260907107000_pilbara_service_null_safe_head_guard.sql"
SERVICE = ROOT / "pdc-email-vehicle-location-service.js"
APP = ROOT / "app.js"
APPLY_SCRIPT = ROOT / "scripts/apply_pilbara_service_open_jobcards_staging.py"
RUNNER = ROOT / "scripts/apply_pilbara_service_open_jobcards_authenticated_staging.py"


class PilbaraServiceDatabaseContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.compact = "".join(cls.sql.split())

    def test_dedicated_append_only_evidence_schema_is_staging_guarded(self) -> None:
        for marker in (
            "pilbara_service_open_jobcards_v1",
            "pdc_pilbara_service_import_batches",
            "pdc_pilbara_service_import_rows",
            "pdc_pilbara_service_operations",
            "pdc_pilbara_service_operation_history",
            "pdc_pilbara_service_import_receipts",
            "cdsmnqxtyyoeoznmbidd",
            "pdc_production_environment_sentinel",
        ):
            self.assertIn(marker, self.sql)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.sql)
        self.assertNotIn("disable row level security", self.sql)

    def test_preview_and_apply_are_private_idempotent_conflict_checked_and_atomic(self) -> None:
        for marker in (
            "createfunctionpublic.pdc_pilbara_service_preview_v1(",
            "createfunctionpublic.pdc_pilbara_service_apply_v1(",
            "pg_advisory_xact_lock",
            "idempotency_conflict",
            "semantic_identity_conflict",
            "v_pair_count",
            "apply_not_eligible",
            "append_only",
        ):
            self.assertIn(marker, self.compact)
        self.assertNotIn("insertintopublic.vehicles", self.compact)
        self.assertNotIn("updatepublic.vehicles", self.compact)
        self.assertNotIn("v_row->>'status", self.compact)
        self.assertIn("rev0keall", self.compact.replace("revoke", "rev0ke"))

    def test_authorized_payload_and_exact_footer_are_cryptographically_bound(self) -> None:
        self.assertIn("284d241601d743123c0d07bd2a85f71cdca833b813c78558a7b77c1ad1f810b8", self.sql)
        self.assertIn("authorized_payload_hash", self.sql)
        self.assertIn("source_order<162", self.compact)
        self.assertIn("source_order=162", self.compact)

    def test_preview_runner_fails_closed_and_reads_back_exact_batch(self) -> None:
        script = APPLY_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("review-evidence/t_5523f3fd/", script)
        self.assertIn('response.get("ok") is not True', script)
        self.assertIn('preview_readback(response["preview_batch_id"])', script)
        self.assertIn("btrim(v.stock_number)=btrim(r.stock_number)", script)
        for marker in ("operation_count", "activation_count", "notification_count", "evidence_path"):
            self.assertIn(marker, script)

    def test_apply_relocks_exact_backend_vehicle_binding(self) -> None:
        for marker in (
            "navision-backend-store",
            "forupdate",
            "forshare",
            "b.canonical_vehicle_idisnullorb.canonical_vehicle_id=v.id",
            "matched_stock_numbers",
            "unmatched_stock_numbers",
            "b.dealer_code='37047'",
            "locktablepublic.navision_backend_recordsinsharerowexclusivemode",
            "locktablepublic.vehiclesinsharerowexclusivemode",
            "pdc_monitor_staging_guard()",
            "project_ref='cdsmnqxtyyoeoznmbidd'",
            "created_actortextnotnull",
            "created_by,created_actor",
            "receipt_kind,outcome,created_by,created_actor",
            "'replay'",
            "auth.uid()",
            "(v_preview.response->'matched'->>'stocks')::integer<>21",
            "(v_preview.response->'matched'->>'lines')::integer<>122",
            "(v_preview.response->'unmatched'->>'stocks')::integer<>16",
            "(v_preview.response->'unmatched'->>'lines')::integer<>39",
            "v_preview.quarantined_line_count<>40",
            "r.vehicle_idisnullandexists",
            "r.vehicle_idisnotnullandnotexists",
        ):
            self.assertIn(marker, self.compact)

    def test_daily_service_activation_lifecycle_invariants_are_fail_closed(self) -> None:
        preview_start = self.compact.index("createfunctionpublic.pdc_pilbara_service_preview_v1")
        apply_start = self.compact.index("createfunctionpublic.pdc_pilbara_service_apply_v1")
        preview_sql = self.compact[preview_start:apply_start]
        apply_sql = self.compact[apply_start:]
        self.assertNotIn("activate_navision_backend_record", preview_sql)
        self.assertIn("activate_navision_backend_record", apply_sql)
        self.assertIn("cardinality(v_matched)>0", preview_sql)
        self.assertIn("reconcile_navision_delivery_734", self.compact)
        self.assertNotIn("deactivate_navision", self.compact)
        self.assertNotIn("status_desc", apply_sql)

    def test_apply_uses_scoped_runtime_actor_without_admin_credentials(self) -> None:
        apply_start = self.compact.index("createfunctionpublic.pdc_pilbara_service_apply_v1")
        apply_sql = self.compact[apply_start:]
        self.assertIn("v_role='viewer'", apply_sql)
        self.assertIn("pdc_email_ai_successor_runtime_identities", apply_sql)
        self.assertIn("identity_purpose='pdc_email_ai_transaction_successor'", apply_sql)
        self.assertIn("pdc_monitor_stage_activation_writers", apply_sql)
        self.assertNotIn("array['importer','administrator']", apply_sql)

    def test_runtime_actor_repair_is_staging_guarded_and_migration_recorded(self) -> None:
        repair = "".join(RUNTIME_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "project_ref='cdsmnqxtyyoeoznmbidd'",
            "(20260907100000,pilbara_service_open_jobcards_v1)",
            "createorreplacefunctionpublic.pdc_pilbara_service_apply_v1",
            "v_role='viewer'",
            "pdc_email_ai_successor_runtime_identities",
            "pdc_monitor_stage_activation_writers",
            "20260907101000",
            "pilbara_service_runtime_actor_gate",
        ):
            self.assertIn(marker, repair)

    def test_scoped_activation_repair_requires_runtime_identity_and_writer(self) -> None:
        repair = "".join(ACTIVATION_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "project_ref='cdsmnqxtyyoeoznmbidd'",
            "(20260907101000,pilbara_service_runtime_actor_gate)",
            "createorreplacefunctionpublic.activate_navision_backend_record",
            "v_role='viewer'",
            "pdc_email_ai_successor_runtime_identities",
            "pdc_monitor_stage_activation_writers",
            "20260907102000",
            "pilbara_service_scoped_activation_gate",
        ):
            self.assertIn(marker, repair)

    def test_delivery_intercept_repair_is_limited_to_scoped_unlinked_activation(self) -> None:
        repair = "".join(DELIVERY_INTERCEPT_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "project_ref='cdsmnqxtyyoeoznmbidd'",
            "(20260907102000,pilbara_service_scoped_activation_gate)",
            "createorreplacefunctionpublic.reconcile_navision_operational_record",
            "normalized='deliveredatdealer'",
            "b.canonical_vehicle_idisnull",
            "activation_source='approved_email_build'",
            "pdc_email_ai_successor_runtime_identities",
            "pdc_monitor_stage_activation_writers",
            "reconcile_navision_operational_record_pre_734",
            "20260907103000",
            "pilbara_service_delivery_intercept_gate",
        ):
            self.assertIn(marker, repair)


    def test_pre_delivery_link_repair_bypasses_all_delivery_wrappers_for_scoped_activation(self) -> None:
        repair = "".join(DELIVERY_BYPASS_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "(20260907103000,pilbara_service_delivery_intercept_gate)",
            "b.canonical_vehicle_idisnull",
            "activation_source='approved_email_build'",
            "reconcile_navision_operational_record_pre_700",
            "20260907104000",
            "pilbara_service_pre_delivery_link_gate",
        ):
            self.assertIn(marker, repair)

    def test_activation_security_successor_restores_direct_operator_only_authorization(self) -> None:
        self.assertTrue(ACTIVATION_SECURITY_REPAIR.is_file(), "append-only activation security successor is missing")
        repair = "".join(ACTIVATION_SECURITY_REPAIR.read_text(encoding="utf-8").lower().split())
        direct_start = repair.index("createorreplacefunctionpublic.activate_navision_backend_record")
        private_start = repair.index("createfunctionpublic.pdc_pilbara_service_activate_backend_record_v1")
        direct_sql = repair[direct_start:private_start]
        self.assertIn("coalesce(v_role=any(array['operator','importer','administrator']),false)", direct_sql)
        self.assertNotIn("v_role='viewer'", direct_sql)
        self.assertNotIn("pdc_email_ai_successor_runtime_identities", direct_sql)
        self.assertNotIn("pdc_monitor_stage_activation_writers", direct_sql)

    def test_private_activation_is_acl_closed_and_rechecks_exact_authorized_scope(self) -> None:
        self.assertTrue(ACTIVATION_SECURITY_REPAIR.is_file(), "append-only activation security successor is missing")
        repair = "".join(ACTIVATION_SECURITY_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "(20260907104000,pilbara_service_pre_delivery_link_gate)",
            "createfunctionpublic.pdc_pilbara_service_activate_backend_record_v1",
            "securitydefiner",
            "p_preview_batch_iduuid",
            "p_source_hashtext",
            "p_backend_record_iduuid",
            "batch_kind='preview'",
            "v_preview.source_hash<>lower(btrim(p_source_hash))",
            "(v_preview.response->'matched'->>'stocks')::integer<>21",
            "(v_preview.response->'matched'->>'lines')::integer<>122",
            "(v_preview.response->'unmatched'->>'stocks')::integer<>16",
            "(v_preview.response->'unmatched'->>'lines')::integer<>39",
            "v_preview.quarantined_line_count<>40",
            "v_preview.conflict_count<>0",
            "r.batch_id=v_preview.batch_id",
            "r.backend_record_id=p_backend_record_id",
            "r.decisionin('insert','unchanged')",
            "b.source_system='microsoft_navision'",
            "b.dealer_code='37047'",
            "b.is_current",
            "b.record_status='current'",
            "count(distinctr.backend_record_id)",
            "count(distinctbtrim(r.stock_number))",
            "btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=v_stock_number)<>1",
            "'||p_backend_record_id::text",
            "revokeallonfunctionpublic.pdc_pilbara_service_activate_backend_record_v1(uuid,text,uuid,bigint)frompublic,anon,authenticated,service_role",
            "20260907105000",
            "pilbara_service_activation_security_repair",
        ):
            self.assertIn(marker, repair)
        self.assertNotIn("grantexecuteonfunctionpublic.pdc_pilbara_service_activate_backend_record_v1", repair)

    def test_apply_uses_private_activation_and_collision_resistant_backend_identity(self) -> None:
        self.assertTrue(ACTIVATION_SECURITY_REPAIR.is_file(), "append-only activation security successor is missing")
        repair = "".join(ACTIVATION_SECURITY_REPAIR.read_text(encoding="utf-8").lower().split())
        apply_sql = repair[repair.index("do$repair_apply$"):]
        self.assertIn("pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)", apply_sql)
        self.assertIn("public.pdc_pilbara_service_activate_backend_record_v1(", apply_sql)
        self.assertIn("v_preview.batch_id,v_preview.source_hash,v_backend,v_revision", apply_sql)
        self.assertIn("executereplace(v_definition,v_old,v_new)", apply_sql)
        self.assertIn("p_backend_record_id::text", repair)
        self.assertNotIn("substr(p_backend_record_id::text,1,8)", repair)

    def test_apply_rechecks_exact_migration_head_inside_atomic_transaction(self) -> None:
        self.assertTrue(ATOMIC_HEAD_REPAIR.is_file(), "append-only atomic head guard is missing")
        repair = "".join(ATOMIC_HEAD_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "(20260907105000,pilbara_service_activation_security_repair)",
            "locktablesupabase_migrations.schema_migrationsinsharemode",
            "schema_head_changed",
            "20260907106000",
            "pilbara_service_atomic_head_guard",
        ):
            self.assertIn(marker, repair)

    def test_apply_head_guard_fails_closed_when_ledger_head_is_missing(self) -> None:
        self.assertTrue(NULL_SAFE_HEAD_REPAIR.is_file(), "append-only null-safe head guard is missing")
        repair = "".join(NULL_SAFE_HEAD_REPAIR.read_text(encoding="utf-8").lower().split())
        for marker in (
            "(20260907106000,pilbara_service_atomic_head_guard)",
            "isdistinctfrom",
            "schema_head_changed",
            "20260907107000",
            "pilbara_service_null_safe_head_guard",
        ):
            self.assertIn(marker, repair)

    def test_authenticated_apply_runner_verifies_partial_batch_and_replay(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        for marker in (
            '"apply-approved"',
            "PDC_APPROVE_PILBARA_SERVICE_APPLY",
            "/auth/v1/token?grant_type=password",
            "/rest/v1/rpc/pdc_pilbara_service_apply_v1",
            '"matched_active_vehicle_count": 21',
            '"operation_count": 122',
            '"unmatched_vehicle_count": 0',
            '"apply_replay"',
            "backend_state_changes",
            "notification_count",
        ):
            self.assertIn(marker, runner)

    def test_apply_runner_has_no_management_impersonation_fallback(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8").lower()
        for forbidden in (
            "management_write",
            "_apply_authenticated_management",
            "set local role authenticated",
            "set_config('request.jwt.claims'",
            "order by r.approved_at nulls last",
            "pilbara-service-one-shot",
        ):
            self.assertNotIn(forbidden, runner)
        self.assertIn("authenticated rest bootstrap unavailable", runner)

    def test_runtime_uses_controlled_navision_activation_and_projects_review_lines(self) -> None:
        service = SERVICE.read_text(encoding="utf-8")
        app = APP.read_text(encoding="utf-8")
        for marker in (
            "activate_navision_backend_record",
            "approved_email_build",
            "get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1",
            "backend_record_id",
            "business_rule_default",
            "parts_semantics",
        ):
            self.assertIn(marker, self.sql)
        self.assertIn("pilbaraServiceOperations", service)
        self.assertIn("partsSemantics", service)
        self.assertIn("sourceEstimatedHours", service)
        self.assertIn("{ key: 'review', stage: 'REVIEW', label: 'Review'", app)


if __name__ == "__main__":
    unittest.main(verbosity=2)
