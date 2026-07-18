from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from stage2b_c3_reconciliation import (  # noqa: E402
    C3ReconciliationError,
    REPORT_SCHEMA_VERSION,
    SYNTHETIC_SOURCE_SYSTEM,
    assert_exact_staging_project_ref,
    build_operation_evidence,
    build_reconciliation_report,
    validate_reconciliation_report,
)
from workshop_vehicle_reference_artifact import (  # noqa: E402
    VehicleReferenceArtifactError,
    VehicleReferenceArtifactStale,
    artifact_checksum,
    build_vehicle_reference_artifact,
)

REVISION = 31
IDS = [
    "10000000-0000-4000-a000-000000000001",
    "10000000-0000-4000-a000-000000000002",
    "10000000-0000-4000-a000-000000000003",
    "10000000-0000-4000-a000-000000000004",
]


def claim(kind, value, origin="canonical", source=None):
    normalized = "".join(value.upper().replace("-", "").split()) if kind in {"stock_number", "vin"} else value.strip().upper()
    return {"identifier_type": kind, "value": value, "normalized_value": normalized, "source_system": source, "origin": origin}


def make_artifact():
    items = [
        {"vehicle_id": IDS[0], "version": 1, "is_archived": False, "identifiers": [
            claim("stock_number", "C3-STK-001"),
            claim("source_record_id", "C3-NEW-STOCK", source=SYNTHETIC_SOURCE_SYSTEM),
        ]},
        {"vehicle_id": IDS[1], "version": 3, "is_archived": False, "identifiers": [
            claim("stock_number", "C3-ALIAS-OLD", origin="alias"),
            claim("source_record_id", "C3-SOURCE-EVIDENCE", origin="source_evidence", source=SYNTHETIC_SOURCE_SYSTEM),
        ]},
        {"vehicle_id": IDS[2], "version": 2, "is_archived": True, "identifiers": [
            claim("stock_number", "C3-STK-ARCHIVED"),
            claim("source_record_id", "C3-ARCHIVED", source=SYNTHETIC_SOURCE_SYSTEM),
        ]},
        {"vehicle_id": IDS[3], "version": 1, "is_archived": False, "identifiers": [
            claim("stock_number", "C3-STK-SHARED-ONLY"),
            claim("source_record_id", "C3-SHARED-ONLY", source=SYNTHETIC_SOURCE_SYSTEM),
        ]},
    ]
    return build_vehicle_reference_artifact({
        "outcome": "exported",
        "export_revision": REVISION,
        "items": items,
        "conflicts": [],
        "completion": {
            "complete": True, "page_count": 1, "terminal_cursor": IDS[-1],
            "pages": [{"after_cursor": None, "end_cursor": IDS[-1], "item_count": 4, "has_more": False, "next_cursor": None}],
        },
    }, generated_at="2026-07-18T12:00:00Z", source_environment="test:stage2b-c3")


def record(scenario_id, source_record_id, payload, **extra):
    return {"id": scenario_id, "source_system": SYNTHETIC_SOURCE_SYSTEM,
            "source_record_id": source_record_id, "payload": payload, **extra}


def operation(row, **result):
    return build_operation_evidence(row, **result)


