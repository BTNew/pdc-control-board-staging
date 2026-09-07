#!/usr/bin/env python3
"""Deploy and execute the preview-first Pilbara Service importer on STAGING."""
from __future__ import annotations

import argparse
import json
import os
import uuid
from pathlib import Path
from typing import Any

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, management_query
from pilbara_service_open_jobcards import (
    EXPECTED_SOURCE_HASH,
    IMPORTER_VERSION,
    build_database_payload,
    parse_source,
)

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260907100000_pilbara_service_open_jobcards_v1.sql"
EVIDENCE = ROOT / "review-evidence/t_5523f3fd/pilbara-service-import-evidence.json"
SOURCE = Path(r"C:/Users/nwmgr/AppData/Local/hermes/cache/documents/doc_e55993a9ad5a_BT Service.csv")
PREDECESSOR = ["20260907090000", "navision_complete_vin_gate"]
TARGET = ["20260907100000", "pilbara_service_open_jobcards_v1"]
APPROVE_MIGRATION = "PDC_APPROVE_STAGING_MIGRATION_20260907100000"
APPROVE_PREVIEW = "PDC_APPROVE_PILBARA_SERVICE_PREVIEW"


def _literal(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).replace("'", "''")


def inspect() -> dict[str, Any]:
    proof = management_query("""
select jsonb_build_object(
 'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
 'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
 'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
 'contract_installed',to_regprocedure('public.pdc_pilbara_service_preview_v1(jsonb,text,text)') is not null,
 'activation_count',(select count(*) from public.navision_board_activations where active),
 'notification_count',(select count(*) from public.vehicle_notifications)
) proof
""")[0]["proof"]
    if proof["contract_installed"]:
        counts = management_query("""select
          count(*) filter(where batch_kind='preview') preview_batches,
          count(*) filter(where batch_kind='apply') apply_batches,
          (select count(*) from public.pdc_pilbara_service_operations where importer_version='pilbara_service_open_jobcards_v1') operation_count
          from public.pdc_pilbara_service_import_batches where importer_version='pilbara_service_open_jobcards_v1'""")[0]
        proof.update(counts)
    else:
        proof.update({"preview_batches": 0, "apply_batches": 0, "operation_count": 0})
    return proof


def forbidden_snapshot() -> list[dict[str, Any]]:
    parsed = parse_source(SOURCE)
    stock_json = _literal(sorted({row["stock_number"] for row in parsed.accepted}))
    return management_query(f"""
with requested as (select value stock_number from jsonb_array_elements_text('{stock_json}'::jsonb))
select v.id::text vehicle_id,
 encode(extensions.digest(convert_to(jsonb_build_object(
  'customer_name',v.customer_name,'vin',v.vin,'eta_to_kewdale',v.eta_to_kewdale,'current_location',v.current_location,
  'registration',v.registration,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
  'lifecycle_state',v.lifecycle_state,'visible_on_board',v.visible_on_board,'workshop_status',v.workshop_status,
  'active_workshop_booking_id',v.active_workshop_booking_id,'qc_completed_at',v.qc_completed_at,
  'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,
  'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
  'sales_build_complete',v.sales_build_complete,'sales_tray_complete',v.sales_tray_complete
 )::text,'UTF8'),'sha256'),'hex') forbidden_state_hash
from requested r join public.vehicles v on v.deleted_at is null and btrim(v.stock_number)=btrim(r.stock_number)
order by v.id
""")


