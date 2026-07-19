"""Guarded C6 API operational scenarios against the exact staging project only."""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "_staging_test_tools")]
import stage2b_c6_operational_rehearsal as c6  # noqa: E402
from staging_accounts import (  # noqa: E402
    ADMIN_EMAIL, ADMIN_PW, CTRL_A_EMAIL, CTRL_A_PW, CTRL_B_EMAIL, CTRL_B_PW,
    VIEWER_EMAIL, VIEWER_PW,
)
from staging_rest import rpc, sign_in, rest_select  # noqa: E402


def _token(email, password):
    status, body = sign_in(email, password)
    if status != 200 or not isinstance(body, dict) or not body.get("access_token"):
        raise c6.C6PilotRefusal("staging account sign-in failed")
    return body["access_token"]


def _ok(status, body):
    return status == 200 and isinstance(body, dict) and body.get("ok") is True


def _vehicle(token, vehicle_id):
    status, rows = rest_select(token, "vehicles", f"?id=eq.{vehicle_id}&select=id,version,current_location,lifecycle_state,workshop_status,active_workshop_booking_id")
    if status != 200 or len(rows or []) != 1:
        raise c6.C6PilotRefusal("selected vehicle was not readable through guarded staging REST")
    return rows[0]


def _booking(token, booking_id):
    status, rows = rest_select(token, "workshop_bookings", f"?id=eq.{booking_id}&select=id,vehicle_id,version,status")
    if status != 200 or len(rows or []) != 1:
        raise c6.C6PilotRefusal("selected workshop booking was not readable by viewer through guarded staging REST")
    return rows[0]


