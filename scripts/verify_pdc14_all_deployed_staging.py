#!/usr/bin/env python3
"""Current-head authenticated deployed PDC-14 browser verification (STAGING only)."""
from __future__ import annotations

import json
import secrets
import string
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import Page, sync_playwright

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

TASK = "t_8075c085"
EMAIL = "functional.pdc.staging@example.com"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
BASE = f"https://{STAGING_REF}.supabase.co"
URL = "https://btnew.github.io/pdc-control-board-staging/"
VEHICLE_ID = "67594974-0000-5000-8000-000000000014"
STOCK = "HERMES-PDC14-67594974"
IMPORT_RECEIPT_ID = "8075c085-0000-5000-8000-000000000001"
OPERATION_LINE_ID = "8075c085-0000-5000-8000-000000000002"
NAVISION_BATCH_ID = "8075c085-0000-5000-8000-000000000003"
NAVISION_RECORD_ID = "8075c085-0000-5000-8000-000000000004"
DEALER_SCOPE_ID = "8075c085-0000-5000-8000-000000000005"
ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "review-evidence" / TASK
OUT = OUT_DIR / "pdc14-deployed-authenticated.json"


def http_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: dict | None = None, allow_error: bool = False):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, data=body, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        if not allow_error:
            raise RuntimeError(f"HTTP {error.code}: {raw[:500]}") from error
        try:
            return error.code, json.loads(raw) if raw else None
        except json.JSONDecodeError:
            return error.code, {"error_present": bool(raw)}


