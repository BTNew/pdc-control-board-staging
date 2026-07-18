import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))

import pdc_restore  # noqa: E402


class CatalogCursor:
    def __init__(self, rows):
        self.rows = rows
        self.executed = []

    def execute(self, sql, params=None):
        self.executed.append((sql, params))

    def fetchall(self):
        return list(self.rows)


class RestorePayloadCompatibilityTests(unittest.TestCase):
    def test_old_payload_uses_only_relationships_between_present_tables(self):
        cursor = CatalogCursor([
            ("vehicle_work_items", "vehicle_id", "vehicles", "id"),
            ("vehicle_master_source_records", "vehicle_id", "vehicles", "id"),
            ("vehicle_master_history", "vehicle_id", "vehicles", "id"),
        ])
        old_payload_tables = {"vehicles", "vehicle_work_items"}

        self.assertEqual(
            pdc_restore.discover_foreign_keys(cursor, old_payload_tables),
            [("vehicle_work_items", "vehicle_id", "vehicles", "id")],
        )

    def test_current_payload_keeps_stage2b_relationships(self):
        cursor = CatalogCursor([
            ("vehicle_work_items", "vehicle_id", "vehicles", "id"),
            ("vehicle_master_source_records", "vehicle_id", "vehicles", "id"),
            ("vehicle_master_history", "vehicle_id", "vehicles", "id"),
        ])
        current_payload_tables = {
            "vehicles",
            "vehicle_work_items",
            "vehicle_master_source_records",
            "vehicle_master_history",
        }

        self.assertEqual(
            pdc_restore.discover_foreign_keys(cursor, current_payload_tables),
            cursor.rows,
        )


if __name__ == "__main__":
    unittest.main()