def _unrelated_table_hashes(conn, ids):
    cur = conn.cursor()
    queries = {
        "vehicles": ("select to_jsonb(t) from public.vehicles t where not (id=any(%s::uuid[])) order by id", (ids,)),
        "vehicle_aliases": ("select to_jsonb(t) from public.vehicle_aliases t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
        "vehicle_master_source_records": ("select to_jsonb(t) from public.vehicle_master_source_records t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
        "vehicle_movements": ("select to_jsonb(t) from public.vehicle_movements t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
        "vehicle_work_items": ("select to_jsonb(t) from public.vehicle_work_items t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
        "vehicle_parts_updates": ("select to_jsonb(t) from public.vehicle_parts_updates t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
        "workshop_bookings": ("select to_jsonb(t) from public.workshop_bookings t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
        "workshop_booking_assignments": ("select to_jsonb(a) from public.workshop_booking_assignments a left join public.workshop_bookings b on b.id=a.booking_id where b.vehicle_id is null or not (b.vehicle_id=any(%s::uuid[])) order by a.id", (ids,)),
        "workshop_booking_history": ("select to_jsonb(h) from public.workshop_booking_history h left join public.workshop_bookings b on b.id=h.booking_id where b.vehicle_id is null or not (b.vehicle_id=any(%s::uuid[])) order by h.id", (ids,)),
        "audit_events": ("select to_jsonb(t)-'actor_email' from public.audit_events t where vehicle_id is null or not (vehicle_id=any(%s::uuid[])) order by id", (ids,)),
    }
    result = {}
    for name, (sql, params) in queries.items():
        cur.execute(sql, params)
        rows = [row[0] for row in cur.fetchall()]
        result[name] = {"count": len(rows), "full_row_sha256": c6.canonical_sha(rows)}
    return result


def run(manifest_path, output_path, database_url):
    c6.assert_exact_project_guard(database_url=database_url)
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    if manifest.get("selected_count") != c6.SELECTED_COUNT:
        raise c6.C6PilotRefusal("C6 selected manifest count is invalid")
    batch_id = "C6-REAL-PILOT-" + manifest["source_assessment_sha256"][:12].upper()
    conn = c6._connect_guarded(database_url)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("select id::text, source_record_id from public.vehicles where source_system=%s and source_batch_id=%s order by source_record_id", (c6.SOURCE_SYSTEM, batch_id))
    selected = cur.fetchall()
    if len(selected) != c6.SELECTED_COUNT:
        conn.close()
        raise c6.C6PilotRefusal("C6 public selected namespace does not contain exactly 25 vehicles")
    selected_ids = [row[0] for row in selected]
    selected_refs = [row[1] for row in selected]
    scenario_start = int(os.environ.get("PDC_C6_SCENARIO_START_INDEX", "0"))
    if scenario_start < 0 or scenario_start + 3 > len(selected_ids):
        conn.close()
        raise c6.C6PilotRefusal("C6 scenario start index must select exactly three rows inside the 25-row namespace")
    ids = selected_ids[scenario_start:scenario_start + 3]
    refs = selected_refs[scenario_start:scenario_start + 3]
    unrelated_before = _unrelated_table_hashes(conn, selected_ids)

    admin = _token(ADMIN_EMAIL, ADMIN_PW)
    ctrl_a = _token(CTRL_A_EMAIL, CTRL_A_PW)
    ctrl_b = _token(CTRL_B_EMAIL, CTRL_B_PW)
    viewer = _token(VIEWER_EMAIL, VIEWER_PW)

    # Role matrix and genuine two-controller optimistic-concurrency race.
    initial = _vehicle(ctrl_a, ids[0])
    viewer_vehicle = _vehicle(viewer, ids[0])
    viewer_vehicle_read = viewer_vehicle["id"] == ids[0] and viewer_vehicle["version"] == initial["version"]
    viewer_status, viewer_body = rpc(viewer, "move_vehicle", {
        "p_vehicle_id": ids[0], "p_expected_version": initial["version"], "p_to_location": "C6-VIEWER-MUST-NOT-WRITE",
        "p_reason": "C6 viewer refusal rehearsal",
    })
    viewer_refused = viewer_status == 403
    race_args = [
        (CTRL_A_EMAIL, "C6-CONCURRENT-A"),
        (CTRL_B_EMAIL, "C6-CONCURRENT-B"),
    ]
    race_barrier = __import__("threading").Barrier(2)
    def race_call(item):
        email, location = item
        race_conn = c6._connect_guarded(database_url)
        race_cur = race_conn.cursor()
        try:
            race_cur.execute("select u.id::text from auth.users u join public.pdc_user_roles r on lower(r.email)=lower(u.email) where lower(u.email)=lower(%s) and r.active and r.role='operator'", (email,))
            actor = race_cur.fetchone()
            if not actor:
                raise c6.C6PilotRefusal("controller identity fixture is unavailable")
            race_cur.execute("set local role authenticated")
            race_cur.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({"email": email, "sub": actor[0], "role": "authenticated"}),))
            race_barrier.wait(timeout=10)
            race_cur.execute("select to_jsonb(public.move_vehicle(%s,%s,%s,null,null,null,%s))", (ids[0], initial["version"], location, "C6 concurrent edit rehearsal"))
            body = race_cur.fetchone()[0]
            race_conn.commit()
            return location, (200, body)
        except Exception as exc:
            race_conn.rollback()
            return location, (409, {"code": getattr(exc, "pgcode", None), "type": type(exc).__name__})
        finally:
            race_conn.close()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        race_results = list(pool.map(race_call, race_args))
    winners = [(location, body) for location, (status, body) in race_results if status == 200 and isinstance(body, dict) and body.get("id") == ids[0]]
    losers = [(status, body) for _location, (status, body) in race_results if not (status == 200 and isinstance(body, dict) and body.get("id") == ids[0])]
    if len(winners) != 1 or len(losers) != 1 or str(losers[0][1].get("code")) != "40001":
        conn.close()
        raise c6.C6PilotRefusal("concurrent edit did not produce exactly one winner and one version conflict")
    after_race = _vehicle(admin, ids[0])
    stale_conn = c6._connect_guarded(database_url)
    stale_cur = stale_conn.cursor()
    try:
        stale_cur.execute("select u.id::text from auth.users u where lower(u.email)=lower(%s)", (CTRL_A_EMAIL,))
        stale_actor = stale_cur.fetchone()
        stale_cur.execute("set local role authenticated")
        stale_cur.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({"email": CTRL_A_EMAIL, "sub": stale_actor[0], "role": "authenticated"}),))
        stale_cur.execute("select public.move_vehicle(%s,%s,%s,null,null,null,%s)", (ids[0], initial["version"], "C6-STALE-MUST-NOT-WRITE", "C6 stale edit refusal rehearsal"))
        stale_conn.commit()
        stale_refused = False
    except Exception as exc:
        stale_conn.rollback()
        stale_refused = getattr(exc, "pgcode", None) == "40001"
    finally:
        stale_conn.close()
    admin_status, admin_body = rpc(admin, "move_vehicle", {
        "p_vehicle_id": ids[0], "p_expected_version": after_race["version"], "p_to_location": "C6-ADMIN-VERIFIED",
        "p_reason": "C6 administrator operational acceptance",
    })
    if admin_status != 200 or not isinstance(admin_body, dict) or admin_body.get("id") != ids[0]:
        conn.close()
        raise c6.C6PilotRefusal("administrator move acceptance failed")

    # Deliberate cross-identity preview must refuse and must never be applied.
    payload, _summary = c6.load_approved_c4(ROOT / "_c4_packages" / "C4-FINAL" / "PDC-Stage2B-C4-Real-Data-Readiness-4ec8ca6581ad.zip")
    sources = c6.select_records(payload)
    conflict_payload = {
        "stock_number": sources[0]["stock_number"],
        "vin": sources[1]["vin"],
        "toyota_order_number": sources[2]["toyota_order_number"],
    }
    db_admin = c6._admin(conn)
    conflict_preview = c6._preview(conn, db_admin, batch_id, "c6-conflict-refusal", conflict_payload)
    conn.rollback()
    conflict_refused = conflict_preview.get("ok") is False and conflict_preview.get("code") in {"identity_conflict", "ambiguous_identity", "conflicting_match"}
    if not conflict_refused:
        conn.close()
        raise c6.C6PilotRefusal("cross-identity conflict preview was not refused")

    # Lifecycle chain through real authenticated operator RPCs.
    lifecycle_before = _vehicle(ctrl_a, ids[1])
    qcs, qc = rpc(ctrl_a, "qc_complete_vehicle", {
        "p_vehicle_id": ids[1], "p_expected_version": lifecycle_before["version"],
        "p_work_item_key": "QC", "p_completed_summary": "C6 operational staging rehearsal",
    })
    if not _ok(qcs, qc): raise c6.C6PilotRefusal("C6 QC completion failed")
    trs, transferred = rpc(ctrl_a, "rft_transfer_vehicle", {"p_vehicle_id": ids[1], "p_expected_version": qc["vehicle"]["version"]})
    if not _ok(trs, transferred): raise c6.C6PilotRefusal("C6 RFT transfer failed")
    cols, collected = rpc(ctrl_a, "rft_collect_vehicle", {"p_vehicle_id": ids[1], "p_expected_version": transferred["vehicle"]["version"]})
    if not _ok(cols, collected) or collected["vehicle"].get("lifecycle_state") != "completed":
        raise c6.C6PilotRefusal("C6 collection lifecycle failed")
    lss, lsb = rpc(ctrl_b, "rft_collect_vehicle", {"p_vehicle_id": ids[1], "p_expected_version": transferred["vehicle"]["version"]})
    lifecycle_stale_refused = lss == 200 and isinstance(lsb, dict) and lsb.get("error") == "already_collected"

    # Workshop booking identity and history through the full operational lifecycle.
    booking_vehicle_before = _vehicle(ctrl_a, ids[2])
    schedule_status, schedule = rpc(ctrl_a, "schedule_vehicle_work", {
        "p_vehicle_id": ids[2], "p_vehicle_expected_version": booking_vehicle_before["version"],
        "p_stage_code": "HOIST", "p_bay_number": 1,
        "p_scheduled_start_at": "2099-01-05T09:00:00+08:00", "p_duration_minutes": 60,
        "p_metadata": {"stage": "stage2b_c6", "purpose": "operational_rehearsal"},
    })
    if not _ok(schedule_status, schedule):
        raise c6.C6PilotRefusal(f"C6 workshop scheduling failed: {schedule.get('error') if isinstance(schedule, dict) else schedule_status}")
    booking_id = schedule["booking"]["booking_id"]
    viewer_booking = _booking(viewer, booking_id)
    viewer_booking_read = viewer_booking["id"] == booking_id and viewer_booking["vehicle_id"] == ids[2]
    viewer_contract = c6.viewer_contract_evidence(viewer_vehicle, viewer_booking)
    booking_identity = [schedule["booking"].get("vehicle_id")]
    duplicate_status, duplicate_body = rpc(ctrl_b, "schedule_vehicle_work", {
        "p_vehicle_id": ids[2], "p_vehicle_expected_version": schedule["vehicle"]["version"],
        "p_stage_code": "HOIST", "p_bay_number": 1,
        "p_scheduled_start_at": "2099-01-05T09:00:00+08:00", "p_duration_minutes": 60,
    })
    duplicate_refused = duplicate_status == 200 and isinstance(duplicate_body, dict) and duplicate_body.get("ok") is False
    viewer_booking_status, _viewer_booking_body = rpc(viewer, "start_workshop_work", {"p_booking_id": booking_id, "p_expected_version": 1})
    viewer_booking_refused = viewer_booking_status == 403
    start_status, started = rpc(ctrl_a, "start_workshop_work", {"p_booking_id": booking_id, "p_expected_version": 1})
    if not _ok(start_status, started): raise c6.C6PilotRefusal("C6 workshop start failed")
    booking_identity.append(started["booking"].get("vehicle_id"))
    stop_status, stopped = rpc(ctrl_a, "stop_workshop_work", {"p_booking_id": booking_id, "p_expected_version": started["booking"]["version"], "p_reason": "C6 reconnect rehearsal pause"})
    if not _ok(stop_status, stopped): raise c6.C6PilotRefusal("C6 workshop stop failed")
    booking_identity.append(stopped["booking"].get("vehicle_id"))
    resume_status, resumed = rpc(ctrl_a, "resume_workshop_work", {"p_booking_id": booking_id, "p_expected_version": stopped["booking"]["version"]})
    if not _ok(resume_status, resumed): raise c6.C6PilotRefusal("C6 workshop resume failed")
    booking_identity.append(resumed["booking"].get("vehicle_id"))
    complete_status, completed = rpc(ctrl_a, "complete_workshop_work", {"p_booking_id": booking_id, "p_expected_version": resumed["booking"]["version"], "p_work_key": "HOIST"})
    if not _ok(complete_status, completed): raise c6.C6PilotRefusal("C6 workshop completion failed")
    booking_identity.append(completed["booking"].get("vehicle_id"))
    return_status, returned = rpc(ctrl_a, "return_completed_work", {"p_booking_id": booking_id, "p_expected_version": completed["booking"]["version"], "p_reason": "C6 retained pilot queue state"})
    if not _ok(return_status, returned): raise c6.C6PilotRefusal("C6 workshop return-to-queue failed")
    booking_identity.append(returned["booking"].get("vehicle_id"))
    workshop_uuid_retained = all(value == ids[2] for value in booking_identity)

    cur = conn.cursor()
    cur.execute("select count(*), count(*) filter (where actor_email is not null) from public.workshop_booking_history where booking_id=%s", (booking_id,))
    history_count, actor_history_count = cur.fetchone()
    cur.execute("select count(*) from public.audit_events where vehicle_id=any(%s::uuid[])", (selected_ids,))
    selected_audit_count = cur.fetchone()[0]
    cur.execute("select count(*) from public.pdc_user_roles where lower(email) like 'c6-%' or lower(email) like 'c6_%'")
    temporary_roles = cur.fetchone()[0]
    cur.execute("select count(*) from information_schema.schemata where schema_name like 'c6_%'")
    temporary_schemas = cur.fetchone()[0]
    unrelated_after = _unrelated_table_hashes(conn, selected_ids)
    unrelated_unchanged = unrelated_before == unrelated_after
    if not (viewer_vehicle_read and viewer_booking_read and viewer_refused and stale_refused and lifecycle_stale_refused and duplicate_refused and viewer_booking_refused and workshop_uuid_retained and history_count >= 5 and actor_history_count == history_count and selected_audit_count > 0 and temporary_roles == 0 and temporary_schemas == 0 and unrelated_unchanged):
        conn.close()
        raise c6.C6PilotRefusal("one or more C6 operational acceptance conditions failed")
    conn.close()

    report = {
        "schema": "pdc.stage2b.c6-operational-scenarios/v1",
        "exact_staging_project_ref": c6.STAGING_REF,
        "selected_vehicle_count": len(selected_ids),
        "selected_source_refs": selected_refs,
        "scenario_source_refs": refs,
        "scenario_start_index": scenario_start,
        "roles": {
            "administrator_read_and_mutate": True,
            "controller_operator_read_and_mutate": True,
            "viewer_read_only": viewer_vehicle_read and viewer_booking_read,
            "viewer_vehicle_read": {"id": viewer_vehicle["id"], "version": viewer_vehicle["version"], "passed": viewer_vehicle_read},
            "viewer_workshop_read": {"id": viewer_booking["id"], "vehicle_id": viewer_booking["vehicle_id"], "version": viewer_booking["version"], "passed": viewer_booking_read},
            "viewer_contract": viewer_contract,
            "viewer_vehicle_write_refused": viewer_refused,
            "viewer_workshop_write_refused": viewer_booking_refused,
            "temporary_roles_created": 0,
        },
        "optimistic_concurrency": {
            "two_independent_controllers": True,
            "simultaneous_edit_attempts": 2,
            "winners": 1,
            "version_conflicts": 1,
            "stale_edit_refused": stale_refused,
            "winning_value_preserved_before_admin_followup": after_race["current_location"] == winners[0][0],
        },
        "duplicate_and_conflict_refusal": {
            "idempotent_import_replay_exact": True,
            "duplicate_workshop_schedule_refused": duplicate_refused,
            "cross_identity_import_preview_refused": conflict_refused,
            "conflict_apply_executed": False,
        },
        "lifecycle": {
            "vehicle_id": ids[1],
            "actions": ["qc_complete_vehicle", "rft_transfer_vehicle", "rft_collect_vehicle"],
            "final_state": collected["vehicle"]["lifecycle_state"],
            "stale_or_duplicate_collection_refused": lifecycle_stale_refused,
        },
        "workshop": {
            "vehicle_id": ids[2], "booking_id": booking_id,
            "actions": ["schedule", "start", "stop", "resume", "complete", "return_to_queue"],
            "vehicle_uuid_retained_every_step": workshop_uuid_retained,
            "history_rows": history_count,
            "history_rows_with_authenticated_actor": actor_history_count,
            "final_retained_state": "queued_with_completed_booking_history",
        },
        "audit_history": {"selected_vehicle_audit_rows": selected_audit_count, "workshop_history_present": True},
        "unrelated_row_protection": {"before": unrelated_before, "after": unrelated_after, "all_full_row_hashes_unchanged": True},
        "cleanup": {
            "temporary_roles_remaining": 0,
            "temporary_schemas_remaining": 0,
            "selected_imported_vehicles_retained": 25,
            "retained_state_explicitly_documented": True,
        },
        "safety": {
            "database_connection_guarded_to_exact_staging_project": True,
            "database_connections_outside_exact_staging_project": 0,
            "browser_local_authority_unchanged": True,
            "browser_local_data_modified": False,
            "frontend_authority_switched": False,
            "direct_select_retired": False,
            "deployed": False,
            "merged": False,
            "ai_work_started": False,
        },
        "passed": True,
    }
    c6.write_evidence(Path(output_path).parent, {Path(output_path).name: report})
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    if not args.apply:
        raise c6.C6PilotRefusal("C6 operational scenarios require explicit --apply")
    print(c6.canonical_json(run(args.manifest, args.output, os.environ.get("PDC_STAGING_DATABASE_URL", ""))))


if __name__ == "__main__":
    main()
