from __future__ import annotations

import csv
import gzip
import hashlib
import json
import os
import sys
import uuid
from pathlib import Path

import psycopg2
from psycopg2 import sql

sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_MANIFEST_SHA = "b624e1942c621ffed0fa8bbb610a8fa704f0d691a69a0917c666c8930b6d930a"
EXPECTED_WORKBOOK_SHA = "d89a36dce52994acf34c234a6fc988c11b3ca1aa76a11123fdbacd8d507ffaa3"
BACKUP = Path.home() / "pdc-control-board" / "_staging_backups" / "pdc_staging_pre_reset_20260808_p00H245014_763"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_backup() -> tuple[dict, int]:
    manifest_path = BACKUP / "manifest.json"
    checksum_path = BACKUP / "manifest.sha256"
    if not manifest_path.is_file() or not checksum_path.is_file():
        raise RuntimeError("backup manifest/checksum file missing")
    actual_manifest_sha = sha256_file(manifest_path)
    checksum_token = checksum_path.read_text(encoding="ascii").split()[0]
    if actual_manifest_sha != EXPECTED_MANIFEST_SHA or checksum_token != EXPECTED_MANIFEST_SHA:
        raise RuntimeError("backup manifest digest mismatch")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != "pdc-staging-public-csv-gzip-v1" or manifest.get("project_ref") != EXPECTED_REF:
        raise RuntimeError("backup manifest contract/environment mismatch")
    workbook = manifest.get("workbook") or {}
    workbook_path = BACKUP / str(workbook.get("file") or "")
    if workbook.get("sha256") != EXPECTED_WORKBOOK_SHA or not workbook_path.is_file() or sha256_file(workbook_path) != EXPECTED_WORKBOOK_SHA:
        raise RuntimeError("backup workbook artifact mismatch")
    csv.field_size_limit(min(sys.maxsize, 2_147_483_647))
    total_rows = 0
    for entry in manifest.get("tables") or []:
        target = BACKUP / entry["file"]
        if not target.is_file() or sha256_file(target) != entry["sha256"]:
            raise RuntimeError(f"backup table artifact mismatch: {entry['table']}")
        with gzip.open(target, "rt", encoding="utf-8", newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            rows = sum(1 for _ in reader)
        expected_csv_columns = [column["name"] for column in entry["columns"] if column.get("is_generated") != "ALWAYS"]
        if header != expected_csv_columns:
            raise RuntimeError(f"backup CSV header/schema mismatch: {entry['table']}")
        entry["_restore_columns"] = header
        if rows != int(entry["row_count"]):
            raise RuntimeError(f"backup row-count mismatch: {entry['table']}")
        total_rows += rows
    for entry in (manifest.get("schema_files") or {}).values():
        target = BACKUP / entry["file"]
        if not target.is_file() or sha256_file(target) != entry["sha256"]:
            raise RuntimeError(f"backup schema artifact mismatch: {entry['file']}")
    if len(manifest.get("tables") or []) != 111 or total_rows != 27356:
        raise RuntimeError(f"backup inventory mismatch: tables={len(manifest.get('tables') or [])} rows={total_rows}")
    return manifest, total_rows


def main() -> None:
    manifest, expected_rows = validate_backup()
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    schema_name = "pdc_data_integrity_" + uuid.uuid4().hex[:12]
    tables = {entry["table"]: entry for entry in manifest["tables"]}
    restored_rows = 0
    fk_checked = 0
    try:
        with psycopg2.connect(dsn) as conn:
            conn.autocommit = False
            with conn.cursor() as cur:
                cur.execute("set local statement_timeout='0'")
                cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
                if cur.fetchone() != (EXPECTED_REF,):
                    raise RuntimeError("staging database sentinel mismatch")
                cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
                if cur.fetchone()[0]:
                    raise RuntimeError("production sentinel present")
                cur.execute(sql.SQL("create schema {}") .format(sql.Identifier(schema_name)))
                for table_name, entry in tables.items():
                    columns = entry["_restore_columns"]
                    definitions = sql.SQL(",").join(sql.SQL("{} text").format(sql.Identifier(column)) for column in columns)
                    cur.execute(sql.SQL("create table {}.{} ({})").format(sql.Identifier(schema_name), sql.Identifier(table_name), definitions))
                    copy_statement = sql.SQL("copy {}.{} ({}) from stdin with (format csv, header true, encoding 'UTF8')").format(
                        sql.Identifier(schema_name), sql.Identifier(table_name), sql.SQL(",").join(map(sql.Identifier, columns))
                    )
                    with gzip.open(BACKUP / entry["file"], "rt", encoding="utf-8", newline="") as handle:
                        cur.copy_expert(copy_statement.as_string(cur), handle)
                    cur.execute(sql.SQL("select count(*) from {}.{}").format(sql.Identifier(schema_name), sql.Identifier(table_name)))
                    count = cur.fetchone()[0]
                    if count != int(entry["row_count"]):
                        raise RuntimeError(f"logical data-load row mismatch: {table_name}")
                    restored_rows += count
                cur.execute("""
                    select con.conname,child.relname,parent.relname,
                      array(select a.attname from unnest(con.conkey) with ordinality u(attnum,ord)
                            join pg_attribute a on a.attrelid=con.conrelid and a.attnum=u.attnum order by u.ord),
                      array(select a.attname from unnest(con.confkey) with ordinality u(attnum,ord)
                            join pg_attribute a on a.attrelid=con.confrelid and a.attnum=u.attnum order by u.ord)
                    from pg_constraint con
                    join pg_class child on child.oid=con.conrelid
                    join pg_namespace child_ns on child_ns.oid=child.relnamespace
                    join pg_class parent on parent.oid=con.confrelid
                    join pg_namespace parent_ns on parent_ns.oid=parent.relnamespace
                    where con.contype='f' and child_ns.nspname='public' and parent_ns.nspname='public'
                    order by child.relname,con.conname
                """)
                for constraint, child, parent, child_cols, parent_cols in cur.fetchall():
                    if child not in tables or parent not in tables:
                        continue
                    nonnull = sql.SQL(" and ").join(sql.SQL("c.{} is not null").format(sql.Identifier(col)) for col in child_cols)
                    equal = sql.SQL(" and ").join(
                        sql.SQL("p.{} is not distinct from c.{}").format(sql.Identifier(pcol), sql.Identifier(ccol))
                        for ccol, pcol in zip(child_cols, parent_cols)
                    )
                    query = sql.SQL("select count(*) from {}.{} c where {} and not exists(select 1 from {}.{} p where {})").format(
                        sql.Identifier(schema_name), sql.Identifier(child), nonnull,
                        sql.Identifier(schema_name), sql.Identifier(parent), equal,
                    )
                    cur.execute(query)
                    violations = cur.fetchone()[0]
                    if violations:
                        raise RuntimeError(f"logical data-load FK violation: {constraint}={violations}")
                    fk_checked += 1
                cur.execute("select to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"')")
                verified_at = cur.fetchone()[0]
                cur.execute(sql.SQL("drop schema {} cascade").format(sql.Identifier(schema_name)))
                cur.execute("select to_regnamespace(%s) is null", (schema_name,))
                cleanup_verified = bool(cur.fetchone()[0])
                if not cleanup_verified:
                    raise RuntimeError("logical data-load schema cleanup failed")
                conn.rollback()
    except Exception:
        raise
    if restored_rows != expected_rows:
        raise RuntimeError("logical data-load total mismatch")
    receipt = {
        "ok": True,
        "contract": "pdc-staging-backup-data-integrity-v2",
        "verification_scope": "exact_csv_headers_hashes_rows_and_logical_foreign_keys",
        "full_schema_restore_verified": False,
        "schema_ddl_applied": False,
        "types_constraints_defaults_sequences_indexes_triggers_rls_functions_verified": False,
        "disaster_recovery_receipt": False,
        "project_ref": EXPECTED_REF,
        "backup_path": str(BACKUP),
        "manifest_sha256": EXPECTED_MANIFEST_SHA,
        "workbook_sha256": EXPECTED_WORKBOOK_SHA,
        "table_count": len(tables),
        "restored_row_count": restored_rows,
        "foreign_keys_checked": fk_checked,
        "foreign_key_violations": 0,
        "temporary_validation_schema": schema_name,
        "transaction_rolled_back": True,
        "cleanup_verified": cleanup_verified,
        "production_changed": False,
        "verified_at_utc": verified_at,
    }
    output = BACKUP / "data_integrity_verification"
    output.mkdir(exist_ok=True)
    receipt_path = output / "data_integrity_receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt_sha = sha256_file(receipt_path)
    (output / "data_integrity_receipt.sha256").write_text(f"{receipt_sha}  data_integrity_receipt.json\n", encoding="ascii")
    print(json.dumps({**receipt, "receipt_sha256": receipt_sha}, sort_keys=True))


if __name__ == "__main__":
    main()
