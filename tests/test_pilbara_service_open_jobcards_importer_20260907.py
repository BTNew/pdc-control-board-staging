from __future__ import annotations

import csv
import hashlib
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.pilbara_service_open_jobcards import (
    build_database_payload,
    IMPORTER_VERSION,
    normalize_operation,
    parse_source,
    plan_operation_changes,
    preview_from_candidates,
    live_candidates,
)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:/Users/nwmgr/AppData/Local/hermes/cache/documents/doc_e55993a9ad5a_BT Service.csv")
EXPECTED_HASH = "9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e"


class PilbaraServiceOpenJobcardsImporterTests(unittest.TestCase):
    def test_authorised_source_hash_and_shape_are_exact(self) -> None:
        parsed = parse_source(SOURCE, EXPECTED_HASH)

        self.assertEqual(IMPORTER_VERSION, "pilbara_service_open_jobcards_v1")
        self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(), EXPECTED_HASH)
        self.assertEqual(len(parsed.accepted), 161)
        self.assertEqual(len(parsed.quarantined), 1)
        self.assertEqual(parsed.quarantined[0]["reason"], "invalid_blank_natural_identity")
        self.assertEqual(len({row["stock_number"] for row in parsed.accepted}), 37)
        self.assertEqual(len({(row["stock_number"], row["repair_order_number"]) for row in parsed.accepted}), 37)

    def test_database_payload_reconciles_all_source_rows_in_original_order(self) -> None:
        parsed = parse_source(SOURCE, EXPECTED_HASH)

        payload = build_database_payload(parsed)

        self.assertEqual(len(payload), 162)
        self.assertEqual([row["source_order"] for row in payload], list(range(1, 163)))
        self.assertEqual(sum(row.get("reason") == "invalid_blank_natural_identity" for row in payload), 1)
        self.assertEqual(payload[-1]["raw_row"]["Estimated labour hours"], "1,339.00")

    def test_natural_identity_uses_repair_order_and_original_line_while_status_is_raw_only(self) -> None:
        raw = {
            "Dept": "Service", "Job #": "sparse-job", "Stock #": " 13000001 ",
            "R/O #": " RO-9 ", "Status Desc": "Completed", "Line #": "17",
            "Operation Desc": "Inspect accessory", "Estimated labour hours": "2.25",
            "Parts on Backorder": "No",
        }

        operation = normalize_operation(raw, source_order=3)

        self.assertEqual(operation["natural_identity"], [IMPORTER_VERSION, "13000001", "RO-9", 17])
        self.assertEqual(operation["source_order"], 3)
        self.assertEqual(operation["raw_row"]["Status Desc"], "Completed")
        self.assertNotIn("status", {key.casefold() for key in operation if key != "raw_row"})

    def test_blank_pre_delivery_hours_default_to_one_point_five_with_provenance(self) -> None:
        operation = normalize_operation({
            "Dept": "PD", "Stock #": "13000001", "R/O #": "RO-9", "Line #": "3",
            "Operation Desc": "Pre-Delivery", "Estimated labour hours": "", "Parts on Backorder": "",
        }, source_order=1)

        self.assertIsNone(operation["source_estimated_hours"])
        self.assertEqual(operation["effective_estimated_hours"], 1.5)
        self.assertEqual(operation["hours_provenance"], "pre_delivery_default_1_5")

    def test_explicit_non_pre_delivery_zero_is_preserved(self) -> None:
        operation = normalize_operation({
            "Dept": "Service", "Stock #": "13000001", "R/O #": "RO-9", "Line #": "4",
            "Operation Desc": "Check first aid kit", "Estimated labour hours": "0.00", "Parts on Backorder": "No",
        }, source_order=2)

        self.assertEqual(operation["source_estimated_hours"], 0)
        self.assertEqual(operation["effective_estimated_hours"], 0)
        self.assertEqual(operation["hours_provenance"], "source_explicit")

    def test_parts_backorder_values_have_non_completion_semantics(self) -> None:
        base = {"Dept": "Service", "Stock #": "13000001", "R/O #": "RO-9", "Line #": "4", "Operation Desc": "Fit item", "Estimated labour hours": "1"}

        yes = normalize_operation({**base, "Parts on Backorder": "Yes"}, source_order=1)
        no = normalize_operation({**base, "Line #": "5", "Parts on Backorder": "No"}, source_order=2)
        unknown = normalize_operation({**base, "Line #": "6", "Parts on Backorder": "pending supplier"}, source_order=3)

        self.assertEqual(yes["parts_semantics"], "explicitly_backordered")
        self.assertEqual(no["parts_semantics"], "not_backordered")
        self.assertEqual(unknown["parts_semantics"], "review")
        self.assertNotIn("complete", json.dumps([yes, no, unknown]).casefold())

    def test_unresolved_classification_is_retained_for_human_review(self) -> None:
        operation = normalize_operation({
            "Dept": "Service", "Stock #": "13000001", "R/O #": "RO-9", "Line #": "7",
            "Operation Desc": "Bespoke instruction", "Estimated labour hours": "1", "Parts on Backorder": "No",
        }, source_order=4)

        self.assertEqual(operation["classification"], "Review")

    def test_status_desc_does_not_change_semantic_hash(self) -> None:
        base = {
            "Dept": "Service", "Stock #": "13000001", "R/O #": "RO-9", "Line #": "7",
            "Operation Desc": "Bespoke instruction", "Estimated labour hours": "1", "Parts on Backorder": "No",
        }

        first = normalize_operation({**base, "Status Desc": "Open"}, source_order=4)
        second = normalize_operation({**base, "Status Desc": "Closed"}, source_order=4)

        self.assertEqual(first["semantic_hash"], second["semantic_hash"])

    def test_exact_stock_cardinality_quarantines_missing_and_ambiguous_without_creation(self) -> None:
        rows = [
            {"stock_number": "A", "repair_order_number": "RA", "original_line_number": 1},
            {"stock_number": "A", "repair_order_number": "RA", "original_line_number": 2},
            {"stock_number": "B", "repair_order_number": "RB", "original_line_number": 1},
            {"stock_number": "C", "repair_order_number": "RC", "original_line_number": 1},
        ]
        candidates = {"A": ["vehicle-a"], "B": [], "C": ["vehicle-c1", "vehicle-c2"]}

        preview = preview_from_candidates(rows, candidates)

        self.assertEqual(preview["matched"], {"stocks": 1, "groups": 1, "lines": 2})
        self.assertEqual(preview["unmatched"], {"stocks": 1, "groups": 1, "lines": 1})
        self.assertEqual(preview["ambiguous"], {"stocks": 1, "groups": 1, "lines": 1})
        self.assertEqual(preview["standalone_vehicles_created"], 0)

    def test_live_candidates_uses_exact_trimmed_stock_without_normalization(self) -> None:
        captured = []
        fake = types.SimpleNamespace(
            STAGING_REF="cdsmnqxtyyoeoznmbidd",
            management_query=lambda sql: captured.append(sql) or [{
                "stock_number": "A-1", "current_navision_count": 1, "exact_vehicle_count": 0, "wrong_dealer_count": 0,
                "compatible_pair_count": 1, "candidate_vehicle_ids": ["backend-a"],
            }],
        )

        with patch.dict(sys.modules, {"inspect_pdc14_staging": fake}):
            candidates, _ = live_candidates({"A-1"})

        self.assertEqual(candidates, {"A-1": ["backend-a"]})
        self.assertIn("btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=btrim(r.stock_number)", captured[0])
        self.assertIn("b.dealer_code='37047'", captured[0])
        self.assertNotIn("regexp_replace", captured[0])

    def test_replay_is_unchanged_and_changed_natural_identity_is_a_conflict(self) -> None:
        rows = [
            {"natural_identity": [IMPORTER_VERSION, "A", "RA", 1], "semantic_hash": "a" * 64},
            {"natural_identity": [IMPORTER_VERSION, "A", "RA", 2], "semantic_hash": "b" * 64},
            {"natural_identity": [IMPORTER_VERSION, "A", "RA", 3], "semantic_hash": "c" * 64},
        ]
        existing = {
            (IMPORTER_VERSION, "A", "RA", 1): "a" * 64,
            (IMPORTER_VERSION, "A", "RA", 2): "changed".ljust(64, "0"),
        }

        plan = plan_operation_changes(rows, existing)

        self.assertEqual(plan["counts"], {"insert": 1, "update": 0, "unchanged": 1, "conflict": 1})
        self.assertFalse(plan["apply_allowed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
