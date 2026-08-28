#!/usr/bin/env python3
"""Execute and verify Craig's exact staging Parts check-off once."""
from __future__ import annotations
import hashlib, importlib.util, json, os
from pathlib import Path
from urllib.parse import urlsplit

PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
VEHICLE_ID = '7fe33693-f519-5152-bbe0-9cc799c4ae33'
STOCK = '13017855'
JOB_CARD = 'J139125422'
CRAIG_ID = '8a83b715-8d79-4b0e-95b2-02b55da6e8d7'
CRAIG_EMAIL = 'craig.watson@broometoyota.com.au'
IDEMPOTENCY_KEY = '75100000-0000-4000-8000-000000000751'
APPROVAL = 'mark Stock 13017855 received via authenticated 751 contract'


def values():
    boot = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
    store = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
    spec = importlib.util.spec_from_file_location('pdc_bootstrap', boot)
    if spec is None or spec.loader is None:
        raise RuntimeError('staging bootstrap unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = json.loads(module.unprotect(store.read_bytes()).decode('utf-8'))
    module.validate(result)
    if result.get('PDC_STAGING_PROJECT_REF') != PROJECT_REF:
        raise RuntimeError('staging project mismatch')
    return result


def connect():
    import psycopg2
    config = values()
    parsed = urlsplit(config['PDC_STAGING_DATABASE_URL'])
    if PRODUCTION_REF in config['PDC_STAGING_DATABASE_URL'].lower():
        raise RuntimeError('production endpoint refused')
    conn = psycopg2.connect(host=parsed.hostname, port=parsed.port or 5432,
                            user=parsed.username, password=parsed.password,
                            dbname='postgres', sslmode='verify-full',
                            sslrootcert=config['PDC_STAGING_SSLROOTCERT'],
                            connect_timeout=20,
                            application_name='hermes_parts_751_exact_checkoff')
    return conn


def set_claims(cur, user_id=CRAIG_ID, email=CRAIG_EMAIL):
    claims = json.dumps({'sub': user_id, 'email': email, 'role': 'authenticated'})
    cur.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true),set_config('app.environment','staging',true)", (user_id, claims))


def rpc(cur, vehicle_id, stock, version, key):
    cur.execute("select public.mark_pdc_parts_received_authenticated_751(%s::uuid,%s,%s,%s::uuid)", (vehicle_id, stock, version, key))
    return cur.fetchone()[0]


def snapshot_row(cur):
    cur.execute('select public.get_pdc_email_vehicle_location_snapshot()')
    raw = cur.fetchone()[0]
    rows = []
    def walk(value):
        if isinstance(value, dict):
            if str(value.get('stock_number', '')).strip() == STOCK and value.get('id'):
                rows.append(value)
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
    walk(raw)
    unique = {str(row['id']): row for row in rows}
    return list(unique.values())


def exact_state(cur):
    cur.execute("""select v.id::text,v.stock_number,v.version,v.lifecycle_state::text,v.visible_on_board,
      coalesce(p.parts_required,false),coalesce(p.parts_ordered,false),coalesce(p.parts_received,false),
      coalesce(p.parts_stoppage,false),p.worst_eta,coalesce(w.completed,false),
      (select revision from public.pdc_email_vehicle_revision where singleton),
      (select count(*) from public.pdc_authenticated_parts_received_receipts_751 r where r.vehicle_id=v.id),
      (select count(*) from public.audit_events a where a.vehicle_id=v.id and a.metadata->>'contract'='pdc-authenticated-parts-received-751')
      from public.vehicles v
      left join lateral (select * from public.vehicle_parts_updates where vehicle_id=v.id order by updated_at desc,id desc limit 1) p on true
      left join public.vehicle_work_items w on w.vehicle_id=v.id and upper(w.work_key)='PARTS'
      where v.id=%s::uuid and public.normalize_vehicle_stock_number(v.stock_number)=%s""", (VEHICLE_ID, STOCK))
    return cur.fetchone()


