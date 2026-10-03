import copy
import importlib.util
import json
import pathlib
import re
import tempfile
import unittest
import zipfile

MODULE = pathlib.Path(__file__).with_name("pack-private-backup.py")
SPEC = importlib.util.spec_from_file_location("karratha_backup", MODULE)
BACKUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BACKUP)


class PrivateBackupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="karratha-backup-fixture-")
        self.root = pathlib.Path(self.directory.name)
        self.schema = self.root / "schema.sql"
        self.schema.write_text("-- fictional rehearsal schema only\n", encoding="utf-8")
        self.envelope = {
            "format": "karratha-pdc-logical-envelope-v1", "project_ref": "cdsmnqxtyyoeoznmbidd",
            "schema": "karratha_pdc", "captured_at": "2026-10-03T00:00:00Z",
            "scope": {"private_schema_rows": True, "private_schema_definitions": True,
                      "prefixed_public_rpc_definitions": True, "centre_memberships": True, "source_evidence": True,
                      "navision_master_rows": False, "auth_accounts": False, "auth_credentials_or_sessions": False,
                      "project_roles": False, "storage_object_bytes": False},
            "tables": [{"name": "jobcards", "row_count": 2,
                        "rows": [{"id": "fixture-a", "notes": "Line 1\nUnicode: café / ✓"},
                                 {"id": "fixture-b", "notes": "Separate RO for same stock"}],
                        "columns": [{"name": "id"}, {"name": "notes"}],
                        "rls": {"enabled": True, "forced": True}}],
            "functions": [{"schema": "karratha_pdc", "name": "fixture", "definition": "fictional"}],
            "restore_limits": ["Never restore over live staging. Requires separate shared master/Auth recovery."]}

    def tearDown(self):
        self.directory.cleanup()

    def package(self, value=None):
        p = self.root / "envelope.json"
        p.write_text(json.dumps(value or self.envelope, ensure_ascii=False), encoding="utf-8")
        return BACKUP.build_backup(p, self.schema, self.root / "backup.zip")

    def test_roundtrip_preserves_all_rows_unicode_multiline_and_schema(self):
        proof = self.package()
        self.assertTrue(proof["zip_crc_passed"])
        self.assertTrue(proof["member_bytes_identical"])
        self.assertTrue(proof["json_roundtrip_passed"])
        self.assertFalse(proof["database_restore_test_performed"])
        self.assertEqual(proof["table_counts"], {"jobcards": 2})
        with zipfile.ZipFile(self.root / "backup.zip") as archive:
            self.assertEqual(json.loads(archive.read("private-recovery-envelope.json")), self.envelope)
            self.assertEqual(archive.read("reviewed-additive-schema.sql"), self.schema.read_bytes())

    def test_cannot_overwrite_existing_backup(self):
        self.package()
        with self.assertRaises(FileExistsError):
            self.package()

    def test_wrong_project_is_rejected(self):
        value = copy.deepcopy(self.envelope)
        value["project_ref"] = "production"
        with self.assertRaisesRegex(ValueError, "staging"):
            self.package(value)

    def test_shared_auth_credential_scope_is_rejected(self):
        for key in ("navision_master_rows", "auth_accounts", "auth_credentials_or_sessions", "project_roles", "storage_object_bytes"):
            with self.subTest(key=key):
                value = copy.deepcopy(self.envelope)
                value["scope"][key] = True
                with self.assertRaisesRegex(ValueError, "scope"):
                    self.package(value)

    def test_missing_row_counts_and_unexpected_columns_are_rejected(self):
        for field, value in (("row_count", 1), ("columns", [{"name": "id"}])):
            with self.subTest(field=field):
                payload = copy.deepcopy(self.envelope)
                payload["tables"][0][field] = value
                with self.assertRaises(ValueError):
                    self.package(payload)

    def test_directly_exposed_unsealed_tables_and_unrelated_rpc_are_rejected(self):
        value = copy.deepcopy(self.envelope)
        value["tables"][0]["rls"]["forced"] = False
        with self.assertRaisesRegex(ValueError, "RLS"):
            self.package(value)
        value = copy.deepcopy(self.envelope)
        value["functions"][0] = {"schema": "public", "name": "schedule_vehicle_work"}
        with self.assertRaisesRegex(ValueError, "unrelated"):
            self.package(value)

    def test_exporter_allows_temporary_workspace_and_rolls_back_without_persistent_writes(self):
        # Keep dynamic INSERT SQL strings in the scan: those execute inside DO.
        sql = pathlib.Path(__file__).with_name("backup-export.sql").read_text(encoding="utf-8")
        code = re.sub(r"--[^\n]*", "", sql).strip()
        self.assertRegex(code, r"(?i)^begin\s+isolation\s+level\s+repeatable\s+read\s*;")
        self.assertNotRegex(code, r"(?i)begin\s+isolation[^;]*\bread\s+only\b")
        self.assertRegex(code, r"(?i)rollback\s*;\s*$")
        self.assertNotRegex(code, r"(?im)^\s*commit\s*;")
        tables = re.findall(r"(?i)\bcreate\s+(?:(temporary|temp)\s+)?table\s+([a-z_][a-z0-9_.]*)", code)
        self.assertEqual(tables, [("temporary", "karratha_recovery_rows")])
        targets = re.findall(r"(?i)\binsert\s+into\s+([a-z_][a-z0-9_.]*)", code)
        self.assertEqual(targets, ["pg_temp.karratha_recovery_rows"])
        self.assertNotRegex(code, r"(?i)\b(?:update|delete\s+from|truncate|alter|drop|copy)\s+[a-z_]")
        self.assertIn("t.relname,'karratha_pdc',t.relname", code)
        self.assertIn("n.nspname='karratha_pdc'", code)
        self.assertIn("'auth_accounts',false", code)
        self.assertIn("'storage_object_bytes',false", code)


if __name__ == "__main__":
    unittest.main()
