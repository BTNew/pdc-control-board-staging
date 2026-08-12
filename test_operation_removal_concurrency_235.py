#!/usr/bin/env python3
"""Rollback-only staging rehearsal for migration 235 and its shared lock.

Requires PDC_STAGING_DIRECT_DATABASE_URL or PDC_STAGING_DATABASE_URL. Nothing is
committed: the migration rehearsal and both concurrency connections roll back.
"""
from __future__ import annotations

import os
import re
import sys
import threading
import time
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parent
MIGRATION_NAMES = [
    "232_workshop_mechanic_bay_assignment_repair.sql",
    "233_uid478_attachment_atomic_import.sql",
    "234_sublet_expected_return_conflict_details.sql",
    "235_reversible_workshop_operation_removal.sql",
]
MIGRATIONS = [ROOT / "supabase/staging_only" / name for name in MIGRATION_NAMES]
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
LOCK_PREFIX = "pdc-operation-line-evidence-serialization-v1:"


def load_ignored_env() -> None:
    tools = Path(r"C:\Users\nwmgr\pdc-control-board\_staging_test_tools")
    if tools.is_dir():
        sys.path.insert(0, str(tools))
        from staging_env import load_local_env
        load_local_env()
        return
    path = ROOT / "_staging_test_tools/.env"
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def dsn() -> str:
    load_ignored_env()
    value = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not value:
        raise RuntimeError("PDC_STAGING_DIRECT_DATABASE_URL or PDC_STAGING_DATABASE_URL is required")
    lowered = value.lower()
    if STAGING_REF not in lowered or PRODUCTION_REF in lowered:
        raise RuntimeError("refusing any database target except the exact PDC staging project")
    return value


def assert_staging(cur) -> None:
    cur.execute("""
      select exists(select 1 from public.pdc_staging_environment_sentinel
                    where singleton and project_ref=%s),
             to_regclass('public.pdc_production_environment_sentinel') is null
    """, (STAGING_REF,))
    if cur.fetchone() != (True, True):
        raise AssertionError("live database sentinel is not exact staging")


def migration_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    sql, count_begin = re.subn(r"^\s*(?:--[^\n]*\n\s*)*begin\s*;\s*", "", sql, count=1, flags=re.I)
    sql, count_commit = re.subn(r"\s*commit\s*;\s*$", "", sql, count=1, flags=re.I)
    if (count_begin, count_commit) != (1, 1):
        raise AssertionError("migration transaction wrapper drift")
    return sql


def rollback_migration_rehearsal(url: str) -> None:
    conn = psycopg2.connect(url, application_name="pdc_235_rollback_rehearsal")
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            assert_staging(cur)
            cur.execute("select max(version::numeric) from supabase_migrations.schema_migrations where version~'^[0-9]+$'")
            if cur.fetchone()[0] != 231:
                raise AssertionError("permanent staging numeric migration head must be exactly 231")
            cur.execute("select pg_get_functiondef('public.submit_pdc_auditor_findings(jsonb,jsonb)'::regprocedure)")
            before_definition = cur.fetchone()[0]
            cur.execute("select proacl from pg_proc where oid='public.submit_pdc_auditor_findings(jsonb,jsonb)'::regprocedure")
            before_acl = cur.fetchone()[0]
            for migration in MIGRATIONS:
                cur.execute(migration_body(migration))
            cur.execute("select pg_get_functiondef('public.submit_pdc_auditor_findings(jsonb,jsonb)'::regprocedure)")
            if cur.fetchone()[0].count(LOCK_PREFIX) != 2:
                raise AssertionError("rehearsed publisher does not contain both shared-lock acquisitions")
            cur.execute("select proacl from pg_proc where oid='public.submit_pdc_auditor_findings(jsonb,jsonb)'::regprocedure")
            if cur.fetchone()[0] != before_acl:
                raise AssertionError("publisher ACL changed during rehearsal")
            cur.execute("select count(*) from supabase_migrations.schema_migrations where version='235'")
            if cur.fetchone()[0] != 1:
                raise AssertionError("migration did not reach its terminal ledger insert")
        conn.rollback()
        with conn.cursor() as cur:
            assert_staging(cur)
            cur.execute("select pg_get_functiondef('public.submit_pdc_auditor_findings(jsonb,jsonb)'::regprocedure)")
            if cur.fetchone()[0] != before_definition:
                raise AssertionError("publisher definition persisted after rollback")
            cur.execute("select count(*) from supabase_migrations.schema_migrations where version='235'")
            if cur.fetchone()[0] != 0:
                raise AssertionError("migration 235 ledger row persisted after rollback")
        conn.rollback()
        print("PASS migration 235 executed completely and rolled back; function definition, ACL, and ledger were nonpersistent")
    finally:
        conn.close()


