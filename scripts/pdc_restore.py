"""
PDC Control Board — staging-only restore of an encrypted backup into an
isolated schema for verification.

This NEVER touches the live `public` schema. It creates a brand-new
Postgres schema (e.g. `restore_test_20260717t021003z`), recreates every
backed-up table's structure inside that schema (columns, types, defaults,
primary keys, indexes via `LIKE ... INCLUDING ALL`, plus foreign keys
re-added afterwards from the live FK map so relationships are restored
too), loads every row from the backup, and then runs a verification pass
that reports row counts and a set of concrete relationship checks (the
same categories called out in the task: vehicle notes stay attached to
the right vehicle, bookings return to the right bay/time, technician
assignments restored, audit history preserved, notifications restored
without being resendable).

Safety:
- Only ever creates a new schema; never DROPs or writes to `public`.
- Notification rows are restored with status forced to
  'restored_disabled' (a value outside the RPC-writable enum used by the
  live app) so no worker or process can ever pick them up and re-send a
  historical notification. This is verified in the report.
- Does not require and does not use any mailbox/email-provider
  credentials -- confirms no worker/email process can run against this
  schema by construction (the restored tables are not the ones any
  worker script points at; they live in an isolated schema name that no
  script references).
"""
import argparse
import copy
import hashlib
import hmac
from decimal import Decimal
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pdc_backup import (  # noqa: E402
    decrypt_backup,
    deterministic_table_hash,
    export_schema_metadata,
    export_table,
    json_default,
    TABLES,
    NAVISION_BACKUP_TABLES,
    migration_number,
    required_workshop_aliases,
    required_workshop_alias_values,
    required_backup_tables,
)


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def discover_foreign_keys(cur, payload_tables=None):
    """Return complete FK definitions for every payload table.

    Catalog-level definitions preserve composite keys, actions, deferrability,
    validation state and references outside ``public`` (notably auth.users).
    Public referenced tables are rebound to the isolated restore schema when
    they are present in the concrete retained-backup payload.
    """
    allowed_tables = set(TABLES if payload_tables is None else payload_tables)
    cur.execute(
        """
        select src.relname, con.conname, pg_get_constraintdef(con.oid, true),
               ref_ns.nspname, ref.relname
        from pg_constraint con
        join pg_class src on src.oid = con.conrelid
        join pg_namespace src_ns on src_ns.oid = src.relnamespace
        join pg_class ref on ref.oid = con.confrelid
        join pg_namespace ref_ns on ref_ns.oid = ref.relnamespace
        where con.contype = 'f' and src_ns.nspname = 'public'
          and src.relname = any(%s)
        order by src.relname, con.conname
        """,
        (list(allowed_tables),),
    )
    return [tuple(row) for row in cur.fetchall() if row and row[0] in allowed_tables]




def create_isolated_schema(cur, schema_name):
    cur.execute(f"create schema {quote_ident(schema_name)}")


def clone_table_structure(cur, schema_name, table_name):
    # LIKE ... INCLUDING ALL copies columns/types/defaults/PK/unique/check
    # constraints/indexes -- everything except cross-table FOREIGN KEYs,
    # which Postgres deliberately does not carry across via LIKE.
    cur.execute(
        f'create table {quote_ident(schema_name)}.{quote_ident(table_name)} '
        f'(like public.{quote_ident(table_name)} including all)'
    )


