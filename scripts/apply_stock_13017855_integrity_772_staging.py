from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import pathlib
import urllib.error
import urllib.request
from decimal import Decimal

import psycopg2

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260830080000_stock_13017855_integrity_and_lifecycle_guards.sql'
BOOTSTRAP = pathlib.Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = pathlib.Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
REF = 'cdsmnqxtyyoeoznmbidd'
PROD = 'vjdtsswhroyguxyfjdkt'
PREDECESSOR = ('20260830081000', 'stock_13017855_restore_navision_parity_successor')
NEW = ('20260830081000', 'stock_13017855_restore_navision_parity_successor')
VEHICLE_ID = 'b02645d9-f411-5de0-97d1-905966b5feae'
TOMBSTONE_ID = 'f8e932e2-0699-46a5-81e7-0cc3f071eaac'
STOCK = '13017855'
JOB_CARD = 'J139125422'
VIN = 'MR0MABAV902402464'
PARTS_RECEIPT = '8660fc9e-09cd-5fb5-9bf9-cbc577a013bb'
DASHBOARD = '20260829_101700_3c31d6'
EXPECTED_OPERATION_IDS = {
    '3b77aef4-cafd-4474-a6eb-f8b4f01e3c2d', '407f44f7-5e5a-4c80-98c6-bf0ba230c958',
    'e561d8d1-0aed-42d4-af42-2076f42a9075', '39cdc54b-4d9c-440a-b476-b7bf3dc38aa6',
    '7caa4123-ab54-494d-a437-157ceb2dbb11', '9a3dc29c-20b9-4d16-b081-7845461342e8',
    '84aab91c-8107-4f93-a187-86f8d4751b29', '2cf57b29-d5d1-4521-ad85-21083367ef2b',
    '19ba3df8-8c47-4ef7-8016-29f56e21b7e3', 'b895ef70-a675-4d8c-9bb9-589a2f9d6f27',
    '21b9ede2-b305-42c0-aa92-3150eabfb906', '9e78b2c1-9c44-4929-aa8c-06add08b156f',
    'a601886e-9c91-4da5-bc07-5a55e9f64905', 'e271f02e-b5e2-442a-86d0-329110678c6a',
    'cefa34f0-96c4-4e75-b9b7-9ce5464fd8f5', '574571f5-6622-4b53-8d00-4544c00226bb',
    '567f7191-169a-456b-b8b9-fd218a7ce579', 'a7c69f42-54b0-45c0-9b13-21be94e10228',
    'e31c7e02-5f69-4bf2-8d23-73d54b4b435f', 'c18d28b4-006b-4234-be7d-607f605e811f',
}


