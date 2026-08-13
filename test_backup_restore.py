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
try:
    import psycopg2  # type: ignore
    import psycopg2.extras  # type: ignore
except ImportError:
    psycopg2 = types.ModuleType("psycopg2")
    psycopg2.extras = types.ModuleType("psycopg2.extras")
    sys.modules["psycopg2"] = psycopg2
    sys.modules["psycopg2.extras"] = psycopg2.extras
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
AI_EMAIL_TABLES = {
    "ai_trusted_senders", "ai_mapping_rules", "ai_intake_config",
    "ai_email_intake", "ai_email_attachments", "ai_email_analysis_results",
    "ai_extracted_fields", "ai_workshop_commands", "ai_proposed_actions",
    "ai_review_items", "ai_undo_actions", "email_response_drafts",
    "import_runs", "label_print_events",
}
assert pdc_backup.BACKUP_FORMAT_VERSION == "2"
assert NAVISION_TABLES == pdc_backup.NAVISION_BACKUP_TABLES
assert NAVISION_TABLES.issubset(set(pdc_backup.TABLES))
assert AI_EMAIL_TABLES == pdc_backup.AI_EMAIL_BACKUP_TABLES
assert AI_EMAIL_TABLES.issubset(set(pdc_backup.TABLES))
assert "workshop_station_revision" in pdc_backup.TABLES
assert "workshop_stage_aliases" in pdc_backup.TABLES
assert len(pdc_backup.WORKSHOP_ALIASES_042) == 22
assert len(pdc_backup.WORKSHOP_ALIASES_044) == 37
assert len(pdc_backup.WORKSHOP_ALIAS_VALUES_044) == 37
versioned_tables = {
    45: pdc_backup.MIGRATION_045_BACKUP_TABLES, 53: pdc_backup.MIGRATION_053_BACKUP_TABLES,
    54: pdc_backup.MIGRATION_054_BACKUP_TABLES, 56: pdc_backup.MIGRATION_056_BACKUP_TABLES,
    60: pdc_backup.MIGRATION_060_BACKUP_TABLES, 61: pdc_backup.MIGRATION_061_BACKUP_TABLES,
    63: pdc_backup.MIGRATION_063_BACKUP_TABLES, 65: pdc_backup.MIGRATION_065_BACKUP_TABLES,
    66: pdc_backup.MIGRATION_066_BACKUP_TABLES, 72: pdc_backup.MIGRATION_072_BACKUP_TABLES,
    74: pdc_backup.MIGRATION_074_BACKUP_TABLES, 93: pdc_backup.MIGRATION_093_BACKUP_TABLES,
    160: pdc_backup.MIGRATION_160_BACKUP_TABLES, 161: pdc_backup.MIGRATION_161_BACKUP_TABLES,
    162: pdc_backup.MIGRATION_162_BACKUP_TABLES, 168: pdc_backup.MIGRATION_168_BACKUP_TABLES,
    170: pdc_backup.MIGRATION_170_BACKUP_TABLES,
}
all_versioned = frozenset().union(*versioned_tables.values())
base_tables = frozenset(pdc_backup.TABLES).difference(all_versioned)
for version in (44, 45, 53, 54, 56, 60, 61, 63, 65, 66, 72, 74, 93, 159, 160, 161, 162, 167, 168, 169, 170):
    expected = base_tables | frozenset().union(*(tables for introduced, tables in versioned_tables.items() if introduced <= version))
    assert pdc_backup.required_backup_tables(str(version).zfill(3)) == expected, version
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
for tamper_key in ("row_hash", "schema_hash"):
    broken = format2_payload({"vehicles"})
    if tamper_key == "row_hash":
        broken["table_hashes"]["vehicles"] = "0" * 64
    else:
        broken["schema_objects"]["vehicles"]["sha256"] = "1" * 64
    try:
        pdc_restore.validate_backup_contract(broken)
        raise AssertionError(f"Tampered non-alias {tamper_key} must fail before schema creation")
    except RuntimeError:
        pass
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
try:
    pdc_restore.validate_backup_contract({"backup_format_version": "1", "migration_version": "044"})
    raise AssertionError("Format-1 payload claiming migration 044 must fail closed")
