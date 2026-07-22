import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import stage2b_c4_assessment as c4


def vehicle(ref, *, stock=None, vin=None, job=None, permanent=None, order=None, key=None):
    return {
        "record_ref": ref, "source_family": "added", "legacy_vehicle_key": key or stock or order or ref,
        "stock_number": stock, "vin": vin, "job_card_number": job,
        "permanent_vehicle_id": permanent, "toyota_order_number": order,
        "legacy_id": ref, "workflow_field_names": [], "parts_task_count": 0, "parts_file_count": 0,
    }


def payload(vehicles=None):
    result = {
        "schema": c4.SCHEMA, "source_origin": "http://127.0.0.1:8124",
        "computer_name": "Computer A", "exported_at": "2026-07-22T04:05:06.000Z",
        "local_storage_sha256_before": "a" * 64, "local_storage_sha256_after": "a" * 64,
        "local_storage_unchanged": True,
        "families": {
            "static_vehicle_count": 0, "added_vehicle_count": len(vehicles or []),
            "deleted_vehicle_count": 0, "edit_row_count": 0, "audit_row_count": 0,
            "navision_import_present": False, "canonical_vehicle_link_count": 0,
            "unknown_vehicle_storage_keys": [],
        },
        "vehicles": vehicles or [], "deleted_records": [], "notes": [], "parts_records": [],
        "workflow_records": [], "bookings": [], "parse_errors": [],
        "excluded_payloads": list(c4.EXCLUDED_PAYLOADS),
    }
    result["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json(result))
    return result


class C4AssessmentTests(unittest.TestCase):
    def test_current_javascript_export_is_accepted_end_to_end(self):
        script = r"""
const exporter = require('./scripts/stage2b_c4_browser_export.js');
class Storage {
  constructor(values) { this.values = values; this.keys = Object.keys(values); }
  get length() { return this.keys.length; }
  key(index) { return this.keys[index] ?? null; }
  getItem(key) { return Object.prototype.hasOwnProperty.call(this.values, key) ? this.values[key] : null; }
}
const storage = new Storage({
  [exporter.KEYS.added]: JSON.stringify([{ stock: '130001', customer: 'must-not-export' }]),
  [exporter.KEYS.edits]: '{}',
  [exporter.KEYS.deleted]: '[]',
  [exporter.KEYS.canonical_links]: '{}',
});
exporter.buildAssessmentExport({
  localStorage: storage,
  windowObject: { location: { origin: 'https://btnew.github.io' } },
  computerName: 'Computer A',
  exportedAt: '2026-07-22T04:05:06.000Z',
}).then(payload => process.stdout.write(JSON.stringify(payload))).catch(error => { console.error(error); process.exit(1); });
"""
        completed = subprocess.run(
            ["node", "-e", script], cwd=ROOT, check=True, capture_output=True, text=True
        )
        exported = json.loads(completed.stdout)
        self.assertEqual(c4.validate_export(exported)["computer_name"], "Computer A")
        self.assertNotIn("must-not-export", completed.stdout)

    def test_current_browser_export_metadata_and_legacy_schema_are_both_accepted(self):
        current = payload([vehicle("added:000001", stock="130001")])
        self.assertEqual(c4.validate_export(current)["computer_name"], "Computer A")

        legacy = payload([vehicle("added:000001", stock="130001")])
        legacy.pop("computer_name")
        legacy.pop("exported_at")
        legacy["families"].pop("canonical_vehicle_link_count")
        legacy["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json({k: v for k, v in legacy.items() if k != "assessment_export_sha256"}))
        self.assertEqual(c4.validate_export(legacy)["schema"], c4.SCHEMA)

    def test_clean_conflicting_ambiguous_invalid_and_orphans(self):
        data = payload([
            vehicle("added:000001", stock="13-0001", vin="JTNAA3BB4C5000001", job="JC-1"),
            vehicle("added:000002", stock="13 0002", vin="JTNAA3BB4C5000002", key="DUPKEY"),
            vehicle("added:000003", stock="13-0002", vin="JTNAA3BB4C5000003", key="DUPKEY"),
            vehicle("added:000004", stock="TBA", vin="BADVIN"),
            vehicle("added:000005", stock="13-0005"),
        ])
        data["notes"] = [{"legacy_vehicle_key": "MISSING", "note_count": 2}]
        data["parts_records"] = [{"family": "po_tasks", "legacy_vehicle_key": "DUPKEY", "item_count": 1}]
        data["bookings"] = [{"booking_ref": "booking:000001", "legacy_vehicle_key": "MISSING", "stage_code": "FITTING"}]
        data["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json({k: v for k, v in data.items() if k != "assessment_export_sha256"}))
        summary, details, rows = c4.assess_export(data)
        self.assertEqual(summary["total_vehicle_count"], 5)
        self.assertEqual(summary["classification_counts"], {"clean": 2, "conflicting": 2, "ambiguous": 0, "invalid": 1})
        self.assertEqual(summary["duplicate_group_counts"]["stock_number"], 1)
        self.assertGreaterEqual(summary["duplicate_group_counts"]["canonical_conflict"], 1)
        self.assertEqual(summary["orphan_record_counts"]["notes"], 1)
        self.assertEqual(summary["orphan_record_counts"]["bookings"], 1)
        self.assertEqual(summary["ambiguous_attachment_counts"]["parts"], 1)
        self.assertTrue(any(row["reason_codes"] == "orphan_vehicle_reference" for row in rows))
        self.assertTrue(details["duplicate_normalized_stock_numbers"])

    def test_malformed_vin_placeholder_and_missing_identity_are_invalid(self):
        data = payload([
            vehicle("added:000001", stock="PENDING-1", vin="JTNAA3BB4C5000001"),
            vehicle("added:000002", stock="130002", vin="123"),
            vehicle("added:000003"),
        ])
        summary, _, rows = c4.assess_export(data)
        self.assertEqual(summary["classification_counts"]["invalid"], 3)
        reasons = ";".join(row["reason_codes"] for row in rows)
        self.assertIn("placeholder_stock", reasons)
        self.assertIn("malformed_vin", reasons)
        self.assertIn("missing_identity", reasons)

    def test_checksum_and_read_only_proof_are_mandatory(self):
        data = payload([vehicle("added:000001", stock="130001")])
        data["local_storage_unchanged"] = False
        with self.assertRaises(c4.C4AssessmentError): c4.assess_export(data)
        data = payload([vehicle("added:000001", stock="130001")])
        data["assessment_export_sha256"] = "0" * 64
        with self.assertRaises(c4.C4AssessmentError): c4.assess_export(data)

    def test_prohibited_broad_data_is_rejected(self):
        data = payload([vehicle("added:000001", stock="130001")])
        data["families"]["customer"] = "not allowed"
        data["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json({k: v for k, v in data.items() if k != "assessment_export_sha256"}))
        with self.assertRaises(c4.C4AssessmentError): c4.assess_export(data)

    def test_attachment_rows_cannot_smuggle_content(self):
        data = payload([vehicle("added:000001", stock="130001")])
        data["notes"] = [{"legacy_vehicle_key": "130001", "note_count": 1, "text": "must not ship"}]
        data["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json({k: v for k, v in data.items() if k != "assessment_export_sha256"}))
        with self.assertRaises(c4.C4AssessmentError): c4.assess_export(data)

    def test_permitted_fields_enforce_narrow_types_order_and_counts(self):
        mutations = []
        data = payload([vehicle("added:000001", stock="130001")])
        data["vehicles"][0]["vin"] = "person@example.com"
        mutations.append(data)
        data = payload([vehicle("added:000001", stock="130001")])
        data["vehicles"][0]["stock_number"] = {"customer": "smuggled"}
        mutations.append(data)
        data = payload([vehicle("added:000001", stock="130001")])
        data["bookings"] = [{"booking_ref": "booking:000001", "legacy_vehicle_key": "130001", "stage_code": {"name": "FITTING"}}]
        mutations.append(data)
        data = payload([vehicle("added:000001", stock="130001")])
        data["families"]["added_vehicle_count"] = 999999
        mutations.append(data)
        data = payload([vehicle("added:000001", stock="130001")])
        data["vehicles"][0]["workflow_field_names"] = ["pmbStage", "pmbStage"]
        mutations.append(data)
        for candidate in mutations:
            candidate["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json({k: v for k, v in candidate.items() if k != "assessment_export_sha256"}))
            with self.assertRaises(c4.C4AssessmentError):
                c4.assess_export(candidate)

    def test_parse_error_is_a_manual_review_row_without_invalidating_all_vehicles(self):
        data = payload([vehicle("added:000001", stock="130001")])
        data["parse_errors"] = [{"family": "notes", "reason_code": "invalid_json"}]
        data["assessment_export_sha256"] = c4.sha256_text(c4.canonical_json({k: v for k, v in data.items() if k != "assessment_export_sha256"}))
        summary, _, rows = c4.assess_export(data)
        self.assertEqual(summary["classification_counts"]["clean"], 1)
        self.assertEqual(summary["parse_error_count"], 1)
        self.assertEqual(rows[0]["record_type"], "parse_error")
        self.assertEqual(rows[0]["classification"], "invalid")

    def test_package_is_deterministic_and_verifiable(self):
        data = payload([vehicle("added:000001", stock="130001", vin="JTNAA3BB4C5000001")])
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a = c4.build_package(data, Path(first))
            b = c4.build_package(data, Path(second))
            self.assertEqual(a["zip_sha256"], b["zip_sha256"])
            self.assertEqual(Path(a["zip_path"]).read_bytes(), Path(b["zip_path"]).read_bytes())
            verified = c4.verify_package(Path(a["zip_path"]))
            self.assertEqual(verified["zip_sha256"], a["zip_sha256"])
            self.assertFalse(a["summary"]["real_import_performed"])
            self.assertFalse(a["summary"]["production_contacted"])

    def test_verifier_rejects_semantically_substituted_import_plan(self):
        data = payload([vehicle("added:000001", stock="130001", vin="JTNAA3BB4C5000001")])
        with tempfile.TemporaryDirectory() as directory:
            built = c4.build_package(data, Path(directory))
            with zipfile.ZipFile(built["zip_path"]) as source:
                files = {name: source.read(name) for name in source.namelist()}
            plan_name = "STAGE-2B-C4-IMPORT-PLAN.md"
            files[plan_name] = b"arbitrary substituted plan\n"
            manifest = json.loads(files["manifest.json"])
            for row in manifest["files"]:
                if row["path"] == plan_name:
                    row["size"] = len(files[plan_name])
                    row["sha256"] = c4.sha256_bytes(files[plan_name])
            files["manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
            files["SHA256SUMS.txt"] = "".join(
                f"{c4.sha256_bytes(files[name])}  {name}\n"
                for name in sorted(files) if name != "SHA256SUMS.txt"
            ).encode("utf-8")
            tampered = Path(directory) / "tampered.zip"
            with zipfile.ZipFile(tampered, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
                for name in sorted(files):
                    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, files[name])
            with self.assertRaisesRegex(c4.C4AssessmentError, "import plan does not recompute"):
                c4.verify_package(tampered)

    def test_analyzer_has_no_browser_database_or_network_client(self):
        source = (ROOT / "scripts" / "stage2b_c4_assessment.py").read_text(encoding="utf-8")
        for prohibited in ("import psycopg", "import requests", "from supabase", "urllib.request", "fetch(", "create_client(", "connect("):
            self.assertNotIn(prohibited, source)


if __name__ == "__main__":
    unittest.main()
