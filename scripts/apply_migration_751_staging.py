#!/usr/bin/env python3
"""Fail-closed installer for staging-only authenticated Parts contract 751."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260829144000_751_authenticated_parts_received_contract.sql'
EXPECTED_SHA256 = '7b08caa9418fde60feeafdef9f50ca8db4ef04c1101ab731043602b909630ce4'
PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
APPLY_ENV = 'PDC_APPROVE_STAGING_MIGRATION_751'
CONCURRENT_RECOVERY_TOKEN = 'pdc-staging-747-recover-stock-13000769'


def load_values() -> dict[str, str]:
    bootstrap = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
    secret_store = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', bootstrap)
    if spec is None or spec.loader is None:
        raise RuntimeError('staging bootstrap unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(secret_store.read_bytes()).decode('utf-8'))
    module.validate(values)
    if values.get('PDC_STAGING_PROJECT_REF') != PROJECT_REF:
        raise RuntimeError('staging project mismatch')
    return values


def connect(values: dict[str, str], application_name: str):
    import psycopg2
    parsed = urlsplit(values['PDC_STAGING_DATABASE_URL'])
    direct = parsed.hostname == f'db.{PROJECT_REF}.supabase.co' and parsed.username == 'postgres' and parsed.port == 5432
    pooler = bool(re.fullmatch(r'aws-[0-9]+-[a-z0-9]+(?:-[a-z0-9]+)*\.pooler\.supabase\.com', parsed.hostname or '')) and parsed.username == f'postgres.{PROJECT_REF}' and parsed.port in (5432, 6543)
    if PRODUCTION_REF in values['PDC_STAGING_DATABASE_URL'].lower() or not (direct or pooler):
        raise RuntimeError('refusing non-staging database endpoint')
    return psycopg2.connect(host=parsed.hostname, port=parsed.port or 5432, user=parsed.username,
                            password=parsed.password, dbname='postgres', sslmode='verify-full',
                            sslrootcert=values['PDC_STAGING_SSLROOTCERT'], connect_timeout=20,
                            application_name=application_name)


def source() -> tuple[bytes, str]:
    payload = MIGRATION.read_bytes()
    if hashlib.sha256(payload).hexdigest() != EXPECTED_SHA256:
        raise RuntimeError('751 migration source hash mismatch')
    text = payload.decode('utf-8', 'strict')
    starts = list(re.finditer(r'(?im)^\s*BEGIN;\s*$', text))
    commits = list(re.finditer(r'(?im)^\s*COMMIT;\s*$', text))
    if len(starts) != 1 or len(commits) != 1 or starts[0].start() > commits[0].start():
        raise RuntimeError('751 transaction shape invalid')
    body = text[starts[0].end():commits[0].start()]
    if re.search(r'(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;\s*$', body):
        raise RuntimeError('751 nested transaction control found')
    return payload, body


def state(cur) -> dict[str, object]:
    cur.execute("""select current_database(),current_user,session_user,
      (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s),
      to_regclass('public.pdc_production_environment_sentinel') is not null,
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version=(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$')),
      to_regprocedure('public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)') is not null,
      to_regclass('public.pdc_authenticated_parts_received_receipts_751') is not null""", (PROJECT_REF,))
    row = cur.fetchone()
    cur.execute("""select pid,application_name,state,query_start,wait_event_type,wait_event
      from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid()
      and (application_name ilike %s or query ilike %s) order by pid""",
                (f'%{CONCURRENT_RECOVERY_TOKEN}%', f'%{CONCURRENT_RECOVERY_TOKEN}%'))
    activity = [dict(zip(('pid', 'application_name', 'state', 'query_start', 'wait_event_type', 'wait_event'), item)) for item in cur.fetchall()]
    return {'database': row[0], 'current_user': row[1], 'session_user': row[2],
            'staging_sentinel': row[3], 'production_sentinel': row[4], 'head': row[5],
            'head_name': row[6], 'rpc': row[7], 'receipt_table': row[8],
            'recovery_activity': activity}


def assert_preflight(s: dict[str, object]) -> None:
    if (s['database'], s['current_user'], s['session_user'], s['staging_sentinel'], s['production_sentinel']) != ('postgres', 'postgres', 'postgres', 1, False):
        raise RuntimeError('staging identity or sentinel mismatch')
    if s['head'] != '20260829143000' or s['head_name'] != '750_project_recovered_stock_qc_operation_lines':
        raise RuntimeError(f"live ledger head changed: {s['head']} {s['head_name']}")
    if s['rpc'] or s['receipt_table']:
        raise RuntimeError('751 successor object collision')
    if s['recovery_activity']:
        raise RuntimeError('recovery lane is still active')


def poststate(cur) -> dict[str, object]:
    cur.execute("""select
      (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
      (select name from supabase_migrations.schema_migrations where version='20260829144000'),
      to_regprocedure('public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)') is not null,
      to_regclass('public.pdc_authenticated_parts_received_receipts_751') is not null,
      (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_authenticated_parts_received_receipts_751'::regclass),
      has_function_privilege('authenticated','public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)','execute'),
      has_function_privilege('anon','public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)','execute'),
      has_function_privilege('service_role','public.mark_pdc_parts_received_authenticated_751(uuid,text,integer,uuid)','execute'),
      to_regclass('public.pdc_production_environment_sentinel') is not null""")
    row = cur.fetchone()
    return dict(zip(('head', 'name', 'rpc', 'receipt_table', 'forced_rls', 'authenticated_execute',
                     'anon_execute', 'service_role_execute', 'production_sentinel'), row))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('preflight', 'apply', 'readback'))
    args = parser.parse_args()
    result: dict[str, object] = {'ok': False, 'mode': args.mode, 'committed': False, 'production_touched': False}
    conn = None
    try:
        payload, body = source()
        result['migration_sha256'] = hashlib.sha256(payload).hexdigest()
        values = load_values()
        conn = connect(values, 'hermes_parts_authenticated_751_installer')
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute("select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0))")
            before = state(cur)
            result['before'] = before
            if args.mode == 'readback':
                result['after'] = before
                result['ok'] = True
            else:
                assert_preflight(before)
                cur.execute(body)
                result['after'] = poststate(cur)
                if args.mode == 'preflight':
                    conn.rollback()
                    result['rollback_verified'] = state(conn.cursor())['head'] == before['head']
                    result['ok'] = True
                else:
                    if os.environ.get(APPLY_ENV) != f'apply migration 751 source {EXPECTED_SHA256}':
                        raise RuntimeError('apply approval phrase missing')
                    conn.commit()
                    result['committed'] = True
                    result['ok'] = True
        if result['committed']:
            conn.close()
            conn = connect(values, 'hermes_parts_authenticated_751_readback')
            with conn.cursor() as cur:
                result['readback'] = poststate(cur)
                readback = result['readback']
                if (readback['head'] != '20260829144000' or not readback['rpc'] or not readback['receipt_table']
                    or not readback['forced_rls'] or not readback['authenticated_execute']
                    or readback['anon_execute'] or readback['service_role_execute'] or readback['production_sentinel']):
                    raise RuntimeError('751 poststate mismatch')
            conn.rollback()
    except Exception as exc:
        if conn is not None:
            try:
                conn.rollback()
            except Exception:
                pass
        result['error'] = str(exc)[:1200]
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
    print(json.dumps(result, default=str, sort_keys=True, separators=(',', ':')))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
