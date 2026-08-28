#!/usr/bin/env python3
"""Fail-closed, staging-only installer for the exact Parts Auditor receipt wrapper."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260829050000_738_authenticated_parts_received_auditor_wrapper.sql'
EXPECTED_SHA256 = 'eddc14decc99ad79b02c1821238c20a9f25deed720ed572f90073270ebb0d160'
PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
APPLY_ENV = 'PDC_APPROVE_STAGING_MIGRATION_738'
CONCURRENT_TOKEN = '20260828_135232_8cb189'


def load_staging_values() -> dict[str, str]:
    bootstrap_path = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
    store_path = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', bootstrap_path)
    if spec is None or spec.loader is None:
        raise RuntimeError('staging bootstrap unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(store_path.read_bytes()).decode('utf-8'))
    module.validate(values)
    if values.get('PDC_STAGING_PROJECT_REF') != PROJECT_REF:
        raise RuntimeError('staging project mismatch')
    return values


def connect(values: dict[str, str], application_name: str):
    import psycopg2
    endpoint = values['PDC_STAGING_DATABASE_URL']
    parsed = urlsplit(endpoint)
    direct = parsed.hostname == f'db.{PROJECT_REF}.supabase.co' and parsed.username == 'postgres' and parsed.port == 5432
    pooler = bool(re.fullmatch(r'aws-[0-9]+-[a-z0-9]+(?:-[a-z0-9]+)*\.pooler\.supabase\.com', parsed.hostname or '')) and parsed.username == f'postgres.{PROJECT_REF}' and parsed.port in (5432, 6543)
    if PRODUCTION_REF in endpoint.lower() or not direct and not pooler:
        raise RuntimeError('refusing non-staging database endpoint')
    if not parsed.password:
        raise RuntimeError('staging database password missing')
    return psycopg2.connect(
        host=parsed.hostname, port=parsed.port or 5432, user=parsed.username,
        password=parsed.password, dbname='postgres', sslmode='verify-full',
        sslrootcert=values['PDC_STAGING_SSLROOTCERT'], connect_timeout=15,
        application_name=application_name,
    )


def source_bytes() -> bytes:
    if MIGRATION.is_symlink() or not MIGRATION.is_file():
        raise RuntimeError('migration source missing')
    payload = MIGRATION.read_bytes()
    actual = hashlib.sha256(payload).hexdigest()
    if actual != EXPECTED_SHA256:
        raise RuntimeError('migration source hash mismatch')
    return payload


def transaction_body(payload: bytes) -> str:
    text = payload.decode('utf-8', 'strict')
    starts = list(re.finditer(r'(?im)^\s*BEGIN;\s*$', text))
    commits = list(re.finditer(r'(?im)^\s*COMMIT;\s*$', text))
    if len(starts) != 1 or len(commits) != 1 or starts[0].start() > commits[0].start():
        raise RuntimeError('migration transaction shape invalid')
    body = text[starts[0].end():commits[0].start()]
    if re.search(r'(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;\s*$', body):
        raise RuntimeError('nested transaction control found')
    return body


def state(cur) -> dict[str, object]:
    cur.execute("""select current_database(),current_user,session_user,
      (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s),
      to_regclass('public.pdc_production_environment_sentinel') is not null,
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version='20260829040000'),
      (select count(*) from supabase_migrations.schema_migrations where version='20260829050000'),
      to_regprocedure('public.mark_pdc_parts_received_auditor(uuid,integer,uuid)') is not null,
      to_regclass('public.pdc_auditor_parts_completion_receipts_738') is not null""", (PROJECT_REF,))
    r = cur.fetchone()
    cur.execute("""select pid,application_name,state,xact_start,query_start,wait_event_type,wait_event
      from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid()
      and (application_name ilike %s or query ilike %s) order by pid""",
      (f'%{CONCURRENT_TOKEN}%', f'%{CONCURRENT_TOKEN}%'))
    activity = [dict(zip(('pid','application_name','state','xact_start','query_start','wait_event_type','wait_event'), x)) for x in cur.fetchall()]
    return {
        'database': r[0], 'current_user': r[1], 'session_user': r[2],
        'staging_sentinel': r[3], 'production_sentinel': r[4], 'head': r[5],
        'head_name': r[6], 'migration_present': r[7], 'wrapper_present': r[8],
        'receipt_table_present': r[9], 'concurrent_736_activity': activity,
    }


def assert_preflight(s: dict[str, object]) -> None:
    if (s['database'], s['current_user'], s['session_user'], s['staging_sentinel'], s['production_sentinel']) != ('postgres', 'postgres', 'postgres', 1, False):
        raise RuntimeError('staging identity or sentinel mismatch')
    if s['head'] != '20260829040000' or s['head_name'] != '736_authoritative_rft_confirmation_toggle':
        raise RuntimeError(f"live ledger head changed: {s['head']} {s['head_name']}")
    if s['migration_present'] or s['wrapper_present'] or s['receipt_table_present']:
        raise RuntimeError('738 successor object collision')
    if s['concurrent_736_activity']:
        raise RuntimeError('RFT migration 736 worker/session is still applying')


def poststate(cur) -> dict[str, object]:
    cur.execute("""select
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version='20260829050000'),
      to_regprocedure('public.mark_pdc_parts_received_auditor(uuid,integer,uuid)') is not null,
      to_regclass('public.pdc_auditor_parts_completion_receipts_738') is not null,
      (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_auditor_parts_completion_receipts_738'::regclass),
      has_function_privilege('authenticated','public.mark_pdc_parts_received_auditor(uuid,integer,uuid)','execute'),
      has_function_privilege('anon','public.mark_pdc_parts_received_auditor(uuid,integer,uuid)','execute'),
      has_function_privilege('service_role','public.mark_pdc_parts_received_auditor(uuid,integer,uuid)','execute'),
      to_regclass('public.pdc_production_environment_sentinel') is not null""")
    r = cur.fetchone()
    return dict(zip(('head','name','wrapper','receipt_table','forced_rls','authenticated_execute','anon_execute','service_role_execute','production_sentinel'), r))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('preflight','apply','readback'))
    args = parser.parse_args()
    result: dict[str, object] = {'ok': False, 'mode': args.mode, 'committed': False, 'production_touched': False}
    conn = None
    try:
        payload = source_bytes()
        result['migration_sha256'] = hashlib.sha256(payload).hexdigest()
        body = transaction_body(payload)
        values = load_staging_values()
        conn = connect(values, 'hermes_parts_auditor_738_installer')
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute("select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0))")
            # Re-read the live ledger only after the shared migration lock is held.
            before = state(cur)
            result['before'] = before
            if args.mode == 'readback':
                result['after'] = before
                result['ok'] = True
            else:
                assert_preflight(before)
                cur.execute(body)
                after = poststate(cur)
                result['after'] = after
                if args.mode == 'preflight':
                    conn.rollback()
                    result['rollback_verified'] = state(conn.cursor())['head'] == before['head']
                    result['ok'] = True
                else:
                    approval = f"apply migration 738 source {EXPECTED_SHA256}"
                    if os.environ.get(APPLY_ENV) != approval:
                        raise RuntimeError('apply approval phrase missing')
                    conn.commit()
                    result['committed'] = True
                    result['ok'] = True
        if result['committed']:
            conn.close()
            conn = connect(values, 'hermes_parts_auditor_738_readback')
            with conn.cursor() as cur:
                result['readback'] = poststate(cur)
                if result['readback']['head'] != '20260829050000' or not result['readback']['wrapper'] or not result['readback']['receipt_table'] or not result['readback']['forced_rls'] or not result['readback']['authenticated_execute'] or result['readback']['anon_execute'] or result['readback']['service_role_execute'] or result['readback']['production_sentinel']:
                    raise RuntimeError('738 poststate mismatch')
            conn.rollback()
    except Exception as exc:
        if conn is not None:
            try: conn.rollback()
            except Exception: pass
        result['error'] = str(exc)[:1200]
    finally:
        if conn is not None:
            try: conn.close()
            except Exception: pass
    print(json.dumps(result, default=str, sort_keys=True, separators=(',',':')))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
