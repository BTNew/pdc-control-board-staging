#!/usr/bin/env python3
"""Guarded staging-only apply or rollback rehearsal for migration 106."""
from __future__ import annotations
import hashlib, json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from pdc_staging_runtime import assert_staging_target, get_conn, load_local_env, required  # noqa: E402

EXPECTED_REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
EXPECTED_BRANCH = 'qa/workshop-bulletproof-20260728'
MIGRATION = ROOT / 'supabase' / 'staging_only' / '106_workshop_booked_chip_move_cascade.sql'
VERSION = '106'
NAME = 'workshop_booked_chip_move_cascade'
PRIOR_VERSION = '105'
PRIOR_NAME = 'authenticated_operation_hours_exact_replay'
PRIOR_SHA256 = 'c72ee9a0fccf697006849fd12d1b9b9de6aa2b3ca18407575a0f7a82d96be3f5'
ROLLBACK_ONLY = os.getenv('PDC_MIGRATION_ROLLBACK_ONLY', '1').lower() not in {'0', 'false', 'no'}
OPERATIONAL_TABLES = ('vehicles', 'workshop_bookings', 'workshop_booking_assignments', 'workshop_booking_history', 'audit_events')


def scalar(cur, query, params=()):
    cur.execute(query, params)
    row = cur.fetchone()
    return row[0] if row else None


def transaction_body(source: str) -> str:
    source = source.strip()
    if source.lower().startswith('begin;'):
        source = source[6:].lstrip()
    if source.lower().endswith('commit;'):
        source = source[:-7].rstrip()
    return source


def signature(cur, table: str) -> tuple[int, str]:
    cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
    count, digest = cur.fetchone()
    return int(count), str(digest)


def effective_checks(cur) -> dict[str, object]:
    regproc = 'public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb)'
    definition = scalar(cur, 'select pg_get_functiondef(%s::regprocedure)', (regproc,)) or ''
    for required_text in ('ORDER BY b.scheduled_start_at DESC', "'cascade_move_shifted'", "'live_booking_conflict'", 'move_workshop_booking'):
        if required_text.lower() not in definition.lower():
            raise RuntimeError(f'effective cascade move definition missing: {required_text}')
    if scalar(cur, "select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='cascade_workshop_booking_move' and grantee='authenticated' and privilege_type='EXECUTE'") < 1:
        raise RuntimeError('authenticated cascade move grant missing')
    if scalar(cur, "select count(*) from information_schema.routine_privileges where specific_schema='public' and routine_name='cascade_workshop_booking_move' and grantee in ('PUBLIC','anon') and privilege_type='EXECUTE'"):
        raise RuntimeError('forbidden cascade move grant present')
    return {'atomicMoveRpc': True, 'liveWorkFixed': True, 'plannedQueueCascade': True}


def main() -> int:
    branch = subprocess.check_output(['git', '-C', str(ROOT), 'branch', '--show-current'], text=True).strip()
    if branch != EXPECTED_BRANCH:
        raise RuntimeError(f'refusing migration 106 from branch {branch!r}')
    source_commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    load_local_env()
    database_url = required('PDC_STAGING_DATABASE_URL')
    lowered = database_url.lower()
    if PRODUCTION_REF in lowered or EXPECTED_REF not in lowered:
        raise RuntimeError('refusing endpoint outside guarded staging')
    assert_staging_target(database_url=database_url)
    source = MIGRATION.read_text(encoding='utf-8')
    source_sha = hashlib.sha256(source.encode('utf-8')).hexdigest()
    conn = get_conn()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("set local statement_timeout='120s'")
            cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode')
            if scalar(cur, 'select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s', (EXPECTED_REF,)) != 1:
                raise RuntimeError('PDC_STAGING_SENTINEL_MISMATCH')
            head = str(scalar(cur, 'select version from supabase_migrations.schema_migrations order by version::int desc limit 1'))
            existing = scalar(cur, 'select count(*) from supabase_migrations.schema_migrations where version=%s', (VERSION,))
            if existing:
                cur.execute('select name,statements from supabase_migrations.schema_migrations where version=%s', (VERSION,))
                name, statements = cur.fetchone()
                recorded = (statements or [''])[0]
                if name != NAME or hashlib.sha256(recorded.encode('utf-8')).hexdigest() != source_sha:
                    raise RuntimeError('migration 106 ledger checksum/name mismatch')
                checks = effective_checks(cur)
                conn.rollback()
                print(json.dumps({'status': 'already_applied', 'migration': VERSION, **checks, 'productionChanged': False}, sort_keys=True))
                return 0
            if head != PRIOR_VERSION:
                raise RuntimeError(f'ledger head mismatch: {head}')
            cur.execute('select name,statements from supabase_migrations.schema_migrations where version=%s', (PRIOR_VERSION,))
            prior_name, prior_statements = cur.fetchone()
            prior_source = (prior_statements or [''])[0]
            if prior_name != PRIOR_NAME or hashlib.sha256(prior_source.encode('utf-8')).hexdigest() != PRIOR_SHA256:
                raise RuntimeError('migration 105 prerequisite checksum/name mismatch')
            before = {table: signature(cur, table) for table in OPERATIONAL_TABLES}
            cur.execute(transaction_body(source))
            checks = effective_checks(cur)
            after = {table: signature(cur, table) for table in OPERATIONAL_TABLES}
            if before != after:
                raise RuntimeError('migration 106 changed operational table signatures')
            cur.execute('insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)', (VERSION, [source], NAME))
            status = 'rollback_dry_run' if ROLLBACK_ONLY else 'applied'
            conn.rollback() if ROLLBACK_ONLY else conn.commit()
            print(json.dumps({'status': status, 'migration': VERSION, 'sourceSha256': source_sha, 'sourceBranch': branch, 'sourceCommit': source_commit, 'operationalSignaturesUnchanged': True, **checks, 'productionChanged': False}, sort_keys=True))
            return 0
    except Exception as exc:
        conn.rollback()
        print(f'MIGRATION_106_FAILED: {exc}', file=sys.stderr)
        return 1
    finally:
        conn.close()


if __name__ == '__main__':
    raise SystemExit(main())