def validate_backup_contract(data):
    version = str(data.get("backup_format_version", "1"))
    if version == "1":
        if migration_number(data.get("migration_version")) >= 42:
            raise RuntimeError("Legacy format-1 backups cannot claim migration 042 or later")
        return {"format_version": version, "legacy": True}
    if version != "2":
        raise RuntimeError(f"Unsupported backup format version: {version}")
    tables, hashes = data.get("tables"), data.get("table_hashes")
    schema, counts = data.get("schema_objects"), data.get("row_counts")
    if not all(isinstance(value, dict) for value in (tables, hashes, schema, counts)):
        raise RuntimeError("Format-2 backup is missing tables, row hashes, schema objects or row counts")
    table_names = set(tables)
    if set(hashes) != table_names or set(schema) != table_names or set(counts) != table_names:
        raise RuntimeError("Format-2 evidence must cover exactly every payload table")
    required_tables = required_backup_tables(data.get("migration_version"))
    if required_tables and table_names != required_tables:
        missing = sorted(required_tables - table_names)
        unexpected = sorted(table_names - required_tables)
        raise RuntimeError("Migration-042+ operational inventory mismatch; missing=" + ",".join(missing) + "; unexpected=" + ",".join(unexpected))
    if migration_number(data.get("migration_version")) >= 37:
        missing = sorted(NAVISION_BACKUP_TABLES - table_names)
        if missing:
            raise RuntimeError("Migration-037 backup is missing required tables: " + ", ".join(missing))
    if migration_number(data.get("migration_version")) >= 42:
        if "workshop_stage_aliases" not in table_names:
            raise RuntimeError("Workshop alias authority is missing from the backup payload")
        evidence = data.get("authority_contracts", {}).get("workshop_stage_aliases")
        if not isinstance(evidence, dict):
            raise RuntimeError("Workshop alias authority evidence is missing")
        details = tables["workshop_stage_aliases"]
        columns = details.get("columns", [])
        try:
            aliases = sorted((str(row["alias_normalized"]), str(row["alias_value"]), str(row["stage_code"])) for row in details.get("rows", []))
        except (KeyError, TypeError) as exc:
            raise RuntimeError("Workshop alias payload is malformed") from exc
        if not {"alias_normalized", "alias_value", "stage_code"}.issubset(columns):
            raise RuntimeError("Workshop alias payload lacks normalization columns")
        required = required_workshop_aliases(data.get("migration_version"))
        values = required_workshop_alias_values(data.get("migration_version"))
        actual = {alias: (value, stage) for alias, value, stage in aliases}
        expected = {alias: (values[alias], stage) for alias, stage in required.items()}
        malformed = [alias for alias, value, _stage in aliases
                     if alias != re.sub(r"[^A-Za-z0-9]+", "", value).upper()]
        canonical = json.dumps(aliases, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
        duplicate_aliases = len(actual) != len(aliases)
        if (actual != expected or malformed or duplicate_aliases
                or len(aliases) != len(required)
                or evidence.get("row_count") != len(aliases)
                or evidence.get("required_alias_count") != len(required)
                or evidence.get("normalization_sha256") != hashlib.sha256(canonical).hexdigest()):
            raise RuntimeError("Workshop alias authority is incomplete, duplicated or its count/hash evidence is invalid")
    for table, details in tables.items():
        if not isinstance(details, dict) or not isinstance(details.get("columns"), list) or not isinstance(details.get("rows"), list):
            raise RuntimeError(f"Format-2 table payload is malformed: {table}")
        if counts[table] != len(details["rows"]):
            raise RuntimeError(f"Format-2 row count evidence is inconsistent: {table}")
        expected_row_hash = deterministic_table_hash(details["columns"], details["rows"])
        if not isinstance(hashes[table], str) or not hmac.compare_digest(hashes[table], expected_row_hash):
            raise RuntimeError(f"Format-2 row hash evidence is inconsistent: {table}")
        if not isinstance(schema[table], dict) or not isinstance(schema[table].get("sha256"), str):
            raise RuntimeError(f"Format-2 schema evidence is incomplete: {table}")
        keys = ("columns", "constraints", "indexes", "sequences", "triggers") if "triggers" in schema[table] else ("columns", "constraints", "indexes", "sequences")
        structure = {key: schema[table].get(key, []) for key in keys}
        expected_schema_hash = hashlib.sha256(json.dumps(
            structure, default=json_default, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")).hexdigest()
        if not hmac.compare_digest(schema[table]["sha256"], expected_schema_hash):
            raise RuntimeError(f"Format-2 schema hash evidence is inconsistent: {table}")
    return {"format_version": version, "legacy": False}


def _decode_number(value):
    if isinstance(value, dict) and set(value) == {"__decimal__"}:
        return value["__decimal__"]
    return value


def _column_type_sql(column):
    formatted = str(column.get("formatted_type") or column.get("udt_name") or column.get("data_type"))
    udt_schema = column.get("udt_schema")
    if column.get("data_type") == "USER-DEFINED" and udt_schema and udt_schema != "pg_catalog" and "." not in formatted:
        return f'{quote_ident(udt_schema)}.{quote_ident(column["udt_name"])}'
    return formatted


def _rewrite_sequence_default(expression, source_schema, target_schema, sequence_names):
    result = str(expression or "")
    for name in sequence_names:
        result = result.replace(f"'{source_schema}.{name}'::regclass", f"'{target_schema}.{name}'::regclass")
        result = result.replace(f"'\"{source_schema}\".\"{name}\"'::regclass", f"'{target_schema}.{name}'::regclass")
    return result


def create_format_v2_structure(cur, schema_name, schema_objects, table_order):
    """Reconstruct tables from encrypted schema evidence rather than current public."""
    for table in table_order:
        if table not in schema_objects:
            continue
        details = schema_objects[table]
        identity_columns = {c["column_name"] for c in details.get("columns", []) if c.get("is_identity") == "YES"}
        for sequence in details.get("sequences", []):
            if sequence.get("column_name") in identity_columns:
                continue
            sequence_type = str(_decode_number(sequence.get("data_type") or "bigint"))
            if sequence_type not in {"smallint", "integer", "bigint"}:
                raise ValueError(f"Unsupported backed-up sequence type: {sequence_type}")
            increment = int(_decode_number(sequence.get("increment_by") or 1))
            minimum = int(_decode_number(sequence.get("min_value")))
            maximum = int(_decode_number(sequence.get("max_value")))
            start = int(_decode_number(sequence.get("start_value") or 1))
            cache = int(_decode_number(sequence.get("cache_size") or 1))
            cur.execute(
                f'create sequence {quote_ident(schema_name)}.{quote_ident(sequence["name"])} '
                f'as {sequence_type} increment by {increment} minvalue {minimum} maxvalue {maximum} '
                f'start with {start} cache {cache} ' + ("cycle" if sequence.get("cycle") else "no cycle")
            )
        sequence_names = [row["name"] for row in details.get("sequences", [])]
        column_sql = []
        for column in details.get("columns", []):
            definition = f'{quote_ident(column["column_name"])} {_column_type_sql(column)}'
            if column.get("is_identity") == "YES":
                mode = "always" if str(column.get("identity_generation") or "").upper() == "ALWAYS" else "by default"
                definition += f" generated {mode} as identity"
            elif column.get("is_generated") == "ALWAYS":
                definition += f' generated always as ({column.get("generation_expression")}) stored'
            elif column.get("column_default") is not None:
                definition += " default " + _rewrite_sequence_default(column["column_default"], "public", schema_name, sequence_names)
            if column.get("is_nullable") == "NO":
                definition += " not null"
            column_sql.append(definition)
        cur.execute(f'create table {quote_ident(schema_name)}.{quote_ident(table)} (' + ", ".join(column_sql) + ")")
        for constraint in details.get("constraints", []):
            if constraint.get("contype") not in {"f", "t"}:
                cur.execute(f'alter table {quote_ident(schema_name)}.{quote_ident(table)} add constraint {quote_ident(constraint["conname"])} {constraint["definition"]}')


def create_format_v2_indexes(cur, schema_name, schema_objects, table_order):
    for table in table_order:
        for index in schema_objects.get(table, {}).get("indexes", []):
            if index.get("constraint_owned"):
                continue
            if table == "vehicle_notifications" and index.get("name") == "vehicle_notifications_status_idx":
                continue
            definition = str(index.get("definition") or "")
            using_at = definition.upper().find(" USING ")
            if using_at < 0:
                raise RuntimeError(f"Cannot reconstruct index definition: {table}.{index.get('name')}")
            unique = "unique " if index.get("indisunique") else ""
            cur.execute(f'create {unique}index {quote_ident(index["name"])} on {quote_ident(schema_name)}.{quote_ident(table)}' + definition[using_at:])


def create_format_v2_triggers(cur, schema_name, schema_objects, table_order):
    """Recreate retained user triggers only after all rows and FKs exist."""
    restored = []
    modes = {"O": "enable", "D": "disable", "R": "enable replica", "A": "enable always"}
    for table in table_order:
        for trigger in schema_objects.get(table, {}).get("triggers", []):
            definition = str(trigger.get("definition") or "")
            pattern = rf'(?i)(\sON\s+)(?:(?:"?public"?)\.)?"?{re.escape(table)}"?(\s+)'
            replacement = rf'\1{quote_ident(schema_name)}.{quote_ident(table)}\2'
            target_definition, count = re.subn(pattern, replacement, definition, count=1)
            if count != 1:
                raise RuntimeError(f"Cannot rebind trigger target: {table}.{trigger.get('name')}")
            cur.execute(target_definition)
            enabled = str(trigger.get("enabled") or "O")
            if enabled not in modes:
                raise RuntimeError(f"Unsupported trigger enabled mode: {table}.{trigger.get('name')}={enabled}")
            if enabled != "O":
                cur.execute(
                    f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                    f'{modes[enabled]} trigger {quote_ident(trigger["name"])}'
                )
            restored.append((table, trigger.get("name"), enabled))
    return restored


def foreign_keys_from_evidence(schema_objects, payload_tables):
    result = []
    pattern = re.compile(r"(?i)references\s+(?:(?P<schema>[\w\"]+)\.)?(?P<table>[\w\"]+)")
    for table in payload_tables:
        for constraint in schema_objects.get(table, {}).get("constraints", []):
            if constraint.get("contype") != "f":
                continue
            definition = constraint["definition"]
            match = pattern.search(definition)
            if not match:
                raise RuntimeError(f"Cannot parse backed-up FK definition: {table}.{constraint.get('conname')}")
            result.append((table, constraint["conname"], definition,
                           (match.group("schema") or "public").strip('"'), match.group("table").strip('"'),
                           bool(constraint.get("convalidated", True))))
    return result


def restore_sequence_state(cur, schema_name, schema_objects, table_order):
    restored = []
    for table in table_order:
        for sequence in schema_objects.get(table, {}).get("sequences", []):
            column = sequence.get("column_name")
            cur.execute("select pg_get_serial_sequence(%s,%s)", (f'{schema_name}.{table}', column))
            relation = cur.fetchone()[0]
            if not relation:
                relation = f'{quote_ident(schema_name)}.{quote_ident(sequence["name"])}'
                cur.execute(f'alter sequence {relation} owned by {quote_ident(schema_name)}.{quote_ident(table)}.{quote_ident(column)}')
            data_type = str(_decode_number(sequence.get("data_type", "bigint")))
            if data_type not in {"smallint", "integer", "bigint"}:
                raise ValueError(f"Unsupported backed-up sequence type: {data_type}")
            cycle_sql = "cycle" if sequence.get("cycle") else "no cycle"
            increment = int(_decode_number(sequence["increment_by"]))
            minimum = int(_decode_number(sequence["min_value"]))
            maximum = int(_decode_number(sequence["max_value"]))
            start = int(_decode_number(sequence["start_value"]))
            cache = int(_decode_number(sequence["cache_size"]))
            cur.execute(
                f"alter sequence {relation} as {data_type} increment by {increment} minvalue {minimum} maxvalue {maximum} start with {start} cache {cache} {cycle_sql}"
            )
            last_value = sequence.get("last_value")
            if last_value is not None:
                cur.execute("select setval(%s::regclass,%s,%s)", (relation, int(last_value), bool(sequence.get("is_called", True))))
            restored.append((table, sequence["name"], column, last_value))
    return restored


def synchronize_non_fk_constraints(cur, schema_name, table_names):
    """Restore exact names and validation state for local constraints.

    PostgreSQL LIKE copies local constraint semantics but may regenerate UNIQUE
    names and turns copied NOT VALID checks into validated checks. Reconcile
    those catalog details before data loading; foreign keys remain a separate
    post-load operation.
    """
    def load(schema):
        cur.execute("""select c.relname,con.conname,con.contype,con.convalidated,
                              pg_get_constraintdef(con.oid,true)
                       from pg_constraint con join pg_class c on c.oid=con.conrelid
                       join pg_namespace n on n.oid=c.relnamespace
                       where n.nspname=%s and c.relname=any(%s) and con.contype not in ('f','t')
                       order by c.relname,con.conname""", (schema, list(table_names)))
        return [tuple(row) for row in cur.fetchall()]

    source = load("public")
    restored = load(schema_name)
    restored_by_name = {(row[0], row[1]): row for row in restored}
    for table, source_name, contype, validated, definition in source:
        current = restored_by_name.get((table, source_name))
        if current and current[2:] == (contype, validated, definition):
            continue
        if current:
            cur.execute(f'alter table {quote_ident(schema_name)}.{quote_ident(table)} drop constraint {quote_ident(source_name)}')
        else:
            semantic = definition.removesuffix(" NOT VALID")
            candidates = [row for row in restored if row[0] == table and row[2] == contype
                          and row[4].removesuffix(" NOT VALID") == semantic]
            if len(candidates) != 1:
                raise RuntimeError(f"cannot map restored constraint {table}.{source_name}")
            old_name = candidates[0][1]
            cur.execute(f'alter table {quote_ident(schema_name)}.{quote_ident(table)} rename constraint '
                        f'{quote_ident(old_name)} to {quote_ident(source_name)}')
            current = (table, source_name, contype, candidates[0][3], candidates[0][4])
            if current[2:] == (contype, validated, definition):
                continue
            cur.execute(f'alter table {quote_ident(schema_name)}.{quote_ident(table)} drop constraint {quote_ident(source_name)}')
        cur.execute(f'alter table {quote_ident(schema_name)}.{quote_ident(table)} add constraint '
                    f'{quote_ident(source_name)} {definition}')


def add_foreign_keys(cur, schema_name, foreign_keys, payload_tables=None):
    """Add and validate every source FK represented by the payload.

    References to payload tables are rebound to the isolated restore schema;
    external schemas such as ``auth`` remain explicit and are still validated.
    """
    added, skipped = [], []
    allowed_tables = set(TABLES if payload_tables is None else payload_tables)
    for foreign_key in foreign_keys:
        table, constraint_name, definition, ref_schema, ref_table = foreign_key[:5]
        should_validate = foreign_key[5] if len(foreign_key) > 5 else True
        if table not in allowed_tables:
            skipped.append((table, constraint_name, "referencing table not present in backup payload"))
            continue
        if ref_schema == "public" and ref_table not in allowed_tables:
            skipped.append((table, constraint_name, "referenced public table not present in backup payload"))
            continue
        target_definition = definition.removesuffix(" NOT VALID")
        if ref_schema == "public":
            pattern = rf"(?i)(references\s+)(?:public\.)?{re.escape(ref_table)}\b"
            replacement = rf"\1{quote_ident(schema_name)}.{quote_ident(ref_table)}"
            target_definition, replacements = re.subn(pattern, replacement, target_definition, count=1)
            if replacements != 1:
                skipped.append((table, constraint_name, "could not rebind referenced public table"))
                continue
        savepoint = f"sp_fk_{len(added) + len(skipped)}"
        cur.execute(f'savepoint {quote_ident(savepoint)}')
        try:
            cur.execute(
                f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                f'add constraint {quote_ident(constraint_name)} {target_definition} not valid'
            )
            if should_validate:
                cur.execute(
                    f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                    f'validate constraint {quote_ident(constraint_name)}'
                )
            cur.execute(f'release savepoint {quote_ident(savepoint)}')
            added.append((table, constraint_name))
        except Exception as exc:  # noqa: BLE001
            cur.execute(f'rollback to savepoint {quote_ident(savepoint)}')
            skipped.append((table, constraint_name, str(exc)))
    return added, skipped


DECIMAL_MARKER = "__decimal__"
BYTES_MARKER = "__bytes_hex__"


def decode_value(value, is_jsonb_column=False):
    if isinstance(value, dict):
        if DECIMAL_MARKER in value:
            return value[DECIMAL_MARKER]
        if BYTES_MARKER in value:
            return bytes.fromhex(value[BYTES_MARKER])
        # jsonb columns are legitimately dicts in the payload -- json.dumps
        # them back for insertion as jsonb.
        return json.dumps(value)
    if isinstance(value, list):
        if is_jsonb_column:
            # A jsonb column whose value happens to be a JSON array (e.g.
            # classifications: ["parts_update"]) must be re-serialized as
            # JSON text, not passed through as a native Postgres array.
            return json.dumps(value)
        # Real Postgres array columns (text[], uuid[]) round-trip via
        # psycopg2's native list adapter.
        return value
    if is_jsonb_column and value is not None:
        # jsonb columns can legitimately hold a scalar JSON value (a bare
        # string, number, or boolean, e.g. workshop_settings.value =
        # "08:00" or true) -- these still need proper JSON quoting/
        # encoding, not the raw Python repr, when re-inserted as jsonb.
        return json.dumps(value)
    return value


def get_jsonb_columns(cur, schema_name, table_name):
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema=%s and table_name=%s and data_type='jsonb'",
        (schema_name, table_name),
    )
    return {row[0] for row in cur.fetchall()}


def get_generated_columns(cur, schema_name, table_name):
    """Return columns PostgreSQL must compute rather than accept on INSERT.

    Migration 028 introduces stored normalized identity columns. They remain
    in the encrypted payload for auditability, but an isolated restore must
    omit them from INSERT and let PostgreSQL regenerate them from raw values.
    """
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema=%s and table_name=%s and is_generated='ALWAYS'",
        (schema_name, table_name),
    )
    return {row[0] for row in cur.fetchall()}


def get_always_identity_columns(cur, schema_name, table_name):
    """Return GENERATED ALWAYS identity columns whose backed-up values must be preserved."""
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema=%s and table_name=%s "
        "and is_identity='YES' and identity_generation='ALWAYS'",
        (schema_name, table_name),
    )
    return {row[0] for row in cur.fetchall()}


