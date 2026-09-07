from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260907110000_pilbara_service_operation_classifier_v1.sql"
REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907111000_pilbara_service_operation_classifier_reconcile_join_repair.sql"
HEAD_REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907112000_pilbara_service_operation_classifier_head_guard_repair.sql"
ROLLBACK_REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907113000_pilbara_service_operation_classifier_work_item_rollback_repair.sql"
CLEANUP_REPAIR_MIGRATION = ROOT / "supabase/staging_only/20260907114000_pilbara_service_operation_classifier_rollback_cleanup.sql"


class PilbaraServiceClassifierDatabaseContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.compact = "".join(cls.sql.split())

    def test_overlay_history_current_pointer_and_private_contract_exist(self) -> None:
        for marker in (
            "pilbara_service_operation_classifier_v1",
            "pdc_pilbara_service_classification_batches",
            "pdc_pilbara_service_classification_history",
            "pdc_pilbara_service_classification_current",
            "pdc_pilbara_service_classification_work_controls",
            "pdc_pilbara_service_classification_preview_v1",
            "pdc_pilbara_service_classification_apply_v1",
            "pdc_pilbara_service_classification_rollback_v1",
            "source_description_hash",
            "source_semantic_hash",
            "supersedes_classification_id",
        ):
            self.assertIn(marker, self.sql)
        self.assertNotIn("update public.pdc_pilbara_service_operations", self.sql)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.sql)

    def test_preview_is_exact_hash_head_state_and_threshold_guarded(self) -> None:
        for marker in (
            "jsonb_array_length(p_manifest->'classifications')<>122",
            "manifest_hash_mismatch",
            "source_binding_conflict",
            "current_state_hash",
            "schema_head_changed",
            "confidence<0.80",
            "category='review'",
            "classification_conflict",
            "quarantine_count',40",
        ):
            self.assertIn(marker, self.compact)

    def test_preview_strictly_binds_manifest_provenance_and_classifier_version(self) -> None:
        for marker in (
            "(selectcount(*)fromjsonb_object_keys(p_manifest))<>7",
            "p_manifest?&array['contract','classifier_version','source_importer_version','source_batch_id','source_hash','generated_by','classifications']",
            "p_manifest->>'classifier_version'<>'pilbara-service-classifier-2026-09-07.1'",
            "p_manifest->'generated_by'isdistinctfrom'{\"model\":\"gpt-5.6-sol\",\"run_id\":\"141\",\"provider\":\"openai-codex\"}'::jsonb",
            "v_current.classifier_version=p_manifest->>'classifier_version'",
            "lower(btrim(coalesce(p_manifest_hash,'')))<>'15ddb6eecbe30d2c6d372e81c549983a4fa97d3b1e32e51f20ed53a07aebfe66'",
            "frompublic.pdc_pilbara_service_operationswhereimporter_version='pilbara_service_open_jobcards_v1')<>122",
            "frompublic.pdc_pilbara_service_operations)<>122",
            "pilbara_service_operation_classifier_v1:preview:",
        ):
            self.assertIn(marker, self.compact)

    def test_batch_audit_rows_are_immutable_after_response_finalization(self) -> None:
        for marker in (
            "pdc_pilbara_service_classification_reject_batch_mutation_v1",
            "beforeupdateordeleteonpublic.pdc_pilbara_service_classification_batches",
            "old.response='{}'::jsonb",
            "to_jsonb(new)-'response'=to_jsonb(old)-'response'",
            "pdc_pilbara_classification_immutable_batch",
        ):
            self.assertIn(marker, self.compact)

    def test_state_and_apply_bind_the_immutable_source_rows(self) -> None:
        self.assertIn("'source',coalesce((selectjsonb_agg(to_jsonb(o)orderbyo.operation_id)", self.compact)
        apply_body = self.compact.split("createfunctionpublic.pdc_pilbara_service_classification_apply_v1", 1)[1]
        self.assertIn("v_source_semantic_hash", apply_body)
        self.assertIn("v_source_description_hash", apply_body)
        self.assertIn("source_binding_conflict", apply_body)
        self.assertIn("h.classifier_version=v_preview.classifier_version", apply_body)

    def test_apply_and_rollback_share_locking_guards_and_pointer_rowcount_checks(self) -> None:
        apply_body = self.compact.split("createfunctionpublic.pdc_pilbara_service_classification_apply_v1", 1)[1].split("createfunctionpublic.pdc_pilbara_service_classification_rollback_v1", 1)[0]
        rollback_body = self.compact.split("createfunctionpublic.pdc_pilbara_service_classification_rollback_v1", 1)[1]
        advisory = "pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v1:mutation',0))"
        for body in (apply_body, rollback_body):
            self.assertIn(advisory, body)
            self.assertIn("pdc_staging_environment_sentinel", body)
            self.assertIn("pdc_production_environment_sentinel", body)
            self.assertIn("forupdate", body)
            self.assertIn("locktablepublic.pdc_pilbara_service_classification_current", body)
            self.assertIn("public.vehicle_work_itemsinsharerowexclusivemode", body)
        self.assertGreaterEqual(rollback_body.count("getdiagnosticsv_pointer_rows=row_count"), 2)
        self.assertIn("ifv_pointer_rows<>1then", rollback_body)

    def test_rollback_replay_is_bound_to_apply_batch_and_manifest(self) -> None:
        apply_body = self.compact.split("createfunctionpublic.pdc_pilbara_service_classification_apply_v1", 1)[1].split("createfunctionpublic.pdc_pilbara_service_classification_rollback_v1", 1)[0]
        self.assertIn("preview_of_batch_iduuidreferencespublic.pdc_pilbara_service_classification_batches", self.compact)
        self.assertIn("v_existing.preview_of_batch_idisdistinctfromp_preview_batch_id", apply_body)
        self.assertIn("idempotency_conflict", apply_body)
        rollback_body = self.compact.split("createfunctionpublic.pdc_pilbara_service_classification_rollback_v1", 1)[1]
        self.assertIn("v_existing.rollback_of_batch_idisdistinctfromp_apply_batch_id", rollback_body)
        self.assertIn("v_existing.manifest_hash<>v_apply.manifest_hash", rollback_body)
        self.assertIn("idempotency_conflict", rollback_body)

    def test_every_classifier_owned_work_control_is_locked_and_validated(self) -> None:
        reconcile = self.compact.split("createfunctionpublic.pdc_pilbara_service_reconcile_work_controls_v1", 1)[1].split("createfunctionpublic.pdc_pilbara_service_classification_apply_v1", 1)[0]
        self.assertIn("frompublic.pdc_pilbara_service_classification_work_controlscjoinpublic.vehicle_work_itemsw", reconcile)
        self.assertIn("forupdateofw,c", reconcile)
        self.assertIn("v_pair.requiredisnottrue", reconcile)
        self.assertIn("v_pair.completedisnotfalse", reconcile)
        self.assertIn("v_pair.completed_byisnotnull", reconcile)
        self.assertIn("v_pair.completed_atisnotnull", reconcile)
        self.assertIn("v_pair.notesisdistinctfrom'pilbaraserviceclassifiermanagedcontrol'", reconcile)
        self.assertIn("v_pair.work_vehicle_idisdistinctfromv_pair.vehicle_id", reconcile)
        self.assertIn("lower(v_pair.work_key)isdistinctfrom(casev_pair.categorywhen'bus_4x4'then'bus4x4'elselower(v_pair.category)end)", reconcile)

    def test_apply_is_atomic_idempotent_append_only_and_preserves_manual_completed_work(self) -> None:
        for marker in (
            "pg_advisory_xact_lock",
            "classification_history",
            "onconflict(operation_id)doupdate",
            "vehicle_work_items",
            "required,completed,completed_by,completed_at",
            "true,false,null,null",
            "manual_or_completed_work_item",
            "apply_replay",
            "rollback_conflict",
            "deletefrompublic.vehicle_work_items",
            "pdc_pilbara_service_classification_work_controls",
        ):
            self.assertIn(marker, self.compact)
        self.assertNotIn("insertintopublic.workshop_bookings", self.compact)
        self.assertNotIn("insertintopublic.sublet_bookings", self.compact)

    def test_rls_acl_and_snapshot_projection_are_fail_closed(self) -> None:
        for table in (
            "pdc_pilbara_service_classification_batches",
            "pdc_pilbara_service_classification_history",
            "pdc_pilbara_service_classification_current",
            "pdc_pilbara_service_classification_work_controls",
        ):
            self.assertIn(f"altertablepublic.{table}enablerowlevelsecurity", self.compact)
            self.assertIn(f"altertablepublic.{table}forcerowlevelsecurity", self.compact)
        self.assertIn("setsearch_path=pg_catalog,public,extensions", self.compact)
        self.assertIn("frompublic,anon,authenticated,service_role", self.compact)
        self.assertIn("orderbyo.source_order", self.compact)
        self.assertIn("h.category", self.sql)
        self.assertIn("h.confidence", self.sql)
        self.assertIn("h.rationale", self.sql)

    def test_follow_up_repair_migration_uses_unambiguous_operation_join(self) -> None:
        self.assertTrue(REPAIR_MIGRATION.exists())
        repair = "".join(REPAIR_MIGRATION.read_text(encoding="utf-8").lower().split())
        self.assertIn("'20260907111000'", repair)
        self.assertIn("createorreplacefunctionpublic.pdc_pilbara_service_reconcile_work_controls_v1", repair)
        self.assertIn("joinpublic.pdc_pilbara_service_operationsoono.operation_id=c.operation_id", repair)

    def test_head_guard_repair_keeps_private_functions_usable_after_repair_migrations(self) -> None:
        self.assertTrue(HEAD_REPAIR_MIGRATION.exists())
        repair = "".join(HEAD_REPAIR_MIGRATION.read_text(encoding="utf-8").lower().split())
        self.assertIn("'20260907112000'", repair)
        for function_name in (
            "pdc_pilbara_service_classification_apply_v1",
            "pdc_pilbara_service_classification_rollback_v1",
        ):
            self.assertIn(function_name, repair)
        self.assertIn("20260907112000", repair)

    def test_rollback_repair_authorizes_only_exact_classifier_managed_deletes(self) -> None:
        self.assertTrue(ROLLBACK_REPAIR_MIGRATION.exists())
        repair = "".join(ROLLBACK_REPAIR_MIGRATION.read_text(encoding="utf-8").lower().split())
        self.assertIn("'20260907113000'", repair)
        self.assertIn("pdc_pilbara_service_classification_work_item_delete_authorizations", repair)
        self.assertIn("forcerowlevelsecurity", repair)
        self.assertIn("old.notes='pilbaraserviceclassifiermanagedcontrol'", repair)
        self.assertIn("a.transaction_id=txid_current()", repair)
        self.assertIn("deletefrompublic.vehicle_work_items", repair)

    def test_cleanup_repair_removes_only_orphaned_classifier_managed_items(self) -> None:
        self.assertTrue(CLEANUP_REPAIR_MIGRATION.exists())
        repair = "".join(CLEANUP_REPAIR_MIGRATION.read_text(encoding="utf-8").lower().split())
        self.assertIn("'20260907114000'", repair)
        self.assertIn("createtableifnotexistspublic.pdc_pilbara_service_classification_work_item_delete_authorizations", repair)
        self.assertIn("notexists(select1frompublic.pdc_pilbara_service_classification_work_controls", repair)
        self.assertIn("notes='pilbaraserviceclassifiermanagedcontrol'", repair)
        self.assertIn("deletefrompublic.vehicle_work_items", repair)


if __name__ == "__main__":
    unittest.main(verbosity=2)