def unrelated_digest(cur):
    cur.execute("""select encode(extensions.digest(coalesce((select string_agg(id::text||':'||stock_number||':'||version::text,'|' order by id) from public.vehicles where id<>%s::uuid),''),'sha256'),'hex'),
      (select count(*) from public.vehicle_parts_updates where vehicle_id<>%s::uuid),
      (select count(*) from public.vehicle_work_items where vehicle_id<>%s::uuid)""", (VEHICLE_ID, VEHICLE_ID, VEHICLE_ID))
    return cur.fetchone()


def main():
    if os.environ.get('PDC_APPROVE_STAGING_PARTS_751') != APPROVAL:
        raise RuntimeError('explicit staging check-off approval phrase missing')
    conn = connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("select (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),(select name from supabase_migrations.schema_migrations where version=(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$')),to_regclass('public.pdc_production_environment_sentinel') is not null,(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s)", (PROJECT_REF,))
            head, head_name, production, sentinel = cur.fetchone()
            if (head, head_name, production, sentinel) != ('20260829144000', '751_authenticated_parts_received_contract', False, 1):
                raise RuntimeError(f'live 751 precondition mismatch: {(head, head_name, production, sentinel)}')
            set_claims(cur)
            before = exact_state(cur)
            if before is None or before[0] != VEHICLE_ID or before[1] != STOCK or before[4] is not True:
                raise RuntimeError(f'exact target prestate mismatch: {before}')
            unrelated_before = unrelated_digest(cur)
            if before[7] is False and before[10] is False:
                if before[2] != 9:
                    raise RuntimeError(f'exact target expected version changed before first check-off: {before}')
                result = rpc(cur, VEHICLE_ID, STOCK, 9, IDEMPOTENCY_KEY)
                if not result.get('ok') or result.get('code') != 'parts_completed' or not result.get('data', {}).get('changed'):
                    raise RuntimeError(f'751 mutation rejected: {result}')
            elif before[2] == 10 and before[7] is True and before[10] is True and before[12] == 1 and before[13] == 2:
                result = {'ok': True, 'code': 'already_applied', 'data': {'changed': False, 'vehicle_id': VEHICLE_ID, 'stock_number': STOCK, 'vehicle_version': 10}}
            else:
                raise RuntimeError(f'exact target state is neither untouched nor verified received: {before}')
            conn.commit()

        with conn.cursor() as cur:
            set_claims(cur)
            after = exact_state(cur)
            if after is None or after[2] != 10 or after[5] is not True or after[6] is not True or after[7] is not True or after[8] is not False or after[10] is not True or after[12] != 1 or after[13] != 2:
                raise RuntimeError(f'authoritative Parts readback mismatch: {after}')
            snapshot = snapshot_row(cur)
            if len(snapshot) != 1:
                raise RuntimeError(f'Board projection identity mismatch: {len(snapshot)}')
            row = snapshot[0]
            if row.get('id') != VEHICLE_ID or row.get('stock_number') != STOCK or row.get('parts_completed') is not True or row.get('parts_update', {}).get('parts_received') is not True:
                raise RuntimeError(f'Board projection mismatch: {row}')
            replay = rpc(cur, VEHICLE_ID, STOCK, 9, IDEMPOTENCY_KEY)
            if not replay.get('ok') or replay.get('code') != 'replayed' or replay.get('data', {}).get('changed') is not False:
                raise RuntimeError(f'exact replay mismatch: {replay}')
            if exact_state(cur)[2] != 10:
                raise RuntimeError('exact replay changed vehicle version')
            conn.rollback()

        with conn.cursor() as cur:
            set_claims(cur)
            wrong_stock = rpc(cur, VEHICLE_ID, '13017856', 10, '75100000-0000-4000-8000-000000000750')
            cur.execute('savepoint wrong_uuid')
            wrong_uuid = rpc(cur, '6fe33693-f519-5152-bbe0-9cc799c4ae33', STOCK, 10, '75100000-0000-4000-8000-000000000755')
            cur.execute('rollback to savepoint wrong_uuid')
            stale = rpc(cur, VEHICLE_ID, STOCK, 9, '75100000-0000-4000-8000-000000000752')
            conflict = rpc(cur, VEHICLE_ID, '13017855', 10, IDEMPOTENCY_KEY)
            negative = {'wrong_stock': wrong_stock, 'wrong_uuid': wrong_uuid, 'stale_version': stale, 'idempotency_conflict': conflict}
            expected = {'wrong_stock': 'vehicle_identity_mismatch', 'wrong_uuid': 'vehicle_identity_mismatch', 'stale_version': 'vehicle_version_conflict', 'idempotency_conflict': 'parts_receipt_idempotency_conflict'}
            if any(negative[key].get('code') != value for key, value in expected.items()):
                raise RuntimeError(f'negative identity/version/idempotency mismatch: {negative}')
            cur.execute("select has_table_privilege('authenticated','public.pdc_authenticated_parts_received_receipts_751','select'),has_table_privilege('authenticated','public.pdc_authenticated_parts_received_receipts_751','insert'),has_table_privilege('authenticated','public.pdc_authenticated_parts_received_receipts_751','update')")
            rls_privileges = cur.fetchone()
            if rls_privileges != (False, False, False):
                raise RuntimeError(f'authenticated receipt table access is too broad: {rls_privileges}')
            cur.execute("select count(*) from public.pdc_authenticated_parts_received_receipts_751 where vehicle_id=%s::uuid", (VEHICLE_ID,))
            receipt_count = cur.fetchone()[0]
            if receipt_count != 1:
                raise RuntimeError(f'receipt count changed during negative probes: {receipt_count}')
            unrelated_after = unrelated_digest(cur)
            if unrelated_after != unrelated_before:
                raise RuntimeError(f'unrelated digest changed: {unrelated_before} -> {unrelated_after}')
            cur.execute("select r.auth_user_id::text,lower(r.email),r.role::text,s.dealer_code from public.pdc_user_roles r left join public.pdc_auditor_user_dealer_scopes s on s.auth_user_id=r.auth_user_id and s.active and s.environment='staging' where r.active and r.account_status='approved' and r.role::text='operator' and s.dealer_code<>'14450' limit 1")
            operator = cur.fetchone()
            operator_probe = 'skipped_no_opposite_dealer_operator'
            if operator:
                set_claims(cur, operator[0], operator[1])
                operator_result = rpc(cur, VEHICLE_ID, STOCK, 10, '75100000-0000-4000-8000-000000000753')
                if operator_result.get('code') != 'dealer_scope_denied':
                    raise RuntimeError(f'wrong-dealer operator was not denied: {operator_result}')
                operator_probe = operator_result
            cur.execute("select r.auth_user_id::text,lower(r.email) from public.pdc_user_roles r where r.active and r.account_status='approved' and r.role::text='viewer' limit 1")
            viewer = cur.fetchone()
            viewer_probe = 'skipped_no_viewer_fixture'
            if viewer:
                set_claims(cur, viewer[0], viewer[1])
                viewer_result = rpc(cur, VEHICLE_ID, STOCK, 10, '75100000-0000-4000-8000-000000000754')
                if viewer_result.get('code') != 'permission_denied':
                    raise RuntimeError(f'wrong-role viewer was not denied: {viewer_result}')
                viewer_probe = viewer_result
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            production_after = cur.fetchone()[0]
            if production_after:
                raise RuntimeError('production sentinel appeared')
            print(json.dumps({'ok': True, 'head': f'{head}/{head_name}', 'target': {'vehicle_id': VEHICLE_ID, 'stock_number': STOCK, 'job_card': JOB_CARD, 'before_version': before[2], 'after_version': after[2]}, 'mutation': result, 'readback': {'parts_received': after[7], 'parts_ordered': after[6], 'parts_stoppage': after[8], 'work_completed': after[10], 'receipt_count': after[12], 'audit_count': after[13], 'snapshot_rows': len(snapshot)}, 'replay': replay, 'negative': negative, 'operator_probe': operator_probe, 'viewer_probe': viewer_probe, 'rls_privileges': rls_privileges, 'unrelated_digest': unrelated_before, 'production_sentinel': production_after}, default=str, sort_keys=True))
            conn.rollback()
    finally:
        conn.close()


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'ok': False, 'error': str(exc)[:1200], 'production_touched': False}, sort_keys=True))
        raise