def preview_readback(preview_batch_id: str) -> dict[str, Any]:
    batch_id = str(uuid.UUID(preview_batch_id))
    return management_query(f"""
select jsonb_build_object(
 'batch',(select jsonb_build_object('batch_id',batch_id,'source_hash',source_hash,'source_row_count',source_row_count,
   'accepted_line_count',accepted_line_count,'quarantined_line_count',quarantined_line_count,
   'matched_stock_count',matched_stock_count,'unmatched_stock_count',unmatched_stock_count,
   'ambiguous_stock_count',ambiguous_stock_count,'insert_count',insert_count,'update_count',update_count,
   'unchanged_count',unchanged_count,'conflict_count',conflict_count,'response',response)
   from public.pdc_pilbara_service_import_batches where batch_id='{batch_id}'::uuid),
 'row_reconciliation',(select jsonb_build_object('total',sum(n),'decisions',jsonb_object_agg(decision,n)) from (
   select decision,count(*) n from public.pdc_pilbara_service_import_rows where batch_id='{batch_id}'::uuid group by decision) q),
 'reason_counts',(select jsonb_object_agg(reason,n) from (select reason,count(*) n from public.pdc_pilbara_service_import_rows
   where batch_id='{batch_id}'::uuid group by reason) q),
 'raw_rows_retained',(select count(*) from public.pdc_pilbara_service_import_rows where batch_id='{batch_id}'::uuid and jsonb_typeof(raw_row)='object'),
 'status_desc_normalized_count',(select count(*) from public.pdc_pilbara_service_import_rows where batch_id='{batch_id}'::uuid and normalized_payload ?| array['Status Desc','status_desc','status']),
 'receipt_count',(select count(*) from public.pdc_pilbara_service_import_receipts where importer_version='pilbara_service_open_jobcards_v1'),
 'operation_count',(select count(*) from public.pdc_pilbara_service_operations where importer_version='pilbara_service_open_jobcards_v1'),
 'rls',(select jsonb_object_agg(relname,jsonb_build_array(relrowsecurity,relforcerowsecurity)) from pg_class where oid in (
   'public.pdc_pilbara_service_import_batches'::regclass,'public.pdc_pilbara_service_import_rows'::regclass,
   'public.pdc_pilbara_service_operations'::regclass,'public.pdc_pilbara_service_operation_history'::regclass,
   'public.pdc_pilbara_service_import_receipts'::regclass)),
 'function_acl',jsonb_build_object(
   'preview_public',has_function_privilege('public','public.pdc_pilbara_service_preview_v1(jsonb,text,text)','execute'),
   'preview_anon',has_function_privilege('anon','public.pdc_pilbara_service_preview_v1(jsonb,text,text)','execute'),
   'preview_authenticated',has_function_privilege('authenticated','public.pdc_pilbara_service_preview_v1(jsonb,text,text)','execute'),
   'preview_service_role',has_function_privilege('service_role','public.pdc_pilbara_service_preview_v1(jsonb,text,text)','execute'),
   'apply_public',has_function_privilege('public','public.pdc_pilbara_service_apply_v1(uuid,text,text)','execute'),
   'apply_anon',has_function_privilege('anon','public.pdc_pilbara_service_apply_v1(uuid,text,text)','execute'),
   'apply_authenticated',has_function_privilege('authenticated','public.pdc_pilbara_service_apply_v1(uuid,text,text)','execute'),
   'apply_service_role',has_function_privilege('service_role','public.pdc_pilbara_service_apply_v1(uuid,text,text)','execute'))
) proof
""")[0]["proof"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inspect", "dry-run", "apply-migration", "record-preview"))
    args = parser.parse_args()
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("refusing non-STAGING target")
    before = inspect()
    if before["project_ref"] != STAGING_REF or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel failed")
    result: dict[str, Any] = {"ok": True, "mode": args.mode, "project_ref": STAGING_REF, "before": before,
                              "containment": {"management_project_ref": STAGING_REF,
                                              "staging_sentinel_verified": True,
                                              "production_contacted": False,
                                              "production_contact_policy": "forbidden"}}
    if args.mode == "dry-run":
        if before["head"] != PREDECESSOR:
            raise RuntimeError(f"dry-run requires predecessor head: {before['head']}")
        sql = MIGRATION.read_text(encoding="utf-8")
        management_write(sql.rsplit("COMMIT;", 1)[0] + "ROLLBACK;")
        after = inspect()
        if after != before:
            raise RuntimeError("dry-run changed STAGING state")
        result.update({"after": after, "compiled_and_rolled_back": True})
    elif args.mode == "apply-migration":
        if os.environ.get(APPROVE_MIGRATION) != "YES":
            raise RuntimeError(f"set {APPROVE_MIGRATION}=YES")
        if before["head"] == PREDECESSOR:
            management_write(MIGRATION.read_text(encoding="utf-8"))
        after = inspect()
        if after["head"] != TARGET or not after["contract_installed"]:
            raise RuntimeError(f"migration readback failed: {after}")
        result.update({"after": after, "security_advisors": security_advisor_summary()})
    elif args.mode == "record-preview":
        if os.environ.get(APPROVE_PREVIEW) != "YES":
            raise RuntimeError(f"set {APPROVE_PREVIEW}=YES")
        if before["head"] != TARGET or not before["contract_installed"]:
            raise RuntimeError("preview contract is not deployed")
        parsed = parse_source(SOURCE, EXPECTED_SOURCE_HASH)
        payload = build_database_payload(parsed)
        before_forbidden = forbidden_snapshot()
        payload_literal = _literal(payload)
        response = management_write(
            f"select public.pdc_pilbara_service_preview_v1('{payload_literal}'::jsonb,'{parsed.source_hash}',"
            f"'pilbara-service-preview-{parsed.source_hash[:32]}') result"
        )[0]["result"]
        if response.get("ok") is not True or response.get("code") not in {"preview_created", "preview_replay"} or not response.get("preview_batch_id"):
            raise RuntimeError(f"preview RPC failed closed: {response}")
        readback = preview_readback(response["preview_batch_id"])
        after_forbidden = forbidden_snapshot()
        after = inspect()
        if before_forbidden != after_forbidden:
            raise RuntimeError("preview changed forbidden vehicle state")
        for field in ("apply_batches", "operation_count", "activation_count", "notification_count"):
            if after[field] != before[field]:
                raise RuntimeError(f"preview changed protected count {field}: {before[field]} -> {after[field]}")
        expected = {"matched_stocks": 21, "matched_lines": 122, "unmatched_stocks": 16,
                    "unmatched_lines": 39, "ambiguous_stocks": 0, "conflict_lines": 0,
                    "quarantine_lines": 40}
        actual = {"matched_stocks": response["matched"]["stocks"], "matched_lines": response["matched"]["lines"],
                  "unmatched_stocks": response["unmatched"]["stocks"], "unmatched_lines": response["unmatched"]["lines"],
                  "ambiguous_stocks": response["ambiguous"]["stocks"],
                  "conflict_lines": response["operations"]["conflict"],
                  "quarantine_lines": response["operations"]["quarantine"]}
        if actual != expected or response.get("apply_allowed") is not True:
            raise RuntimeError(f"preview no longer matches approved partial-batch decision: {actual}")
        if readback["row_reconciliation"]["total"] != 162 or readback["raw_rows_retained"] != 162:
            raise RuntimeError(f"preview reconciliation failed: {readback}")
        result.update({"preview": response, "readback": readback, "after": after,
                       "forbidden_vehicle_snapshots": len(before_forbidden),
                       "forbidden_vehicle_state_changes": 0, "apply_executed": False,
                       "evidence_path": str(EVIDENCE)})
        EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
        EVIDENCE.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
    else:
        result["after"] = before
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