except RuntimeError:
    pass

# Migration-044 alias authority must be present, complete and independently
# count/hash evidenced; removing or remapping one alias fails closed.
alias_tables = set(pdc_backup.required_backup_tables("044"))
alias_payload = format2_payload(alias_tables, "044")
alias_rows = [{"alias_normalized": alias, "alias_value": pdc_backup.WORKSHOP_ALIAS_VALUES_044[alias], "stage_code": stage}
              for alias, stage in sorted(pdc_backup.WORKSHOP_ALIASES_044.items())]
alias_columns = ["alias_normalized", "alias_value", "stage_code"]
alias_payload["tables"]["workshop_stage_aliases"] = {"columns": alias_columns, "rows": alias_rows}
alias_payload["row_counts"]["workshop_stage_aliases"] = len(alias_rows)
alias_payload["table_hashes"]["workshop_stage_aliases"] = pdc_backup.deterministic_table_hash(alias_columns, alias_rows)
alias_pairs = [(row["alias_normalized"], row["alias_value"], row["stage_code"]) for row in alias_rows]
alias_payload["authority_contracts"] = {"workshop_stage_aliases": {
    "row_count": len(alias_pairs),
    "required_alias_count": len(pdc_backup.WORKSHOP_ALIASES_044),
    "normalization_sha256": hashlib.sha256(json.dumps(alias_pairs, separators=(",", ":")).encode()).hexdigest(),
}}
pdc_restore.validate_backup_contract(alias_payload)
# 045 makes the reconciliation receipt table mandatory without breaking the
# pre-045 backup needed immediately before migration application.
receipt_payload = copy.deepcopy(alias_payload)
receipt_payload["migration_version"] = "045"
receipt_payload["tables"]["legacy_stage_reconciliation_receipts"] = {"columns": [], "rows": []}
receipt_payload["row_counts"]["legacy_stage_reconciliation_receipts"] = 0
receipt_payload["table_hashes"]["legacy_stage_reconciliation_receipts"] = pdc_backup.deterministic_table_hash([], [])
receipt_payload["schema_objects"]["legacy_stage_reconciliation_receipts"] = copy.deepcopy(empty_structure)
receipt_payload["schema_objects"]["legacy_stage_reconciliation_receipts"]["sha256"] = empty_hash
pdc_restore.validate_backup_contract(receipt_payload)
missing_receipt = copy.deepcopy(receipt_payload)
for key in ("tables", "row_counts", "table_hashes", "schema_objects"):
    missing_receipt[key].pop("legacy_stage_reconciliation_receipts", None)
try:
    pdc_restore.validate_backup_contract(missing_receipt)
    raise AssertionError("Migration-045 payload missing reconciliation receipts must fail closed")
except RuntimeError:
    pass
# Duplicate normalized identities must fail before any restore schema is created,
# even when all caller-supplied counts and hashes are self-consistent.
duplicate_alias = copy.deepcopy(alias_payload)
duplicate_alias["tables"]["workshop_stage_aliases"]["rows"].append(copy.deepcopy(alias_rows[0]))
duplicate_rows = duplicate_alias["tables"]["workshop_stage_aliases"]["rows"]
duplicate_alias["row_counts"]["workshop_stage_aliases"] = len(duplicate_rows)
duplicate_alias["table_hashes"]["workshop_stage_aliases"] = pdc_backup.deterministic_table_hash(alias_columns, duplicate_rows)
duplicate_pairs = sorted((row["alias_normalized"], row["alias_value"], row["stage_code"]) for row in duplicate_rows)
duplicate_alias["authority_contracts"]["workshop_stage_aliases"]["row_count"] = len(duplicate_pairs)
duplicate_alias["authority_contracts"]["workshop_stage_aliases"]["normalization_sha256"] = hashlib.sha256(json.dumps(duplicate_pairs, separators=(",", ":")).encode()).hexdigest()
try:
    pdc_restore.validate_backup_contract(duplicate_alias)
    raise AssertionError("Duplicate alias identity must fail preflight before DDL")
