"""Offline safety and determinism tests for the controlled C5 staging pilot."""
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
import stage2b_c5_real_data_pilot as pilot  # noqa: E402


class Stage2BC5RealDataPilotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        matches = list((ROOT / "_c4_packages").glob("**/PDC-Stage2B-C4-Real-Data-Readiness-4ec8ca6581ad.zip"))
        matches.append(ROOT / "review-evidence" / "stage2b-c5" / "approved-c4-package.zip")
        cls.c4_zip = next((path for path in matches if path.is_file() and pilot.sha256_bytes(path.read_bytes()) == pilot.APPROVED_C4_SHA256), None)
        cls.c4_payload = json.loads((ROOT / "review-evidence" / "stage2b-c5" /
                                     "approved-c4-sanitized-assessment.json").read_text(encoding="utf-8"))

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
                with self.assertRaises(pilot.C5PilotRefusal):
                    pilot.assert_exact_project_guard(ref, dsn)

    def test_approved_c4_selection_is_exactly_five_clean_attachment_free_rows(self):
        summary, _, _ = pilot.assess_export(self.c4_payload)
        selected = pilot.select_records(self.c4_payload)
        self.assertEqual([row["record_ref"] for row in selected], [
            "added:000001", "added:000002", "added:000003", "added:000004", "added:000005",
        ])
        self.assertEqual(summary["classification_counts"]["clean"], 192)
        self.assertTrue(all(not row["workflow_field_names"] for row in selected))
        manifest = pilot.selected_manifest(selected, summary["source_assessment_sha256"])
        self.assertEqual(manifest["selected_count"], 5)
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
            with self.assertRaises(pilot.C5PilotRefusal):
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
        with self.assertRaises(pilot.C5PilotRefusal):
            pilot.validate_preview_response("added:000001", bad, copy.deepcopy(bad))
        with self.assertRaises(pilot.C5PilotRefusal):
            pilot.validate_preview_response("added:000001", response, {**response, "code": "changed"})

    def test_rollback_export_checksum_and_revision_are_locked(self):
        tables = {name: [] for name in pilot.ROLLBACK_TABLES}
        logical = {
            "schema": "pdc.stage2b.c5-rollback-export/v1", "source_system": pilot.SOURCE_SYSTEM,
            "source_batch_id": "C5-TEST", "resolver_revision": 7,
            "vehicle_master_revision": 42, "vehicle_ids": [], "tables": tables,
        }
        export = {**logical, "checksum": {"algorithm": "sha256", "value": pilot.canonical_sha(logical)}}
        self.assertTrue(pilot.validate_rollback_export(export, 7))
        with self.assertRaises(pilot.C5PilotRefusal):
            pilot.validate_rollback_export(export, 8)
        tampered = copy.deepcopy(export)
        tampered["source_batch_id"] = "C5-TAMPERED"
        with self.assertRaises(pilot.C5PilotRefusal):
            pilot.validate_rollback_export(tampered, 7)

    def test_restored_database_revision_lock_actually_refuses_stale_expected_value(self):
        class Cursor:
            def __init__(self):
                self.executions = []
            def execute(self, sql):
                self.executions.append(sql)
            def fetchone(self):
                return (42,)
        cur = Cursor()
        with self.assertRaises(pilot.C5PilotRefusal):
            pilot._lock_restored_vehicle_master_revision(cur, "c5_full_rollback_000000000000", 43)
        self.assertEqual(pilot._lock_restored_vehicle_master_revision(
            cur, "c5_full_rollback_000000000000", 42), 42)
        self.assertEqual(len(cur.executions), 2)
        self.assertTrue(all("for update" in sql.lower() for sql in cur.executions))

    def test_import_is_offline_and_apply_flag_is_required(self):
        self.assertTrue(callable(pilot.main))
        self.assertNotIn("PDC_STAGING_DATABASE_URL", pilot.__dict__)
        with self.assertRaises(pilot.C5PilotRefusal):
            pilot.main(["--c4-zip", "x", "--backup-manifest", "x", "--restore-report", "x",
                        "--rollback-restore-report", "x", "--rollback-schema", "c5_full_rollback_000000000000",
                        "--pilot-window-counts-report", "x", "--evidence-dir", "x"])


if __name__ == "__main__":
    unittest.main()