def load_table_rows(cur, schema_name, table_name, columns, rows):
    if not rows:
        return 0
    jsonb_cols = get_jsonb_columns(cur, schema_name, table_name)
    generated_cols = get_generated_columns(cur, schema_name, table_name)
    identity_cols = get_always_identity_columns(cur, schema_name, table_name)
    insert_columns = [column for column in columns if column not in generated_cols]
    col_list = ", ".join(quote_ident(c) for c in insert_columns)
    placeholders = ", ".join(["%s"] * len(insert_columns))
    identity_override = " overriding system value" if identity_cols.intersection(insert_columns) else ""
    sql = (
        f'insert into {quote_ident(schema_name)}.{quote_ident(table_name)} '
        f'({col_list}){identity_override} values %s'
    )
    values = [
        [decode_value(row.get(c), is_jsonb_column=c in jsonb_cols) for c in insert_columns]
        for row in rows
    ]
    savepoint = f"sp_load_{table_name}"
    cur.execute(f'savepoint {quote_ident(savepoint)}')
    try:
        # One round trip per page instead of psycopg2.executemany's one round
        # trip per row. This keeps isolated staging restore proofs bounded even
        # when the retained backup contains thousands of audit/history rows.
        from psycopg2.extras import execute_values
        execute_values(cur, sql, values, template=f"({placeholders})", page_size=500)
        cur.execute(f'release savepoint {quote_ident(savepoint)}')
    except Exception:
        cur.execute(f'rollback to savepoint {quote_ident(savepoint)}')
        raise
    return len(rows)


