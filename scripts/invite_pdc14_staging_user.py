from __future__ import annotations

import json
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, TARGET_EMAIL, management_query, supabase_access_token

PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'


def request_json(url: str, *, method: str = 'GET', headers: dict[str, str] | None = None, payload: dict | None = None):
    body = None if payload is None else json.dumps(payload).encode('utf-8')
    request = Request(url, data=body, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=30) as response:
            raw = response.read().decode('utf-8')
            return json.loads(raw) if raw else None
    except HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'HTTP {error.code} from approved STAGING invitation path: {detail}') from error


def inspection() -> dict:
    sql = f"""
      select jsonb_build_object(
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',(select to_regclass('public.pdc_production_environment_sentinel') is not null),
        'auth_users',(select coalesce(jsonb_agg(jsonb_build_object('id',id::text,'email',email,'invited_at',invited_at,'created_at',created_at)),'[]'::jsonb) from auth.users where lower(email)='{TARGET_EMAIL}'),
        'role_rows',(select coalesce(jsonb_agg(jsonb_build_object('id',id::text,'email',email,'auth_user_id',auth_user_id::text,'role',role,'active',active,'account_status',account_status)),'[]'::jsonb) from public.pdc_user_roles where lower(email)='{TARGET_EMAIL}')
      ) as inspection
    """
    rows = management_query(sql)
    return rows[0]['inspection']


def assign_role_and_verify() -> tuple[dict, dict]:
    outcome_rows = management_write('select public.apply_pdc14_parts_coordinator_role() as outcome')
    outcome = outcome_rows[0]['outcome'] if outcome_rows else {}
    after = inspection()
    matching = after['role_rows']
    if len(matching) != 1:
        raise RuntimeError('exact Parts Coordinator role read-back failed')
    role = matching[0]
    if (str(role.get('role')) != 'operator' or role.get('active') is not True
            or str(role.get('account_status')) != 'approved'):
        raise RuntimeError('Parts Coordinator role was not approved as Operator')
    return outcome, after


def main() -> None:
    if STAGING_REF == PRODUCTION_REF:
        raise RuntimeError('refusing Production target')
    before = inspection()
    if before['staging_sentinel_count'] != 1 or before['production_sentinel_present']:
        raise RuntimeError('STAGING sentinel preflight failed')
    if before['auth_users']:
        assignment, after = assign_role_and_verify()
        print(json.dumps({
            'ok': True,
            'sent': False,
            'reason': 'user_already_exists',
            'project_ref': STAGING_REF,
            'assignment': assignment,
            'readback': after,
            'production_contacted': False,
        }, indent=2))
        return

    management_headers = {
        'Authorization': f'Bearer {supabase_access_token()}',
        'Accept': 'application/json',
        'User-Agent': 'SupabaseCLI/2.116.0',
    }
    keys = request_json(f'https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys', headers=management_headers)
    service_key = next((entry.get('api_key') for entry in keys or [] if entry.get('name') == 'service_role'), None)
    if not service_key:
        raise RuntimeError('STAGING service_role key was not available')

    invited = request_json(
        f'https://{STAGING_REF}.supabase.co/auth/v1/invite',
        method='POST',
        headers={
            'apikey': service_key,
            'Authorization': f'Bearer {service_key}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        },
        payload={'email': TARGET_EMAIL, 'data': {'display_name': 'Parts Coordinator'}},
    )
    assignment, after = assign_role_and_verify()
    matching = after['auth_users']
    if len(matching) != 1 or str(matching[0].get('email', '')).lower() != TARGET_EMAIL:
        raise RuntimeError('invitation returned but exact STAGING auth read-back failed')
    print(json.dumps({
        'ok': True,
        'sent': True,
        'project_ref': STAGING_REF,
        'assignment': assignment,
        'invited_user': {
            'id': invited.get('id'),
            'email': invited.get('email'),
            'aud': invited.get('aud'),
            'role': invited.get('role'),
        },
        'readback': after,
        'production_contacted': False,
    }, indent=2, default=str))


if __name__ == '__main__':
    main()