except RuntimeError:
    pass
for omitted in pdc_backup.required_backup_tables("044"):
    broken = copy.deepcopy(alias_payload)
    for key in ("tables", "row_counts", "table_hashes", "schema_objects"):
        broken[key].pop(omitted, None)
    try:
        pdc_restore.validate_backup_contract(broken)
        raise AssertionError(f"Migration-044 payload missing {omitted} must fail closed")
    except RuntimeError:
        pass

for tamper in ("unexpected_alias", "malformed_alias_value"):
    broken = copy.deepcopy(alias_payload)
    if tamper == "unexpected_alias":
        broken["tables"]["workshop_stage_aliases"]["rows"].append({"alias_normalized":"EXTRA","alias_value":"Extra","stage_code":"HOIST"})
        broken["row_counts"]["workshop_stage_aliases"] += 1
    else:
        broken["tables"]["workshop_stage_aliases"]["rows"][0]["alias_value"] = "Wrong Value"
    try:
        pdc_restore.validate_backup_contract(broken)
        raise AssertionError(f"Alias semantic tamper must fail closed: {tamper}")
    except RuntimeError:
        pass
for tamper in ("missing_table", "missing_alias", "bad_hash"):
    broken = copy.deepcopy(alias_payload)
    if tamper == "missing_table":
        for key in ("tables", "row_counts", "table_hashes", "schema_objects"):
            broken[key].pop("workshop_stage_aliases", None)
    elif tamper == "missing_alias":
        broken["tables"]["workshop_stage_aliases"]["rows"].pop()
        broken["row_counts"]["workshop_stage_aliases"] -= 1
    else:
        broken["authority_contracts"]["workshop_stage_aliases"]["normalization_sha256"] = "0" * 64
    try:
        pdc_restore.validate_backup_contract(broken)
        raise AssertionError(f"Alias authority tamper must fail closed: {tamper}")
    except RuntimeError:
        pass

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
for required in ('artifact_path', 'artifact_size_bytes', 'artifact_sha256'):
    assert required in main_source, f"Restore receipt must bind exact backup {required}"
assert main_source.index('report["artifact_sha256"]') < main_source.index("insert into public.restore_test_runs"), "Exact artifact identity must be persisted in the restore receipt before commit"
assert main_source.index("if args.drop_after:") < main_source.index("conn.commit()") < main_source.index("print(json.dumps(report"), "Drop-after cleanup and report persistence must commit atomically before success output"

class TriggerCursor:
    def __init__(self): self.statements = []
    def execute(self, statement, params=None): self.statements.append((statement, params))

trigger_cursor = TriggerCursor()
restored_triggers = pdc_restore.create_format_v2_triggers(trigger_cursor, "restore_gate", {
    "sample": {"triggers": [{
        "name": "sample_guard", "enabled": "A",
        "definition": "CREATE CONSTRAINT TRIGGER sample_guard AFTER INSERT ON public.sample DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.sample_guard()",
    }]}
}, ["sample"])
assert restored_triggers == [("sample", "sample_guard", "A")]
assert 'ON "restore_gate"."sample"' in trigger_cursor.statements[0][0]
assert 'enable always trigger "sample_guard"' in trigger_cursor.statements[1][0].lower()
assert "triggers" in inspect.getsource(pdc_backup.export_schema_metadata)

print("Backup format-2 exact evidence, historical structure, fail-closed inventory and legacy compatibility checks passed")
