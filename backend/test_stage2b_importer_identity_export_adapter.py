import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "workshop_legacy_import.py"
spec = importlib.util.spec_from_file_location("workshop_legacy_import", MODULE_PATH)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


UUID_A = "11111111-1111-4111-8111-111111111111"
UUID_B = "22222222-2222-4222-8222-222222222222"


def identifier(identifier_type, value, normalized, origin="canonical", source_system=None):
    return {
        "identifier_type": identifier_type,
        "value": value,
        "normalized_value": normalized,
        "source_system": source_system,
        "origin": origin,
    }


def vehicle(vehicle_id, identifiers, archived=False, version=1):
    return {
        "vehicle_id": vehicle_id,
        "version": version,
        "is_archived": archived,
        "identifiers": identifiers,
    }


def reference(items, conflicts=None, revision=7):
    return {
        "vehicles": items,
        "vehicleIdentityExport": {
            "outcome": "exported",
            "export_revision": revision,
            "conflicts": conflicts or [],
            "rollback_used": False,
        },
        "stages": [{"id": "stage-1", "code": "fit"}],
        "bays": [],
        "technicians": [],
        "workItems": [],
        "requireWorkItemForStages": [],
    }


def extract(key, plan_id="plan-1"):
    return {
        "bookings": [{
            "legacy_plan_id": plan_id,
            "legacy_vehicle_key": key,
            "stage_code": "fit",
            "bay_number": None,
            "assignee": "",
            "scheduled_start_at": "2026-07-18T00:00:00Z",
            "duration_minutes": 60,
            "status": "planned",
        }]
    }


