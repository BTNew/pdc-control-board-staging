"""Portable safety/schema tests for the guarded C3 staging pilot."""
from __future__ import annotations

import copy
import inspect
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "backend"))

import stage2b_c3_synthetic_pilot as pilot  # noqa: E402
from stage2b_c3_reconciliation import build_reconciliation_report  # noqa: E402
from test_stage2b_c3_reconciliation import REVISION, make_artifact  # noqa: E402


class Stage2BC3SyntheticPilotTests(unittest.TestCase):
    def test_project_guard_requires_exact_link_and_exact_dsn_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            ref = Path(temp) / "project-ref"
            ref.write_text(pilot.STAGING_REF, encoding="utf-8")
            valid = (
                f"postgresql://postgres.{pilot.STAGING_REF}:unused@"
                "aws-0-ap-southeast-2.pooler.supabase.com/postgres"
            )
            self.assertTrue(pilot.assert_exact_project_guard(ref, valid))
            for dsn in (
                None,
                "",
                "postgresql://postgres:unused@localhost/postgres",
                f"https://{pilot.STAGING_REF}.supabase.co",
                f"postgresql://postgres.{pilot.STAGING_REF}:unused@pooler.invalid/postgres",
            ):
                with self.assertRaises(pilot.C3PilotRefusal):
                    pilot.assert_exact_project_guard(ref, dsn)
            ref.write_text(pilot.STAGING_REF + "x", encoding="utf-8")
            with self.assertRaises(pilot.C3PilotRefusal):
                pilot.assert_exact_project_guard(ref, valid)

    def test_fixture_has_exact_declared_scenario_coverage(self):
        fixture = pilot.load_fixture()
        expected = {
            "new_stock_only", "new_vin_only", "stock_vin_job_match", "alias_match",
            "retained_source_evidence_match", "manual_edit_after_import", "stale_optimistic_version",
            "duplicate_normalized_stock", "duplicate_normalized_job_card", "canonical_alias_conflict",
            "canonical_source_evidence_conflict", "archived_vehicle", "deleted_retained_source_evidence",
            "malformed_vin", "placeholder_stock", "missing_identity", "ambiguous_identity",
            "unchanged_replay", "updated_import", "missing_in_legacy",
        }
        self.assertEqual({row["id"] for row in fixture["scenarios"]}, expected)
        self.assertEqual(fixture["source_system"], pilot.SOURCE_SYSTEM)
        self.assertEqual(fixture["source_batch_id"], pilot.SOURCE_BATCH_ID)

    def test_preview_evidence_is_allowlisted_and_payload_free(self):
        response = {"ok": True, "code": "preview", "data": {"action": "insert", "vehicle_id": "secret-id",
                    "vehicle": {"customer_name": "Must Not Leak"}, "request_fingerprint": "abc"}}
        safe = pilot.sanitize_preview("new_stock_only", response)
        self.assertEqual(set(safe), pilot.SAFE_PREVIEW_KEYS)
        encoded = json.dumps(safe).lower()
        self.assertNotIn("customer", encoded)
        self.assertNotIn("must not leak", encoded)
        self.assertNotIn("secret-id", encoded)

    def test_cleanup_sql_is_captured_id_and_namespace_restricted(self):
        source = inspect.getsource(pilot.cleanup_synthetic).lower()
        self.assertNotIn("truncate", source)
        self.assertNotIn("delete from public.vehicles where source_system=%s\"", source)
        self.assertIn("id = any(%s::uuid[])", source)
        self.assertIn("source_system=%s and source_batch_id=%s", source)
        self.assertIn("metadata_legacy_plan_id like 'c3-pilot-%%'", source)
        self.assertLess(source.index("workshop_booking_assignments"), source.index("workshop_bookings where"))

    def test_evidence_schema_accepts_only_sanitized_deterministic_bundle(self):
        report = build_reconciliation_report(artifact=make_artifact(), legacy_records=[],
                                             operation_results={}, expected_resolver_revision=REVISION)
        bundle = {
            "pilot": {"schema_version": "pdc.stage2b.c3-pilot-evidence/v1",
                      "source_system": pilot.SOURCE_SYSTEM, "source_batch_id": pilot.SOURCE_BATCH_ID,
                      "scenario_count": 20, "preview_deterministic": True, "preview_apply_parity": True,
                      "exact_apply_replay": True, "response_loss_replay": True, "validator_cli": True,
                      "c2b_dry_run": True, "evidence_files": sorted(pilot.EVIDENCE_FILES.values())},
            "preview": [pilot.sanitize_preview("x", {"ok": True, "code": "preview", "data": {"action": "insert"}})],
            "artifact": {"schema_version": "pdc.workshop.vehicle-reference/v2", "resolver_revision": REVISION, "item_count": 4,
                         "checksum": {"algorithm": "sha256", "value": "0" * 64},
                         "deterministic_regeneration": True, "stale_revision_refused": True,
                         "malformed_refused": True, "truncated_refused": True},
            "reconciliation": report,
            "rollback": {"rollback_used": True, "exact_revision_lock": REVISION,
                         "stale_rollback_refused": True, "synthetic_apply_receipt_replayed": True},
            "cleanup": {"baseline_counts": {name: 0 for name in pilot.COUNT_TABLES},
                        "after_counts": {name: 0 for name in pilot.COUNT_TABLES}, "baseline_restored": True,
                        "unresolved_synthetic_conflicts": 0, "temp_schemas": 0, "temp_roles": 0,
                        "synthetic_residue_counts": {"vehicles": 0}},
        }
        self.assertTrue(pilot.validate_evidence_bundle(bundle))
        bad = copy.deepcopy(bundle)
        bad["artifact"]["database_url"] = "postgresql://must-not-leak"
        with self.assertRaises(pilot.C3PilotRefusal):
            pilot.validate_evidence_bundle(bad)

        for section, key, value in (
            ("artifact", "deterministic_regeneration", False),
            ("rollback", "stale_rollback_refused", False),
            ("cleanup", "baseline_restored", False),
            ("cleanup", "synthetic_residue_counts", {"vehicles": 1}),
        ):
            bad = copy.deepcopy(bundle)
            bad[section][key] = value
            with self.assertRaises(pilot.C3PilotRefusal):
                pilot.validate_evidence_bundle(bad)

    def test_receipt_projection_rejects_matching_id_with_changed_content(self):
        durable = {"receipt_id": "r-1", "request_fingerprint": "f-1", "inserted": 1, "replayed": False}
        replay = {**durable, "replayed": True}
        self.assertEqual(pilot.immutable_receipt_projection(durable),
                         pilot.immutable_receipt_projection(replay))
        replay["inserted"] = 2
        self.assertNotEqual(pilot.immutable_receipt_projection(durable),
                            pilot.immutable_receipt_projection(replay))

    def test_import_has_no_connection_or_environment_side_effect(self):
        self.assertTrue(callable(pilot.main))
        self.assertNotIn("PDC_STAGING_DATABASE_URL", pilot.__dict__)


if __name__ == "__main__":
    unittest.main()