class Stage2BC3ReconciliationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads((ROOT / "backend" / "fixtures" / "stage2b_c3_synthetic_pilot.json").read_text(encoding="utf-8"))

    def test_fixture_covers_every_required_scenario_and_uses_only_synthetic_namespace(self):
        required = {
            "new_stock_only", "new_vin_only", "stock_vin_job_match", "alias_match",
            "retained_source_evidence_match", "manual_edit_after_import", "stale_optimistic_version",
            "duplicate_normalized_stock", "duplicate_normalized_job_card", "canonical_alias_conflict",
            "canonical_source_evidence_conflict", "archived_vehicle", "deleted_retained_source_evidence",
            "malformed_vin", "placeholder_stock", "missing_identity", "ambiguous_identity",
            "unchanged_replay", "updated_import", "missing_in_legacy",
        }
        self.assertEqual({row["id"] for row in self.fixture["scenarios"]}, required)
        self.assertEqual(self.fixture["source_system"], SYNTHETIC_SOURCE_SYSTEM)
        self.assertEqual(len(self.fixture["protocol_scenarios"]), 8)

    def test_exact_project_guard_refuses_unknown_and_production(self):
        self.assertTrue(assert_exact_staging_project_ref("cdsmnqxtyyoeoznmbidd"))
        for value in (None, "", "production", "wrong-project"):
            with self.assertRaises(C3ReconciliationError):
                assert_exact_staging_project_ref(value)

    def test_created_alias_source_evidence_archived_and_missing_in_legacy_outcomes(self):
        artifact = make_artifact()
        legacy = [
            record("created", "C3-NEW-STOCK", {"stock_number": "c3 stk 001"}),
            record("alias", "C3-ALIAS-MATCH", {"stock_number": "C3-ALIAS-OLD"}),
            record("source", "C3-SOURCE-EVIDENCE", {}, allow_source_evidence_only=True),
            record("archived", "C3-ARCHIVED", {"stock_number": "C3-STK-ARCHIVED"}),
        ]
        report = build_reconciliation_report(
            artifact=artifact, legacy_records=legacy,
            operation_results={"created": operation(legacy[0], action="insert", vehicle_id=IDS[0])},
            expected_resolver_revision=REVISION,
        )
        by_id = {row["scenario_id"]: row for row in report["results"]}
        self.assertEqual(by_id["created"]["outcome"], "created")
        self.assertEqual(by_id["alias"]["reason_code"], "alias_match")
        self.assertEqual(by_id["source"]["reason_code"], "source_evidence_match")
        self.assertEqual(by_id["archived"]["outcome"], "manual_review_required")
        self.assertEqual(by_id[f"missing-in-legacy:{IDS[3]}"]["outcome"], "missing_in_legacy")

    def test_invalid_stale_ambiguous_conflict_and_deleted_evidence_outcomes(self):
        artifact = make_artifact()
        legacy = [
            record("bad-vin", "C3-BAD-VIN", {"vin": "BAD"}),
            record("placeholder", "C3-PLACEHOLDER", {"stock_number": "TBA"}),
            record("missing", "C3-MISSING", {}),
            record("stale", "C3-STALE", {"stock_number": "C3-STK-001"}, expected_version=0),
            record("ambiguous", "C3-SOURCE-EVIDENCE", {"stock_number": "C3-STK-001"}),
            record("conflict", "C3-SOURCE-EVIDENCE", {"stock_number": "C3-STK-001"}),
            record("deleted", "C3-DELETED", {}, allow_source_evidence_only=True),
        ]
        operations = {
            "stale": operation(legacy[3], code="stale_version", vehicle_id=IDS[0], actual_version=1),
            "ambiguous": operation(legacy[4], code="ambiguous_match"),
            "conflict": operation(legacy[5], code="canonical_alias_conflict"),
            "deleted": operation(legacy[6], code="unlinked_source_evidence"),
        }
        report = build_reconciliation_report(artifact=artifact, legacy_records=legacy,
                                             operation_results=operations,
                                             expected_resolver_revision=REVISION)
        by_id = {row["scenario_id"]: row for row in report["results"]}
        self.assertEqual(by_id["bad-vin"]["reason_code"], "malformed_vin")
        self.assertEqual(by_id["placeholder"]["reason_code"], "placeholder_stock")
        self.assertEqual(by_id["missing"]["reason_code"], "missing_identity")
        self.assertEqual(by_id["stale"]["outcome"], "stale_version")
        self.assertEqual(by_id["ambiguous"]["outcome"], "ambiguous")
        self.assertEqual(by_id["conflict"]["outcome"], "conflict")
        self.assertEqual(by_id["deleted"]["outcome"], "missing_in_shared")

    def test_manual_edit_divergence_update_and_unchanged_accuracy(self):
        artifact = make_artifact()
        legacy = [
            record("manual", "C3-NEW-STOCK", {"stock_number": "C3-STK-001"}, desired_fields={"model": "Original"}),
            record("updated", "C3-ALIAS-MATCH", {"stock_number": "C3-ALIAS-OLD"}),
            record("unchanged", "C3-ARCHIVED", {"stock_number": "C3-STK-ARCHIVED"}),
        ]
        artifact["items"][2]["is_archived"] = False
        artifact["checksum"]["value"] = artifact_checksum(artifact)
        report = build_reconciliation_report(
            artifact=artifact, legacy_records=legacy,
            operation_results={"updated": operation(legacy[1], action="update", vehicle_id=IDS[1])},
            actual_vehicle_fields={IDS[0]: {"model": "Manually changed"}},
            expected_resolver_revision=REVISION,
        )
        by_id = {row["scenario_id"]: row for row in report["results"]}
        self.assertEqual(by_id["manual"]["reason_code"], "manual_edit_divergence")
        self.assertEqual(by_id["updated"]["outcome"], "updated")
        self.assertEqual(by_id["unchanged"]["outcome"], "unchanged")

    def test_report_is_deterministic_canonically_ordered_and_checksummed(self):
        artifact = make_artifact()
        legacy = [
            record("b", "C3-SOURCE-EVIDENCE", {}, allow_source_evidence_only=True),
            record("a", "C3-NEW-STOCK", {"stock_number": "C3-STK-001"}),
        ]
        first = build_reconciliation_report(artifact=artifact, legacy_records=legacy,
                                            operation_results={}, expected_resolver_revision=REVISION)
        second = build_reconciliation_report(artifact=artifact, legacy_records=list(reversed(legacy)),
                                             operation_results={}, expected_resolver_revision=REVISION)
        self.assertEqual(first, second)
        self.assertEqual(first["schema_version"], REPORT_SCHEMA_VERSION)
        self.assertEqual(validate_reconciliation_report(first), first)

    def test_report_contains_only_narrow_allowlisted_fields(self):
        report = build_reconciliation_report(
            artifact=make_artifact(),
            legacy_records=[record("safe", "C3-NEW-STOCK", {"stock_number": "C3-STK-001", "customer_name": "must-not-leak"})],
            operation_results={}, expected_resolver_revision=REVISION,
        )
        encoded = json.dumps(report)
        self.assertNotIn("customer_name", encoded)
        self.assertNotIn("must-not-leak", encoded)
        for row in report["results"]:
            self.assertEqual(set(row), {
                "scenario_id", "outcome", "vehicle_id", "source_system", "source_record_id",
                "matched_claim_type", "expected_version", "actual_version", "reason_code",
            })

    def test_stale_artifact_revision_is_refused(self):
        with self.assertRaises(VehicleReferenceArtifactStale):
            build_reconciliation_report(artifact=make_artifact(), legacy_records=[], operation_results={},
                                        expected_resolver_revision=REVISION + 1)

    def test_truncated_and_malformed_typed_artifacts_are_refused(self):
        for mutate in (
            lambda value: value["completion"].update({"complete": False}),
            lambda value: value.update({"item_count": 99}),
            lambda value: value["items"][0].update({"customer_name": "prohibited"}),
        ):
            artifact = make_artifact()
            mutate(artifact)
            artifact["checksum"]["value"] = artifact_checksum(artifact)
            with self.assertRaises(VehicleReferenceArtifactError):
                build_reconciliation_report(artifact=artifact, legacy_records=[], operation_results={},
                                            expected_resolver_revision=REVISION)

    def test_report_tamper_is_refused(self):
        report = build_reconciliation_report(artifact=make_artifact(), legacy_records=[],
                                             operation_results={}, expected_resolver_revision=REVISION)
        tampered = copy.deepcopy(report)
        tampered["results"][0]["reason_code"] = "tampered"
        with self.assertRaises(C3ReconciliationError):
            validate_reconciliation_report(tampered)

    def test_unknown_source_namespace_is_refused(self):
        with self.assertRaises(C3ReconciliationError):
            build_reconciliation_report(artifact=make_artifact(), legacy_records=[], operation_results={},
                                        expected_resolver_revision=REVISION, source_system="legacy_migration")

    def test_operation_evidence_is_schema_bound_and_artifact_verified(self):
        row = record("safe", "C3-NEW-STOCK", {"stock_number": "C3-STK-001"}, expected_version=0)
        valid = operation(row, code="stale_version", vehicle_id=IDS[0], actual_version=1)
        build_reconciliation_report(artifact=make_artifact(), legacy_records=[row],
                                    operation_results={"safe": valid}, expected_resolver_revision=REVISION)
        mutations = []
        bad = copy.deepcopy(valid); bad["vehicle_id"] = "not-in-artifact"; mutations.append(bad)
        bad = copy.deepcopy(valid); bad["actual_version"] = 999; mutations.append(bad)
        bad = copy.deepcopy(valid); bad["operation_fingerprint"] = "0" * 64; mutations.append(bad)
        bad = copy.deepcopy(valid); bad["extra"] = True; mutations.append(bad)
        for bad in mutations:
            with self.assertRaises(C3ReconciliationError):
                build_reconciliation_report(artifact=make_artifact(), legacy_records=[row],
                                            operation_results={"safe": bad}, expected_resolver_revision=REVISION)
        with self.assertRaises(C3ReconciliationError):
            build_reconciliation_report(artifact=make_artifact(), legacy_records=[row],
                                        operation_results={"unknown": valid}, expected_resolver_revision=REVISION)

    def test_fixture_declares_required_replay_and_rollback_protocols(self):
        self.assertEqual(set(self.fixture["protocol_scenarios"]), {
            "repeated_preview", "repeated_apply", "response_loss_replay",
            "stale_artifact_revision", "truncated_typed_artifact",
            "malformed_typed_artifact", "rollback_revision_lock", "stale_rollback_refusal",
        })


if __name__ == "__main__":
    unittest.main()
