import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts" / "workshop_vehicle_reference_artifact.py"
spec = importlib.util.spec_from_file_location("workshop_vehicle_reference_artifact", MODULE)
artifact_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact_module)

UUID_A = "11111111-1111-4111-8111-111111111111"
UUID_B = "22222222-2222-4222-8222-222222222222"
REVISION = 31


def claim(kind="stock_number", value="STK-100", normalized="STK100", origin="canonical", source_system=None):
    return {"identifier_type": kind, "value": value, "normalized_value": normalized, "source_system": source_system, "origin": origin}


def item(vehicle_id=UUID_A, claims=None):
    return {"vehicle_id": vehicle_id, "version": 2, "is_archived": False, "identifiers": claims or [claim()]}


def export(items=None, conflicts=None):
    items = items if items is not None else [item()]
    last = items[-1]["vehicle_id"] if items else None
    return {
        "outcome": "exported", "export_revision": REVISION,
        "items": items, "conflicts": conflicts or [],
        "completion": {"complete": True, "page_count": 1, "terminal_cursor": last,
                       "pages": [{"after_cursor": None, "end_cursor": last, "item_count": len(items), "has_more": False, "next_cursor": None}]},
    }


def build(data=None, generated_at="2026-07-18T10:00:00Z"):
    return artifact_module.build_vehicle_reference_artifact(
        data or export(), generated_at=generated_at, source_environment="test:c2b-python",
    )


def resign(value):
    value["checksum"]["value"] = artifact_module.artifact_checksum(value)
    return value