def counts() -> dict[str, object]:
    return management_query(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),
        'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),
        'vehicle_count',(select count(*) from public.vehicles where id='{VEHICLE_ID}'::uuid),
        'work_count',(select count(*) from public.vehicle_work_items where vehicle_id='{VEHICLE_ID}'::uuid),
        'parts_count',(select count(*) from public.vehicle_parts_updates where vehicle_id='{VEHICLE_ID}'::uuid),
        'sublet_count',(select count(*) from public.pdc_sublet_bookings where vehicle_id='{VEHICLE_ID}'::uuid),
        'booking_count',(select count(*) from public.workshop_bookings where vehicle_id='{VEHICLE_ID}'::uuid),
        'operation_count',(select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='{VEHICLE_ID}'::uuid),
        'schedule_recovery_count',(select count(*) from public.workshop_schedule_recovery_receipts r where r.actor_user_id in (select id from auth.users where lower(email)='{EMAIL}')),
        'scope_count',(select count(*) from public.pdc_auditor_user_dealer_scopes where scope_id='{DEALER_SCOPE_ID}'::uuid),
        'navision_record_count',(select count(*) from public.navision_backend_records where id='{NAVISION_RECORD_ID}'::uuid),
        'navision_batch_count',(select count(*) from public.navision_import_batches where id='{NAVISION_BATCH_ID}'::uuid),
        'cleanup_history_count',(select count(*) from public.pdc14_location_replay_fixture_cleanup_history_20260904 where vehicle_id='{VEHICLE_ID}'::uuid),
        'receipt_count',(select count(*) from public.pdc_vehicle_location_receipts_20260904 where vehicle_id='{VEHICLE_ID}'::uuid)
      ) as result
    """)[0]["result"]


def fixture_readback() -> dict[str, object]:
    return management_query(f"""
      select jsonb_build_object(
        'vehicle',(select jsonb_build_object('id',id,'version',version,'stock',stock_number,'vin',vin,'jobcard',job_card_number,
          'client',customer_name,'location',current_location,'date_to_pmb',date_to_pmb,'eta',eta_to_kewdale,'payload',source_payload)
          from public.vehicles where id='{VEHICLE_ID}'::uuid),
        'work',(select coalesce(jsonb_object_agg(lower(work_key),jsonb_build_object('required',required,'completed',completed)),'{{}}'::jsonb)
          from public.vehicle_work_items where vehicle_id='{VEHICLE_ID}'::uuid),
        'parts',(select to_jsonb(p) from public.vehicle_parts_updates p where vehicle_id='{VEHICLE_ID}'::uuid order by updated_at desc,id desc limit 1),
        'sublet',(select to_jsonb(s) from public.pdc_sublet_bookings s where vehicle_id='{VEHICLE_ID}'::uuid),
        'operation',(select jsonb_build_object('id',operation_line_id,'work_key',work_key,'hours',estimated_hours,'source',estimated_hours_source)
          from public.pdc_authenticated_email_operation_lines where operation_line_id='{OPERATION_LINE_ID}'::uuid),
        'hours_receipts',(select coalesce(jsonb_agg(jsonb_build_object('id',receipt_id,'base_version',base_vehicle_version,'response',response)),'[]'::jsonb)
          from public.vehicle_workshop_hours_batch_receipts_768 where vehicle_id='{VEHICLE_ID}'::uuid),
        'location_receipts',(select count(*) from public.pdc_vehicle_location_receipts_20260904 where vehicle_id='{VEHICLE_ID}'::uuid),
        'audit_count',(select count(*) from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid)
      ) as result
    """)[0]["result"]


def create_fixture(user_id: str) -> None:
    work_keys = ["BUS4X4", "TINT", "HOIST", "FITTING", "FABRICATION", "ELECTRICAL", "TYRE", "PITINSPECTION", "SUBLET", "PARTS"]
    values = ",".join(f"('{VEHICLE_ID}'::uuid,'{key}',true,false)" for key in work_keys)
    management_write(f"""
      insert into public.vehicles(
        id,permanent_vehicle_id,stock_number,vin,job_card_number,customer_name,vehicle_description,
        lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,
        source_payload,version,created_by,updated_by,date_to_pmb,eta_to_kewdale
      ) values(
        '{VEHICLE_ID}'::uuid,'HERMES-PDC14-PERM-67594974','{STOCK}','REBHV100551477',
        'HERMES-JC-PDC14','PDC-14 Fixture','Electric HiLux PDC-14 deployed fixture',
        'active',true,'YH','microsoft_navision','14450','{NAVISION_RECORD_ID}',
        jsonb_build_object('bounded_fixture','{TASK}','verification_task','{TASK}','email_sent',false,
          'navision_record_id','{NAVISION_RECORD_ID}','navision_version','1','navision_status','Yard Hold',
          'navision_updated_at',transaction_timestamp(),'navisionLocationStatus','IT','navisionSubLocationDescription','Yard Hold'),
        1,'{user_id}'::uuid,'{user_id}'::uuid,current_date-3,current_date+2
      );
      insert into public.pdc_auditor_user_dealer_scopes(
        scope_id,auth_user_id,normalized_email,dealer_code,environment,active)
      values('{DEALER_SCOPE_ID}'::uuid,'{user_id}'::uuid,'{EMAIL}','14450','staging',true);
      insert into public.navision_import_batches(
        id,idempotency_key,request_hash,source_name,source_timestamp,source_hash,preview_hash,
        base_revision,result_revision,status,total_rows,receipt,actor_id,actor_email,source_system,dealer_code)
      values('{NAVISION_BATCH_ID}'::uuid,'{TASK}-bounded-navision-batch',repeat('4',64),'{TASK}',clock_timestamp(),
        repeat('3',64),repeat('2',64),1,1,'applied',1,
        '{{"bounded_fixture":"{TASK}","email_sent":false}}'::jsonb,'{user_id}'::uuid,'{EMAIL}','microsoft_navision','14450');
      insert into public.navision_backend_records(
        id,source_record_id,row_hash,normalized_data,raw_evidence,canonical_vehicle_id,
        first_seen_batch_id,last_seen_batch_id,updated_at,source_system,dealer_code,record_status)
      values('{NAVISION_RECORD_ID}'::uuid,'{TASK}-bounded-navision-record',repeat('1',64),
        '{{"batch":"{STOCK}","vin":"REBHV100551477","toyotaStatus":"Yard Hold","navisionLocationStatus":"IT","navisionSubLocationDescription":"Yard Hold"}}'::jsonb,
        '{{"bounded_fixture":"{TASK}","email_sent":false}}'::jsonb,'{VEHICLE_ID}'::uuid,
        '{NAVISION_BATCH_ID}'::uuid,'{NAVISION_BATCH_ID}'::uuid,transaction_timestamp(),'microsoft_navision','14450','current');
      insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values {values};
      insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by)
      values('{VEHICLE_ID}'::uuid,true,false,false,false,null,current_date+4,'{user_id}'::uuid);
      insert into public.pdc_sublet_bookings(vehicle_id,provider,provider_email,booking_date,expected_return_date,notes,email_sent,updated_by)
      values('{VEHICLE_ID}'::uuid,'HERMES Test Sublet','',current_date+1,current_date+2,'{TASK} bounded no-email fixture',false,'{user_id}'::uuid);
      insert into public.pdc_authenticated_email_import_receipts(
        receipt_id,actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,
        source_received_at,stock_number,vin,vehicle_id,identity_source,required_work,response)
      values('{IMPORT_RECEIPT_ID}'::uuid,'{user_id}'::uuid,'{TASK}-fixture-import',
        repeat('8',64),repeat('7',64),repeat('6',64),'{TASK}-fixture','no-email@invalid.example',clock_timestamp(),
        '{STOCK}','REBHV100551477','{VEHICLE_ID}'::uuid,'email_new',
        '["bus4x4","tint","hoist","fitting","fabrication","electrical","tyre","pitInspection","sublet","parts"]'::jsonb,
        '{{"ok":true,"code":"bounded_fixture","email_sent":false}}'::jsonb);
      insert into public.pdc_authenticated_email_operation_lines(
        operation_line_id,import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,
        operation_fingerprint,estimated_hours,estimated_hours_source,job_card_number,source_row_no,source_contract)
      select x.operation_line_id::uuid,'{IMPORT_RECEIPT_ID}'::uuid,'{VEHICLE_ID}'::uuid,repeat('7',64),'{TASK}-fixture',
        'OP'||x.ordinal,x.work_key,'PDC-14 bounded '||x.work_key||' operation',
        encode(extensions.digest(convert_to('{TASK}:'||x.work_key,'UTF8'),'sha256'),'hex'),
        x.estimated_hours,'job_card','HERMES-JC-PDC14',x.ordinal,'pmb-non-navision-jobcard-161'
      from (values
        ('8075c085-0000-5000-8000-000000000101',1,'bus4x4',2.5::numeric),
        ('8075c085-0000-5000-8000-000000000102',2,'tint',2.5::numeric),
        ('8075c085-0000-5000-8000-000000000103',3,'hoist',2.5::numeric),
        ('{OPERATION_LINE_ID}',4,'fitting',2.5::numeric),
        ('8075c085-0000-5000-8000-000000000105',5,'fabrication',2.5::numeric),
        ('8075c085-0000-5000-8000-000000000106',6,'electrical',2.5::numeric),
        ('8075c085-0000-5000-8000-000000000107',7,'tyre',2.5::numeric),
        ('8075c085-0000-5000-8000-000000000108',8,'sublet',2.5::numeric)
      ) as x(operation_line_id,ordinal,work_key,estimated_hours);
    """)


def create_workshop_bookings(user_id: str) -> None:
    stage_codes = ["BUS_4X4", "TINT", "HOIST", "FITTING", "FABRICATION", "ELECTRICAL", "TYRE"]
    values = []
    for index, code in enumerate(stage_codes, start=1):
        booking_id = f"8075c085-0000-5000-8000-{index:012d}"
        values.append(f"('{booking_id}'::uuid,'{code}',{index})")
    management_write(f"""
      with requested(booking_id,stage_code,offset_days) as (values {','.join(values)})
      insert into public.workshop_bookings(
        id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
        source,created_by,updated_by,metadata)
      select r.booking_id,'{VEHICLE_ID}'::uuid,s.id,
        (select b.id from public.workshop_bays b where b.stage_id=s.id and b.is_active order by b.bay_number limit 1),
        'queued',slot.scheduled_start,
        public.workshop_add_operational_minutes(slot.scheduled_start,duration.minutes),duration.minutes,
        'planner','{user_id}'::uuid,'{user_id}'::uuid,'{{"bounded_fixture":"{TASK}","email_sent":false}}'::jsonb
      from requested r
      join public.workshop_stages s on s.code=r.stage_code and s.active
      cross join lateral (
        select public.workshop_vehicle_stage_estimated_duration_minutes('{VEHICLE_ID}'::uuid,s.id) as minutes
      ) duration
      cross join lateral (
        select public.workshop_next_calendar_window(
          date_trunc('day',clock_timestamp())+(r.offset_days||' days')::interval+interval '8 hours',duration.minutes
        ) as scheduled_start
      ) slot;
    """)


def cleanup_fixture() -> dict[str, object]:
    """Archive exact fixture evidence, then remove its mutable rows."""
    management_write(f"""
      begin;
      do $guard$
      begin
        if (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}')<>1
           or to_regclass('public.pdc_production_environment_sentinel') is not null then
          raise exception 'PDC14_ALL_UI_WRONG_ENVIRONMENT';
        end if;
        if exists(select 1 from public.vehicles where id='{VEHICLE_ID}'::uuid and
          (permanent_vehicle_id<>'HERMES-PDC14-PERM-67594974' or stock_number<>'{STOCK}' or
           source_system<>'microsoft_navision' or source_batch_id<>'14450' or
           source_payload->>'bounded_fixture'<>'{TASK}')) then
          raise exception 'PDC14_ALL_UI_FIXTURE_PROVENANCE_MISMATCH';
        end if;
      end $guard$;
      insert into public.pdc14_location_replay_fixture_cleanup_history_20260904(
        vehicle_id,actor_id,actor_email,before_vehicle,lifecycle_history,movement_count,audit_count,
        retained_replay_receipt_count,cleanup_reason,production_writes)
      select v.id,v.created_by,'{EMAIL}',to_jsonb(v) || jsonb_build_object(
        '_bounded_verification_evidence',jsonb_build_object(
          'detail_edit_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.pdc_vehicle_detail_edit_receipts_388 r where r.vehicle_id=v.id),'[]'::jsonb),
          'detail_edit_history',coalesce((select jsonb_agg(to_jsonb(h)) from public.pdc_vehicle_detail_edit_history_388 h where h.vehicle_id=v.id),'[]'::jsonb),
          'hours_batch_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.vehicle_workshop_hours_batch_receipts_768 r where r.vehicle_id=v.id),'[]'::jsonb)
          ,'schedule_recovery_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.workshop_schedule_recovery_receipts r where r.actor_user_id=v.created_by),'[]'::jsonb)
          ,'parts_stoppage_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.pdc_parts_stoppage_receipts_376 r where r.vehicle_id=v.id),'[]'::jsonb)
          ,'parts_order_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.pdc_parts_order_receipts_377 r where r.vehicle_id=v.id),'[]'::jsonb)
          ,'parts_received_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.pdc_authenticated_parts_received_receipts_751 r where r.vehicle_id=v.id),'[]'::jsonb)
          ,'department_completion_receipts',coalesce((select jsonb_agg(to_jsonb(r)) from public.pdc_vehicle_department_completion_receipts_772 r where r.vehicle_id=v.id),'[]'::jsonb)
          ,'workshop_booking_history',coalesce((select jsonb_agg(to_jsonb(h)) from public.workshop_booking_history h where h.vehicle_id=v.id),'[]'::jsonb)
        )
      ),
        coalesce((select jsonb_agg(to_jsonb(h)) from public.pdc_vehicle_lifecycle_history_events_82000 h where h.vehicle_id=v.id),'[]'::jsonb),
        (select count(*) from public.vehicle_movements m where m.vehicle_id=v.id),
        (select count(*) from public.audit_events a where a.vehicle_id=v.id),
        (select count(*) from public.pdc_vehicle_location_receipts_20260904 r where r.vehicle_id=v.id),
        'bounded authenticated PDC-14 replay fixture; immutable replay receipts retained',false
      from public.vehicles v where v.id='{VEHICLE_ID}'::uuid;
      delete from public.workshop_booking_history where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_vehicle_department_completion_receipts_772 disable trigger pdc_vehicle_department_completion_receipts_772_immutable;
      delete from public.pdc_vehicle_department_completion_receipts_772 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_vehicle_department_completion_receipts_772 enable trigger pdc_vehicle_department_completion_receipts_772_immutable;
      alter table public.workshop_bookings disable trigger user;
      delete from public.workshop_bookings where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.workshop_bookings enable trigger user;
      delete from public.pdc_sublet_bookings where vehicle_id='{VEHICLE_ID}'::uuid;
      delete from public.vehicle_parts_updates where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_parts_stoppage_receipts_376 disable trigger pdc_parts_stoppage_receipts_append_only_376;
      delete from public.pdc_parts_stoppage_receipts_376 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_parts_stoppage_receipts_376 enable trigger pdc_parts_stoppage_receipts_append_only_376;
      alter table public.pdc_parts_order_receipts_377 disable trigger pdc_parts_order_receipts_append_only_377;
      delete from public.pdc_parts_order_receipts_377 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_parts_order_receipts_377 enable trigger pdc_parts_order_receipts_append_only_377;
      alter table public.pdc_authenticated_parts_received_receipts_751 disable trigger pdc_authenticated_parts_received_receipts_751_append_only;
      delete from public.pdc_authenticated_parts_received_receipts_751 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_authenticated_parts_received_receipts_751 enable trigger pdc_authenticated_parts_received_receipts_751_append_only;
      alter table public.vehicle_workshop_hours_batch_receipts_768 disable trigger user;
      delete from public.vehicle_workshop_hours_batch_receipts_768 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.vehicle_workshop_hours_batch_receipts_768 enable trigger user;
      alter table public.vehicle_workshop_line_adjustments disable trigger user;
      delete from public.vehicle_workshop_line_adjustments where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.vehicle_workshop_line_adjustments enable trigger user;
      alter table public.pdc_vehicle_detail_edit_history_388 disable trigger user;
      delete from public.pdc_vehicle_detail_edit_history_388 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_vehicle_detail_edit_history_388 enable trigger user;
      alter table public.pdc_vehicle_detail_edit_receipts_388 disable trigger user;
      delete from public.pdc_vehicle_detail_edit_receipts_388 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_vehicle_detail_edit_receipts_388 enable trigger user;
      alter table public.pdc_authenticated_email_operation_lines disable trigger user;
      delete from public.pdc_authenticated_email_operation_lines where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_authenticated_email_operation_lines enable trigger user;
      alter table public.pdc_authenticated_email_import_receipts disable trigger user;
      delete from public.pdc_authenticated_email_import_receipts where receipt_id='{IMPORT_RECEIPT_ID}'::uuid;
      alter table public.pdc_authenticated_email_import_receipts enable trigger user;
      alter table public.vehicle_work_items disable trigger user;
      delete from public.vehicle_work_items where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.vehicle_work_items enable trigger user;
      delete from public.navision_backend_records where id='{NAVISION_RECORD_ID}'::uuid;
      delete from public.navision_import_batches where id='{NAVISION_BATCH_ID}'::uuid;
      delete from public.pdc_auditor_user_dealer_scopes where scope_id='{DEALER_SCOPE_ID}'::uuid;
      delete from public.workshop_schedule_recovery_receipts where actor_user_id=(select created_by from public.vehicles where id='{VEHICLE_ID}'::uuid);
      lock table public.pdc_vehicle_lifecycle_history_events_82000 in access exclusive mode;
      alter table public.pdc_vehicle_lifecycle_history_events_82000 disable trigger pdc_vehicle_lifecycle_history_events_82000_immutable;
      delete from public.pdc_vehicle_lifecycle_history_events_82000 where vehicle_id='{VEHICLE_ID}'::uuid;
      alter table public.pdc_vehicle_lifecycle_history_events_82000 enable trigger pdc_vehicle_lifecycle_history_events_82000_immutable;
      delete from public.audit_events where vehicle_id='{VEHICLE_ID}'::uuid;
      delete from public.vehicle_movements where vehicle_id='{VEHICLE_ID}'::uuid;
      delete from public.vehicles where id='{VEHICLE_ID}'::uuid;
      commit;
    """)
    return {"ok": True, "code": "bounded_fixture_archived_and_cleaned", "production_writes": False}


def browser_snapshot(page: Page) -> dict[str, object]:
    return page.evaluate("""stock => {
      const state = typeof app === 'object' ? app : null;
      const row = (state?.data || []).find(v => String(v.stock || '') === stock);
      const body = document.body.innerText;
      return {
        authState: document.body.dataset.authState,
        role: window.PDC_AUTH_CONTEXT?.role || null,
        project: window.PDC_SUPABASE_CONFIG?.projectRef || null,
        currentView: state?.currentView || null,
        row: row ? {
          id: row.id, canonicalVehicleId: row.__emailVehicleCanonicalId, stock: row.stock,
          vin: row.vin, jobcard: row.jobcard, client: row.client,
          location: row.pdcLocation, version: row.__emailVehicleVersion,
          required: Object.fromEntries(Object.entries(row).filter(([key]) => key.startsWith('pdcRequires'))),
          completed: Object.fromEntries(Object.entries(row).filter(([key]) => key.startsWith('pdcComplete'))),
          parts: {ordered: row.pdcPartsOrdered, received: row.pdcPartsReceived, stoppage: row.pdcPartsStoppage, reason: row.pdcPartsStoppageReason},
          sublet: {provider: row.pmbSubletProvider, bookingDate: row.pmbSubletBookingDate}
        } : null,
        bodyHasStock: body.includes(stock),
        modalOpen: document.getElementById('vehicle-modal')?.hidden === false,
        modalText: document.querySelector('#vehicle-modal-panel')?.innerText?.slice(0, 3000) || '',
        selectors: {
          workflowOpen: document.querySelectorAll(`[data-open-stock="${stock}"]`).length,
          copy: document.querySelectorAll('[data-copy-vehicle-stock]').length,
          pdcLocation: document.querySelectorAll('select[name="pdcLocation"]').length,
          saveChanges: document.querySelectorAll('[data-vehicle-edit-form] button[type="submit"]').length,
          workStates: document.querySelectorAll('[data-pdc-work-state]').length,
          hoursInputs: document.querySelectorAll('[data-vehicle-workshop-hours-batch-input]').length,
          saveAllHours: document.querySelectorAll('[data-vehicle-workshop-hours-batch-save]').length,
          plannerRefresh: document.querySelectorAll('[data-workshop-refresh-vehicle]').length,
          partsOrdered: document.querySelectorAll('[data-parts-ordered]').length,
          partsComplete: document.querySelectorAll('[data-parts-complete]').length,
          partsStoppage: document.querySelectorAll('[data-parts-stoppage]').length
        }
      };
    }""", STOCK)


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    evidence: dict[str, object] = {
        "task": TASK,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "url": URL,
        "project_ref": STAGING_REF,
        "email_sent": False,
        "production_contacted": False,
        "credentials_redacted": True,
        "browser": {},
    }
    user_id = ""
    service_key = ""
    assignment_applied = False
    cleanup_errors: list[str] = []
    try:
        before = counts()
        evidence["before"] = before
        if before["head"] != ["20260904011500", "parts_stoppage_runtime_containment_repair"]:
            raise RuntimeError(f"unexpected STAGING head {before['head']}")
        if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
            raise RuntimeError("STAGING sentinel preflight failed")
        if before["auth_count"] or before["role_count"] or before["vehicle_count"]:
            raise RuntimeError("bounded fixture namespace is not clean")

        management_headers = {"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"}
        _, keys = http_json(f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys", headers=management_headers)
        service_entry = next((item for item in keys or [] if item.get("name") == "service_role"), None)
        public_entry = next((item for item in keys or [] if item.get("name") in {"anon", "publishable"}), None)
        service_key = str((service_entry or {}).get("api_key") or "")
        public_key = str((public_entry or {}).get("api_key") or "")
        if not service_key or not public_key:
            raise RuntimeError("STAGING API keys unavailable")

        admin_headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json", "Accept": "application/json"}
        status, created = http_json(f"{BASE}/auth/v1/admin/users", method="POST", headers=admin_headers, payload={"email": EMAIL, "password": password, "email_confirm": True})
        user_id = str((created or {}).get("id") or "")
        if status != 200 or not user_id:
            raise RuntimeError("temporary Auth Admin createUser failed")
        assignment = management_write("select public.apply_pdc14_staging_test_operator_role() as outcome")[0]["outcome"]
        assignment_applied = assignment.get("ok") is True
        evidence["operator_assignment"] = assignment
        if not assignment_applied:
            raise RuntimeError("temporary Operator assignment failed")
        create_fixture(user_id)
        evidence["fixture_created"] = counts()

        browser_events = {"console": [], "page_errors": [], "request_failures": [], "http_errors": [], "production_requests": [], "mutations": []}
        evidence["browser_events"] = browser_events
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1440, "height": 1000}, permissions=["clipboard-read", "clipboard-write"])
            page = context.new_page()
            page.on("console", lambda message: browser_events["console"].append({"type": message.type, "text": message.text}) if message.type in {"error", "warning"} else None)
            page.on("pageerror", lambda error: browser_events["page_errors"].append(str(error)))
            page.on("requestfailed", lambda request: browser_events["request_failures"].append({"method": request.method, "url": request.url, "failure": request.failure}))
            page.on("response", lambda response: browser_events["http_errors"].append({"status": response.status, "url": response.url}) if response.status >= 400 else None)
            page.on("request", lambda request: browser_events["production_requests"].append(request.url) if PRODUCTION_REF in request.url else None)
            page.on("request", lambda request: browser_events["mutations"].append({"method": request.method, "url": request.url}) if request.method not in {"GET", "HEAD", "OPTIONS"} else None)
            page.goto(URL + "?pdc14=" + TASK, wait_until="domcontentloaded", timeout=90000)
            page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
            page.locator("#pdc-login-email").fill(EMAIL)
            page.locator("#pdc-login-password").fill(password)
            page.locator("#pdc-password-login").click()
            page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=30000)
            evidence["browser"]["post_login"] = page.evaluate("""() => ({
              authState: document.body.dataset.authState,
              authRole: window.PDC_AUTH_CONTEXT?.role || null,
              bodyText: document.body.innerText.slice(0, 2000),
              appAvailable: typeof app === 'object',
              rowCount: typeof app === 'object' ? (app.emailVehicleLocationRows || []).length : -1,
              locationError: typeof app === 'object' ? app.emailVehicleLocationError : 'app_unavailable'
            })""")
            evidence["browser"]["direct_snapshot"] = page.evaluate("""async stock => {
              const response = await app.emailVehicleLocationService?.snapshot?.();
              const vehicles = response?.data?.vehicles || [];
              return {ok: response?.ok === true, code: response?.code || '', vehicleCount: vehicles.length,
                fixture: vehicles.find(v => String(v.stock_number || '') === stock) || null};
            }""", STOCK)
            evidence["browser"]["explicit_refresh_result"] = page.evaluate("() => refreshEmailVehicleLocations()")
            evidence["browser"]["mapped_rows_after_refresh"] = page.evaluate("""() => ({
              emailRows: app.emailVehicleLocationRows.map(v => ({stock:v.stock,id:v.id,canonical:v.__emailVehicleCanonicalId})),
              dataRows: app.data.filter(v => String(v.stock || '').includes('HERMES')).map(v => ({stock:v.stock,id:v.id,canonical:v.__emailVehicleCanonicalId}))
            })""")
            page.screenshot(path=str(OUT_DIR / "00-post-login.png"), full_page=True)
            page.wait_for_function("stock => (typeof app === 'object' ? app.data || [] : []).some(v => String(v.stock || '') === stock)", arg=STOCK, timeout=30000)
            evidence["browser"]["authenticated"] = browser_snapshot(page)

            matrix: dict[str, object] = {}
            evidence["matrix"] = matrix
            matrix["8"] = {
                "name": "REBHV100551477 bounded identity",
                "ui": {"vin": evidence["browser"]["authenticated"]["row"]["vin"]},
                "db": management_write("select jsonb_build_object('positive',public.is_valid_vehicle_vin('REBHV100551477'),'upper',public.is_valid_vehicle_vin('REBHV199999999'),'short',public.is_valid_vehicle_vin('REBHV10055147'),'long',public.is_valid_vehicle_vin('REBHV1005514777'),'wrong_prefix',public.is_valid_vehicle_vin('REBXX100551477')) result")[0]["result"],
            }

            # Open the deployed modal against the exact mapped authoritative row.
            page.evaluate("stock => openVehicleModal(stock)", STOCK)
            page.wait_for_function("() => document.getElementById('vehicle-modal')?.hidden === false")
            page.locator("[data-copy-vehicle-stock]:visible").dispatch_event("click")
            page.wait_for_function("() => document.querySelector('[data-copy-vehicle-stock-status]')?.textContent?.trim().length > 0", timeout=5000)
            copy_feedback = page.locator("[data-copy-vehicle-stock-status]").all_text_contents()
            matrix["3"] = {
                "name": "Copyable Stock Number",
                "dom": page.locator("[data-vehicle-stock]:visible").evaluate("el => ({text:el.textContent,userSelect:getComputedStyle(el).userSelect})"),
                "feedback": copy_feedback,
                "button_text": page.locator("[data-copy-vehicle-stock]:visible").text_content(),
                "clipboard": page.evaluate("() => navigator.clipboard.readText()"),
            }
            page.screenshot(path=str(OUT_DIR / "02-copy-stock-feedback.png"), full_page=True)

            # Inline Save all hours: use the actual deployed tab/input/button.
            page.locator('[data-vehicle-detail-tab="work"]:visible').click()
            page.wait_for_selector("[data-vehicle-workshop-hours-batch-input]:visible", timeout=30000)
            hours_input = page.locator("[data-vehicle-workshop-hours-batch-input]:visible").first
            hours_input.fill("3.75")
            evidence["browser"]["hours_before_save"] = page.locator("[data-vehicle-workshop-hours-batch-page]:visible").evaluate("page => ({canonicalId:vehicleWorkshopDetailCanonicalId(selectedVehicle() || {}),cache:[...app.vehicleWorkshopDetailCache.entries()],rows:vehicleWorkshopHoursBatchRowsFromPage(page),saveDisabled:page.querySelector('[data-vehicle-workshop-hours-batch-save]')?.disabled})")
            page.locator("[data-vehicle-workshop-hours-batch-save]:visible").click()
            page.wait_for_function("() => document.querySelector('.vehicle-workshop-hours-batch-message')?.textContent?.includes('saved atomically')", timeout=30000)
            matrix["2"] = {
                "name": "Inline Save all hours persistence",
                "message": page.locator(".vehicle-workshop-hours-batch-message:visible").text_content(),
                "readback": fixture_readback(),
                "rerendered_value": page.locator("[data-vehicle-workshop-hours-batch-input]:visible").first.input_value(),
            }
            page.screenshot(path=str(OUT_DIR / "03-save-all-hours.png"), full_page=True)

            # Persist Vehicle Detail fields through the deployed form.
            page.locator('[data-vehicle-detail-tab="details"]:visible').click()
            page.locator('[data-vehicle-edit-form] input[name="client"]:visible').fill("PDC-14 UI Persisted")
            page.locator('[data-vehicle-edit-form] input[name="pdcJobcard"]:visible').fill("HERMES-JC-PDC14-UI")
            page.locator('[data-vehicle-edit-form] button[type="submit"]:visible').click()
            page.wait_for_function("() => app.data.some(v => v.stock === 'HERMES-PDC14-67594974' && v.client === 'PDC-14 UI Persisted' && v.jobcard === 'HERMES-JC-PDC14-UI')", timeout=30000)
            detail_readback = fixture_readback()
            matrix["11"] = {
                "name": "Vehicle Detail controls and links persistence",
                "readback": detail_readback,
                "controls": page.locator("[data-vehicle-edit-form]:visible").evaluate("form => ({client:form.client.value,jobcard:form.pdcJobcard.value,location:form.pdcLocation.value,workControls:form.querySelectorAll('[data-pdc-work-state]').length,workLinkCount:document.querySelectorAll('[data-pdc-work-destination-view]').length})"),
            }

            # PDC Location dropdown: mutate YH -> PMB using the deployed form.
            page.locator('[data-vehicle-edit-form] select[name="pdcLocation"]:visible').select_option("PMB")
            page.locator('[data-vehicle-edit-form] button[type="submit"]:visible').click()
            page.wait_for_function("() => app.data.some(v => v.stock === 'HERMES-PDC14-67594974' && v.pdcLocation === 'PMB')", timeout=30000)
            matrix["10"] = {
                "name": "PDC Location dropdown boundaries",
                "valid_ui_readback": fixture_readback(),
                "rerender": browser_snapshot(page),
            }
            matrix["13"] = {
                "name": "PMB integer days and neutral unknown",
                "known_dom": page.locator('[data-vehicle-edit-form] input[readonly]').evaluate_all("els => els.map(el => el.value)"),
            }
            page.screenshot(path=str(OUT_DIR / "04-location-pmb-and-detail.png"), full_page=True)

            # Add bounded authoritative planned bookings, refresh, and inspect every deployed tile projection.
            red_states = page.locator("[data-pdc-work-state]:visible").evaluate_all("els => els.map(el => ({key:el.dataset.pdcWorkState,classes:el.className,status:el.querySelector('.pdc-work-state-status')?.textContent}))")
            create_workshop_bookings(user_id)
            page.evaluate("() => refreshEmailVehicleLocations()")
            page.evaluate("stock => { openVehicleModal(stock); selectVehicleDetailPage('details'); }", STOCK)
            page.wait_for_timeout(1000)
            booked_states = page.locator("[data-pdc-work-state]:visible").evaluate_all("els => els.map(el => ({key:el.dataset.pdcWorkState,state:el.dataset.state,classes:el.className,status:el.querySelector('.pdc-work-state-status')?.textContent}))")
            matrix["6"] = {"name": "Every workshop-bookable work type red-orange-green", "required": evidence["browser"]["authenticated"]["row"]["required"], "red_dom": red_states, "booked_dom": booked_states}
            matrix["7"] = {"name": "Sublet orange parity", "detail": next((state for state in booked_states if state["key"] == "sublet"), None), "db": fixture_readback()["sublet"]}
            page.screenshot(path=str(OUT_DIR / "05-booked-orange-matrix.png"), full_page=True)

            # Close the modal, enter a real planner route, and click Refresh Vehicle.
            page.evaluate("() => closeVehicleModal()")
            page.locator("[data-view='planner-hoist']").click()
            page.wait_for_selector("[data-workshop-refresh-vehicle]:visible", timeout=30000)
            before_refresh_requests = len(browser_events["mutations"])
            page.locator("[data-workshop-refresh-vehicle]:visible").click()
            page.wait_for_timeout(2000)
            matrix["1"] = {
                "name": "Workshop Planner Refresh Vehicle",
                "button": page.locator("[data-workshop-refresh-vehicle]:visible").evaluate("el => ({text:el.textContent,disabled:el.disabled,ariaBusy:el.getAttribute('aria-busy')})"),
                "new_network_mutations": browser_events["mutations"][before_refresh_requests:],
                "dom": browser_snapshot(page),
            }
            page.screenshot(path=str(OUT_DIR / "06-planner-refresh.png"), full_page=True)

            # Parts: verify computed action colours and perform STOPPAGE set/clear.
            page.locator("[data-view='parts']").click()
            page.wait_for_selector("[data-parts-stoppage]:visible", timeout=30000)
            parts_style = page.locator("[data-parts-stoppage]:visible").first.evaluate("el => ({text:el.textContent,color:getComputedStyle(el).color,background:getComputedStyle(el).backgroundColor,classes:el.className})")
            page.once("dialog", lambda dialog: dialog.accept(f"{TASK} bounded STOPPAGE"))
            page.locator("[data-parts-stoppage]:visible").first.click()
            page.wait_for_function("() => app.data.some(v => v.stock === 'HERMES-PDC14-67594974' && v.pdcPartsStoppage === true)", timeout=30000)
            stoppage_readback = fixture_readback()
            matrix["5"] = {"name": "Reliable Parts STOPPAGE", "valid_readback": stoppage_readback, "dom": browser_snapshot(page)}
            page.screenshot(path=str(OUT_DIR / "07-parts-stoppage.png"), full_page=True)
            page.once("dialog", lambda dialog: dialog.accept(f"{TASK} bounded recovery"))
            page.locator("[data-parts-clear-stoppage]:visible").first.click()
            page.wait_for_function("() => app.data.some(v => v.stock === 'HERMES-PDC14-67594974' && v.pdcPartsStoppage === false)", timeout=30000)
            # Clearing a row while the STOPPAGE chip is active removes it from
            # that filtered table. Return to Not Ordered before continuing.
            page.locator('[data-parts-operational-filter="notordered"]:visible').click()
            page.wait_for_selector("[data-parts-ordered]:visible", timeout=30000)
            fixture_parts_row = page.locator("tr", has_text=STOCK).first
            mark_ordered_style = fixture_parts_row.locator("[data-parts-ordered]").evaluate("el => ({text:el.textContent,color:getComputedStyle(el).color,background:getComputedStyle(el).backgroundColor,classes:el.className})")
            fixture_parts_row.locator("[data-parts-ordered]").click()
            page.wait_for_function("() => app.data.some(v => v.stock === 'HERMES-PDC14-67594974' && v.pdcPartsOrdered === true)", timeout=30000)
            page.locator('[data-parts-operational-filter="ordered"]:visible').click()
            fixture_parts_row = page.locator("tr", has_text=STOCK).first
            ordered_style = fixture_parts_row.locator("[data-parts-complete]").evaluate("el => ({text:el.textContent,color:getComputedStyle(el).color,background:getComputedStyle(el).backgroundColor,classes:el.className})")
            page.once("dialog", lambda dialog: dialog.dismiss())
            fixture_parts_row.locator("[data-parts-complete]").click()
            page.wait_for_function("() => app.data.some(v => v.stock === 'HERMES-PDC14-67594974' && v.pdcCompleteParts === true)", timeout=30000)
            parts_complete_readback = fixture_readback()
            matrix["4"] = {"name": "Parts action colours", "mark_ordered": mark_ordered_style, "mark_received": ordered_style, "stoppage": parts_style}
            matrix["12"] = {"name": "Planner Parts received/completed parity", "readback": parts_complete_readback, "mapped": browser_snapshot(page)["row"]}
            page.screenshot(path=str(OUT_DIR / "08-parts-complete.png"), full_page=True)

            # Department completion is intentionally administrator-only. Elevate
            # only the bounded fixture user, mirror that authoritative role into
            # the current app context, and exercise its real card-completion action.
            sales_email_cancel = page.locator("[data-sales-email-cancel]:visible")
            if sales_email_cancel.count():
                sales_email_cancel.last.click()
            management_write(f"update public.pdc_user_roles set role='administrator', updated_at=clock_timestamp() where auth_user_id='{user_id}'::uuid")
            page.evaluate("() => { window.PDC_AUTH_CONTEXT.role='administrator'; }")
            page.evaluate("() => showView('planner-hoist')")
            page.wait_for_function("() => !!window.__workshopSharedActions?.completeVehicleDepartment && !!window.__workshopDataService?.getTrustedSnapshot?.()", timeout=30000)
            page.evaluate("""() => {
              const original=window.__workshopSharedActions.completeVehicleDepartment.bind(window.__workshopSharedActions);
              window.__pdc14CompletionTrace=[];
              window.__workshopSharedActions.completeVehicleDepartment=async payload=>{
                const response=await original(payload);
                window.__pdc14CompletionTrace.push({payload,response});
                return response;
              };
            }""")
            completion_results = []
            for work_key in ("bus4x4", "tint", "hoist", "fitting", "fabrication", "electrical", "tyre"):
                result = page.evaluate("""async workKey => {
                  window.confirm=()=>true;
                  const ok=await togglePdcJobCompletionFromCard('HERMES-PDC14-67594974',workKey);
                  const vehicle=app.data.find(v=>v.stock==='HERMES-PDC14-67594974');
                  const def=PDC_JOB_DEFS.find(item=>item.key===workKey);
                  const canonicalId=vehicle?vehicleWorkshopDetailCanonicalId(vehicle):'';
                  return {work_key:workKey,ok:ok===true,role:window.PDC_AUTH_CONTEXT?.role,shared:vehicleLifecycleSharedModeActive(),detail:canonicalId?app.vehicleWorkshopDetailCache.get(canonicalId):null,projected:vehicle&&def?canonicalVehicleWorkState(vehicle,def):null,trace:window.__pdc14CompletionTrace.at(-1)||null};
                }""", work_key)
                completion_results.append(result)
                if result.get("ok") is not True:
                    raise RuntimeError(f"deployed {work_key} department completion failed: {json.dumps(result, default=str)}")
                page.wait_for_function("key => { const row=app.data.find(v=>v.stock==='HERMES-PDC14-67594974'); const def=PDC_JOB_DEFS.find(item=>item.key===key); return !!(row && def && canonicalVehicleWorkState(row,def).state==='completed'); }", arg=work_key, timeout=30000)
            page.evaluate("""async () => {
              const row=app.data.find(v=>v.stock==='HERMES-PDC14-67594974');
              await refreshSharedVehicleWorkState(row);
              await loadWorkshopEligibilitySnapshot('pdc14_department_completion');
              await refreshEmailVehicleLocations();
            }""")
            page.evaluate("""async () => {
              await loadWorkshopEligibilitySnapshot('pdc14_department_completion_rerender');
              await refreshEmailVehicleLocations();
            }""")
            try:
                page.wait_for_function("() => { const row=app.data.find(v=>v.stock==='HERMES-PDC14-67594974'); return !!row && PDC_JOB_DEFS.filter(def=>['bus4x4','tint','hoist','fitting','fabrication','electrical','tyre'].includes(def.key)).every(def=>pdcJobComplete(row,def)); }", timeout=30000)
            except Exception as error:
                raise RuntimeError(f"completion rerender work-state snapshot failed: {error}") from error
            page.evaluate("stock => { openVehicleModal(stock); selectVehicleDetailPage('details'); }", STOCK)
            page.wait_for_timeout(1200)
            completed_states = page.locator("[data-pdc-work-state]:visible").evaluate_all("els => els.map(el => ({key:el.dataset.pdcWorkState,classes:el.className,status:el.querySelector('.pdc-work-state-status')?.textContent}))")
            matrix["6"]["completed_api"] = completion_results
            matrix["6"]["completed_dom"] = completed_states
            matrix["14"] = {"name": "Workshop completion updates required-work tile", "fitting": next((state for state in completed_states if state["key"] == "fitting"), None), "readback": fixture_readback()["work"].get("fitting")}
            page.screenshot(path=str(OUT_DIR / "09-completion-green.png"), full_page=True)

            # Current Navision rules and exact-latch readback from authoritative STAGING functions.
            matrix["9"] = {
                "name": "Navision IT to YH / Body Builder to PMB",
                "db": management_write("select jsonb_build_object('it_to_yh',public.navision_operational_location(jsonb_build_object('navisionLocationStatus','IT','navisionSubLocationDescription','Yard Hold')),'body_builder_to_pmb',public.navision_operational_location(jsonb_build_object('navisionLocationStatus','IT','navisionSubLocationDescription','Delivered - At Body Builder')),'eta',public.navision_kewdale_eta_from_payload(jsonb_build_object('navisionLocationStatus','IT','etaToKewdale',to_char(current_date+2,'YYYY-MM-DD')))) result")[0]["result"],
                "current_vehicle_latch": fixture_readback()["vehicle"],
            }
            evidence["authoritative_final_readback"] = fixture_readback()
            context.close()
            browser.close()

        workshop_keys = {"bus4x4", "tint", "hoist", "fitting", "fabrication", "electrical", "tyre"}
        red_by_key = {row["key"]: row for row in matrix["6"]["red_dom"]}
        booked_by_key = {row["key"]: row for row in matrix["6"]["booked_dom"]}
        completed_by_key = {row["key"]: row for row in matrix["6"]["completed_dom"]}
        if any("pdc-work-state-required" not in red_by_key.get(key, {}).get("classes", "") for key in workshop_keys):
            raise RuntimeError("all-work red DOM progression was not proved")
        if any("pdc-work-state-booked" not in booked_by_key.get(key, {}).get("classes", "") for key in workshop_keys):
            raise RuntimeError("all-work orange DOM progression was not proved")
        if any("pdc-work-state-complete" not in completed_by_key.get(key, {}).get("classes", "") for key in workshop_keys):
            raise RuntimeError("all-work green DOM progression was not proved")
        if any(item.get("ok") is not True for item in matrix["6"]["completed_api"]):
            raise RuntimeError("one or more deployed workshop department completions failed")
        if matrix["14"]["readback"] != {"required": True, "completed": True}:
            raise RuntimeError("Fitting completion did not persist")
        if (evidence["browser_events"]["production_requests"] or evidence["browser_events"]["page_errors"]
                or evidence["browser_events"]["request_failures"] or evidence["browser_events"]["http_errors"]):
            raise RuntimeError(f"unexpected deployed browser/network errors: {evidence['browser_events']}")
        evidence["all_checks_passed"] = True
    except Exception as error:
        evidence["execution_error"] = str(error)
        evidence["all_checks_passed"] = False
    finally:
        try:
            cleanup_result = cleanup_fixture()
            evidence["bounded_fixture_cleanup"] = cleanup_result
            if cleanup_result.get("ok") is not True:
                raise RuntimeError(f"bounded fixture cleanup failed closed: {cleanup_result}")
        except Exception as error:
            cleanup_errors.append(f"vehicle cleanup failed: {error}")
        if assignment_applied:
            try:
                # Department completion temporarily elevates the bounded user;
                # restore the exact operator state expected by the audited
                # rollback function even when browser verification fails.
                if user_id:
                    management_write(f"update public.pdc_user_roles set role='operator', updated_at=clock_timestamp() where auth_user_id='{user_id}'::uuid")
                management_write(f"select public.rollback_pdc14_staging_test_operator_role('{TASK} deployed browser verification complete')")
            except Exception as error:
                cleanup_errors.append(f"role rollback failed: {error}")
        if user_id and service_key:
            try:
                http_json(f"{BASE}/auth/v1/admin/users/{user_id}", method="DELETE", headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Accept": "application/json"})
            except Exception as error:
                cleanup_errors.append(f"auth cleanup failed: {error}")
        try:
            management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
        except Exception as error:
            cleanup_errors.append(f"role cleanup failed: {error}")
        try:
            evidence["cleanup"] = counts()
        except Exception as error:
            cleanup_errors.append(f"cleanup readback failed: {error}")
        evidence["cleanup_errors"] = cleanup_errors
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence["password_retained"] = False
        password = service_key = ""
        OUT.write_text(json.dumps(evidence, indent=2, default=str) + "\n", encoding="utf-8")
        print(json.dumps({
            "evidence": str(OUT),
            "all_checks_passed": evidence.get("all_checks_passed", False),
            "execution_error": evidence.get("execution_error"),
            "cleanup": evidence.get("cleanup"),
            "cleanup_errors": cleanup_errors,
        }, indent=2, default=str))
    clean = evidence.get("cleanup") or {}
    return 0 if evidence.get("all_checks_passed") and not cleanup_errors and clean.get("auth_count") == 0 and clean.get("role_count") == 0 and clean.get("vehicle_count") == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
