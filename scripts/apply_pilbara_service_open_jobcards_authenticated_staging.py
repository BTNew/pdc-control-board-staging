#!/usr/bin/env python3
"""Apply the approved Pilbara Service preview through an authenticated STAGING RPC."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from inspect_pdc14_staging import STAGING_REF, supabase_access_token
from pilbara_service_open_jobcards import EXPECTED_SOURCE_HASH, IMPORTER_VERSION

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "review-evidence/t_5523f3fd/pilbara-service-apply-evidence.json"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_HOST = "cdsmnqxtyyoeoznmbidd.supabase.co"
MANAGEMENT_HOST = "api.supabase.com"
EXPECTED_MIGRATION_HEAD = ["20260907107000", "pilbara_service_null_safe_head_guard"]
APPROVAL = "PDC_APPROVE_PILBARA_SERVICE_APPLY"
PREVIEW_BATCH_ID = "05d4f8f2-d1c1-430f-8474-b16a2b08b258"
APPLY_IDEMPOTENCY_KEY = f"pilbara-service-apply-{EXPECTED_SOURCE_HASH[:32]}"
EXPECTED_POST_APPLY = {
    "matched_active_vehicle_count": 21,
    "operation_count": 122,
    "unmatched_vehicle_count": 0,
}
MATCHED_STOCKS = [
    "13086233", "13086232", "13086229", "13075150", "13064619", "13061263", "13056938",
    "13056890", "13056889", "13047111", "13040515", "13029548", "13029390", "13021036",
    "13019169", "13015144", "13007660", "13000714", "12715989", "12705303", "12705177",
]
UNMATCHED_STOCKS = [
    "13028624", "13022407", "13011180", "13000914", "12716598", "12716594", "12715919",
    "12714889", "12682620", "12675070", "12660176", "12660174", "12659321", "12658235",
    "12657856", "12657854",
]


def _load_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_pilbara_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("STAGING bootstrap unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(values)
    return values


def _value(values: dict[str, str], *names: str) -> str:
    for name in names:
        value = str(values.get(name, "")).strip()
        if value:
            return value
    raise RuntimeError(f"required STAGING setting unavailable: {names[0]}")


def _validate_staging_origin(url: str) -> urllib.parse.SplitResult:
    parsed = urllib.parse.urlsplit(url)
    try:
        port = parsed.port
    except ValueError as error:
        raise RuntimeError("non-STAGING authentication target refused") from error
    if (
        parsed.scheme != "https"
        or parsed.hostname != STAGING_HOST
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
    ):
        raise RuntimeError("non-STAGING authentication target refused")
    return parsed


def _validated_staging_base(url: str) -> str:
    parsed = _validate_staging_origin(url)
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise RuntimeError("non-STAGING authentication target refused")
    return f"https://{STAGING_HOST}"


class _StagingRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self, req: urllib.request.Request, fp: Any, code: int, msg: str,
        headers: Any, newurl: str,
    ) -> urllib.request.Request | None:
        _validate_staging_origin(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _validate_management_origin(url: str) -> urllib.parse.SplitResult:
    parsed = urllib.parse.urlsplit(url)
    try:
        port = parsed.port
    except ValueError as error:
        raise RuntimeError("non-Supabase management target refused") from error
    if (
        parsed.scheme != "https"
        or parsed.hostname != MANAGEMENT_HOST
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
    ):
        raise RuntimeError("non-Supabase management target refused")
    return parsed


class _ManagementRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self, req: urllib.request.Request, fp: Any, code: int, msg: str,
        headers: Any, newurl: str,
    ) -> urllib.request.Request | None:
        _validate_management_origin(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _management_query(sql: str) -> Any:
    url = f"https://{MANAGEMENT_HOST}/v1/projects/{STAGING_REF}/database/query"
    _validate_management_origin(url)
    request = urllib.request.Request(
        url,
        data=json.dumps({"query": sql, "read_only": True}, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {supabase_access_token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "SupabaseCLI/2.75.0",
        },
    )
    opener = urllib.request.build_opener(_ManagementRedirectHandler())
    try:
        with opener.open(request, timeout=30) as response:
            _validate_management_origin(response.geturl())
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Supabase STAGING read-back failed ({error.code}): {detail}") from error


def _post(url: str, headers: dict[str, str], payload: dict[str, Any]) -> tuple[int, Any]:
    _validate_staging_origin(url)
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    opener = urllib.request.build_opener(_StagingRedirectHandler())
    try:
        with opener.open(request, timeout=90) as response:
            _validate_staging_origin(response.geturl())
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        try:
            parsed: Any = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"error": body[:500]}
        return error.code, parsed


def _authenticate(values: dict[str, str]) -> tuple[str, dict[str, str]]:
    base = _validated_staging_base(_value(values, "PDC_STAGING_SUPABASE_URL"))
    anon = _value(values, "PDC_STAGING_SUPABASE_ANON_KEY", "PDC_STAGING_ANON_KEY")
    email = _value(values, "PDC_EMAIL_AI_RUNTIME_EMAIL")
    password = _value(values, "PDC_EMAIL_AI_RUNTIME_PASSWORD")
    status, body = _post(
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
        {"email": email, "password": password},
    )
    token = body.get("access_token") if isinstance(body, dict) else None
    if status != 200 or not token:
        raise RuntimeError(f"authenticated STAGING login failed: HTTP {status}")
    return base, {"apikey": anon, "Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def _stocks_literal(stocks: list[str]) -> str:
    return json.dumps(stocks, separators=(",", ":")).replace("'", "''")


def _snapshot() -> dict[str, Any]:
    matched = _stocks_literal(MATCHED_STOCKS)
    unmatched = _stocks_literal(UNMATCHED_STOCKS)
    return _management_query(f"""
