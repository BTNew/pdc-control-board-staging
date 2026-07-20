"""Local contract and adversarial checks for backup format 2."""
import copy
from decimal import Decimal
import hashlib
import inspect
import tempfile
import json
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
psycopg2 = types.ModuleType("psycopg2")
psycopg2.extras = types.ModuleType("psycopg2.extras")
sys.modules.setdefault("psycopg2", psycopg2)
sys.modules.setdefault("psycopg2.extras", psycopg2.extras)
cryptography = types.ModuleType("cryptography")
fernet = types.ModuleType("cryptography.fernet")
fernet.Fernet = object
sys.modules.setdefault("cryptography", cryptography)
sys.modules.setdefault("cryptography.fernet", fernet)

import pdc_backup  # noqa: E402
import pdc_restore  # noqa: E402

NAVISION_TABLES = {
    "navision_backend_revision", "navision_import_batches", "navision_backend_records",
    "navision_import_items", "navision_operation_receipts", "navision_rollback_items",
    "navision_backend_audit",
}
assert pdc_backup.BACKUP_FORMAT_VERSION == "2"
assert NAVISION_TABLES == pdc_backup.NAVISION_BACKUP_TABLES
assert NAVISION_TABLES.issubset(set(pdc_backup.TABLES))
assert pdc_backup.migration_number("037_shared") == 37

columns = ["id", "payload"]
rows_a = [{"id": 2, "payload": {"b": 2}}, {"id": 1, "payload": {"a": 1}}]
rows_b = list(reversed(rows_a))
assert pdc_backup.deterministic_table_hash(columns, rows_a) == pdc_backup.deterministic_table_hash(columns, rows_b)
assert pdc_backup.deterministic_table_hash(columns, rows_a) != pdc_backup.deterministic_table_hash(columns, [{"id": 1, "payload": {"a": 2}}])

legacy = pdc_restore.verify_format_v2_evidence(None, "restore_test_legacy", {"backup_format_version": "1"})
assert legacy["legacy_format_supported"] is True
assert legacy["all_hashes_match"] is True
assert legacy["all_schema_objects_match"] is True