class ImporterIdentityExportAdapterTests(unittest.TestCase):
    def test_sql_equivalent_normalization(self):
        self.assertEqual(importer.normalize_vehicle_stock_number(" ab- 12 "), "AB12")
        self.assertEqual(importer.normalize_vehicle_vin("1hgcm82633-a004352"), "1HGCM82633A004352")
        self.assertTrue(importer.is_valid_vehicle_vin("1hgcm82633-a004352"))
        self.assertFalse(importer.is_valid_vehicle_vin("BADVIN"))
        self.assertFalse(importer.is_real_vehicle_stock_number("NEW-123"))
        self.assertEqual(importer.normalize_vehicle_source_identifier(" jc-9 "), "JC-9")

    def test_uuid_retention_and_stock_vin_job_alias_matching(self):
        item = vehicle(UUID_A, [
            identifier("stock_number", "AB-12", "AB12"),
            identifier("vin", "1HGCM82633A004352", "1HGCM82633A004352"),
            identifier("job_card_number", "JC-9", "JC-9", source_system="navision"),
            identifier("stock_number", "OLD-12", "OLD12", origin="alias"),
        ], version=4)
        for key in ("ab 12", "1hgcm82633-a004352", " jc-9 ", "old 12"):
            buckets = importer.classify(extract(key), reference([item]))
            self.assertEqual(len(buckets["safely_matched"]), 1, key)
            resolved = buckets["safely_matched"][0]["resolved"]
            self.assertEqual(resolved["vehicle_id"], UUID_A)
            self.assertEqual(resolved["vehicle_version"], 4)

    def test_zero_duplicate_conflict_and_archived_fail_closed(self):
        a = vehicle(UUID_A, [identifier("stock_number", "AB-12", "AB12")])
        b = vehicle(UUID_B, [identifier("stock_number", "AB 12", "AB12", origin="alias")])
        self.assertEqual(len(importer.classify(extract("missing"), reference([a]))["missing_vehicle"]), 1)
        duplicate = importer.classify(extract("ab-12"), reference([a, b]))
        self.assertEqual(len(duplicate["duplicate_vehicle_match"]), 1)
        conflict = {
            "classification": "canonical_alias_conflict",
            "identifier_type": "stock_number",
            "normalized_value": "AB12",
            "source_system": None,
            "vehicle_ids": [UUID_A, UUID_B],
            "candidates": [],
        }
        conflicted = importer.classify(extract("ab-12"), reference([a, b], [conflict]))
        self.assertEqual(len(conflicted["conflicting_vehicle_identity"]), 1)
        self.assertEqual(conflicted["conflicting_vehicle_identity"][0]["identity_conflicts"][0]["classification"], "canonical_alias_conflict")
        archived = importer.classify(extract("ab-12"), reference([vehicle(UUID_A, a["identifiers"], archived=True)]))
        self.assertEqual(len(archived["inactive_vehicle"]), 1)
        self.assertEqual(len(archived["safely_matched"]), 0)

    def test_deterministic_bounded_pagination_and_response_loss_retry(self):
        calls = []
        page_one = {
            "outcome": "exported", "export_revision": 7,
            "items": [vehicle(UUID_A, [identifier("stock_number", "A-1", "A1")])],
            "conflicts": [], "has_more": True, "next_cursor": UUID_A,
        }
        page_two = {
            "outcome": "exported", "export_revision": 7,
            "items": [vehicle(UUID_B, [identifier("stock_number", "B-2", "B2")])],
            "conflicts": [], "has_more": False, "next_cursor": None,
        }
        lost = {"value": True}

        def fetch_page(cursor, page_size, expected_revision):
            calls.append((cursor, page_size, expected_revision))
            if lost["value"]:
                lost["value"] = False
                raise TimeoutError("response lost after read")
            return page_one if cursor is None else page_two

        result = importer.fetch_vehicle_identity_export_pages(fetch_page, page_size=2, retry_attempts=2)
        self.assertEqual([row["vehicle_id"] for row in result["items"]], [UUID_A, UUID_B])
        self.assertEqual(result["export_revision"], 7)
        self.assertEqual(calls, [(None, 2, None), (None, 2, None), (UUID_A, 2, 7)])
        repeat_pages = iter([page_one, page_two])
        repeated = importer.fetch_vehicle_identity_export_pages(
            lambda _cursor, _size, _revision: next(repeat_pages), page_size=2,
        )
        self.assertEqual(repeated, result)

    def test_stale_revision_duplicate_uuid_and_bad_cursor_fail_closed(self):
        with self.assertRaises(importer.VehicleIdentityExportStale):
            importer.fetch_vehicle_identity_export_pages(
                lambda _c, _s, _r: {"outcome": "stale_export", "export_revision": 8},
            )
        duplicate_pages = iter([
            {"outcome": "exported", "export_revision": 7, "items": [vehicle(UUID_A, [])], "conflicts": [], "has_more": True, "next_cursor": UUID_A},
            {"outcome": "exported", "export_revision": 7, "items": [vehicle(UUID_A, [])], "conflicts": [], "has_more": False, "next_cursor": None},
        ])
        with self.assertRaises(importer.VehicleIdentityExportInvalid):
            importer.fetch_vehicle_identity_export_pages(lambda _c, _s, _r: next(duplicate_pages))
        with self.assertRaises(importer.VehicleIdentityExportInvalid):
            importer.fetch_vehicle_identity_export_pages(
                lambda _c, _s, _r: {"outcome": "exported", "export_revision": 7, "items": [], "conflicts": [], "has_more": True, "next_cursor": None}
            )
        for malformed in (
            {"outcome": "exported", "export_revision": 7, "items": [], "conflicts": []},
            {"outcome": "exported", "export_revision": 7, "items": [], "conflicts": [], "has_more": "false", "next_cursor": None},
            {"outcome": "exported", "export_revision": 7, "items": [], "conflicts": [], "has_more": False, "next_cursor": UUID_A},
        ):
            with self.assertRaises(importer.VehicleIdentityExportInvalid):
                importer.fetch_vehicle_identity_export_pages(lambda _c, _s, _r, page=malformed: page)

    def test_unauthorized_export_fails_without_rollback(self):
        with self.assertRaises(PermissionError):
            importer.fetch_vehicle_identity_export_pages(
                lambda _c, _s, _r: {"outcome": "unauthorized"}
            )

    def test_explicit_rollback_logs_and_exports_ambiguity_evidence(self):
        class Cursor:
            def __init__(self):
                self.sql = ""

            def execute(self, sql, _params=None):
                self.sql = " ".join(sql.lower().split())

            def fetchone(self):
                if "synthetic tech alpha" in self.sql:
                    return (1,)
                raise AssertionError(self.sql)

            def fetchall(self):
                if "vehicle_lifecycle_resolver_revision" in self.sql:
                    return [(7,)]
                if "select id, stock_number, permanent_vehicle_id, version from vehicles" in self.sql:
                    return [
                        (UUID_A, "AB-12", "PERM-A", 3),
                        (UUID_B, "AB 12", "PERM-B", 4),
                    ]
                raise AssertionError(self.sql)

        class Conn:
            def get_dsn_parameters(self):
                return {"user": f"postgres.{importer.STAGING_PROJECT_REF}", "host": "pooler.supabase.com"}

            def cursor(self):
                return Cursor()

        messages = []
        result = importer._fetch_vehicle_identity_export_rollback(Conn(), messages.append)
        self.assertTrue(result["rollback_used"])
        self.assertEqual(result["export_revision"], 7)
        self.assertEqual([row["version"] for row in result["items"]], [3, 4])
        self.assertEqual(len(messages), 1)
        self.assertIn("rollback", messages[0].lower())
        self.assertEqual(result["conflicts"][0]["classification"], "ambiguous_normalized_identity")
        self.assertEqual(result["conflicts"][0]["vehicle_ids"], [UUID_A, UUID_B])

        class WrongProjectConn(Conn):
            def get_dsn_parameters(self):
                return {"user": "postgres.some-other-project", "host": "pooler.supabase.com"}

        with self.assertRaises(RuntimeError):
            importer.assert_staging_project(WrongProjectConn())

    def test_import_request_fingerprint_is_deterministic_and_revision_bound(self):
        ref = reference([
            vehicle(UUID_A, [identifier("stock_number", "AB12", "AB12")])
        ], revision=7)
        payload = extract("AB12")
        buckets = importer.classify(payload, ref)
        first = importer._import_request_fingerprint(payload, ref, buckets)
        second = importer._import_request_fingerprint(payload, ref, buckets)
        self.assertEqual(first, second)
        changed = reference([
            vehicle(UUID_A, [identifier("stock_number", "AB12", "AB12")])
        ], revision=8)
        self.assertNotEqual(first, importer._import_request_fingerprint(payload, changed, buckets))
        self.assertRegex(first, r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