class OfflineVehicleReferenceArtifactTests(unittest.TestCase):
    def test_typed_fields_source_evidence_and_checksum(self):
        value = build(export([item(claims=[
            claim(), claim("source_record_id", "ROW-1", "ROW-1", "source_evidence", "NAVISION"),
        ])]))
        self.assertEqual(value["items"][0]["vehicle_id"], UUID_A)
        self.assertEqual(value["items"][0]["version"], 2)
        self.assertTrue(any(row["origin"] == "source_evidence" for row in value["items"][0]["identifiers"]))
        self.assertRegex(value["checksum"]["value"], r"^[0-9a-f]{64}$")

    def test_truncated_missing_cursor_malformed_item_and_count_rejected(self):
        cases = []
        truncated = build(); truncated["completion"]["complete"] = False; cases.append(truncated)
        missing = build(); del missing["completion"]["terminal_cursor"]; cases.append(missing)
        broad = build(); broad["items"][0]["customer"] = "no"; cases.append(broad)
        count = build(); count["item_count"] = 2; cases.append(count)
        for value in cases:
            with self.subTest(value=value):
                with self.assertRaises(artifact_module.VehicleReferenceArtifactError):
                    artifact_module.validate_vehicle_reference_artifact(resign(value), expected_resolver_revision=REVISION)

    def test_checksum_mismatch_and_stale_revision_rejected(self):
        value = build(); value["items"][0]["version"] = 9
        with self.assertRaisesRegex(artifact_module.VehicleReferenceArtifactError, "checksum mismatch"):
            artifact_module.validate_vehicle_reference_artifact(value, expected_resolver_revision=REVISION)
        with self.assertRaises(artifact_module.VehicleReferenceArtifactStale):
            artifact_module.validate_vehicle_reference_artifact(build(), expected_resolver_revision=REVISION + 1)

    def test_page_boundary_and_non_utc_timestamp_rejected(self):
        boundary = build()
        boundary["completion"]["pages"][0]["end_cursor"] = UUID_B
        boundary["completion"]["terminal_cursor"] = UUID_B
        with self.assertRaisesRegex(artifact_module.VehicleReferenceArtifactError, "boundary"):
            artifact_module.validate_vehicle_reference_artifact(resign(boundary), expected_resolver_revision=REVISION)
        timestamp = build()
        timestamp["generated_at"] = "2026-07-18"
        with self.assertRaisesRegex(artifact_module.VehicleReferenceArtifactError, "timestamp"):
            artifact_module.validate_vehicle_reference_artifact(resign(timestamp), expected_resolver_revision=REVISION)

    def test_malformed_conflicts_rejected(self):
        value = build(); value["conflicts"] = {}
        with self.assertRaises(artifact_module.VehicleReferenceArtifactError):
            artifact_module.validate_vehicle_reference_artifact(resign(value), expected_resolver_revision=REVISION)

    def test_duplicate_normalized_identifier_requires_conflict_evidence(self):
        duplicate = item(UUID_B, [claim(value="STK 100", normalized="STK100", origin="alias")])
        with self.assertRaisesRegex(artifact_module.VehicleReferenceArtifactError, "lacks explicit conflict"):
            build(export([item(), duplicate]))

    def test_conflict_evidence_is_retained_for_fail_closed_matcher(self):
        duplicate = item(UUID_B, [claim(value="STK 100", normalized="STK100", origin="alias")])
        conflict = {"classification": "canonical_alias_conflict", "identifier_type": "stock_number", "normalized_value": "STK100", "source_system": None,
                    "vehicle_ids": [UUID_A, UUID_B], "candidates": [
                        {"vehicle_id": UUID_A, "origin": "canonical", "value": "STK-100"},
                        {"vehicle_id": UUID_B, "origin": "alias", "value": "STK 100"}]}
        self.assertEqual(len(build(export([item(), duplicate], [conflict]))["conflicts"]), 1)

    def test_permanent_vehicle_id_alias_rejected_but_canonical_permitted(self):
        with self.assertRaisesRegex(artifact_module.VehicleReferenceArtifactError, "permanent-vehicle-ID"):
            build(export([item(claims=[claim("permanent_vehicle_id", "PERM-1", "PERM-1", "alias")])]))
        value = build(export([item(claims=[claim("permanent_vehicle_id", "PERM-1", "PERM-1")])]))
        self.assertEqual(value["items"][0]["identifiers"][0]["origin"], "canonical")

    def test_deterministic_logical_regeneration(self):
        first = build(generated_at="2026-07-18T10:00:00Z")
        second = build(generated_at="2026-07-18T11:00:00Z")
        self.assertEqual(first["checksum"], second["checksum"])
        self.assertNotEqual(first["generated_at"], second["generated_at"])

    def test_legacy_format_disabled_and_explicit_version_bound_rollback(self):
        legacy = {"vehicles": [{"id": UUID_A, "version": 3, "is_archived": False,
                                  "stock_number": " STK-100 ", "permanent_vehicle_id": "perm-100"}],
                  "vehicleIdentityExport": {"outcome": "exported", "export_revision": REVISION, "conflicts": [], "rollback_used": True}}
        with self.assertRaisesRegex(artifact_module.VehicleReferenceArtifactError, "disabled"):
            artifact_module.parse_workshop_reference(legacy, expected_resolver_revision=REVISION)
        messages = []
        parsed = artifact_module.parse_workshop_reference(legacy, expected_resolver_revision=REVISION, allow_legacy_rollback=True, legacy_source_environment="test:c2b-rollback", diagnostic=messages.append)
        self.assertEqual(parsed["vehicles"][0]["vehicle_id"], UUID_A)
        self.assertEqual({row["identifier_type"] for row in parsed["vehicles"][0]["identifiers"]}, {"stock_number", "permanent_vehicle_id"})
        self.assertIn("WARNING", messages[0])
        with self.assertRaises(artifact_module.VehicleReferenceArtifactError):
            artifact_module.parse_workshop_reference(legacy, expected_resolver_revision=REVISION + 1, allow_legacy_rollback=True, legacy_source_environment="test:c2b-rollback")

    def test_python_and_node_checksum_are_identical(self):
        value = build()
        script = "const m=require('./scripts/workshop_vehicle_reference_artifact');let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>process.stdout.write(m.artifactChecksum(JSON.parse(s))));"
        result = subprocess.run(["node", "-e", script], cwd=ROOT, input=json.dumps(value), text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, value["checksum"]["value"])

    def test_no_broad_or_customer_fields_in_logical_artifact(self):
        encoded = json.dumps(build()).lower()
        for prohibited in ("customer", "notes", "parts", "workshop_status", "ai_", "source_payload", "salesperson"):
            self.assertNotIn(prohibited, encoded)


if __name__ == "__main__":
    unittest.main()