empty_structure = {"columns": [], "constraints": [], "indexes": [], "sequences": []}
empty_hash = hashlib.sha256(json.dumps(empty_structure, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
def format2_payload(table_names, migration="036"):
    return {
        "backup_format_version": "2", "migration_version": migration,
        "tables": {name: {"columns": [], "rows": []} for name in table_names},
        "table_hashes": {name: pdc_backup.deterministic_table_hash([], []) for name in table_names},
        "schema_objects": {name: {**copy.deepcopy(empty_structure), "sha256": empty_hash} for name in table_names},
        "row_counts": {name: 0 for name in table_names},
    }

pdc_restore.validate_backup_contract(format2_payload({"vehicles"}))
broken = format2_payload({"vehicles"})
del broken["table_hashes"]["vehicles"]
try:
    pdc_restore.validate_backup_contract(broken)
    raise AssertionError("Missing format-2 row hash must fail closed")
except RuntimeError:
    pass
try:
    pdc_restore.validate_backup_contract(format2_payload({"vehicles"}, "037"))
    raise AssertionError("Migration-037 payload missing Navision tables must fail closed")
except RuntimeError:
    pass
pdc_restore.validate_backup_contract(format2_payload(NAVISION_TABLES, "037"))

# Adversarial exact-schema verifier: wrong index definition must not pass.
meta = {
    "columns": [{
        "column_name": "id", "formatted_type": "uuid", "data_type": "uuid",
        "udt_schema": "pg_catalog", "udt_name": "uuid", "is_nullable": "NO",
        "column_default": None, "is_identity": "NO", "identity_generation": None,
        "is_generated": "NEVER", "generation_expression": None, "collation_name": None,
        "character_maximum_length": None, "numeric_precision": None, "numeric_scale": None,
    }],
    "constraints": [{"conname": "sample_pkey", "contype": "p", "convalidated": True,
                     "condeferrable": False, "condeferred": False, "definition": "PRIMARY KEY (id)"}],
    "indexes": [{"name": "sample_pkey", "indisunique": True, "indisprimary": True,
                 "indisvalid": True, "indisready": True, "constraint_owned": True,
                 "definition": "CREATE UNIQUE INDEX sample_pkey ON public.sample USING btree (id)"}],
    "sequences": [],
}
meta_hash = hashlib.sha256(json.dumps(meta, default=pdc_backup.json_default, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
rows = [{"id": "00000000-0000-0000-0000-000000000001"}]
data = {
    "backup_format_version": "2", "migration_version": "036",
    "tables": {"sample": {"columns": ["id"], "rows": rows}},
    "table_hashes": {"sample": pdc_backup.deterministic_table_hash(["id"], rows)},
    "schema_objects": {"sample": {**copy.deepcopy(meta), "sha256": meta_hash}},
    "row_counts": {"sample": 1},
}
original_export_table = pdc_restore.export_table
original_export_schema = pdc_restore.export_schema_metadata
pdc_restore.export_table = lambda cur, table, schema: (["id"], copy.deepcopy(rows))
pdc_restore.export_schema_metadata = lambda cur, schema, names: {"sample": {**copy.deepcopy(meta), "sha256": meta_hash}}
report = pdc_restore.verify_format_v2_evidence(object(), "restore_test", data)
assert report["all_hashes_match"] and report["all_schema_objects_match"]
wrong = copy.deepcopy(meta)
wrong["indexes"][0]["definition"] = "CREATE UNIQUE INDEX sample_pkey ON restore_test.sample USING hash (id)"
pdc_restore.export_schema_metadata = lambda cur, schema, names: {"sample": {**wrong, "sha256": "irrelevant"}}
report = pdc_restore.verify_format_v2_evidence(object(), "restore_test", data)
assert report["all_schema_objects_match"] is False, "Wrong index column/method must fail exact structural verification"
pdc_restore.export_table = original_export_table
pdc_restore.export_schema_metadata = original_export_schema

class SequenceCursor:
    def __init__(self): self.statements = []
    def execute(self, statement, params=None): self.statements.append((statement, params))
    def fetchone(self): return ('"restore"."records_id_seq"',)

sequence_cursor = SequenceCursor()
restored = pdc_restore.restore_sequence_state(sequence_cursor, "restore", {
    "records": {"sequences": [{"name": "records_id_seq", "column_name": "id", "data_type": "bigint",
        "start_value": 7, "min_value": 3, "max_value": 9999, "increment_by": 4,
        "cycle": True, "cache_size": 8, "last_value": 123, "is_called": False}]}
}, ["records"])
sequence_sql = "\n".join(str(item[0]).lower() for item in sequence_cursor.statements)
assert "increment by 4 minvalue 3 maxvalue 9999 start with 7 cache 8 cycle" in sequence_sql
assert any("setval" in item[0].lower() and item[1][1:] == (123, False) for item in sequence_cursor.statements)
assert restored == [("records", "records_id_seq", "id", 123)]
assert pdc_restore._canonical_schema_value(Decimal("123.0"), "restore") == "123.0"


class PublicationCursor:
    def __init__(self):
        self.statements = []
        self._last_sql = ""

    def execute(self, sql, params=None):
        self._last_sql = " ".join(str(sql).lower().split())
        self.statements.append((self._last_sql, params))

    def fetchall(self):
        if "from information_schema.tables" in self._last_sql:
            return [("alpha",)]
        return []


class PublicationConnection:
    def __init__(self, commit_check=None):
        self.cur = PublicationCursor()
        self.commits = 0
        self.rollbacks = 0
        self.commit_check = commit_check

    def cursor(self):
        return self.cur

    def commit(self):
        self.commits += 1
        if self.commit_check:
            self.commit_check(self.commits)

    def rollback(self):
        self.rollbacks += 1


class AmbiguousCommitConnection(PublicationConnection):
    def commit(self):
        self.commits += 1
        if self.commits == 2:
            raise ConnectionError("injected disconnect during success commit")

    def rollback(self):
        raise ConnectionError("injected disconnected rollback failure")


original_tables = list(pdc_backup.TABLES)
original_get_migration = pdc_backup.get_migration_version
original_export_table = pdc_backup.export_table
original_export_schema = pdc_backup.export_schema_metadata
original_durable_replace = pdc_backup.durable_replace
original_fernet = pdc_backup.Fernet
try:
    pdc_backup.TABLES[:] = ["alpha"]
    pdc_backup.get_migration_version = lambda _cur: "036"
    pdc_backup.export_table = lambda _cur, _table: (["id"], [{"id": 1}])
    pdc_backup.export_schema_metadata = lambda _cur, _schema, tables: {
        table: {"columns": [], "constraints": [], "indexes": [], "sequences": [], "sha256": "0" * 64}
        for table in tables
    }
    class PublicationFernet:
        def __init__(self, _key):
            pass

        def encrypt(self, content):
            return b"test-encrypted:" + content

    pdc_backup.Fernet = PublicationFernet
    key = b"publication-test-key"

    with tempfile.TemporaryDirectory() as output_dir:
        publication_seen = []

        def check_success_commit(number):
            if number == 2:
                names = sorted(path.name for path in Path(output_dir).iterdir())
                assert any(name.endswith(".bin") for name in names)
                assert any(name.endswith(".manifest.json") for name in names)
                assert not any(name.endswith(".tmp") for name in names)
                publication_seen.append(True)

        success_conn = PublicationConnection(check_success_commit)
        _, success = pdc_backup.run_backup(success_conn, "staging", output_dir, key)
        assert success["status"] == "success" and publication_seen, success
        statements = [sql for sql, _ in success_conn.cur.statements]
        isolation_index = next(i for i, sql in enumerate(statements) if "set transaction isolation level repeatable read" in sql)
        inventory_index = next(i for i, sql in enumerate(statements) if "from information_schema.tables" in sql)
        assert isolation_index < inventory_index

    with tempfile.TemporaryDirectory() as output_dir:
        ambiguous_conn = AmbiguousCommitConnection()
        _, ambiguous = pdc_backup.run_backup(ambiguous_conn, "staging", output_dir, key)
        assert ambiguous["status"] == "failed"
        assert "outcome is unknown" in ambiguous["error"]
        assert "disconnected rollback failure" in ambiguous["rollback_error"]
        retained = sorted(path.name for path in Path(output_dir).iterdir())
        assert any(name.endswith(".bin") for name in retained)
        assert any(name.endswith(".manifest.json") for name in retained)

    with tempfile.TemporaryDirectory() as output_dir:
        replacement_count = [0]

        def fail_manifest_replace(source, target):
            replacement_count[0] += 1
            if replacement_count[0] == 2:
                raise OSError("injected manifest publication failure")
            return original_durable_replace(source, target)

        pdc_backup.durable_replace = fail_manifest_replace
        failure_conn = PublicationConnection()
        _, failure = pdc_backup.run_backup(failure_conn, "staging", output_dir, key)
        assert failure["status"] == "failed"
        assert list(Path(output_dir).iterdir()) == [], "Failed pair publication must remove final and temporary files"
finally:
    pdc_backup.TABLES[:] = original_tables
    pdc_backup.get_migration_version = original_get_migration
    pdc_backup.export_table = original_export_table
    pdc_backup.export_schema_metadata = original_export_schema
    pdc_backup.durable_replace = original_durable_replace
    pdc_backup.Fernet = original_fernet

backup_source = Path("scripts/pdc_backup.py").read_text(encoding="utf-8")
restore_source = Path("scripts/pdc_restore.py").read_text(encoding="utf-8")
assert 'set transaction isolation level repeatable read' in backup_source.lower(), "Backup export must use one repeatable-read MVCC snapshot"
snapshot_gate = backup_source.index('cur.execute("set transaction isolation level repeatable read")')
first_export = backup_source.index('for table in payload_tables:')
assert snapshot_gate < first_export, "Repeatable-read snapshot must begin before any table export"
artifact_publish = backup_source.index("durable_replace(artifact_tmp, file_path)")
manifest_publish = backup_source.index("durable_replace(manifest_tmp, manifest_path)")
directory_sync = backup_source.index("fsync_directory(output_dir)")
success_update = backup_source.index("set status = 'success'")
success_commit = backup_source.index("success_commit_attempted = True")
assert artifact_publish < manifest_publish < directory_sync < success_update < success_commit, "Both complete files and rename metadata must be durable before the database can be marked successful"
assert "file_path.write_bytes(encrypted)" not in backup_source, "Encrypted artifact must not be written directly to its final path"
assert "os.fsync(handle.fileno())" in backup_source, "Temporary backup files must be flushed before atomic publication"
assert "movefile_write_through = 0x8" in backup_source, "Windows publication must request write-through rename durability"
for required in ["table_hashes", "schema_objects", "sequences", "is_called", "NAVISION_BACKUP_TABLES"]:
    assert required in backup_source
for required in ["validate_backup_contract", "create_format_v2_structure", "foreign_keys_from_evidence", "restore_sequence_state", "source_evidence_hash_valid"]:
    assert required in restore_source
restore_function_source = inspect.getsource(pdc_restore.restore_backup)
assert ".commit(" not in restore_function_source, "Restore helper must leave DDL, load and verification in the caller-owned transaction"
assert "if not report[\"all_checks_passed\"]" in restore_function_source, "Failed parity must abort before caller commit"
main_source = inspect.getsource(pdc_restore.main)
assert main_source.index("if args.drop_after:") < main_source.index("conn.commit()") < main_source.index("print(json.dumps(report"), "Drop-after cleanup and report persistence must commit atomically before success output"

print("Backup format-2 exact evidence, historical structure, fail-closed inventory and legacy compatibility checks passed")