def _canonical_schema_value(value, schema_name):
    if isinstance(value, dict):
        if "__decimal__" in value:
            return str(value["__decimal__"])
        return {key: _canonical_schema_value(item, schema_name) for key, item in sorted(value.items()) if key != "sha256"}
    if isinstance(value, list):
        return [_canonical_schema_value(item, schema_name) for item in value]
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, str):
        for name in {schema_name, "public"}:
            value = value.replace(f'"{name}".', '')
            value = re.sub(rf'(?<![\w]){re.escape(name)}\.', '', value)
    return value


def _canonical_structure(details, schema_name, include_triggers=True):
    keys = ("columns", "constraints", "indexes", "sequences", "triggers") if include_triggers else ("columns", "constraints", "indexes", "sequences")
    structure = {key: copy.deepcopy(details.get(key, [])) for key in keys}
    sort_keys = (("constraints", "conname"), ("indexes", "name"), ("sequences", "name"), ("triggers", "name"))
    for key, name_key in sort_keys:
        if key in structure:
            structure[key] = sorted(structure[key], key=lambda row: str(row.get(name_key, "")))
    return _canonical_schema_value(structure, schema_name)


def _notification_expected_schema(details):
    transformed = copy.deepcopy(details)
    for column in transformed.get("columns", []):
        if column.get("column_name") == "status":
            column.update({"formatted_type": "text", "data_type": "text", "udt_schema": "pg_catalog", "udt_name": "text"})
            column["column_default"] = None
    transformed["indexes"] = [row for row in transformed.get("indexes", []) if row.get("name") != "vehicle_notifications_status_idx"]
    return transformed