def values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location('pdc_772_bootstrap', BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError('staging bootstrap unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode('utf-8'))
    module.validate(data)
    dsn = data['PDC_STAGING_DATABASE_URL']
    if REF not in dsn or PROD in dsn:
        raise RuntimeError('PDC_772_NON_STAGING_DATABASE_TARGET')
    return data


def scalar(cur, sql: str, args: tuple = ()):
    cur.execute(sql, args)
    row = cur.fetchone()
    return row[0] if row else None


def head(cur) -> tuple[str, str] | None:
    cur.execute("select version,name from supabase_migrations.schema_migrations order by version::bigint desc limit 1")
    row = cur.fetchone()
    return tuple(row) if row else None


def admin_token() -> tuple[str, str, str]:
    base = os.environ['PDC_STAGING_SUPABASE_URL'].rstrip('/')
    anon = os.environ['PDC_STAGING_ANON_KEY']
    payload = json.dumps({'email': os.environ['PDC_STAGING_ADMIN_EMAIL'], 'password': os.environ['PDC_STAGING_ADMIN_PASSWORD']}).encode()
    req = urllib.request.Request(base + '/auth/v1/token?grant_type=password', data=payload, headers={'apikey': anon, 'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(req, timeout=30) as response:
        body = json.loads(response.read())
    return base, anon, body['access_token']


def rpc(base: str, anon: str, token: str, name: str, payload: dict) -> tuple[int, object]:
    req = urllib.request.Request(base + '/rest/v1/rpc/' + name, data=json.dumps(payload).encode(), headers={'apikey': anon, 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode(errors='replace'))


def hash_json(cur, value: dict) -> str:
    return scalar(cur, 'select public.pdc_772_hash(%s::jsonb)', (json.dumps(value),))


def verify(cur) -> dict[str, object]:
    vehicle = scalar(cur, "select row_to_json(v) from public.vehicles v where v.id=%s", (VEHICLE_ID,))
    operations = cur.execute("select operation_line_id,operation_no,description,estimated_hours,work_key from public.pdc_authenticated_email_operation_lines where vehicle_id=%s order by operation_no,operation_line_id", (VEHICLE_ID,)) or None
    operations = cur.fetchall()
    operation_ids = {str(row[0]) for row in operations}
    total = sum((Decimal(str(row[3] or 0)) for row in operations), Decimal('0'))
    zeroes = sum(1 for row in operations if Decimal(str(row[3] or 0)) == 0)
    work_items = scalar(cur, "select coalesce(jsonb_agg(to_jsonb(w) order by w.work_key),'[]'::jsonb) from public.vehicle_work_items w where w.vehicle_id=%s", (VEHICLE_ID,))
    fabrication = scalar(cur, "select row_to_json(a) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=%s and a.line_key='display:FABRICATION:59539f1d'", (VEHICLE_ID,))
    parts = scalar(cur, "select row_to_json(p) from public.vehicle_parts_updates p where p.vehicle_id=%s order by p.updated_at desc,p.id desc limit 1", (VEHICLE_ID,))
    parts_receipt = scalar(cur, "select count(*) from public.pdc_authenticated_parts_received_receipts_751 where receipt_id=%s::uuid and vehicle_id=%s", (PARTS_RECEIPT, VEHICLE_ID))
    booking_dates = scalar(cur, "select coalesce(jsonb_agg(jsonb_build_object('booking_id',h.booking_id,'event_type',h.event_type,'scheduled_start_at',h.after_data->>'scheduled_start_at','scheduled_end_at',h.after_data->>'scheduled_end_at') order by h.booking_id,h.created_at,h.id),'[]'::jsonb) from public.workshop_booking_history h where h.vehicle_id=%s", (VEHICLE_ID,))
    active_bookings = scalar(cur, "select count(*) from public.workshop_bookings where vehicle_id=%s and deleted_at is null and status::text not in ('completed','deleted','cancelled')", (VEHICLE_ID,))
    receipt = scalar(cur, "select row_to_json(r) from public.pdc_stock_13017855_restore_receipts_772 r where vehicle_id=%s", (VEHICLE_ID,))
    activation = scalar(cur, "select count(*) from public.navision_board_activations where canonical_vehicle_id=%s and backend_record_id='e39eb741-cf03-44f2-8a75-54362ecc8a26'::uuid and active", (VEHICLE_ID,))
    return {
        'vehicle': vehicle,
        'identity': bool(vehicle and vehicle['id'] == VEHICLE_ID and vehicle['stock_number'] == STOCK and vehicle['vin'] == VIN and vehicle['job_card_number'] == JOB_CARD and vehicle['lifecycle_state'] == 'active' and vehicle['visible_on_board'] is True and vehicle['version'] == 20),
        'operations': {'count': len(operations), 'total_hours': str(total), 'zero_hour_count': zeroes, 'exact_ids': operation_ids == EXPECTED_OPERATION_IDS},
        'work_items': work_items,
        'parts_complete': bool(parts and parts['parts_received'] is True and parts_receipt == 1),
        'parts_receipt_id': PARTS_RECEIPT,
        'fabrication_projection': fabrication,
        'active_fabrication_projection': bool(fabrication and fabrication['active'] is True),
        'active_booking_count': active_bookings,
        'booking_dates': booking_dates,
        'booking_date_hash': hash_json(cur, json.loads(json.dumps(booking_dates, default=str))) if booking_dates is not None else None,
        'board_activation_active': activation == 1,
        'restore_receipt': receipt,
    }


def main() -> dict[str, object]:
    approval = os.environ.get('PDC_APPROVE_STOCK_13017855_772', '')
    migration_sha = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    if approval != f'apply Stock 13017855 migration 772 source {migration_sha}':
        raise RuntimeError('PDC_772_EXPLICIT_STAGING_APPROVAL_MISSING')
    secret_values = values()
    conn = psycopg2.connect(secret_values['PDC_STAGING_DATABASE_URL'], sslmode='verify-full', sslrootcert=secret_values['PDC_STAGING_SSLROOTCERT'], application_name='pdc-stock-13017855-integrity-772')
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            current_head = head(cur)
            if current_head != NEW:
                raise RuntimeError(f'PDC_772_PREDECESSOR_MISMATCH:{current_head}')
            if scalar(cur, "select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (REF,)) != 1 or scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError('PDC_772_STAGING_BOUNDARY_FAILED')
            unrelated_before = scalar(cur, "select public.pdc_772_hash(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)) from public.vehicles x where x.stock_number_normalized='13000769'")
            head_after = head(cur)
            if head_after != NEW:
                raise RuntimeError(f'PDC_772_APPLY_HEAD_FAILED:{head_after}')
            payload = {'contract': 'stock-13017855-restore-772', 'vehicle_id': VEHICLE_ID, 'tombstone_id': TOMBSTONE_ID, 'expected_version': 19, 'confirmation_stock': STOCK, 'idempotency_key': f'{DASHBOARD}-restore-13017855', 'reason': f'Restore Stock {STOCK} for dashboard {DASHBOARD}'}
            request_hash = hash_json(cur, payload)
            unrelated_after_apply = scalar(cur, "select public.pdc_772_hash(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)) from public.vehicles x where x.stock_number_normalized='13000769'")
        base, anon, token = admin_token()
        restore_payload = {'p_vehicle_id': VEHICLE_ID, 'p_tombstone_id': TOMBSTONE_ID, 'p_expected_version': 19, 'p_confirmation_stock': STOCK, 'p_idempotency_key': payload['idempotency_key'], 'p_request_hash': request_hash, 'p_reason': payload['reason']}
        restore_status, restore_body = rpc(base, anon, token, 'restore_stock_13017855_archived_vehicle_772', restore_payload)
        replay_status, replay_body = rpc(base, anon, token, 'restore_stock_13017855_archived_vehicle_772', restore_payload)
        with conn.cursor() as cur:
            evidence = verify(cur)
            unrelated_after_restore = scalar(cur, "select public.pdc_772_hash(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)) from public.vehicles x where x.stock_number_normalized='13000769'")
            live_detail_status, live_detail = rpc(base, anon, token, 'get_vehicle_workshop_detail', {'p_vehicle_id': VEHICLE_ID})
            checks = {
                'restore_http_ok': restore_status == 200 and restore_body.get('ok') is True,
                'restore_code': restore_body.get('code') in {'stock_13017855_restored_772', 'stock_13017855_restore_replayed_772'},
                'replay_http_ok': replay_status == 200 and replay_body.get('ok') is True and replay_body.get('replay') is True,
                'same_receipt_replay': restore_body.get('receipt_id') == replay_body.get('receipt_id'),
                'live_detail_http_ok': live_detail_status == 200 and live_detail.get('ok') is not False,
                'target_identity': evidence['identity'],
                'operation_parity': evidence['operations'] == {'count': 20, 'total_hours': '17.29', 'zero_hour_count': 6, 'exact_ids': True},
                'parts_complete_receipt': evidence['parts_complete'],
                'fabrication_active': evidence['active_fabrication_projection'],
                'no_active_booking_occupancy': evidence['active_booking_count'] == 0,
                'booking_history_preserved': isinstance(evidence['booking_dates'], list) and len(evidence['booking_dates']) == 12,
                'board_activation_active': evidence['board_activation_active'],
                'unrelated_13000769_isolated': unrelated_before == unrelated_after_apply == unrelated_after_restore,
                'production_absent': scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null") is False,
            }
            if not all(checks.values()):
                summary = {key: evidence[key] for key in ('identity', 'operations', 'parts_complete', 'active_fabrication_projection', 'active_booking_count', 'board_activation_active')}
                raise RuntimeError(json.dumps({'checks': checks, 'restore_code': restore_body.get('code'), 'replay_code': replay_body.get('code'), 'evidence_summary': summary}, default=str))
            return {'ok': True, 'environment': 'staging', 'project_ref': REF, 'migration': f'{NEW[0]}_{NEW[1]}', 'migration_sha256': migration_sha, 'predecessor': PREDECESSOR, 'restore': restore_body, 'replay': replay_body, 'live_detail': live_detail, 'checks': checks, 'evidence': evidence, 'dashboard_session': DASHBOARD, 'production_contacted': False}
    finally:
        conn.close()


if __name__ == '__main__':
    try:
        print(json.dumps(main(), indent=2, sort_keys=True, default=str))
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error), 'production_contacted': False}, indent=2))
        raise SystemExit(1)
