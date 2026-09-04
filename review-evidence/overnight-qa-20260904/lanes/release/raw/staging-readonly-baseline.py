from __future__ import annotations

import ctypes
from ctypes import wintypes
import json
from urllib.request import Request, urlopen

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
TARGET = "[REDACTED_UUID_d8ff3d1b0e]"
ACTOR_ID = "[REDACTED_UUID_1a4cb3c4c8]"
ACTOR_EMAIL = "[REDACTED_EMAIL]"
CREDENTIAL_TARGET = "Supabase CLI:supabase"


class CREDENTIALW(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD), ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR), ("Comment", wintypes.LPWSTR),
        ("LastWritten", wintypes.FILETIME), ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD), ("AttributeCount", wintypes.DWORD),
        ("Attributes", ctypes.c_void_p), ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


def access_token() -> str:
    pointer = ctypes.POINTER(CREDENTIALW)()
    api = ctypes.WinDLL("Advapi32.dll")
    api.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(CREDENTIALW))]
    api.CredReadW.restype = wintypes.BOOL
    api.CredFree.argtypes = [ctypes.c_void_p]
    if not api.CredReadW(CREDENTIAL_TARGET, 1, 0, ctypes.byref(pointer)):
        raise ctypes.WinError()
    try:
        value = pointer.contents
        return ctypes.string_at(value.CredentialBlob, value.CredentialBlobSize).decode("utf-8").strip("\x00")
    finally:
        api.CredFree(pointer)


def request_json(url: str, *, data: dict | None = None):
    body = None if data is None else json.dumps(data, separators=(",", ":")).encode()
    request = Request(url, data=body, method="GET" if body is None else "POST", headers={
        "Authorization": f"Bearer {access_token()}",
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "PDC-release-baseline/1.0",
    })
    with urlopen(request, timeout=90) as response:
        payload = response.read().decode()
    return json.loads(payload) if payload else []


def query(sql: str, *, read_only: bool = True):
    return request_json(
        f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query",
        data={"query": sql, "read_only": read_only},
    )


def advisor(kind: str):
    payload = request_json(f"https://api.supabase.com/v1/projects/{STAGING_REF}/advisors/{kind}?lint_type=sql")
    lints = payload.get("lints", []) if isinstance(payload, dict) else []
    levels: dict[str, int] = {}
    names: dict[str, int] = {}
    scoped = []
    for lint in lints:
        level = str(lint.get("level") or "UNKNOWN").upper()
        name = str(lint.get("name") or "UNKNOWN")
        levels[level] = levels.get(level, 0) + 1
        names[name] = names.get(name, 0) + 1
        encoded = json.dumps(lint, default=str).lower()
        if any(token in encoded for token in ("pdc14", "provenance_history", "lifecycle_history_82000", "u158318")):
            scoped.append({key: lint.get(key) for key in ("name", "level", "cache_key", "detail", "description") if key in lint})
    return {"total": len(lints), "levels": levels, "names": names, "release_scoped": scoped}


def claims_sql(sub: str | None, email: str = "") -> str:
    claims = {} if sub is None else {"sub": sub, "email": email, "role": "authenticated"}
    encoded = json.dumps(claims, separators=(",", ":")).replace("'", "''")
    return f"select set_config('request.jwt.claims','{encoded}',true);"


def call_rpc(sub: str | None, email: str, target: str = TARGET):
    rows = query(
        "begin;" + claims_sql(sub, email) + "set local role authenticated;"
        + f"select public.get_pdc_vehicle_provenance_history('{target}'::uuid) result;rollback;",
        read_only=False,
    )
    return next(row["result"] for row in rows if "result" in row)


def fixture(where: str):
    row = query(
        "select coalesce(auth_user_id::text,'[REDACTED_UUID_993224b4fe]') sub, lower(email) email "
        f"from public.pdc_user_roles where {where} order by id limit 1"
    )[0]
    return row["sub"], row["email"]


def compact_result(value):
    return {
        "ok": value.get("ok"), "code": value.get("code"),
        "has_data": "data" in value,
        "vehicle_id": value.get("data", {}).get("vehicle", {}).get("vehicle_id"),
    }


