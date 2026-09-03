from __future__ import annotations

import ctypes
from ctypes import wintypes
import json
from urllib.error import HTTPError
from urllib.request import Request, urlopen

STAGING_REF = 'cdsmnqxtyyoeoznmbidd'
TARGET_EMAIL = 'functional@pdc.online'
CREDENTIAL_TARGET = 'Supabase CLI:supabase'


class CREDENTIALW(ctypes.Structure):
    _fields_ = [
        ('Flags', wintypes.DWORD), ('Type', wintypes.DWORD), ('TargetName', wintypes.LPWSTR),
        ('Comment', wintypes.LPWSTR), ('LastWritten', wintypes.FILETIME), ('CredentialBlobSize', wintypes.DWORD),
        ('CredentialBlob', ctypes.POINTER(ctypes.c_ubyte)), ('Persist', wintypes.DWORD),
        ('AttributeCount', wintypes.DWORD), ('Attributes', ctypes.c_void_p), ('TargetAlias', wintypes.LPWSTR),
        ('UserName', wintypes.LPWSTR),
    ]


def supabase_access_token() -> str:
    pointer = ctypes.POINTER(CREDENTIALW)()
    advapi32 = ctypes.WinDLL('Advapi32.dll')
    advapi32.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(CREDENTIALW))]
    advapi32.CredReadW.restype = wintypes.BOOL
    advapi32.CredFree.argtypes = [ctypes.c_void_p]
    if not advapi32.CredReadW(CREDENTIAL_TARGET, 1, 0, ctypes.byref(pointer)):
        raise ctypes.WinError()
    try:
        credential = pointer.contents
        blob = ctypes.string_at(credential.CredentialBlob, credential.CredentialBlobSize)
        token = blob.decode('utf-8').strip('\x00')
        if not token:
            raise RuntimeError('empty Supabase CLI credential')
        return token
    finally:
        advapi32.CredFree(pointer)


def management_query(sql: str):
    payload = json.dumps({'query': sql, 'read_only': True}).encode('utf-8')
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
        with urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode('utf-8'))
    except HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'Supabase management query failed ({error.code}): {detail}') from error


def main():
    sql = f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'columns',(select jsonb_agg(jsonb_build_array(column_name,data_type,udt_name,is_nullable,column_default) order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='pdc_user_roles'),
        'target_rows',(select coalesce(jsonb_agg(jsonb_build_array(id::text,email,full_name,display_name,role,active,account_status,auth_user_id::text)),'[]'::jsonb) from public.pdc_user_roles where lower(email)='{TARGET_EMAIL}'),
        'auth_users',(select coalesce(jsonb_agg(jsonb_build_array(id::text,email,created_at,last_sign_in_at,raw_user_meta_data)),'[]'::jsonb) from auth.users where lower(email)='{TARGET_EMAIL}'),
        'role_enum',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='pdc_app_role'),
        'status_enum',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='pdc_account_status'),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',(select to_regclass('public.pdc_production_environment_sentinel') is not null)
      ) as inspection
    """
    result = management_query(sql)
    print(json.dumps({
        'ok': True,
        'environment': 'staging',
        'project_ref': STAGING_REF,
        'inspection': result,
        'production_contacted': False,
    }, indent=2, default=str))


if __name__ == '__main__':
    main()
