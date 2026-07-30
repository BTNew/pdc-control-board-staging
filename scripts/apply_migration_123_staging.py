#!/usr/bin/env python3
"""Apply staging migration 123 with backup, ledger and non-operational gates."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/123_harden_ai_auditor_human_review_binding.sql"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_HEAD = "122"


def body(source):
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("migration wrapper missing")
    return source[begin.end():commits[-1].start()]


def table_names(cur):
    cur.execute("select tablename from pg_tables where schemaname='public' order by tablename")
    return [row[0] for row in cur.fetchall() if not row[0].startswith("pdc_auditor_")]


def signature(cur, table):
    safe = '"' + table.replace('"', '""') + '"'
    cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{safe} t")
    return cur.fetchone()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-run-id", required=True)
    parser.add_argument("--backup-file", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    if not dsn:
        raise RuntimeError("PDC_STAGING_DATABASE_URL missing")
    backup = Path(args.backup_file).resolve()
    if not backup.is_file() or backup.stat().st_size < 1024:
        raise RuntimeError("encrypted backup artifact missing")
    source = MIGRATION.read_text("utf-8")
    receipt = {
        "status": "failed", "environment": "staging", "project_ref": "[REDACTED]",
        "expected_predecessor": EXPECTED_HEAD, "backup_run_id": args.backup_run_id,
        "backup_sha256": hashlib.sha256(backup.read_bytes()).hexdigest(),
        "source_sha256": hashlib.sha256(source.encode()).hexdigest(), "production_changed": False,
    }
    try:
        with psycopg.connect(dsn, autocommit=False) as conn:
            cur = conn.cursor()
            cur.execute("set local statement_timeout='240s'")
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton for update")
            if cur.fetchone()[0] != PROJECT_REF:
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select status,environment from public.backup_runs where id=%s", (args.backup_run_id,))
            if cur.fetchone() != ("success", "staging"):
                raise RuntimeError("successful staging backup prerequisite missing")
            cur.execute("lock table supabase_migrations.schema_migrations in exclusive mode")
            cur.execute("select max(version::bigint)::text from supabase_migrations.schema_migrations")
            if cur.fetchone()[0] != EXPECTED_HEAD:
                raise RuntimeError("ledger head mismatch")
            names = table_names(cur)
            before = {name: signature(cur, name) for name in names}
            cur.execute(body(source))
            after = {name: signature(cur, name) for name in names}
            changed = sorted(name for name in names if before[name] != after[name])
            if changed:
                raise RuntimeError("migration changed non-Auditor rows: " + ",".join(changed))
            cur.execute("select name from supabase_migrations.schema_migrations where version='123'")
            if cur.fetchone() != ("harden_ai_auditor_human_review_binding",):
                raise RuntimeError("migration 123 ledger identity mismatch")
            cur.execute("""select
              exists(select 1 from pg_constraint where conrelid='public.pdc_auditor_decisions'::regclass and conname='pdc_auditor_decisions_exact_occurrence_key'),
              has_function_privilege('authenticated','public.get_pdc_auditor_review_queue(integer)'::regprocedure,'EXECUTE'),
              has_function_privilege('authenticated','public.record_pdc_auditor_decision(uuid,text,uuid,text,text)'::regprocedure,'EXECUTE'),
              not has_function_privilege('authenticated','public.attest_pdc_authenticated_email_attachments(text,jsonb)'::regprocedure,'EXECUTE'),
              not has_function_privilege('authenticated','public.import_pdc_authenticated_vehicle_attachment(text,integer,text,jsonb,jsonb)'::regprocedure,'EXECUTE'),
              not has_function_privilege('authenticated','public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure,'EXECUTE')""")
            if cur.fetchone() != (True, True, True, True, True, True):
                raise RuntimeError("effective privilege or containment contract failed")
            cur.execute("select pg_get_functiondef('public.record_pdc_auditor_decision(uuid,text,uuid,text,text)'::regprocedure),pg_get_functiondef('public.get_pdc_auditor_review_queue(integer)'::regprocedure)")
            decide, queue = cur.fetchone()
            for token in ("finding_last_seen_run_id=p_last_seen_run_id", "v_existing.reason is distinct from v_reason", "v_snapshot->>'rule_set_hash'"):
                if token.lower() not in decide.lower():
                    raise RuntimeError("effective decision hardening missing")
            if "d.finding_last_seen_run_id = f.last_seen_run_id" not in queue.lower():
                raise RuntimeError("effective review queue exact-run join missing")
            conn.commit()
        receipt.update({"status": "applied", "prior_ledger_head": "122", "ledger_head_after": "123", "non_auditor_signatures_unchanged": True, "exact_occurrence_binding": True, "rule_freshness": True, "contained_email_import_acl_preserved": True})
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