def main():
    before = query(
        f"select jsonb_build_object('vehicle',to_jsonb(v),'fingerprint',md5(to_jsonb(v)::text)) result "
        f"from public.vehicles v where id='{TARGET}'::uuid"
    )[0]["result"]
    inactive = fixture("not active and account_status='disabled'")
    pending = fixture("account_status='pending'")
    denied = fixture(
        "active and account_status='approved' and exists (select 1 from public.pdc_auditor_user_dealer_scopes s "
        "where s.auth_user_id=pdc_user_roles.auth_user_id and s.normalized_email=lower(pdc_user_roles.email) "
        "and s.environment='staging' and s.active and s.dealer_code='14450')"
    )
    matrix = {
        "no_approved_role": compact_result(call_rpc("[REDACTED_UUID_e79acd97ac]", "[REDACTED_EMAIL]")),
        "inactive_role": compact_result(call_rpc(*inactive)),
        "pending_role": compact_result(call_rpc(*pending)),
        "uuid_email_mismatch": compact_result(call_rpc(ACTOR_ID, "[REDACTED_EMAIL]")),
        "denied_dealer_scope": compact_result(call_rpc(*denied)),
        "unauthenticated": compact_result(call_rpc(None, "")),
        "invalid_target": compact_result(call_rpc(ACTOR_ID, ACTOR_EMAIL, "[REDACTED_UUID_11e594f481]")),
        "authorized_target": compact_result(call_rpc(ACTOR_ID, ACTOR_EMAIL)),
    }
    catalog = query("""
      select jsonb_build_object(
        'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'migration_head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'rpc',(
          select jsonb_build_object('security_definer',p.prosecdef,'config',p.proconfig,
            'authenticated_execute',has_function_privilege('authenticated',p.oid,'execute'),
            'anon_execute',has_function_privilege('anon',p.oid,'execute'),
            'service_role_execute',has_function_privilege('service_role',p.oid,'execute'))
          from pg_proc p where p.oid='public.get_pdc_vehicle_provenance_history(uuid)'::regprocedure),
        'obsolete_two_arg_exists',to_regprocedure('public.get_pdc_vehicle_provenance_history(uuid,text)') is not null,
        'history_table',(
          select jsonb_build_object('rls',relrowsecurity,'force_rls',relforcerowsecurity,
            'authenticated_select',has_table_privilege('authenticated',c.oid,'select'),
            'anon_select',has_table_privilege('anon',c.oid,'select'))
          from pg_class c where c.oid='public.pdc_vehicle_lifecycle_history_events_82000'::regclass),
        'public_security_definer_count',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef),
        'public_security_definer_without_fixed_search_path',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and not coalesce(p.proconfig,'{}')::text[] && array['search_path=pg_catalog, public','search_path=pg_catalog,public','search_path=public, pg_catalog','search_path=public,pg_catalog','search_path='])
      ) result
    """)[0]["result"]
    exposure = query("""
      select jsonb_build_object(
        'public_tables',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p')),
        'public_tables_rls_disabled',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p') and not c.relrowsecurity),
        'rls_disabled_with_anon_or_authenticated_privilege',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p') and not c.relrowsecurity and (has_table_privilege('anon',c.oid,'select') or has_table_privilege('authenticated',c.oid,'select'))),
        'default_acl_rows',(select coalesce(jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(defaclrole),'object_type',defaclobjtype,'acl',defaclacl)),'[]'::jsonb) from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace where n.nspname='public' or d.defaclnamespace=0)
      ) result
    """)[0]["result"]
    after = query(
        f"select jsonb_build_object('vehicle',to_jsonb(v),'fingerprint',md5(to_jsonb(v)::text)) result "
        f"from public.vehicles v where id='{TARGET}'::uuid"
    )[0]["result"]
    u158318 = query(f"""
      select jsonb_build_object(
        'operation_count',(select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='{TARGET}'::uuid),
        'estimated_hours',(select coalesce(sum(estimated_hours),0) from public.pdc_authenticated_email_operation_lines where vehicle_id='{TARGET}'::uuid),
        'zero_hour_lines',(select coalesce(jsonb_agg(operation_no order by source_row_no),'[]'::jsonb) from public.pdc_authenticated_email_operation_lines where vehicle_id='{TARGET}'::uuid and estimated_hours=0),
        'required_work_count',(select count(*) from public.vehicle_work_items where vehicle_id='{TARGET}'::uuid and required),
        'completed_work_count',(select count(*) from public.vehicle_work_items where vehicle_id='{TARGET}'::uuid and completed),
        'workshop_booking_count',(select count(*) from public.workshop_bookings where vehicle_id='{TARGET}'::uuid)
      ) result
    """)[0]["result"]
    result = {
        "task_id": "t_95939b14", "environment": "STAGING", "project_ref": STAGING_REF,
        "production_ref_contacted": False, "email_contacted": False,
        "persistent_mutation_queries": False,
        "transactional_rpc_probes_rolled_back": True,
        "authorization_matrix": matrix,
        "denied_cases_have_no_data": all(not value["has_data"] for key, value in matrix.items() if key != "authorized_target"),
        "catalog": catalog, "data_api_exposure_review": exposure,
        "u158318_fresh": u158318,
        "target_before": before, "target_after": after,
        "target_unchanged": before["fingerprint"] == after["fingerprint"],
        "advisors": {"security": advisor("security"), "performance": advisor("performance")},
    }
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
