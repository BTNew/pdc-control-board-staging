#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import sys
from decimal import Decimal
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path.home() / 'pdc-control-board' / '_staging_test_tools'
sys.path.insert(0, str(TOOLS))
from staging_env import assert_staging_target, load_local_env  # noqa: E402

MIGRATION = ROOT / 'supabase' / 'staging_only' / '149_move_source_lines_between_workshop_stations.sql'
EXPECTED_SHA256 = '256b7945cb5a3ef14f1c5ac88bdff5f77535684389f878b729af42fcc97d692b'
MIGRATION_150 = ROOT / 'supabase' / 'staging_only' / '150_lock_source_and_target_completion_for_station_moves.sql'
EXPECTED_SHA256_150 = '1ad56011d89ef3bf8f7efd189ae33324cdff148c145f76076d5cefdef2444a8e'


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def transaction_body(source):
    lines = source.splitlines()
    if not lines or lines[0].strip().lower() != 'begin;' or lines[-1].strip().lower() != 'commit;':
        raise RuntimeError('migration transaction wrapper mismatch')
    return '\n'.join(lines[1:-1])


def durable_counts(cur):
    tables = (
        'vehicles', 'vehicle_work_items', 'workshop_bookings', 'vehicle_parts_updates',
        'pdc_authenticated_email_operation_lines', 'vehicle_workshop_line_adjustments', 'audit_events',
    )
    return {table: scalar(cur, f'select count(*) from public.{table}') for table in tables}


def verify_structure(cur):
    if scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='149' and name='move_source_lines_between_workshop_stations'") != 1:
        raise RuntimeError('migration 149 ledger mismatch')
    if scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='150' and name='lock_source_and_target_completion_for_station_moves'") != 1:
        raise RuntimeError('migration 150 ledger mismatch')
    definition = scalar(cur, "select lower(pg_get_functiondef('public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure))")
    required = (
        "require_pdc_role('operator')", "v_line_key !~ '^source:", 'for update', 'for share',
        'workshop_source_stage_completed_or_unavailable', 'v_current_stage',
        'workshop_stage_not_editable', "'hours_changed'", "'bookings_changed'",
        "'parts_changed'", "'completion_changed'", "'location_changed'",
    )
    for marker in required:
        if marker not in definition:
            raise RuntimeError(f'station move function marker missing: {marker}')
    for forbidden in ('insert into public.vehicles', 'update public.vehicles', 'workshop_bookings', 'vehicle_parts_updates', 'update public.vehicle_work_items'):
        if forbidden in definition:
            raise RuntimeError(f'forbidden operational family in station move function: {forbidden}')
    constraint = scalar(cur, "select lower(pg_get_constraintdef(oid)) from pg_constraint where conrelid='public.vehicle_workshop_line_adjustments'::regclass and conname='vehicle_workshop_line_adjustments_estimated_hours_check'")
    if not constraint or "'source'" not in constraint or "'display'" not in constraint or "'manual'" not in constraint or '999.99' not in constraint or '0.25' not in constraint:
        raise RuntimeError('source precise/manual quarter-hour constraint mismatch')
    if scalar(cur, "select is_nullable from information_schema.columns where table_schema='public' and table_name='vehicle_workshop_line_adjustments' and column_name='estimated_hours'") != 'YES':
        raise RuntimeError('source null-hour preservation missing')
    grants = scalar(cur, """
      select coalesce(jsonb_object_agg(r.rolname,acl.privilege_type order by r.rolname),'{}'::jsonb)
      from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      join pg_roles r on r.oid=acl.grantee
      where p.oid='public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure
        and acl.privilege_type='EXECUTE'
    """)
    if grants != {'authenticated': 'EXECUTE', 'postgres': 'EXECUTE'}:
        raise RuntimeError(f'unexpected direct execution grants: {grants}')