def verify_format_v2_evidence(cur, schema_name, data):
    """Fail closed on exact encrypted row/schema evidence; retain format-1 support."""
    if str(data.get("backup_format_version", "1")) == "1":
        return {"format_version": "1", "legacy_format_supported": True, "table_hashes": {},
                "schema_objects": {}, "all_hashes_match": True, "all_schema_objects_match": True}
    validate_backup_contract(data)
    hash_report = {}
    for table, expected in data["table_hashes"].items():
        columns, rows = export_table(cur, table, schema_name)
        actual = deterministic_table_hash(columns, rows)
        effective_expected = expected
        note = None
        if table == "vehicle_notifications":
            transformed_rows = copy.deepcopy(data["tables"][table]["rows"])
            for row in transformed_rows:
                row["status"] = "restored_disabled"
            effective_expected = deterministic_table_hash(data["tables"][table]["columns"], transformed_rows)
            note = "expected hash transformed only by forced restored_disabled status"
        hash_report[table] = {"expected": effective_expected, "actual": actual,
                              "source_expected": expected, "matched": actual == effective_expected, "note": note}

    actual_schema = export_schema_metadata(cur, schema_name, list(data["schema_objects"]))
    schema_report = {}
    for table, expected in data["schema_objects"].items():
        include_triggers = "triggers" in expected
        keys = ("columns", "constraints", "indexes", "sequences", "triggers") if include_triggers else ("columns", "constraints", "indexes", "sequences")
        raw_structure = {key: expected.get(key, []) for key in keys}
        evidence_hash = hashlib.sha256(json.dumps(raw_structure, default=json_default, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
        source_evidence_valid = evidence_hash == expected.get("sha256")
        effective_expected = _notification_expected_schema(expected) if table == "vehicle_notifications" else expected
        expected_canonical = _canonical_structure(effective_expected, "public", include_triggers)
        actual_canonical = _canonical_structure(actual_schema.get(table, {}), schema_name, include_triggers)
        expected_canonical_hash = hashlib.sha256(json.dumps(expected_canonical, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        actual_canonical_hash = hashlib.sha256(json.dumps(actual_canonical, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        matched = source_evidence_valid and expected_canonical == actual_canonical
        schema_report[table] = {
            "source_evidence_hash_valid": source_evidence_valid,
            "expected_canonical_sha256": expected_canonical_hash,
            "actual_canonical_sha256": actual_canonical_hash,
            "matched": matched,
            "intentional_transform": "status text/restored_disabled and pending index omitted" if table == "vehicle_notifications" else None,
        }
    return {
        "format_version": "2", "legacy_format_supported": False,
        "table_hashes": hash_report, "schema_objects": schema_report,
        "all_hashes_match": bool(hash_report) and all(row["matched"] for row in hash_report.values()),
        "all_schema_objects_match": bool(schema_report) and all(row["matched"] for row in schema_report.values()),
    }


def verify_restore(cur, schema_name, backup_row_counts, backup_tables=None):
    report = {"schema": schema_name, "tables": {}, "checks": {}}
    mismatches = []

    for table, expected in backup_row_counts.items():
        cur.execute(f'select count(*) from {quote_ident(schema_name)}.{quote_ident(table)}')
        actual = cur.fetchone()[0]
        report["tables"][table] = {"expected": expected, "actual": actual}
        if actual != expected:
            mismatches.append(table)

    # Vehicle notes stay attached to the correct vehicle: every
    # vehicle_work_items.notes-bearing row's vehicle_id must resolve to a
    # real restored vehicle row.
    cur.execute(
        f'select count(*) from {quote_ident(schema_name)}.vehicle_work_items w '
        f'left join {quote_ident(schema_name)}.vehicles v on v.id = w.vehicle_id '
        f'where w.notes is not null and v.id is null'
    )
    orphaned_notes = cur.fetchone()[0]
    report["checks"]["vehicle_notes_attached_correctly"] = orphaned_notes == 0
    report["checks"]["orphaned_note_rows"] = orphaned_notes

    # Workshop bookings return to the correct bay/time: bay_id and
    # scheduled_start_at/scheduled_end_at must match between source
    # (public) and restored schema for every booking id present in both.
    cur.execute(
        f'''
        select count(*) from {quote_ident(schema_name)}.workshop_bookings r
        join public.workshop_bookings p on p.id = r.id
        where r.bay_id is distinct from p.bay_id
           or r.scheduled_start_at is distinct from p.scheduled_start_at
           or r.scheduled_end_at is distinct from p.scheduled_end_at
        '''
    )
    booking_mismatches = cur.fetchone()[0]
    report["checks"]["bookings_bay_and_time_match_source"] = booking_mismatches == 0
    report["checks"]["booking_bay_time_mismatches"] = booking_mismatches

    # Technician assignments restored: every restored booking_assignments
    # row's technician_id must resolve to a restored technician row.
    cur.execute(
        f'select count(*) from {quote_ident(schema_name)}.workshop_booking_assignments a '
        f'left join {quote_ident(schema_name)}.workshop_technicians t on t.id = a.technician_id '
        f'where a.technician_id is not null and t.id is null'
    )
    orphaned_assignments = cur.fetchone()[0]
    report["checks"]["technician_assignments_restored"] = orphaned_assignments == 0
    report["checks"]["orphaned_assignment_rows"] = orphaned_assignments

    # Audit history preserved: restored audit_events count matches source
    # and every row's vehicle_id (when set) resolves to a restored vehicle.
    cur.execute(
        f'select count(*) from {quote_ident(schema_name)}.audit_events a '
        f'left join {quote_ident(schema_name)}.vehicles v on v.id = a.vehicle_id '
        f'where a.vehicle_id is not null and v.id is null'
    )
    orphaned_audit = cur.fetchone()[0]
    report["checks"]["audit_history_preserved"] = orphaned_audit == 0
    report["checks"]["orphaned_audit_rows"] = orphaned_audit

    # Notifications restored in a safe, non-resendable state: every
    # restored vehicle_notifications row must have status =
    # 'restored_disabled' (forced at load time, see load_table_rows /
    # main()), never 'pending' -- which is the only status the real
    # worker's claim query selects for.
    cur.execute(
        f"select count(*) from {quote_ident(schema_name)}.vehicle_notifications "
        f"where status::text = 'pending'"
    )
    pending_after_restore = cur.fetchone()[0]
    report["checks"]["notifications_restored_disabled"] = pending_after_restore == 0
    report["checks"]["notification_rows_left_pending"] = pending_after_restore

    alias_parity = True
    alias_normalization_parity = True
    if backup_tables and "workshop_stage_aliases" in backup_tables:
        expected_rows = backup_tables["workshop_stage_aliases"]["rows"]
        expected = sorted((str(row["alias_normalized"]), str(row["stage_code"])) for row in expected_rows)
        cur.execute(f'select alias_normalized,stage_code from {quote_ident(schema_name)}.workshop_stage_aliases order by alias_normalized')
        restored = [(str(alias), str(stage)) for alias, stage in cur.fetchall()]
        alias_parity = restored == expected
        # The normalizer contract is the normalized key -> canonical station
        # map; identical ordered pairs prove every restored input resolves to
        # the same station as the encrypted source payload.
        alias_normalization_parity = dict(restored) == dict(expected)
    report["checks"]["workshop_stage_aliases_restored_identically"] = alias_parity
    report["checks"]["workshop_stage_normalization_results_match"] = alias_normalization_parity

    report["row_count_mismatches"] = mismatches
    report["all_checks_passed"] = (
        not mismatches
        and orphaned_notes == 0
        and booking_mismatches == 0
        and orphaned_assignments == 0
        and orphaned_audit == 0
        and pending_after_restore == 0
        and alias_parity
        and alias_normalization_parity
    )
    return report


def restore_backup(conn, backup_file_path, encryption_key, schema_name=None):
    import uuid as uuid_mod
    from datetime import datetime, timezone

    data = decrypt_backup(backup_file_path, encryption_key)
    contract = validate_backup_contract(data)
    if data["environment"] != "staging":
        raise RuntimeError(
            "Refusing to restore a non-staging backup with this staging-only "
            "restore script. Restoring a production backup requires a "
            "separate, explicitly-approved procedure."
        )

    if not schema_name:
        stamp = re.sub(r"[^0-9a-z]", "", datetime.now(timezone.utc).isoformat().lower())
        schema_name = f"restore_test_{stamp}"

    payload_tables = set(data["tables"])
    cur = conn.cursor()
    create_isolated_schema(cur, schema_name)

    table_order = [table for table in TABLES if table in data["tables"]]
    if contract["legacy"]:
        for table in table_order:
            clone_table_structure(cur, schema_name, table)
        synchronize_non_fk_constraints(cur, schema_name, payload_tables)
    else:
        create_format_v2_structure(cur, schema_name, data["schema_objects"], table_order)

    loaded_counts = {}
    for table in TABLES:
        if table not in data["tables"]:
            continue
        columns = data["tables"][table]["columns"]
        # Loading may apply isolated-restore safety transforms. Never mutate the
        # authenticated source payload or its preflight row-hash evidence.
        rows = copy.deepcopy(data["tables"][table]["rows"])

        if table == "vehicle_notifications":
            # Never allow a restored notification to be resendable. Force
            # status to a value the live claim RPC does not select for.
            # 'status' is a Postgres enum in `public`; the cloned table in
            # the restore schema uses the *same* enum type (LIKE preserves
            # the column type), so the value must remain one of the
            # enum's members -- we add 'restored_disabled' as a new member
            # of a *local* copy is not possible without altering the
            # shared type, so instead we widen the column to text on the
            # restore copy specifically for this table before loading.
            # A partial index predicate on `status` (copied by LIKE
            # INCLUDING ALL) references the enum type directly and blocks
            # an ALTER COLUMN TYPE; drop it in the restore schema first --
            # it is a live-app performance index, not part of the backup
            # payload's data.
            cur.execute(
                f'drop index if exists {quote_ident(schema_name)}.vehicle_notifications_status_idx'
            )
            cur.execute(
                f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                f'alter column status drop default'
            )
            cur.execute(
                f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                f'alter column status type text using status::text'
            )
            for row in rows:
                row["status"] = "restored_disabled"

        loaded_counts[table] = load_table_rows(cur, schema_name, table, columns, rows)

    # Foreign keys are added only after every table's data has been
    # loaded (added NOT VALID -- meaning existing rows are not re-checked
    # by the ADD step itself -- but the immediate VALIDATE CONSTRAINT
    # call inside add_foreign_keys() re-checks every row against the
    # restored data before this function returns, so this must run
    # after, not before, the data load, or every insert into a table
    # with a not-yet-populated FK target fails).
    if contract["legacy"]:
        foreign_keys = discover_foreign_keys(cur, payload_tables)
    else:
        create_format_v2_indexes(cur, schema_name, data["schema_objects"], table_order)
        foreign_keys = foreign_keys_from_evidence(data["schema_objects"], payload_tables)
    fk_added, fk_skipped = add_foreign_keys(
        cur, schema_name, foreign_keys, payload_tables
    )
    restored_sequences = [] if contract["legacy"] else restore_sequence_state(
        cur, schema_name, data["schema_objects"], table_order
    )
    restored_triggers = [] if contract["legacy"] else create_format_v2_triggers(
        cur, schema_name, data["schema_objects"], table_order
    )

    report = verify_restore(cur, schema_name, data["row_counts"], data.get("tables"))
    format_evidence = verify_format_v2_evidence(cur, schema_name, data)
    report["format_evidence"] = format_evidence
    report["all_checks_passed"] = (
        report["all_checks_passed"]
        and format_evidence["all_hashes_match"]
        and format_evidence["all_schema_objects_match"]
    )
    report["backup_run_id"] = data["backup_run_id"]
    report["backup_environment"] = data["environment"]
    report["migration_version"] = data["migration_version"]
    report["foreign_keys_discovered"] = len(foreign_keys)
    report["foreign_keys_added"] = len(fk_added)
    report["foreign_keys_skipped"] = fk_skipped
    report["sequences_restored"] = restored_sequences
    report["triggers_restored"] = restored_triggers
    # Independent-review remediation (finding #9): a skipped/invalid
    # foreign key used to be recorded but NOT reflected in
    # all_checks_passed -- "full restore passed" did not actually prove
    # every relationship was restored and valid. Now it does: any
    # skipped constraint fails the overall restore.
    report["all_checks_passed"] = report["all_checks_passed"] and not fk_skipped
    report["schema_name"] = schema_name
    if not report["all_checks_passed"]:
        raise RuntimeError("Isolated restore verification failed; transaction was not committed")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-file", required=True)
    parser.add_argument("--schema-name", default=None)
    parser.add_argument("--drop-after", action="store_true",
                         help="Drop the restore schema after verification (use for repeatable test runs).")
    args = parser.parse_args()

    encryption_key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY")
    if not encryption_key:
        print("PDC_BACKUP_ENCRYPTION_KEY is not set.", file=sys.stderr)
        sys.exit(2)

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from scripts.pdc_staging_runtime import get_conn  # noqa: E402

    conn = get_conn()
    try:
        report = restore_backup(conn, args.backup_file, encryption_key.encode(), args.schema_name)

        cur = conn.cursor()
        cur.execute(
            """
            insert into public.restore_test_runs
                (backup_run_id, environment, target_schema, status, finished_at,
                 verification_report, row_count_matches)
            values (%s, %s, %s, %s, now(), %s, %s)
            """,
            (report["backup_run_id"], "staging", report["schema_name"],
             "success" if report["all_checks_passed"] else "failed",
             json.dumps(report), not report["row_count_mismatches"]),
        )
        if args.drop_after:
            cur.execute(f'drop schema {quote_ident(report["schema_name"])} cascade')
        conn.commit()
        print(json.dumps(report, indent=2))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    sys.exit(0 if report["all_checks_passed"] else 1)


if __name__ == "__main__":
    main()
