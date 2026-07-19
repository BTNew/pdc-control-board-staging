"""Offline safety and determinism tests for the controlled C6 staging pilot."""
from __future__ import annotations

import copy
import json
import sys
import tempfile
import types
import unittest
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import stage2b_c6_operational_rehearsal as pilot  # noqa: E402
import stage2b_c6_full_schema_verify as full_schema  # noqa: E402


class Stage2BC6RealDataPilotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        matches = list((ROOT / "_c4_packages").glob("**/PDC-Stage2B-C4-Real-Data-Readiness-4ec8ca6581ad.zip"))
        matches.append(ROOT / "review-evidence" / "stage2b-c6" / "approved-c4-package.zip")
        cls.c4_zip = next((path for path in matches if path.is_file() and pilot.sha256_bytes(path.read_bytes()) == pilot.APPROVED_C4_SHA256), None)
        cls.c4_payload = json.loads((ROOT / "review-evidence" / "stage2b-c6" /
                                     "approved-c4-sanitized-assessment.json").read_text(encoding="utf-8"))

    def test_nullable_vehicle_ids_remain_inside_unrelated_full_row_proof(self):
        where, params, category = full_schema.predicate(
            "vehicle_aliases", {"id", "vehicle_id"}, ["00000000-0000-0000-0000-000000000001"], [], [])
        self.assertEqual(where, "vehicle_id is null or not (vehicle_id=any(%s::uuid[]))")
        self.assertEqual(params, (["00000000-0000-0000-0000-000000000001"],))
        self.assertEqual(category, "selected_vehicle_id")
        where, params, category = full_schema.predicate(
            "audit_events", {"id", "vehicle_id", "row_id", "before_data", "after_data"},
            ["00000000-0000-0000-0000-000000000001"], [], [])
        self.assertIn("row_id is null", where)
        self.assertIn("before_data->>'vehicle_id' is null", where)
        self.assertIn("after_data->>'vehicle_id' is null", where)
        self.assertEqual(len(params), 4)
        self.assertEqual(category, "selected_vehicle_audit_dependency")
        where, params, category = full_schema.predicate(
            "vehicle_master_history", {"id", "vehicle_id", "entity_id"},
            ["00000000-0000-0000-0000-000000000001"], [], [])
        self.assertIn("vehicle_id is null", where)
        self.assertIn("entity_id is null", where)
        self.assertEqual(len(params), 2)
        self.assertEqual(category, "selected_vehicle_or_entity_id")

    def test_frozen_partition_survives_mutable_dependency_fields_and_detects_unrelated_drift(self):
        before_all = {'selected-row': 'selected-before', 'nullable-unrelated': 'null-hash', 'ordinary-unrelated': 'ordinary-hash'}
        before_unrelated = {'nullable-unrelated': 'null-hash', 'ordinary-unrelated': 'ordinary-hash'}
        baseline = full_schema.frozen_partition_baseline(before_all, before_unrelated, 'selected dependency')
        self.assertTrue(baseline['partition_reconciled'])
        relationship_changed = {'selected-row': 'selected-after', 'nullable-unrelated': 'null-hash', 'ordinary-unrelated': 'ordinary-hash'}
        self.assertTrue(full_schema.reconcile_frozen_partition(before_all, before_unrelated, relationship_changed)['stable_unrelated_rows_unchanged'])
        unrelated_changed = {**relationship_changed, 'nullable-unrelated': 'changed'}
        self.assertFalse(full_schema.reconcile_frozen_partition(before_all, before_unrelated, unrelated_changed)['stable_unrelated_rows_unchanged'])
        new_row = {**relationship_changed, 'new-row': 'new'}
        self.assertFalse(full_schema.reconcile_frozen_partition(before_all, before_unrelated, new_row)['stable_unrelated_rows_unchanged'])
        after_unrelated = {'nullable-unrelated': 'null-hash', 'ordinary-unrelated': 'ordinary-hash'}
        self.assertTrue(full_schema.reconcile_frozen_partition(before_all, before_unrelated, new_row, after_unrelated)['stable_unrelated_rows_unchanged'])

    def test_sanitized_field_name_attestations_are_allowed_but_payloads_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            pilot.write_evidence(temp, {"sanitized.json": {"prohibited_fields_checked": ["customer_name"], "passed": True}})
            self.assertTrue((Path(temp) / "sanitized.json").is_file())
            with self.assertRaises(pilot.C6PilotRefusal):
                pilot.write_evidence(temp, {"unsafe.json": {"customer_name": "must-not-be-packaged"}})

    def test_exact_project_guard_rejects_host_and_user_near_matches(self):
        with tempfile.TemporaryDirectory() as temp:
            ref = Path(temp) / "project-ref"
            ref.write_text(pilot.STAGING_REF, encoding="utf-8")
            valid = f"postgresql://postgres.{pilot.STAGING_REF}:must-not-leak@aws-0-ap-southeast-2.pooler.supabase.com/postgres"
            self.assertTrue(pilot.assert_exact_project_guard(ref, valid))
            direct = f"postgresql://postgres:must-not-leak@db.{pilot.STAGING_REF}.supabase.co/postgres"
            self.assertTrue(pilot.assert_exact_project_guard(ref, direct))
            invalid = (
                f"postgresql://postgres.{pilot.STAGING_REF}:must-not-leak@evil.pooler.supabase.com/postgres",
                f"postgresql://POSTGRES.{pilot.STAGING_REF}:must-not-leak@aws-0-ap-southeast-2.pooler.supabase.com/postgres",
                f"postgresql://postgres.{pilot.STAGING_REF}:must-not-leak@aws-0-ap-southeast-2.pooler.supabase.com/other",
                f"https://postgres.{pilot.STAGING_REF}:must-not-leak@aws-0-ap-southeast-2.pooler.supabase.com/postgres",
            )
            for dsn in invalid:
                with self.assertRaises(pilot.C6PilotRefusal):
                    pilot.assert_exact_project_guard(ref, dsn)

    def test_approved_c4_selection_is_exactly_twenty_five_clean_attachment_free_rows(self):
        summary, _, _ = pilot.assess_export(self.c4_payload)
        selected = pilot.select_records(self.c4_payload)
        self.assertEqual([row["record_ref"] for row in selected], [
            "added:000006", "added:000007", "added:000008", "added:000009", "added:000010", "added:000011", "added:000012", "added:000013", "added:000014", "added:000015", "added:000016", "added:000017", "added:000018", "added:000019", "added:000020", "added:000021", "added:000022", "added:000023", "added:000024", "added:000025", "added:000026", "added:000027", "added:000028", "added:000029", "added:000030",
        ])
        self.assertEqual(summary["classification_counts"]["clean"], 192)
        self.assertTrue(all(not row["workflow_field_names"] for row in selected))
        manifest = pilot.selected_manifest(selected, summary["source_assessment_sha256"])
        self.assertEqual(manifest["selected_count"], 25)
        logical = {key: manifest[key] for key in manifest if key != "checksum"}
        self.assertEqual(manifest["checksum"]["value"], pilot.canonical_sha(logical))

    def test_operational_connection_is_bound_to_exact_guarded_dsn(self):
        called = []
        sentinel = object()
        fake = types.SimpleNamespace(connect=lambda value: called.append(value) or sentinel)
        dsn = "postgresql://postgres:must-not-leak@db.example.invalid/postgres"
        with mock.patch.dict(sys.modules, {"psycopg2": fake}):
            self.assertIs(pilot._connect_guarded(dsn), sentinel)
        self.assertEqual(called, [dsn])

    def test_c4_checksum_is_fail_closed(self):
        if self.c4_zip is None:
            self.skipTest("ignored approved C4 runtime package is not present")
        with tempfile.TemporaryDirectory() as temp:
            bad = Path(temp) / "bad.zip"
            bad.write_bytes(self.c4_zip.read_bytes() + b"x")
            with self.assertRaises(pilot.C6PilotRefusal):
                pilot.load_approved_c4(bad)

    def test_preview_validation_requires_exact_repeat_and_zero_ambiguity(self):
        response = {"ok": True, "code": "ok", "data": {
            "action": "insert", "vehicle_id": "00000000-0000-4000-a000-000000000001",
            "expected_version": None, "proposed": {"version": 1}, "candidate_ids": [],
            "candidate_sets": {"vin": [], "stock_number": []}, "request_fingerprint": "a" * 64,
        }}
        safe = pilot.validate_preview_response("added:000001", response, copy.deepcopy(response))
        self.assertEqual(safe["candidate_count"], 0)
        bad = copy.deepcopy(response)
        bad["data"]["candidate_ids"] = ["a", "b"]
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.validate_preview_response("added:000001", bad, copy.deepcopy(bad))
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.validate_preview_response("added:000001", response, {**response, "code": "changed"})

    def test_rollback_export_checksum_and_revision_are_locked(self):
        tables = {name: [] for name in pilot.ROLLBACK_TABLES}
        logical = {
            "schema": "pdc.stage2b.c6-rollback-export/v1", "source_system": pilot.SOURCE_SYSTEM,
            "source_batch_id": "C6-TEST", "resolver_revision": 7,
            "vehicle_master_revision": 42, "vehicle_ids": [], "tables": tables,
        }
        export = {**logical, "checksum": {"algorithm": "sha256", "value": pilot.canonical_sha(logical)}}
        self.assertTrue(pilot.validate_rollback_export(export, 7))
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.validate_rollback_export(export, 8)
        tampered = copy.deepcopy(export)
        tampered["source_batch_id"] = "C6-TAMPERED"
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.validate_rollback_export(tampered, 7)

    def test_restored_database_revision_locks_actually_refuse_stale_expected_values(self):
        class Cursor:
            def __init__(self):
                self.executions = []
            def execute(self, sql):
                self.executions.append(sql)
            def fetchone(self):
                return (42,)
        cur = Cursor()
        # The saved export is at 41 while the authoritative DB independently
        # advanced to 42: each revision lock must refuse it on its own.
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot._lock_restored_vehicle_master_revision(cur, "c6_full_rollback_000000000000", 41)
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot._lock_restored_resolver_revision(cur, "c6_full_rollback_000000000000", 41)
        cur.executions.clear()
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot._lock_restored_vehicle_master_revision(cur, "c6_full_rollback_000000000000", 43)
        self.assertEqual(pilot._lock_restored_vehicle_master_revision(
            cur, "c6_full_rollback_000000000000", 42), 42)
        self.assertEqual(len(cur.executions), 2)
        self.assertTrue(all("for update" in sql.lower() for sql in cur.executions))
        cur.executions.clear()
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot._lock_restored_resolver_revision(cur, "c6_full_rollback_000000000000", 43)
        self.assertEqual(pilot._lock_restored_resolver_revision(
            cur, "c6_full_rollback_000000000000", 42), 42)
        self.assertEqual(len(cur.executions), 2)
        self.assertTrue(all("vehicle_lifecycle_resolver_revision" in sql and "for update" in sql.lower()
                            for sql in cur.executions))

    def test_migration_031_evidence_is_exactly_selected_and_omits_staff(self):
        selected = [f"00000000-0000-4000-a000-{index:012d}" for index in range(25)]
        reference = {"vehicleIdentityArtifact": {
            "resolver_revision": 7, "item_count": 27,
            "items": [{"vehicle_id": value} for value in selected + [
                "00000000-0000-4000-a000-999999999998", "00000000-0000-4000-a000-999999999999"]],
            "technicians": [{"id": "staff", "name": "Must not be packaged"}],
        }, "technicians": [{"id": "staff"}]}
        focused = pilot._selected_reference_evidence(reference, selected)
        self.assertEqual(focused["item_count"], 25)
        self.assertEqual({row["vehicle_id"] for row in focused["items"]}, set(selected))
        self.assertEqual(focused["unrelated_vehicle_records_retained"], 0)
        self.assertEqual(focused["staff_records_retained"], 0)
        self.assertNotIn("technicians", focused)

    def test_bounded_classifier_artifact_excludes_unselected_identity_and_refuses_cross_boundary_conflict(self):
        proof = json.loads((ROOT / "review-evidence" / "stage2b-c6" / "operational-proof.json").read_text(encoding="utf-8"))
        focused = copy.deepcopy(proof["migration_031_reference"])
        selected = [row["vehicle_id"] for row in focused["items"]]
        from workshop_vehicle_reference_artifact import build_vehicle_reference_artifact, validate_vehicle_reference_artifact
        source = build_vehicle_reference_artifact({
            "outcome": "exported", "export_revision": focused["resolver_revision"],
            "items": focused["items"], "conflicts": [],
            "completion": {"complete": True, "page_count": 1, "terminal_cursor": selected[-1],
                           "pages": [{"after_cursor": None, "end_cursor": selected[-1],
                                      "item_count": 25, "has_more": False, "next_cursor": None}]},
        }, source_environment=f"staging:{pilot.STAGING_REF}", generated_at="2026-07-19T00:00:00Z")
        unselected = "00000000-0000-4000-a000-999999999999"
        extra = copy.deepcopy(source["items"][0])
        extra["vehicle_id"] = unselected
        source["items"].append(extra)
        source["item_count"] += 1
        reference = {"vehicleIdentityArtifact": source}
        bounded = pilot._bounded_reference_artifact(reference, selected)
        validate_vehicle_reference_artifact(bounded, expected_resolver_revision=bounded["resolver_revision"])
        self.assertEqual({row["vehicle_id"] for row in bounded["items"]}, set(selected))
        self.assertNotIn(unselected, pilot.canonical_json(bounded))
        crossed = copy.deepcopy(reference)
        crossed["vehicleIdentityArtifact"]["conflicts"] = [{
            "vehicle_ids": [selected[0], unselected],
        }]
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot._bounded_reference_artifact(crossed, selected)

    def test_viewer_contract_is_exact_and_fail_closed(self):
        vehicle = {
            "id": "00000000-0000-4000-a000-000000000001", "version": 7,
            "current_location": "PDC", "lifecycle_state": "active",
            "workshop_status": "queued", "active_workshop_booking_id": None,
        }
        booking = {
            "id": "00000000-0000-4000-a000-000000000002",
            "vehicle_id": vehicle["id"], "version": 2, "status": "queued",
        }
        evidence = pilot.viewer_contract_evidence(vehicle, booking)
        self.assertTrue(evidence["prohibited_fields_absent"])
        self.assertFalse(evidence["broad_direct_vehicle_projection_used"])
        self.assertFalse(evidence["technician_or_sensitive_data_retained"])
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.viewer_contract_evidence({**vehicle, "customer_name": "Must not leak"}, booking)
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.viewer_contract_evidence(vehicle, {**booking, "technician_id": "Must not leak"})

    def test_final_gate_evidence_must_be_packaged_and_checksum_bound(self):
        builder = (ROOT / "scripts" / "build_stage2b_c6_review_package.py").read_text(encoding="utf-8")
        verifier = (ROOT / "scripts" / "verify_stage2b_c6_review_package.py").read_text(encoding="utf-8")
        for marker in ("FINAL-TEST-EVIDENCE/", "final_test_evidence", "final gate evidence is unavailable"):
            self.assertIn(marker, builder)
        for marker in ("FINAL_TEST_EVIDENCE_PREFIX", "final gate evidence does not resolve inside package", "expected_final_evidence"):
            self.assertIn(marker, verifier)

    def test_browser_acceptance_requires_repeated_full_offline_cycles_and_error_ledgers(self):
        source = (ROOT / "scripts" / "stage2b_c6_browser_realtime_acceptance.js").read_text(encoding="utf-8")
        self.assertGreaterEqual(source.count("setOffline(true)"), 2)
        self.assertGreaterEqual(source.count("setOffline(false)"), 2)
        for marker in (
            "offlineMutationNotReportedPersisted", "noDuplicateChannelsAfterRepeatedReconnect",
            "noMultipliedRealtimeCallbacks", "securityPolicyViolations", "unexpectedFailedRequests",
            "webSocketEvidence", "initialOnlineStateSynchronized",
            "playwright-ephemeral-incognito-contexts", "persistentUserDataDirUsed: false",
            "authorityCanariesPresentBeforeBootstrapCompleted", "authorityCanariesUnchanged",
            "browserLocalAuthorityObservations", "browserLocalCanonicalObservationsEqual",
            "zeroInstrumentedBrowserProductionProjectRequests",
            "exactHashKeyAndByteEquality", "storageObservation",
            "vehicleTrackingCoreNavisionOnlyVehicles:v1",
        ):
            self.assertIn(marker, source)

    def test_production_contact_evidence_is_scoped_to_observed_surfaces(self):
        evidence_root = ROOT / "review-evidence" / "stage2b-c6"
        safety = json.loads((evidence_root / "safety.json").read_text(encoding="utf-8"))
        scenarios = json.loads((evidence_root / "operational-scenarios.json").read_text(encoding="utf-8"))
        post = json.loads((evidence_root / "post-rehearsal-verification.json").read_text(encoding="utf-8"))
        deployment = json.loads((evidence_root / "staging-deployment-identity.json").read_text(encoding="utf-8"))
        browser = json.loads((evidence_root / "browser-realtime-acceptance.json").read_text(encoding="utf-8"))
        for report in (safety, scenarios["safety"], post, deployment):
            self.assertNotIn("production_contacted", report)
            self.assertNotIn("production_untouched", report)
        self.assertTrue(safety["database_connection_guarded_to_exact_staging_project"])
        self.assertTrue(scenarios["safety"]["database_connection_guarded_to_exact_staging_project"])
        self.assertEqual(scenarios["safety"]["database_connections_outside_exact_staging_project"], 0)
        self.assertEqual(post["instrumented_browser_production_project_requests"], [])
        self.assertEqual(post["production_project_requests_observed_in_instrumented_browser_contexts"], 0)
        self.assertTrue(post["database_connection_guarded_to_exact_staging_project"])
        self.assertNotIn("zeroProductionRequests", browser["checks"])
        self.assertTrue(browser["checks"]["zeroInstrumentedBrowserProductionProjectRequests"])
        builder = (ROOT / "scripts" / "build_stage2b_c6_review_package.py").read_text(encoding="utf-8")
        verifier = (ROOT / "scripts" / "verify_stage2b_c6_review_package.py").read_text(encoding="utf-8")
        self.assertIn('final_test_results.get("remote_head") != head', builder)
        self.assertIn('final_results.get("remote_head") != manifest["source_head"]', verifier)

    def test_import_is_offline_and_apply_flag_is_required(self):
        self.assertTrue(callable(pilot.main))
        self.assertNotIn("PDC_STAGING_DATABASE_URL", pilot.__dict__)
        with self.assertRaises(pilot.C6PilotRefusal):
            pilot.main(["--c4-zip", "x", "--backup-manifest", "x", "--restore-report", "x",
                        "--rollback-restore-report", "x", "--rollback-schema", "c6_full_rollback_000000000000",
                        "--pilot-window-counts-report", "x", "--evidence-dir", "x"])


if __name__ == "__main__":
    unittest.main()
