from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260830101000_pdc_lifecycle_history_synthetic_scope_repair.sql'
BOOTSTRAP = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
EVIDENCE = Path(r'C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/review-evidence/lifecycle-history-20260830101000-staging-readback.json')
REF = 'cdsmnqxtyyoeoznmbidd'
PROD = 'vjdtsswhroyguxyfjdkt'
PREDECESSOR = ('20260830100000', '771_workshop_admin_block_audit_projection_successor')
NEW_HEAD = ('20260830101000', 'pdc_lifecycle_history_synthetic_scope_repair')


def staging_values():
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap_82000', BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError('staging bootstrap unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode('utf-8'))
    module.validate(values)
    dsn = values['PDC_STAGING_DATABASE_URL']
    if REF not in dsn or PROD in dsn:
        raise RuntimeError('PDC_82000_NON_STAGING_DATABASE_TARGET')
    return values


def head(cur):
    cur.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
    return tuple(cur.fetchone())


def scalar(cur, query, args=()):
    cur.execute(query, args)
    row = cur.fetchone()
    return row[0] if row else None


def readback(cur):
    cur.execute("select transition_kind,event_kind,count(*) from public.pdc_vehicle_lifecycle_history_events_82000 group by transition_kind,event_kind order by transition_kind,event_kind")
    event_counts = [list(row) for row in cur.fetchall()]
    complete = scalar(cur, "select count(*) from public.pdc_vehicle_lifecycle_history_events_82000 e where e.event_kind='latch' and e.transition_kind='YH' and exists(select 1 from public.pdc_vehicle_lifecycle_history_events_82000 p where p.vehicle_id=e.vehicle_id and p.event_kind='latch' and p.transition_kind='PMB') and exists(select 1 from public.pdc_vehicle_lifecycle_history_events_82000 r where r.vehicle_id=e.vehicle_id and r.event_kind='latch' and r.transition_kind='RFT')")
    total = scalar(cur, 'select count(distinct vehicle_id) from public.pdc_vehicle_lifecycle_history_events_82000')
    cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_vehicle_lifecycle_history_events_82000'::regclass")
    rls = list(cur.fetchone())
    cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_vehicle_lifecycle_history_controls_82000'::regclass")
    control_rls = list(cur.fetchone())
    return {
        'head': list(head(cur)),
        'production_sentinel_present': bool(scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")),
        'staging_sentinel_count': scalar(cur, 'select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s', (REF,)),
        'event_counts': event_counts,
        'vehicles_with_retained_events': total,
        'complete_yh_pmb_rft_vehicle_count': complete,
        'history_events_rls_force': rls,
        'history_controls_rls_force': control_rls,
        'history_enabled': scalar(cur, 'select public.pdc_lifecycle_history_enabled_82000()'),
        'latch_trigger_present': scalar(cur, "select count(*) from pg_trigger where tgrelid='public.vehicles'::regclass and tgname='pdc_capture_vehicle_lifecycle_transition_82000' and not tgisinternal") == 1,
        'history_rpc_execute_authenticated': scalar(cur, "select has_function_privilege('authenticated','public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)','EXECUTE')"),
        'history_rpc_execute_anon': scalar(cur, "select has_function_privilege('anon','public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)','EXECUTE')"),
        'history_table_direct_authenticated': scalar(cur, "select has_table_privilege('authenticated','public.pdc_vehicle_lifecycle_history_events_82000','SELECT,INSERT,UPDATE,DELETE')"),
        'history_table_direct_service_role': scalar(cur, "select has_table_privilege('service_role','public.pdc_vehicle_lifecycle_history_events_82000','SELECT,INSERT,UPDATE,DELETE')"),
    }


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected_approval = f'apply PDC lifecycle history 82000 source {digest}'
    if os.environ.get('PDC_APPROVE_LIFECYCLE_HISTORY_82000') != expected_approval:
        raise RuntimeError('PDC_82000_EXPLICIT_STAGING_APPROVAL_MISSING')
    values = staging_values()
    conn = psycopg2.connect(values['PDC_STAGING_DATABASE_URL'], sslmode='verify-full', sslrootcert=values['PDC_STAGING_SSLROOTCERT'], application_name='pdc-lifecycle-history-82000')
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            before = {'head': list(head(cur)), 'production_sentinel_present': bool(scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")), 'staging_sentinel_count': scalar(cur, 'select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s', (REF,)), 'vehicle_count': scalar(cur, 'select count(*) from public.vehicles')}
            if tuple(before['head']) != PREDECESSOR or before['production_sentinel_present'] or before['staging_sentinel_count'] != 1:
                raise RuntimeError(f'PDC_82000_PREDECESSOR_OR_SENTINEL_MISMATCH:{before}')
            cur.execute(MIGRATION.read_text(encoding='utf-8'))
            conn.commit()
        with conn.cursor() as cur:
            after = readback(cur)
            if tuple(after['head']) != NEW_HEAD or after['production_sentinel_present'] or after['staging_sentinel_count'] != 1 or after['history_enabled'] is not True or after['latch_trigger_present'] is not True or after['history_events_rls_force'] != [True, True] or after['history_controls_rls_force'] != [True, True] or after['history_rpc_execute_authenticated'] is not True or after['history_rpc_execute_anon'] is not False or after['history_table_direct_authenticated'] is not False or after['history_table_direct_service_role'] is not False:
                raise RuntimeError(json.dumps({'after': after}, default=str))
            result = {'ok': True, 'environment': 'staging', 'project_ref': REF, 'migration': f'{NEW_HEAD[0]}_{NEW_HEAD[1]}', 'migration_sha256': digest, 'predecessor': list(PREDECESSOR), 'before': before, 'after': after, 'production_contacted': False, 'rollback_disable_rpc': 'disable_pdc_vehicle_lifecycle_history_82000(false, reason)', 'recovery_evidence': 'append-only events remain protected by FORCE ROW LEVEL SECURITY and vehicle FK ON DELETE RESTRICT'}
    finally:
        conn.close()
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps(result, indent=2, sort_keys=True, default=str) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2, sort_keys=True, default=str))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error), 'production_contacted': False}, indent=2))
        raise SystemExit(1)
