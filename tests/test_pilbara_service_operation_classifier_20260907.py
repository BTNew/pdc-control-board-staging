from __future__ import annotations

import json
import unittest
from pathlib import Path

from backend.pdc_email_ai_v2_taxonomy import classify_operation
from scripts.pilbara_service_operation_classifier import (
    CLASSIFIER_VERSION,
    MIN_ASSIGNED_CONFIDENCE,
    validate_manifest,
)
from scripts.pilbara_service_open_jobcards import parse_source

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:/Users/nwmgr/AppData/Local/hermes/cache/documents/doc_e55993a9ad5a_BT Service.csv")
MANIFEST = ROOT / "data/pilbara_service_operation_classifications_v1.json"


class PilbaraServiceOperationClassifierTests(unittest.TestCase):
    @staticmethod
    def _classified_source_rows(manifest: dict, accepted: list[dict]) -> list[dict]:
        identities = {tuple(row["natural_identity"]) for row in manifest["classifications"]}
        return [row for row in accepted if tuple(row["natural_identity"]) in identities]

    def test_craig_deterministic_mappings_and_false_positives(self) -> None:
        cases = {
            "Darkest Legal Window Tint": "TINT",
            "Long Ranger long-range fuel tank": "HOIST",
            "Genuine GVM suspension upgrade": "HOIST",
            "Pre-Delivery": "FITTING",
            "Canvas seat covers": "FITTING",
            "Tow Bar with flat plug": "FITTING",
            "ARB bullbar": "FITTING",
            "Rear wheel carrier mount": "FABRICATION",
            "Structural trade module tray work": "FABRICATION",
            "Anderson plugs wiring": "ELECTRICAL",
            "Lightforce vehicle lighting wiring": "ELECTRICAL",
            "Additional spare tyre upgrade": "TYRE",
            "Wheel Nut Indicator Set": "TYRE",
            "Fire extinguisher mounting hardware": "FABRICATION",
            "Bus 4x4 conversion": "BUS_4X4",
        }
        for description, expected in cases.items():
            with self.subTest(description=description):
                result = classify_operation(description)
                self.assertEqual(result.work_key, expected)
                self.assertEqual(result.disposition, "PLANNED")
                self.assertTrue(result.rule_id)
        self.assertEqual(classify_operation("generic 4WD accessory").disposition, "REVIEW")
        self.assertEqual(classify_operation("FMG GVM GCM Tare signage decal").disposition, "REVIEW")
        self.assertEqual(classify_operation("Reflective stripes").disposition, "REVIEW")
        self.assertEqual(classify_operation("Reflective stripes", explicit_sublet=True).work_key, "SUBLET")
        for description in (
            "NO BUS 4X4 CONVERSION REQUIRED",
            "BUS 4X4 SIGNAGE ONLY",
            "NO SPOTLIGHT REQUIRED",
            "NO LIFT KIT REQUIRED",
            "NO TYRES REQUIRED",
            "PLEASE NOTE NO TYRES REQUIRED",
            "CUSTOMER DOES NOT REQUIRE A LIFT KIT",
            "WITHOUT SPOTLIGHT",
        ):
            with self.subTest(negative_description=description):
                self.assertEqual(classify_operation(description).disposition, "REVIEW")

    def test_manifest_is_hash_bound_thresholded_and_reconciles_exactly_122(self) -> None:
        parsed = parse_source(SOURCE)
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        source_rows = self._classified_source_rows(manifest, parsed.accepted)
        validated = validate_manifest(manifest, source_rows, source_hash=parsed.source_hash)
        self.assertEqual(manifest["classifier_version"], CLASSIFIER_VERSION)
        self.assertEqual(manifest["contract"], "pilbara_service_operation_classifier_v1")
        self.assertEqual(len(validated), 122)
        self.assertEqual(len({tuple(row["natural_identity"]) for row in validated}), 122)
        self.assertTrue(all(row["category"] == "REVIEW" or row["confidence"] >= MIN_ASSIGNED_CONFIDENCE for row in validated))
        self.assertTrue(all(row["rationale"].strip() for row in validated))
        self.assertTrue(all(len(row["source_description_hash"]) == 64 for row in validated))
        ai_rows = [row for row in validated if row["method"] == "ai_semantic"]
        self.assertTrue(ai_rows)
        self.assertTrue(all(row["provider"] == "openai-codex" and row["model"] == "gpt-5.6-sol" for row in ai_rows))
        deterministic = [row for row in validated if row["method"] == "deterministic_rule"]
        self.assertTrue(deterministic)
        self.assertTrue(all(row["rule_id"] and row["ruleset_version"] for row in deterministic))
        reviews = [row for row in validated if row["category"] == "REVIEW"]
        self.assertTrue(reviews)
        self.assertTrue(all(row["method"] == "review" and row["confidence"] < MIN_ASSIGNED_CONFIDENCE for row in reviews))

    def test_manifest_rejects_changed_source_description_hash_and_low_confidence_assignment(self) -> None:
        parsed = parse_source(SOURCE)
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        source_rows = self._classified_source_rows(manifest, parsed.accepted)
        changed_hash = json.loads(json.dumps(manifest))
        changed_hash["classifications"][0]["source_description_hash"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "source description hash"):
            validate_manifest(changed_hash, source_rows, source_hash=parsed.source_hash)
        low_confidence = json.loads(json.dumps(manifest))
        row = next(item for item in low_confidence["classifications"] if item["category"] != "REVIEW")
        row["confidence"] = 0.79
        with self.assertRaisesRegex(ValueError, "confidence"):
            validate_manifest(low_confidence, source_rows, source_hash=parsed.source_hash)

    def test_manifest_rejects_inexact_source_identity_set_and_source_artifact_hash(self) -> None:
        parsed = parse_source(SOURCE)
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        source_rows = self._classified_source_rows(manifest, parsed.accepted)
        with self.assertRaisesRegex(ValueError, "source identity set"):
            validate_manifest(manifest, source_rows + [dict(source_rows[0])], source_hash=parsed.source_hash)
        with self.assertRaisesRegex(ValueError, "source hash mismatch"):
            validate_manifest(manifest, source_rows, source_hash="0" * 64)

    def test_manifest_cannot_override_negated_description_with_ai_assignment(self) -> None:
        parsed = parse_source(SOURCE)
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        source_rows = self._classified_source_rows(manifest, parsed.accepted)
        changed = json.loads(json.dumps(manifest))
        row = next(item for item in changed["classifications"] if item["category"] == "REVIEW" and " NO " in f" {next(source['operation_description'] for source in source_rows if source['natural_identity'] == item['natural_identity']).upper()} ")
        row.update(category="ELECTRICAL", method="ai_semantic", confidence=0.90, rationale="Incorrectly overrides explicit negation.")
        with self.assertRaisesRegex(ValueError, "negated or non-work"):
            validate_manifest(changed, source_rows, source_hash=parsed.source_hash)


if __name__ == "__main__":
    unittest.main(verbosity=2)