def two_connection_serialization_rehearsal(url: str) -> None:
    remover = psycopg2.connect(url, application_name="pdc_235_remover_side")
    publisher = psycopg2.connect(url, application_name="pdc_235_publisher_side")
    result: dict[str, object] = {}
    acquired = threading.Event()
    try:
        remover.autocommit = publisher.autocommit = False
        with remover.cursor() as cur:
            assert_staging(cur)
            # Choose a genuine absent-row case plus an existing occurrence whose
            # FK identity can host a rollback-only evidence append.
            cur.execute("""
              select ol.operation_line_id,x.finding_id,x.occurrence_id,x.dealer_code,
                     x.environment,x.max_ordinal
              from public.pdc_authenticated_email_operation_lines ol
              cross join lateral (
                select e.finding_id,e.occurrence_id,e.dealer_code,e.environment,
                       max(o.ordinal) over(partition by e.occurrence_id) as max_ordinal
                from public.pdc_auditor_finding_evidence e
                join public.pdc_auditor_finding_evidence o on o.occurrence_id=e.occurrence_id
                where e.ordinal=1 order by e.evidence_id limit 1
              ) x
              where not exists(
                select 1 from public.pdc_auditor_finding_evidence e
                where e.entity_type='operation_line' and e.entity_id=ol.operation_line_id)
                and x.max_ordinal<20
              order by ol.operation_line_id limit 1
            """)
            row = cur.fetchone()
            if row is None:
                raise AssertionError("staging lacks an absent operation-line evidence fixture")
            operation_line_id, finding_id, occurrence_id, dealer_code, environment, max_ordinal = row
            cur.execute("select pg_advisory_xact_lock(hashtextextended(%s,0))", (LOCK_PREFIX + str(operation_line_id),))
            cur.execute("select exists(select 1 from public.pdc_auditor_finding_evidence where entity_type='operation_line' and entity_id=%s)", (operation_line_id,))
            if cur.fetchone()[0] is not False:
                raise AssertionError("fixture is not the required no-row evidence case")

        def publisher_side() -> None:
            started = time.monotonic()
            try:
                with publisher.cursor() as cur:
                    cur.execute("set local statement_timeout='10000ms'")
                    cur.execute("select pg_advisory_xact_lock(hashtextextended(%s,0))", (LOCK_PREFIX + str(operation_line_id),))
                    result["wait_seconds"] = time.monotonic() - started
                    acquired.set()
                    cur.execute("""
                      insert into public.pdc_auditor_finding_evidence(
                        finding_id,occurrence_id,dealer_code,environment,entity_type,entity_id,
                        signal_code,field_code,ordinal)
                      values(%s,%s,%s,%s,'operation_line',%s,
                             'concurrency_rehearsal','serialization_guard',%s)
                    """, (finding_id, occurrence_id, dealer_code, environment,
                            operation_line_id, max_ordinal + 1))
                    cur.execute("select exists(select 1 from public.pdc_auditor_finding_evidence where entity_type='operation_line' and entity_id=%s)", (operation_line_id,))
                    result["evidence_inserted"] = cur.fetchone()[0]
            except BaseException as exc:
                result["error"] = exc

        thread = threading.Thread(target=publisher_side, daemon=True)
        thread.start()
        time.sleep(1.0)
        if acquired.is_set():
            raise AssertionError("publisher did not block behind removal's shared advisory key")
        remover.rollback()  # removal serial position ends; its rehearsal mutation is nonpersistent
        thread.join(timeout=12)
        if thread.is_alive():
            raise AssertionError("publisher did not resume after removal rollback")
        if "error" in result:
            raise result["error"]  # type: ignore[misc]
        if float(result.get("wait_seconds", 0)) < 0.9:
            raise AssertionError("measured lock wait was too short to establish blocking")
        if result.get("evidence_inserted") is not True:
            raise AssertionError("publisher did not append evidence after acquiring serialization")
        publisher.rollback()
        with remover.cursor() as cur:
            cur.execute("select exists(select 1 from public.pdc_auditor_finding_evidence where entity_type='operation_line' and entity_id=%s)", (operation_line_id,))
            if cur.fetchone()[0] is not False:
                raise AssertionError("rollback-only rehearsal left permanent Auditor evidence")
        remover.rollback()
        print(f"PASS two connections: evidence publisher blocked {result['wait_seconds']:.3f}s behind absent-row removal check")
        print(f"PASS invariant operation_line_id={operation_line_id}; publisher appended only after removal's serial position, then all work rolled back")
    finally:
        try:
            remover.rollback()
        finally:
            remover.close()
        try:
            publisher.rollback()
        finally:
            publisher.close()


def main() -> int:
    url = dsn()
    rollback_migration_rehearsal(url)
    two_connection_serialization_rehearsal(url)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL {type(exc).__name__}: {exc}", file=sys.stderr)
        raise
