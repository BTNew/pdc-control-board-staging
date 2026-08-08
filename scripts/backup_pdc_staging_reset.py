from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

from psycopg2 import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env
from staging_conn import get_conn

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
DEFAULT_WORKBOOK = Path.home() / "AppData" / "Local" / "hermes" / "cache" / "documents" / "doc_dd1168d8b7ba_Hermes_PDC_JC_Stock_Operations_Matched.xlsx"
DEFAULT_ROOT = Path.home() / "pdc-control-board" / "_staging_backups"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a complete checksummed staging public-schema reset backup.")
    parser.add_argument("--workbook", type=Path, default=DEFAULT_WORKBOOK)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()

    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    if not args.workbook.is_file():
        raise RuntimeError(f"workbook not found: {args.workbook}")

    with get_conn() as conn:
        conn.autocommit = False
        conn.set_session(readonly=True, isolation_level="REPEATABLE READ")
        with conn.cursor() as cur:
            cur.execute("set local statement_timeout='0'")
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            sentinel = cur.fetchone()
            if sentinel != (EXPECTED_REF,):
                raise RuntimeError(f"staging sentinel mismatch: {sentinel}")
            cur.execute("select to_char(transaction_timestamp() at time zone 'UTC','YYYYMMDD_TZHH24MISS_MS')")
            stamp = cur.fetchone()[0].replace("+", "p").replace("-", "m").replace(":", "")
            output = args.output_root / f"pdc_staging_pre_reset_{stamp}"
            data_dir = output / "public_data"
            data_dir.mkdir(parents=True, exist_ok=False)

            cur.execute("""
                select table_name from information_schema.tables
                where table_schema='public' and table_type='BASE TABLE'
                order by table_name
            """)
            tables = [row[0] for row in cur.fetchall()]
            manifest = {
                "format": "pdc-staging-public-csv-gzip-v1",
                "project_ref": EXPECTED_REF,
                "database_transaction_timestamp_utc": stamp,
                "transaction_isolation": "repeatable read / read only",
                "workbook": {},
                "tables": [],
                "sequences": [],
                "schema_files": {},
            }

            for table in tables:
                cur.execute("""
                    select column_name,data_type,udt_schema,udt_name,is_nullable,column_default,
                           is_identity,identity_generation,is_generated,generation_expression
                    from information_schema.columns
                    where table_schema='public' and table_name=%s order by ordinal_position
                """, (table,))
                columns = [dict(zip(
                    ("name","data_type","udt_schema","udt_name","nullable","default","is_identity","identity_generation","is_generated","generation_expression"),
                    row,
                )) for row in cur.fetchall()]
                cur.execute(sql.SQL("select count(*) from public.{}") .format(sql.Identifier(table)))
                row_count = cur.fetchone()[0]
                target = data_dir / f"{table}.csv.gz"
                copy_query = sql.SQL("copy public.{} to stdout with (format csv, header true, encoding 'UTF8')").format(sql.Identifier(table))
                with gzip.open(target, "wt", encoding="utf-8", newline="") as handle:
                    cur.copy_expert(copy_query.as_string(cur), handle)
                manifest["tables"].append({
                    "schema": "public",
                    "table": table,
                    "row_count": row_count,
                    "columns": columns,
                    "file": str(target.relative_to(output)).replace("\\", "/"),
                    "compressed_bytes": target.stat().st_size,
                    "sha256": sha256_file(target),
                })

            cur.execute("""
                select schemaname,sequencename,start_value,min_value,max_value,increment_by,cycle,cache_size,last_value
                from pg_sequences where schemaname='public' order by sequencename
            """)
            keys = ("schema","sequence","start_value","min_value","max_value","increment_by","cycle","cache_size","last_value")
            manifest["sequences"] = [dict(zip(keys, row)) for row in cur.fetchall()]

            schema_queries = {
                "constraints.sql": """select '-- '||quote_ident(n.nspname)||'.'||quote_ident(c.relname)||' '||quote_ident(con.conname)||E'\\n'||pg_get_constraintdef(con.oid,true)||';' from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' order by c.relname,con.conname""",
                "indexes.sql": """select indexdef||';' from pg_indexes where schemaname='public' order by tablename,indexname""",
                "triggers.sql": """select pg_get_triggerdef(t.oid,true)||';' from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal order by c.relname,t.tgname""",
                "views.sql": """select 'create or replace view public.'||quote_ident(viewname)||E' as\\n'||definition||';' from pg_views where schemaname='public' order by viewname""",
                "functions.sql": """select pg_get_functiondef(p.oid)||';' from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by p.proname,p.oid""",
            }
            schema_dir = output / "schema_evidence"
            schema_dir.mkdir()
            for filename, query in schema_queries.items():
                cur.execute(query)
                target = schema_dir / filename
                target.write_text("\n\n".join(row[0] for row in cur.fetchall()) + "\n", encoding="utf-8")
                manifest["schema_files"][filename] = {
                    "file": str(target.relative_to(output)).replace("\\", "/"),
                    "bytes": target.stat().st_size,
                    "sha256": sha256_file(target),
                }

            workbook_target = output / args.workbook.name
            shutil.copy2(args.workbook, workbook_target)
            manifest["workbook"] = {
                "source_name": args.workbook.name,
                "file": workbook_target.name,
                "bytes": workbook_target.stat().st_size,
                "sha256": sha256_file(workbook_target),
            }

            manifest_path = output / "manifest.json"
            manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")
            manifest_sha = sha256_file(manifest_path)
            (output / "manifest.sha256").write_text(f"{manifest_sha}  manifest.json\n", encoding="ascii")
            conn.rollback()

    total_rows = sum(item["row_count"] for item in manifest["tables"])
    total_bytes = sum(path.stat().st_size for path in output.rglob("*") if path.is_file())
    print(json.dumps({
        "ok": True,
        "project_ref": EXPECTED_REF,
        "backup_path": str(output),
        "table_count": len(manifest["tables"]),
        "total_rows": total_rows,
        "total_bytes": total_bytes,
        "manifest_sha256": manifest_sha,
        "workbook_sha256": manifest["workbook"]["sha256"],
    }, sort_keys=True))


if __name__ == "__main__":
    main()
