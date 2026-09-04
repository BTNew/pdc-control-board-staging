#!/usr/bin/env python3
"""Focused authenticated-claims STAGING regression for linked Navision location projection."""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

TASK = "t_86e58618"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
BASE = f"https://{STAGING_REF}.supabase.co"
ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "review-evidence" / TASK
VEHICLES = ("86e58618-0000-5000-8000-000000000901", "86e58618-0000-5000-8000-000000000902")
RECORDS = ("86e58618-0000-5000-8000-000000000911", "86e58618-0000-5000-8000-000000000912")
BATCHES = ("86e58618-0000-5000-8000-000000000921", "86e58618-0000-5000-8000-000000000922")
STOCKS = ("HERMES-NAV-YH-86E58618", "HERMES-NAV-PMB-86E58618")
VINS = ("REBHV186586180", "REBHV186586181")
PRE_HEAD = ["20260904011500", "parts_stoppage_runtime_containment_repair"]
TARGET_HEAD = ["20260905010100", "navision_projection_cleanup_evidence_parity"]


def http_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None,
              payload: dict | None = None) -> tuple[int, object]:
    request = Request(url, data=None if payload is None else json.dumps(payload).encode(),
                      method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            body = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            body = {"raw": raw[:500]}
        return error.code, body


def read_result(sql: str) -> object:
    rows = management_query(sql)
    return rows[0]["result"] if rows else None


def write_result(sql: str) -> object:
    rows = management_write(sql)
    for row in reversed(rows):
        if "result" in row:
            return row["result"]
    return None


def id_list(values: tuple[str, ...]) -> str:
    return ",".join(f"'{value}'::uuid" for value in values)


def counts() -> dict[str, object]:
    vehicles, records, batches = id_list(VEHICLES), id_list(RECORDS), id_list(BATCHES)
    return read_result(f"""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
        'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
        'auth_count',(select count(*) from auth.users where lower(email)='functional.pdc.navision.t86e58618@example.com'),
        'role_count',(select count(*) from public.pdc_user_roles where lower(email)='functional.pdc.navision.t86e58618@example.com'),
        'vehicle_count',(select count(*) from public.vehicles where id in ({vehicles})),
        'work_count',(select count(*) from public.vehicle_work_items where vehicle_id in ({vehicles})),
        'parts_count',(select count(*) from public.vehicle_parts_updates where vehicle_id in ({vehicles})),
        'sublet_count',(select count(*) from public.pdc_sublet_bookings where vehicle_id in ({vehicles})),
        'booking_count',(select count(*) from public.workshop_bookings where vehicle_id in ({vehicles})),
        'operation_count',(select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id in ({vehicles})),
        'navision_record_count',(select count(*) from public.navision_backend_records where id in ({records})),
        'navision_batch_count',(select count(*) from public.navision_import_batches where id in ({batches})),
        'scope_count',(select count(*) from public.pdc_auditor_user_dealer_scopes where normalized_email='functional.pdc.navision.t86e58618@example.com'),
        'location_receipt_count',(select count(*) from public.pdc_vehicle_location_receipts_20260904 where vehicle_id in ({vehicles})),
        'cleanup_history_count',case when to_regclass('public.pdc_navision_projection_cleanup_history_20260905') is null then 0 else 1 end
      ) result
    """)


def vehicle_state(index: int) -> dict[str, object] | None:
    return write_result(f"""
      select jsonb_build_object(
        'id',v.id,'version',v.version,'location',v.current_location,'date_to_pmb',v.date_to_pmb,
        'eta',v.eta_to_kewdale,'lifecycle',v.lifecycle_state,'visible',v.visible_on_board,
        'audit_count',(select count(*) from public.audit_events a where a.vehicle_id=v.id),
        'movement_count',(select count(*) from public.vehicle_movements m where m.vehicle_id=v.id),
        'parity',public.pdc_navision_vehicle_parity_494(v.id),'payload',v.source_payload) result
      from public.vehicles v where v.id='{VEHICLES[index]}'::uuid
    """)


def create_fixtures() -> None:
    statements = []
    for index in range(2):
        statements.append(f"""
          insert into public.navision_import_batches(
            id,idempotency_key,request_hash,source_name,source_timestamp,source_hash,preview_hash,
            base_revision,result_revision,status,total_rows,receipt,actor_id,actor_email,source_system,dealer_code)
          values('{BATCHES[index]}'::uuid,'{TASK}-nav-{index}',repeat('{index + 3}',64),'{TASK}',clock_timestamp(),
            repeat('{index + 5}',64),repeat('{index + 7}',64),1,1,'applied',1,
            '{{"bounded_fixture":"{TASK}","email_sent":false}}'::jsonb,'{ACTOR_ID}'::uuid,'{ACTOR_EMAIL}','microsoft_navision','14450');
          insert into public.vehicles(
            id,permanent_vehicle_id,stock_number,vin,customer_name,vehicle_description,lifecycle_state,
            visible_on_board,current_location,eta_to_kewdale,source_system,source_batch_id,source_record_id,
            source_payload,version,created_by,updated_by,date_to_pmb)
          values('{VEHICLES[index]}'::uuid,'HERMES-NAV-PERM-86E58618-{index}','{STOCKS[index]}','{VINS[index]}',
            'Navision Projection Fixture','Bounded linked location regression','active',true,'IT',current_date+2,
            'microsoft_navision','14450','{RECORDS[index]}',jsonb_build_object(
              'bounded_fixture','{TASK}','email_sent',false,'navision_record_id','{RECORDS[index]}',
              'navision_version','1','navision_status','From TWA - Despatched','navision_updated_at',transaction_timestamp()),
            1,'{ACTOR_ID}'::uuid,'{ACTOR_ID}'::uuid,null);
          insert into public.navision_backend_records(
            id,source_record_id,row_hash,normalized_data,raw_evidence,canonical_vehicle_id,
            first_seen_batch_id,last_seen_batch_id,updated_at,source_system,dealer_code,record_status)
          values('{RECORDS[index]}'::uuid,'{TASK}-nav-record-{index}',repeat('{index + 1}',64),jsonb_build_object(
            'batch','{STOCKS[index]}','vin','{VINS[index]}','toyotaStatus','From TWA - Despatched',
            'navisionLocationStatus','IT','navisionSubLocationDescription','From TWA - Despatched',
            'etaToKewdale',to_char(current_date+2,'YYYY-MM-DD')),
            '{{"bounded_fixture":"{TASK}","email_sent":false}}'::jsonb,'{VEHICLES[index]}'::uuid,
            '{BATCHES[index]}'::uuid,'{BATCHES[index]}'::uuid,transaction_timestamp(),'microsoft_navision','14450','current');
        """)
    management_write("begin; " + "\n".join(statements) + " commit;")


def set_navision(index: int, status: str, eta_days: int) -> None:
    escaped = status.replace("'", "''")
    management_write(f"""
      begin; lock table public.vehicles,public.navision_backend_records in access exclusive mode;
      alter table public.navision_backend_records disable trigger navision_record_operational_reconcile;
      alter table public.navision_backend_records disable trigger zz_navision_all_vehicle_parity_494;
      alter table public.vehicles disable trigger zz_vehicle_navision_parity_494;
      update public.navision_backend_records set normalized_data=normalized_data||jsonb_build_object(
        'navisionLocationStatus','IT','navisionSubLocationDescription','{escaped}','toyotaStatus','{escaped}',
        'etaToKewdale',to_char(current_date+{eta_days},'YYYY-MM-DD'),
        'navisionKewdaleEta',to_char(current_date+{eta_days},'YYYY-MM-DD')),
        row_hash=encode(extensions.digest(convert_to(normalized_data::text||clock_timestamp()::text,'UTF8'),'sha256'),'hex'),
        updated_at=clock_timestamp() where id='{RECORDS[index]}'::uuid;
      alter table public.navision_backend_records enable trigger navision_record_operational_reconcile;
      alter table public.navision_backend_records enable trigger zz_navision_all_vehicle_parity_494;
      alter table public.vehicles enable trigger zz_vehicle_navision_parity_494; commit;
    """)


def reconcile(index: int, actor_id: str = ACTOR_ID, actor_email: str = ACTOR_EMAIL,
              *, public_route: bool = False) -> object:
    claims = json.dumps({"sub": ACTOR_ID, "email": ACTOR_EMAIL, "role": "authenticated"}).replace("'", "''")
    function_name = "reconcile_navision_operational_record" if public_route else "reconcile_navision_operational_record_pre_700"
    return write_result(f"""
      begin;
      select set_config('request.jwt.claims','{claims}',true);
      select set_config('request.jwt.claim.sub','{ACTOR_ID}',true);
      select set_config('request.jwt.claim.email','{ACTOR_EMAIL}',true);
      select set_config('request.jwt.claim.role','authenticated',true);
      select public.{function_name}(
        '{RECORDS[index]}'::uuid,'{actor_id}'::uuid,'{actor_email}') result;
      commit;
    """)


def reconcile_delivery(index: int) -> object:
    claims = json.dumps({"sub": ACTOR_ID, "email": ACTOR_EMAIL, "role": "authenticated"}).replace("'", "''")
    return write_result(f"""
      begin;
      select set_config('request.jwt.claims','{claims}',true);
      select set_config('request.jwt.claim.sub','{ACTOR_ID}',true);
      select set_config('request.jwt.claim.email','{ACTOR_EMAIL}',true);
      select set_config('request.jwt.claim.role','authenticated',true);
      select public.reconcile_navision_delivery_734(
        '{RECORDS[index]}'::uuid,'{ACTOR_ID}'::uuid,'{ACTOR_EMAIL}') result;
      commit;
    """)


def manual_latch_pmb() -> None:
    management_write(f"""
      begin; select * from public.vehicles where id='{VEHICLES[0]}'::uuid for update;
      with before_row as (select to_jsonb(v) body from public.vehicles v where v.id='{VEHICLES[0]}'::uuid),
      changed as (
        update public.vehicles set current_location='PMB',visible_on_board=true,
          source_payload=coalesce(source_payload,'{{}}'::jsonb)||jsonb_build_object(
            'manual_location_authority','PMB','manual_location_updated_at',clock_timestamp(),'manual_location_updated_by','{ACTOR_EMAIL}'),
          version=version+1,updated_by='{ACTOR_ID}'::uuid where id='{VEHICLES[0]}'::uuid returning *)
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      select 'move','vehicles','{VEHICLES[0]}'::uuid,'{VEHICLES[0]}'::uuid,'{ACTOR_ID}'::uuid,'{ACTOR_EMAIL}',b.body,to_jsonb(c),
        jsonb_build_object('action','bounded_manual_pmb_latch','task','{TASK}') from before_row b cross join changed c;
      insert into public.vehicle_movements(vehicle_id,from_location,to_location,reason,moved_by)
      values('{VEHICLES[0]}'::uuid,'YH','PMB','Bounded manual PMB latch invariant','{ACTOR_ID}'::uuid);
      commit;
    """)


def cleanup() -> None:
    vehicles, records, batches = id_list(VEHICLES), id_list(RECORDS), id_list(BATCHES)
    management_write(f"""
      begin;
      do $guard$ begin
        if (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}')<>1
           or to_regclass('public.pdc_production_environment_sentinel') is not null then
          raise exception 'PDC_NAVISION_PROJECTION_CLEANUP_WRONG_ENVIRONMENT'; end if;
        if exists(select 1 from public.vehicles where id in ({vehicles}) and source_payload->>'bounded_fixture'<>'{TASK}') then
          raise exception 'PDC_NAVISION_PROJECTION_CLEANUP_PROVENANCE_MISMATCH'; end if;
      end $guard$;
      do $archive$
      begin
        if to_regclass('public.pdc_navision_projection_cleanup_history_20260905') is not null then
          insert into public.pdc_navision_projection_cleanup_history_20260905(
            vehicle_id,actor_id,actor_email,before_vehicle,navision_record,parity,audit_evidence,movement_evidence,cleanup_reason,production_writes)
          select v.id,'{ACTOR_ID}'::uuid,'{ACTOR_EMAIL}',to_jsonb(v),to_jsonb(n),public.pdc_navision_vehicle_parity_494(v.id),
            coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.audit_events a where a.vehicle_id=v.id),'[]'::jsonb),
            coalesce((select jsonb_agg(to_jsonb(m) order by m.id) from public.vehicle_movements m where m.vehicle_id=v.id),'[]'::jsonb),
            'bounded linked Navision projection fixture archived before mutable cleanup',false
          from public.vehicles v join public.navision_backend_records n on n.canonical_vehicle_id=v.id
          where v.id in ({vehicles}) on conflict(vehicle_id) do nothing;
        end if;
      end $archive$;
      alter table public.pdc_vehicle_location_receipts_20260904 disable trigger user;
      delete from public.pdc_vehicle_location_receipts_20260904 where vehicle_id in ({vehicles});
      alter table public.pdc_vehicle_location_receipts_20260904 enable trigger user;
      lock table public.pdc_vehicle_lifecycle_history_events_82000 in access exclusive mode;
      alter table public.pdc_vehicle_lifecycle_history_events_82000 disable trigger pdc_vehicle_lifecycle_history_events_82000_immutable;
      delete from public.pdc_vehicle_lifecycle_history_events_82000 where vehicle_id in ({vehicles});
      alter table public.pdc_vehicle_lifecycle_history_events_82000 enable trigger pdc_vehicle_lifecycle_history_events_82000_immutable;
      delete from public.audit_events where vehicle_id in ({vehicles});
      delete from public.vehicle_movements where vehicle_id in ({vehicles});
      alter table public.navision_backend_records disable trigger navision_record_operational_reconcile;
      alter table public.navision_backend_records disable trigger zz_navision_all_vehicle_parity_494;
      alter table public.vehicles disable trigger zz_vehicle_navision_parity_494;
      delete from public.navision_backend_records where id in ({records});
      delete from public.vehicles where id in ({vehicles});
      alter table public.navision_backend_records enable trigger navision_record_operational_reconcile;
      alter table public.navision_backend_records enable trigger zz_navision_all_vehicle_parity_494;
      alter table public.vehicles enable trigger zz_vehicle_navision_parity_494;
      delete from public.navision_import_batches where id in ({batches}); commit;
    """)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("red", "green"))
    args = parser.parse_args()
    expected_head = PRE_HEAD if args.phase == "red" else TARGET_HEAD
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    evidence: dict[str, object] = {"task": TASK, "phase": args.phase,
        "started_at": datetime.now(timezone.utc).isoformat(), "project_ref": STAGING_REF,
        "authentication": "exact deployed monitor actor and JWT claims applied to the canonical pre-700 reconciliation chain; public RPC ACL and disabled-monitor fail-closed route checked separately",
        "production_contacted": False, "email_sent": False, "credentials_redacted": True}
    failure: Exception | None = None
    cleanup_errors: list[str] = []
    try:
        before = counts(); evidence["before"] = before
        if before["head"] != expected_head or before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
            raise RuntimeError(f"unexpected STAGING preflight: {before}")
        if any(before[key] for key in ("auth_count","role_count","vehicle_count","work_count","parts_count","sublet_count","booking_count","operation_count","navision_record_count","navision_batch_count","scope_count","location_receipt_count")):
            raise RuntimeError(f"bounded namespace not clean: {before}")
        create_fixtures(); evidence["fixture_created"] = counts()

        management_headers = {"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"}
        _, keys = http_json(f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys", headers=management_headers)
        public_key = str(next((item.get("api_key") for item in keys or [] if item.get("name") in {"anon","publishable"}), ""))
        anon = http_json(f"{BASE}/rest/v1/rpc/reconcile_navision_operational_record", method="POST",
            headers={"apikey": public_key,"Content-Type":"application/json"},
            payload={"p_backend_record_id":RECORDS[0],"p_actor_id":None,"p_actor_email":None})
        evidence["anonymous_denied"] = {"status":anon[0],"body":anon[1]}
        if anon[0] not in (401,403): raise RuntimeError(f"anonymous route was not denied: {anon}")
        wrong = reconcile(0, "86e58618-0000-5000-8000-000000000999", "wrong.identity@example.com", public_route=True)
        evidence["actor_mismatch_denied"] = {"response":wrong,"readback":vehicle_state(0)}
        if not isinstance(wrong,dict) or wrong.get("ok") is not False or wrong.get("code") not in {"actor_identity_mismatch","monitor_identity_required"}:
            raise RuntimeError(f"actor mismatch did not fail closed: {wrong}")

        set_navision(0,"Vehicle Waiting Wholesale",2)
        future = reconcile(0); future_state = vehicle_state(0)
        evidence["future_eta_remains_it"] = {"response":future,"readback":future_state}
        if not future.get("ok") or future_state["location"]!="IT" or future_state["date_to_pmb"] is not None:
            raise RuntimeError(f"future ETA invariant failed: {future} {future_state}")

        version_before, audit_before = int(future_state["version"]), int(future_state["audit_count"])
        set_navision(0,"Vehicle Waiting Wholesale",-1)
        past = reconcile(0); past_state = vehicle_state(0)
        evidence["past_eta_it_to_yh"] = {"response":past,"readback":past_state,"version_before":version_before,"audit_before":audit_before}
        expected_eta = read_result("select to_char(current_date-1,'YYYY-MM-DD') result")
        if (not past.get("ok") or past_state["location"]!="YH" or past_state["date_to_pmb"] is not None
                or past_state["eta"]!=expected_eta or int(past_state["version"])<=version_before
                or int(past_state["audit_count"])<=audit_before or not past_state["parity"]["ok"]
                or past_state["parity"]["mismatch_count"]!=0):
            raise RuntimeError(f"authoritative linked IT to YH projection failed: response={past}, readback={past_state}")

        ordinary = reconcile(0); ordinary_state = vehicle_state(0)
        evidence["generic_yh_does_not_auto_pmb"] = {"response":ordinary,"readback":ordinary_state}
        if ordinary_state["location"]!="YH" or ordinary_state["date_to_pmb"] is not None:
            raise RuntimeError("generic YH to PMB was auto-performed")
        manual_latch_pmb(); manual_state = vehicle_state(0); manual_date = manual_state["date_to_pmb"]
        evidence["manual_pmb_latch"] = manual_state
        if manual_state["location"]!="PMB" or not manual_date: raise RuntimeError("manual PMB latch failed")
        set_navision(0,"Vehicle Waiting Wholesale",-2)
        latched = reconcile(0); latched_state = vehicle_state(0)
        evidence["ordinary_navision_preserves_manual_pmb"] = {"response":latched,"readback":latched_state}
        if latched_state["location"]!="PMB" or latched_state["date_to_pmb"]!=manual_date:
            raise RuntimeError("ordinary Navision update repositioned a manually latched PMB vehicle")

        set_navision(1,"Delivered - At Body Builder",-1)
        body = reconcile(1); body_state = vehicle_state(1)
        evidence["body_builder_establishes_pmb"] = {"response":body,"readback":body_state}
        if not body.get("ok") or body_state["location"]!="PMB" or not body_state["date_to_pmb"]:
            raise RuntimeError(f"Body Builder PMB behavior failed: {body} {body_state}")
        set_navision(1,"Delivered - At Dealer",-1)
        od = reconcile_delivery(1); od_state = vehicle_state(1)
        evidence["od_routes_to_canonical_close"] = {"response":od,"readback":od_state}
        if od.get("ok") is not False or od.get("code")!="delivery_requires_collected_interval" or od_state["location"]!="PMB":
            raise RuntimeError(f"OD did not route to canonical close guard: {od} {od_state}")
        evidence["security_advisors"] = security_advisor_summary()
        evidence["all_checks_passed"] = True
    except Exception as error:
        failure = error; evidence["execution_error"] = str(error); evidence["all_checks_passed"] = False
    finally:
        try: cleanup()
        except Exception as error: cleanup_errors.append(f"database cleanup failed: {error}")
        try: evidence["cleanup"] = counts()
        except Exception as error: cleanup_errors.append(f"cleanup readback failed: {error}")
        evidence["cleanup_errors"] = cleanup_errors
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        out = OUT_DIR/f"navision-linked-location-{args.phase}.json"
        out.write_text(json.dumps(evidence,indent=2,default=str)+"\n",encoding="utf-8")
        print(json.dumps({"ok":failure is None and not cleanup_errors,"phase":args.phase,"evidence":str(out),
            "execution_error":str(failure) if failure else None,"cleanup_errors":cleanup_errors,"cleanup":evidence.get("cleanup")},indent=2,default=str))
    return 0 if failure is None and not cleanup_errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