select jsonb_build_object(
  'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations
          where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
  'notification_count',(select count(*) from public.vehicle_notifications),
  'notification_hash',(select encode(extensions.digest(convert_to(
    coalesce(jsonb_agg(to_jsonb(n) order by to_jsonb(n)::text),'[]'::jsonb)::text,
    'UTF8'),'sha256'),'hex') from public.vehicle_notifications n),
  'eligible_runtime_actor_count',(select count(*) from public.pdc_user_roles r
    where r.auth_user_id is not null and r.active and r.account_status='approved' and r.role='viewer'
      and exists(select 1 from public.pdc_email_ai_successor_runtime_identities i
        where i.auth_user_id=r.auth_user_id and i.normalized_email=lower(r.email)
          and i.environment='staging' and i.identity_purpose='pdc_email_ai_transaction_successor'
          and i.active and i.revoked_at is null)
      and exists(select 1 from public.pdc_monitor_stage_activation_writers w
        where w.user_id=r.auth_user_id and w.active and w.revoked_at is null)),
  'backend_authority_hash',(
    select encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object(
      'id',b.id,'source_system',b.source_system,'source_record_id',b.source_record_id,'dealer_code',b.dealer_code,
      'record_status',b.record_status,'is_current',b.is_current,'normalized_data',b.normalized_data,
      'row_hash',b.row_hash) order by b.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
    from public.navision_backend_records b
    where b.source_system='microsoft_navision' and b.is_current and b.record_status='current'
      and btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) in
          (select value from jsonb_array_elements_text('{matched}'::jsonb))),
  'matched_active_vehicle_count',(
    select count(distinct v.id) from public.navision_backend_records b join public.vehicles v on v.id=b.canonical_vehicle_id
    where b.source_system='microsoft_navision' and b.is_current and b.record_status='current' and b.dealer_code='37047'
      and v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
      and btrim(v.stock_number)=btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))
      and btrim(v.stock_number) in (select value from jsonb_array_elements_text('{matched}'::jsonb))),
  'unmatched_vehicle_count',(
    select count(*) from public.vehicles v where v.deleted_at is null
      and btrim(v.stock_number) in (select value from jsonb_array_elements_text('{unmatched}'::jsonb))),
  'operation_count',(select count(*) from public.pdc_pilbara_service_operations
                     where importer_version='{IMPORTER_VERSION}'),
  'operation_history_count',(select count(*) from public.pdc_pilbara_service_operation_history),
  'apply_batch_count',(select count(*) from public.pdc_pilbara_service_import_batches
                       where importer_version='{IMPORTER_VERSION}' and batch_kind='apply'),
  'receipt_count',(select count(*) from public.pdc_pilbara_service_import_receipts
                   where importer_version='{IMPORTER_VERSION}'),
  'backend_state_changes',(select count(*) from public.navision_backend_records b
    where b.source_system='microsoft_navision' and b.is_current and b.record_status='current'
      and btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) in
          (select value from jsonb_array_elements_text('{matched}'::jsonb))
      and (b.canonical_vehicle_id is null or not exists(select 1 from public.vehicles v
        where v.id=b.canonical_vehicle_id and v.deleted_at is null and btrim(v.stock_number)=btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))))),
  'status_desc_normalized_count',(select count(*) from public.pdc_pilbara_service_import_rows
    where normalized_payload ?| array['Status Desc','status_desc','status']),
  'reconciliation',(select jsonb_build_object(
    'preview_rows',(select count(*) from public.pdc_pilbara_service_import_rows where batch_id='{PREVIEW_BATCH_ID}'::uuid),
    'quarantined_lines',(select quarantined_line_count from public.pdc_pilbara_service_import_batches where batch_id='{PREVIEW_BATCH_ID}'::uuid),
    'accepted_operations',(select count(*) from public.pdc_pilbara_service_operations where importer_version='{IMPORTER_VERSION}'),
    'matched_stocks',(select count(distinct stock_number) from public.pdc_pilbara_service_operations where importer_version='{IMPORTER_VERSION}'),
    'matched_groups',(select count(distinct (stock_number,repair_order_number)) from public.pdc_pilbara_service_operations where importer_version='{IMPORTER_VERSION}'),
    'raw_operation_rows',(select count(*) from public.pdc_pilbara_service_operations o join public.pdc_pilbara_service_import_rows r on r.evidence_id=o.raw_evidence_id where jsonb_typeof(r.raw_row)='object'),
    'review_classification',(select count(*) from public.pdc_pilbara_service_operations where classification='Review'),
    'parts_yes',(select count(*) from public.pdc_pilbara_service_operations where parts_semantics='explicitly_backordered'),
    'parts_no',(select count(*) from public.pdc_pilbara_service_operations where parts_semantics='not_backordered'),
    'parts_review',(select count(*) from public.pdc_pilbara_service_operations where parts_semantics='review'),
    'pd_defaults',(select count(*) from public.pdc_pilbara_service_operations where hours_provenance='pre_delivery_default_1_5'),
    'non_pd_explicit_zero',(select count(*) from public.pdc_pilbara_service_operations where hours_provenance='source_explicit' and source_estimated_hours=0 and effective_estimated_hours=0)))
) proof
""")[0]["proof"]


def _apply(base: str, headers: dict[str, str]) -> tuple[int, Any]:
    return _post(
        f"{base}/rest/v1/rpc/pdc_pilbara_service_apply_v1",
        headers,
        {"p_preview_batch_id": PREVIEW_BATCH_ID, "p_source_hash": EXPECTED_SOURCE_HASH,
         "p_idempotency_key": APPLY_IDEMPOTENCY_KEY},
    )


def _validate_apply_snapshot(snapshot: dict[str, Any]) -> None:
    if snapshot.get("project_ref") != STAGING_REF or snapshot.get("production_sentinel_present"):
        raise RuntimeError("STAGING sentinel failed")
    if snapshot.get("head") != EXPECTED_MIGRATION_HEAD:
        raise RuntimeError(f"unexpected STAGING migration head: {snapshot.get('head')}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inspect", "apply-approved"))
    args = parser.parse_args()
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("STAGING project binding failed")
    before = _snapshot()
    if before["project_ref"] != STAGING_REF or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel failed")
    result: dict[str, Any] = {
        "ok": True, "mode": args.mode, "project_ref": STAGING_REF, "source_hash": EXPECTED_SOURCE_HASH,
        "importer_version": IMPORTER_VERSION, "before": before,
        "containment": {"staging_sentinel_verified": True},
    }
    if args.mode == "apply-approved":
        _validate_apply_snapshot(before)
        result["containment"]["migration_head_verified"] = True
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES")
        if not BOOTSTRAP.exists() or not SECRETS.exists():
            raise RuntimeError("authenticated REST bootstrap unavailable")
        base, headers = _authenticate(_load_values())
        result["containment"].update({
            "authenticated_rest_origin": base,
            "cross_origin_redirects_rejected": True,
        })
        status, apply_response = _apply(base, headers)
        if status != 200 or not isinstance(apply_response, dict) or apply_response.get("ok") is not True or apply_response.get("code") not in {"applied", "apply_replay"}:
            raise RuntimeError(f"apply RPC failed closed: HTTP {status}, response={apply_response}")
        after_apply = _snapshot()
        _validate_apply_snapshot(after_apply)
        replay_status, replay_response = _apply(base, headers)
        after_replay = _snapshot()
        _validate_apply_snapshot(after_replay)
        checks = {
            "apply_http_ok": status == 200,
            "apply_or_prior_replay": apply_response.get("code") in {"applied", "apply_replay"},
            "replay_http_ok": replay_status == 200,
            "replay_idempotent": isinstance(replay_response, dict) and replay_response.get("ok") is True and replay_response.get("code") == "apply_replay",
            "matched_active_vehicle_count": after_replay["matched_active_vehicle_count"] == EXPECTED_POST_APPLY["matched_active_vehicle_count"],
            "operation_count": after_replay["operation_count"] == EXPECTED_POST_APPLY["operation_count"],
            "unmatched_vehicle_count": after_replay["unmatched_vehicle_count"] == EXPECTED_POST_APPLY["unmatched_vehicle_count"],
            "operation_history_count": after_replay["operation_history_count"] == 122,
            "single_apply_batch": after_replay["apply_batch_count"] == 1,
            "backend_state_changes": after_replay["backend_state_changes"] == 0,
            "backend_authority_unchanged": before["backend_authority_hash"] == after_apply["backend_authority_hash"] == after_replay["backend_authority_hash"],
            "notification_queue_unchanged": (
                before["notification_count"] == after_apply["notification_count"] == after_replay["notification_count"]
                and before["notification_hash"] == after_apply["notification_hash"] == after_replay["notification_hash"]
            ),
            "status_desc_excluded": after_replay["status_desc_normalized_count"] == 0,
            "replay_did_not_duplicate": after_apply["operation_count"] == after_replay["operation_count"] and after_apply["operation_history_count"] == after_replay["operation_history_count"] and after_apply["apply_batch_count"] == after_replay["apply_batch_count"],
            "all_source_rows_reconciled": (
                after_replay["reconciliation"]["preview_rows"] == 162
                and after_replay["reconciliation"]["accepted_operations"] + after_replay["reconciliation"]["quarantined_lines"] == 162
                and after_replay["receipt_count"] == 4
                and after_replay["reconciliation"]["matched_stocks"] == 21
                and after_replay["reconciliation"]["matched_groups"] == 21
            ),
            "all_imported_rows_reviewable": after_replay["reconciliation"]["review_classification"] == 122 and after_replay["reconciliation"]["raw_operation_rows"] == 122,
        }
        if not all(checks.values()):
            raise RuntimeError(json.dumps({"checks": checks, "after_apply": after_apply, "after_replay": after_replay}, default=str))
        result["containment"]["notification_queue_unchanged"] = checks["notification_queue_unchanged"]
        result.update({"apply": apply_response, "replay": replay_response, "after_apply": after_apply,
                       "after_replay": after_replay, "checks": checks, "evidence_path": str(EVIDENCE)})
        EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
        EVIDENCE.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
    else:
        result["after"] = before
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}, indent=2))
        raise SystemExit(1)
