#!/usr/bin/env python3
"""Apply staging migrations 121/122 atomically with backup and invariant gates."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [
    ("121", "beta_ai_auditor_foundation", ROOT / "supabase/staging_only/121_beta_ai_auditor_foundation.sql"),
    ("122", "ai_auditor_human_review_decisions", ROOT / "supabase/staging_only/122_ai_auditor_human_review_decisions.sql"),
]
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_HEAD = "120"
EXCLUDED_PREFIXES = ("pdc_auditor_",)


def transaction_body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("migration transaction wrapper missing")
    return source[begin.end():commits[-1].start()]


def table_names(cur):
    cur.execute("""select tablename from pg_tables where schemaname='public' order by tablename""")
    return [row[0] for row in cur.fetchall() if not row[0].startswith(EXCLUDED_PREFIXES)]


def signature(cur, table: str):
    safe = '"' + table.replace('"', '""') + '"'
    cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{safe} t")
    return cur.fetchone()


def postconditions(cur):
    cur.execute("select version,name from supabase_migrations.schema_migrations where version in ('121','122') order by version")
    if cur.fetchall() != [("121", "beta_ai_auditor_foundation"), ("122", "ai_auditor_human_review_decisions")]:
        raise AssertionError("migration ledger identity mismatch")
    cur.execute("""select
      to_regclass('public.pdc_auditor_decisions') is not null,
      has_function_privilege('authenticated','public.get_pdc_auditor_snapshot(uuid,integer)'::regprocedure,'EXECUTE'),
      has_function_privilege('authenticated','public.get_pdc_auditor_review_queue(integer)'::regprocedure,'EXECUTE'),
      has_function_privilege('authenticated','public.record_pdc_auditor_decision(uuid,text,uuid,text,text)'::regprocedure,'EXECUTE'),
      not has_function_privilege('authenticated','public.attest_pdc_authenticated_email_attachments(text,jsonb)'::regprocedure,'EXECUTE'),
      not has_function_privilege('authenticated','public.import_pdc_authenticated_vehicle_attachment(text,integer,text,jsonb,jsonb)'::regprocedure,'EXECUTE'),
      not has_function_privilege('authenticated','public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure,'EXECUTE')""")
    checks = cur.fetchone()
    if checks != (True, True, True, True, True, True, True):
        raise AssertionError("post-deployment ACL/function contract failed")
    cur.execute("select count(*)=0 from information_schema.role_table_grants where grantee='authenticated' and table_schema='public' and table_name='pdc_auditor_decisions' and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES')")
    if cur.fetchone()[0] is not True:
        raise AssertionError("authenticated gained direct decision mutation authority")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-run-id", required=True)
    parser.add_argument("--backup-file", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    if not dsn:
        raise RuntimeError("PDC_STAGING_DATABASE_URL missing")
    backup_file = Path(args.backup_file).resolve()
    if not backup_file.is_file() or backup_file.stat().st_size < 1024:
        raise RuntimeError("encrypted backup artifact missing or too small")
    sources = [(version, name, path.read_text("utf-8")) for version, name, path in MIGRATIONS]
    source_hashes = {version: hashlib.sha256(source.encode()).hexdigest() for version, _name, source in sources}
    backup_hash = hashlib.sha256(backup_file.read_bytes()).hexdigest()
    receipt = {
        "status": "failed",
        "environment": "staging",
        "project_ref": "[REDACTED]",
        "expected_predecessor": EXPECTED_HEAD,
        "backup_run_id": args.backup_run_id,
        "backup_sha256": backup_hash,
        "source_sha256": source_hashes,
        "production_changed": False,
    }
    try:
        with psycopg.connect(dsn, autocommit=False) as conn:
            cur = conn.cursor()
            cur.execute("set local statement_timeout='240s'")
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton for update")
            if cur.fetchone()[0] != PROJECT_REF:
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select status,environment from public.backup_runs where id=%s", (args.backup_run_id,))
            backup = cur.fetchone()
            if backup != ("success", "staging"):
                raise RuntimeError("successful staging backup prerequisite missing")
            cur.execute("lock table supabase_migrations.schema_migrations in exclusive mode")
            cur.execute("select max(version::bigint)::text from supabase_migrations.schema_migrations")
            head = cur.fetchone()[0]
            if head != EXPECTED_HEAD:
                raise RuntimeError(f"ledger head mismatch: expected {EXPECTED_HEAD}, got {head}")
            names = table_names(cur)
            before = {table: signature(cur, table) for table in names}
            for version, name, source in sources:
                cur.execute(transaction_body(source))
                cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)", (version, [source], name))
            after = {table: signature(cur, table) for table in names}
            changed = sorted(table for table in names if before[table] != after[table])
            if changed:
                raise RuntimeError("migration changed operational rows: " + ",".join(changed))
            postconditions(cur)
            conn.commit()
        receipt.update({
            "status": "applied",
            "prior_ledger_head": EXPECTED_HEAD,
            "ledger_head_after": "122",
            "operational_signatures_unchanged": True,
            "authenticated_review_only": True,
            "contained_email_import_acl_preserved": True,
        })
    except Exception as exc:
        receipt["error"] = str(exc)
        raise
    finally:
        target = Path(args.receipt)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", "utf-8")
    print(json.dumps(receipt, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