def verify_behavior(cur):
    cur.execute("""
      select r.auth_user_id,lower(r.email)
      from public.pdc_user_roles r join auth.users au on au.id=r.auth_user_id and lower(au.email)=lower(r.email)
      where r.role::text in ('operator','administrator') and r.active and r.account_status='approved'
      order by case when r.role::text='operator' then 0 else 1 end limit 1
    """)
    actor = cur.fetchone()
    if not actor:
        raise RuntimeError('no guarded Operator fixture available')
    actor_id, actor_email = actor
    scalar(cur, "select set_config('request.jwt.claims',%s,true)", (json.dumps({'sub': str(actor_id), 'email': actor_email, 'role': 'authenticated'}),))

    cur.execute("""
      select ol.vehicle_id,ol.operation_line_id,ol.description,ol.estimated_hours,
             coalesce(public.workshop_stage_code_for_work_key(ol.work_key),upper(regexp_replace(btrim(ol.work_key),'[^a-zA-Z0-9]+','_','g'))) source_stage,
             target.target_stage
      from public.pdc_authenticated_email_operation_lines ol
      join public.vehicles v on v.id=ol.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      cross join lateral (
        select coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g'))) target_stage
        from public.vehicle_work_items wi
        where wi.vehicle_id=ol.vehicle_id and wi.required and not wi.completed
          and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))
              <>coalesce(public.workshop_stage_code_for_work_key(ol.work_key),upper(regexp_replace(btrim(ol.work_key),'[^a-zA-Z0-9]+','_','g')))
        order by target_stage limit 1
      ) target
      where v.stock_number='12535460'
        and (ol.estimated_hours=0 or ol.estimated_hours is null or mod(ol.estimated_hours,0.25)<>0)
        and not exists(select 1 from public.vehicle_workshop_line_adjustments a where a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text)
      order by case when ol.estimated_hours is not null and ol.estimated_hours>0 then 0 else 1 end,ol.operation_no
    """)
    candidates = cur.fetchall()
    if not candidates:
        raise RuntimeError('Stock 12535460 precise/zero-hour source move fixture unavailable')
    candidate = candidates[0]
    vehicle_id, operation_line_id, description, source_hours, source_stage, target_stage = candidate
    line_key = f'source:{operation_line_id}'
    cur.execute('savepoint completed_source_guard')
    cur.execute("""
      update public.vehicle_work_items wi set completed=true
       where wi.vehicle_id=%s
         and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=%s
    """, (vehicle_id, source_stage))
    try:
        cur.execute("select public.move_vehicle_workshop_source_line_stage(%s,null,0,%s,%s)", (vehicle_id, line_key, target_stage))
        raise RuntimeError('completed current source station was not rejected')
    except psycopg2.Error as exc:
        if 'workshop_source_stage_completed_or_unavailable' not in str(exc):
            raise
    finally:
        cur.execute('rollback to savepoint completed_source_guard')
        cur.execute('release savepoint completed_source_guard')
    before = durable_counts(cur)
    moved = []
    for vehicle_id, operation_line_id, description, source_hours, source_stage, target_stage in candidates:
        receipt = scalar(cur, "select public.move_vehicle_workshop_source_line_stage(%s,null,0,%s,%s)", (vehicle_id, f'source:{operation_line_id}', target_stage))
        if not receipt.get('ok') or receipt.get('code') != 'workshop_source_line_station_moved':
            raise RuntimeError(f'station move receipt failed: {receipt}')
        data = receipt['data']
        returned_hours = data.get('estimated_hours')
        hours_match = (returned_hours is None and source_hours is None) or (
            returned_hours is not None and source_hours is not None and Decimal(str(returned_hours)) == Decimal(source_hours)
        )
        if data['stage_code'] != target_stage or data['description'] != description or not hours_match:
            raise RuntimeError('station move did not preserve exact source description/hours')
        metadata = scalar(cur, "select metadata from public.audit_events where row_id=%s order by id desc limit 1", (data['adjustment_id'],))
        if not metadata or metadata.get('source') != 'vehicle_detail_workshop_station_move_150' or any(metadata.get(key) is not False for key in ('hours_changed','bookings_changed','parts_changed','completion_changed','location_changed')):
            raise RuntimeError('station-only audit metadata mismatch')
        moved.append(None if source_hours is None else str(source_hours))
    after = durable_counts(cur)
    for table in ('vehicles','vehicle_work_items','workshop_bookings','vehicle_parts_updates','pdc_authenticated_email_operation_lines'):
        if after[table] != before[table]:
            raise RuntimeError(f'station move changed forbidden table {table}')
    if after['vehicle_workshop_line_adjustments'] != before['vehicle_workshop_line_adjustments'] + len(candidates) or after['audit_events'] != before['audit_events'] + len(candidates):
        raise RuntimeError('station move overlay/audit counts mismatch')
    return {
        'stock': '12535460', 'tested_source_hours': moved,
        'overlay_count': len(candidates), 'audit_count': len(candidates), 'completed_source_rejected': True,
        'forbidden_tables_unchanged': True,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    load_local_env()
    dsn = os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL')
    if not dsn:
        raise RuntimeError('staging database URL is unavailable')
    assert_staging_target(database_url=dsn)
    source = MIGRATION.read_text(encoding='utf-8')
    source_150 = MIGRATION_150.read_text(encoding='utf-8')
    digest = hashlib.sha256(source.encode()).hexdigest()
    digest_150 = hashlib.sha256(source_150.encode()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise RuntimeError(f'migration SHA-256 mismatch: {digest}')
    if digest_150 != EXPECTED_SHA256_150:
        raise RuntimeError(f'migration 150 SHA-256 mismatch: {digest_150}')

    conn = psycopg2.connect(dsn)
    try:
        with conn.cursor() as cur:
            before = durable_counts(cur)
            applied_149 = scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='149' and name='move_source_lines_between_workshop_stations')")
            applied_150 = scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='150' and name='lock_source_and_target_completion_for_station_moves')")
            if not applied_149:
                cur.execute(transaction_body(source))
            if not applied_150:
                cur.execute(transaction_body(source_150))
            verify_structure(cur)
            behavior = verify_behavior(cur)
        conn.rollback()
        with conn.cursor() as cur:
            if durable_counts(cur) != before:
                raise RuntimeError('rehearsal rollback leaked durable state')
            durable_149 = scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='149' and name='move_source_lines_between_workshop_stations')")
            durable_150 = scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='150' and name='lock_source_and_target_completion_for_station_moves')")
            if durable_149 != applied_149 or durable_150 != applied_150:
                raise RuntimeError('rehearsal changed durable migration ledger state')
        if args.apply and not (applied_149 and applied_150):
            with conn.cursor() as cur:
                if not applied_149:
                    cur.execute(transaction_body(source))
                if not applied_150:
                    cur.execute(transaction_body(source_150))
                verify_structure(cur)
            conn.commit()
            with conn.cursor() as cur:
                verify_structure(cur)
            mode = 'applied'
        elif applied_149 and applied_150:
            mode = 'already_applied_verified'
        else:
            mode = 'rehearsal'
        print(json.dumps({'ok': True, 'migrations': ['149','150'], 'mode': mode, 'sha256': {'149': digest, '150': digest_150}, 'behavior': behavior, 'rollback_verified': True}, sort_keys=True))
    finally:
        conn.rollback()
        conn.close()


if __name__ == '__main__':
    main()
