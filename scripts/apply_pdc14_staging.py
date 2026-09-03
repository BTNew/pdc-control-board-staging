#!/usr/bin/env python3
"""Apply and verify the PDC-14 STAGING-only migrations."""
from __future__ import annotations

import json
import os
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from inspect_pdc14_staging import STAGING_REF, TARGET_EMAIL, supabase_access_token, management_query

ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
APPROVAL = 'PDC_APPROVE_STAGING_MIGRATION_20260903190000'
MIGRATIONS = [
    ROOT / 'supabase/staging_only/20260903150000_pdc14_parts_coordinator_role.sql',
    ROOT / 'supabase/staging_only/20260903160000_pdc14_canonical_controls.sql',
    ROOT / 'supabase/staging_only/20260903170000_pdc14_role_history_rls.sql',
    ROOT / 'supabase/staging_only/20260903180000_pdc14_location_review_hardening.sql',
    ROOT / 'supabase/staging_only/20260903190000_pdc14_role_replay_rollback_hardening.sql',
]


def management_write(sql: str):
    payload = json.dumps({'query': sql, 'read_only': False}).encode('utf-8')
    request = Request(
        f'https://api.supabase.com/v1/projects/{STAGING_REF}/database/query',
        data=payload,
        method='POST',
        headers={
            'Authorization': f'Bearer {supabase_access_token()}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'SupabaseCLI/2.75.0',
        },
    )
    try:
        with urlopen(request, timeout=90) as response:
            body = response.read().decode('utf-8')
            return json.loads(body) if body else []
    except HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'Supabase STAGING migration failed ({error.code}): {detail}') from error


def security_advisor_summary() -> dict[str, object]:
    request = Request(
        f'https://api.supabase.com/v1/projects/{STAGING_REF}/advisors/security?lint_type=sql',
        method='GET',
        headers={
            'Authorization': f'Bearer {supabase_access_token()}',
            'Accept': 'application/json',
            'User-Agent': 'SupabaseCLI/2.75.0',
        },
    )
    try:
        with urlopen(request, timeout=60) as response:
            payload = json.loads(response.read().decode('utf-8'))
    except HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'Supabase STAGING security-advisor read failed ({error.code}): {detail}') from error
    lints = payload.get('lints', []) if isinstance(payload, dict) else []
    levels: dict[str, int] = {}
    for lint in lints:
        level = str(lint.get('level') or 'UNKNOWN').upper()
        levels[level] = levels.get(level, 0) + 1
    pdc14 = [
        {
            'name': lint.get('name'),
            'level': lint.get('level'),
            'detail': lint.get('detail'),
        }
        for lint in lints
        if 'pdc14' in json.dumps(lint).lower()
    ]
    return {
        'total': len(lints),
        'levels': levels,
        'pdc14_findings': pdc14,
    }


def main() -> None:
    if os.environ.get(APPROVAL) != 'YES':
        raise RuntimeError(f'Set {APPROVAL}=YES for this reversible STAGING-only migration')
    applied_versions = {
        str(row['version'])
        for row in management_query(
            "select version from supabase_migrations.schema_migrations "
            "where version in ('20260903150000','20260903160000','20260903170000','20260903180000','20260903190000')"
        )
    }
    chunks = []
    for path in MIGRATIONS:
        sql = path.read_text(encoding='utf-8')
        if STAGING_REF not in sql or PRODUCTION_REF in sql:
            raise RuntimeError(f'PDC_14_NON_STAGING_MIGRATION:{path.name}')
        version = path.name.split('_', 1)[0]
        if version not in applied_versions:
            chunks.append(sql)
    head = management_query("select version from supabase_migrations.schema_migrations where version='20260903190000'")
    if chunks and not head:
        management_write('\n\n'.join(chunks))

    rows = management_write(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'standard_vin',public.is_valid_vehicle_vin('MR0BA3CD100000001'),
        'electric_hilux',public.is_valid_vehicle_vin('REBHV100551477'),
        'electric_hilux_upper_bound',public.is_valid_vehicle_vin('REBHV199999999'),
        'short_rejected',not public.is_valid_vehicle_vin('REBHV10055147'),
        'long_rejected',not public.is_valid_vehicle_vin('REBHV1005514777'),
        'wrong_prefix_rejected',not public.is_valid_vehicle_vin('REBXX100551477'),
        'body_builder_location',public.navision_operational_location(jsonb_build_object('navisionSubLocationDescription','Delivered - At Body Builder')),
        'location_rpc_exists',to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text)') is not null,
        'authenticated_can_execute',has_function_privilege('authenticated','public.set_pdc_vehicle_location_1500(uuid,integer,text)','execute'),
        'anon_cannot_execute',not has_function_privilege('anon','public.set_pdc_vehicle_location_1500(uuid,integer,text)','execute'),
        'role_apply_private',not has_function_privilege('authenticated','public.apply_pdc14_parts_coordinator_role()','execute'),
        'target_rows',(select coalesce(jsonb_agg(jsonb_build_object('email',email,'display_name',display_name,'role',role,'active',active,'account_status',account_status)),'[]'::jsonb) from public.pdc_user_roles where lower(email)='{TARGET_EMAIL}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
      ) as inspection
    """)[0]['inspection']
    checks = [
        rows['head'] == ['20260903190000', 'pdc14_role_replay_rollback_hardening'],
        rows['standard_vin'], rows['electric_hilux'], rows['electric_hilux_upper_bound'],
        rows['short_rejected'], rows['long_rejected'], rows['wrong_prefix_rejected'],
        rows['body_builder_location'] == 'PMB', rows['location_rpc_exists'],
        rows['authenticated_can_execute'], rows['anon_cannot_execute'], rows['role_apply_private'],
        not rows['production_sentinel_present'],
    ]
    if not all(checks):
        raise RuntimeError(f'PDC_14_STAGING_POSTCONDITION_FAILED:{rows}')
    print(json.dumps({
        'ok': True,
        'environment': 'staging',
        'project_ref': STAGING_REF,
        'inspection': rows,
        'security_advisors': security_advisor_summary(),
        'production_contacted': False,
        'production_writes': False,
    }, indent=2, default=str))


if __name__ == '__main__':
    main()
