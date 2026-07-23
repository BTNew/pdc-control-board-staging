#!/usr/bin/env python3
"""Rollback-only regression proof for migration 045.

Uses the guarded staging connection, applies migration 045 inside one transaction,
creates synthetic UUID-only fixtures, proves the authority/reconciliation contract,
and always rolls back.
"""
from __future__ import annotations

import json
import sys
import uuid
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "_staging_test_tools"))
from staging_conn import get_conn  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql"
STATIONS = ["BUS_4X4", "TINT", "HOIST", "FITTING", "FABRICATION", "ELECTRICAL", "TYRE", "PIT_INSPECTION"]
ACTUAL_LEGACY_IDS = [
    "18e6b520-d3d0-434a-a4a6-9223b45b76af", "23bd4310-c542-44f5-a421-bf2ffbda9341",
    "2c800223-5901-4854-a190-07ac72db9b83", "781c3923-8a5d-4ea8-aa32-f9bd777008b0",
    "feba3549-dd9c-42bb-af65-d9ebda5c3579",
]
ACTUAL_EXPECTED = {
    ACTUAL_LEGACY_IDS[0]: ("D_AMBIGUOUS", "multiple_active_same_station_bookings", "HOIST", "PMB", 2, True, 0, 1),
    ACTUAL_LEGACY_IDS[1]: ("D_AMBIGUOUS", "active_status_booking_has_completion_markers", "HOIST", "PMB", 1, True, 0, 1),
    ACTUAL_LEGACY_IDS[2]: ("D_AMBIGUOUS", "multiple_active_same_station_bookings", "HOIST", "PMB", 2, True, 0, 1),
    ACTUAL_LEGACY_IDS[3]: ("D_AMBIGUOUS", "multiple_active_same_station_bookings", "HOIST", "PMB", 3, False, 0, 0),
    ACTUAL_LEGACY_IDS[4]: ("B_ACTIVE_BOOKING", "active_booking_represents_job", "FITTING", "PMB", 1, False, 0, 0),
}


def assert_true(value, message):
    if not value:
        raise AssertionError(message)


def main():
    conn = get_conn()
    cur = conn.cursor()
    result = {"migration": "045", "transaction_rolled_back": False, "checks": []}
    try:
        cur.execute("begin")
        cur.execute(MIGRATION.read_text(encoding="utf-8"))
        cur.execute(
            """select vehicle_id::text,classification,reason_code,canonical_station,current_location,
               (evidence->>'active_same_station_bookings')::int,(evidence->>'booking_completion_markers')::boolean,
               (evidence->>'open_equivalent_work_items')::int,(evidence->>'completed_equivalent_work_items')::int
               from public.preview_legacy_stage_reconciliation(%s::uuid[]) order by vehicle_id""",
            (ACTUAL_LEGACY_IDS,),
        )
        actual_preview = {row[0]: tuple(row[1:]) for row in cur.fetchall()}
        assert_true(actual_preview == ACTUAL_EXPECTED, f"actual five-record preview drifted: {actual_preview}")
        result["checks"].append("actual_five_record_preview_ids_and_classifications")

        cur.execute("select auth_user_id::text,email from public.pdc_user_roles where active and role='administrator' and auth_user_id is not null order by id limit 1")
        admin = cur.fetchone()
        assert_true(admin, "active staging administrator fixture required")
        cur.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)",
                    (admin[0], json.dumps({"sub": admin[0], "email": admin[1], "role": "authenticated"})))

        stage_ids = {}
        for stage in STATIONS + ["SUBLET"]:
            cur.execute("select id::text,work_key from public.workshop_stages where code=%s", (stage,))
            row = cur.fetchone()
            assert_true(row, f"missing stage {stage}")
            stage_ids[stage] = row

        def vehicle(stage, location="PMB", eta=None):
            vehicle_id = str(uuid.uuid4())
            cur.execute(
                "insert into public.vehicles(id,permanent_vehicle_id,current_location,pmb_stage,eta_to_kewdale,visible_on_board,source_payload) "
                "values(%s,%s,%s,%s,%s,true,'{}'::jsonb)",
                (vehicle_id, "M045-" + vehicle_id, location, stage, eta),
            )
            return vehicle_id

        def work(vehicle_id, stage, required=True, completed=False):
            work_id = str(uuid.uuid4())
            cur.execute(
                "insert into public.vehicle_work_items(id,vehicle_id,work_key,required,completed,completed_at) "
                "values(%s,%s,%s,%s,%s,case when %s then now() else null end)",
                (work_id, vehicle_id, stage_ids[stage][1], required, completed, completed),
            )
            return work_id

        def booking(vehicle_id, stage, start="2026-07-23 01:00:00+00", end="2026-07-23 04:00:00+00", completion_markers=False):
            booking_id = str(uuid.uuid4())
            cur.execute(
                "insert into public.workshop_bookings(id,vehicle_id,stage_id,status,scheduled_start_at,scheduled_end_at,"
                "default_duration_minutes,created_by,updated_by,actual_start_at,actual_end_at) "
                "values(%s,%s,%s,'planned',%s,%s,180,%s,%s,case when %s then %s::timestamptz else null end,"
                "case when %s then %s::timestamptz else null end)",
                (booking_id, vehicle_id, stage_ids[stage][0], start, end, admin[0], admin[0], completion_markers, start, completion_markers, end),
            )
            return booking_id

        def evidence(vehicle_id, stage):
            cur.execute(
                "insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata) "
                "values('move','vehicles',%s,%s,'{}'::jsonb,jsonb_build_object('pmb_stage',%s),'{}'::jsonb)",
                (vehicle_id, vehicle_id, stage),
            )

        # Required A/B/C/D classifier cases.
        a_hoist = vehicle("HOIST"); evidence(a_hoist, "HOIST")
        a_fitting = vehicle("FITTING"); evidence(a_fitting, "FITTING")
        c_open = vehicle("HOIST"); work(c_open, "HOIST")
        b_booked = vehicle("HOIST"); wb = work(b_booked, "HOIST"); booking(b_booked, "HOIST"); cur.execute("update public.vehicle_work_items set required=false where id=%s", (wb,))
        c_completed = vehicle("HOIST"); work(c_completed, "HOIST", completed=True)
        d_completed_booked = vehicle("HOIST"); dcb_work = work(d_completed_booked, "HOIST"); booking(d_completed_booked, "HOIST"); cur.execute("update public.vehicle_work_items set completed=true,completed_at=now() where id=%s", (dcb_work,))
        d_conflict = vehicle("HOIST"); wd = work(d_conflict, "HOIST"); booking(d_conflict, "HOIST"); booking(d_conflict, "HOIST", "2026-07-24 01:00:00+00", "2026-07-24 04:00:00+00"); cur.execute("update public.vehicle_work_items set required=false where id=%s", (wd,))
        ids = [a_hoist, a_fitting, c_open, b_booked, c_completed, d_completed_booked, d_conflict]
        cur.execute("select vehicle_id::text,classification,reason_code from public.preview_legacy_stage_reconciliation(%s::uuid[])", (ids,))
        preview = {r[0]: (r[1], r[2]) for r in cur.fetchall()}
        assert_true(preview[a_hoist][0] == "A_SAFE_CREATE", "Hoist A classification")
        assert_true(preview[a_fitting][0] == "A_SAFE_CREATE", "Fitting A classification")
        assert_true(preview[c_open] == ("C_COMPLETED_OR_OBSOLETE", "canonical_open_work_item_exists"), "open item no-duplicate classification")
        assert_true(preview[b_booked] == ("B_ACTIVE_BOOKING", "active_booking_represents_job"), "booking classification")
        assert_true(preview[c_completed] == ("C_COMPLETED_OR_OBSOLETE", "completed_equivalent_work_exists"), "completed classification")
        assert_true(preview[d_completed_booked] == ("D_AMBIGUOUS", "completed_work_conflicts_with_active_booking"), "completed work plus active booking must be ambiguous")
        assert_true(preview[d_conflict][0] == "D_AMBIGUOUS", "ambiguous classification")
        result["checks"].append("deterministic_A_B_C_D_preview")

        batch = "m045-regression-" + uuid.uuid4().hex
        cur.execute("select public.apply_legacy_stage_reconciliation(%s,%s::uuid[])", (batch, ids))
        first = cur.fetchone()[0]
        cur.execute("select public.apply_legacy_stage_reconciliation(%s,%s::uuid[])", (batch, ids))
        second = cur.fetchone()[0]
        assert_true(first == second, "idempotent replay response")
        cur.execute("select count(*),count(*) filter(where decision_state='applied'),count(*) filter(where decision_state='ambiguous') from public.legacy_stage_reconciliation_receipts where batch_id=%s", (batch,))
        assert_true(cur.fetchone() == (7, 2, 2), "receipt cardinality/state")
        cur.execute("select max(created_at) from public.legacy_stage_reconciliation_receipts where batch_id=%s", (batch,))
        assert_true(cur.fetchone()[0] is not None, "finalize receipt timestamp must use created_at")
        cur.execute("select exists(select 1 from information_schema.columns where table_schema='public' and table_name='legacy_stage_reconciliation_receipts' and column_name='applied_at')")
        assert_true(cur.fetchone()[0] is False, "receipt schema unexpectedly exposes stale applied_at column")
        result["checks"].append("finalize_uses_real_receipt_created_at_column")
        cur.execute("select count(*) from public.vehicle_work_items where id in (select applied_work_item_id from public.legacy_stage_reconciliation_receipts where batch_id=%s)", (batch,))
        assert_true(cur.fetchone()[0] == 2, "only A creates work items")
        cur.execute("select count(*) from public.audit_events where metadata->>'source'='legacy_pmb_stage_reconciliation' and metadata->>'batch_id'=%s", (batch,))
        assert_true(cur.fetchone()[0] == 2, "apply audit events")
        result["checks"].append("idempotent_apply_duplicate_prevention_receipts_audit")

        cur.execute("select public.rollback_legacy_stage_reconciliation(%s)", (batch,))
        rollback_first = cur.fetchone()[0]
        cur.execute("select public.rollback_legacy_stage_reconciliation(%s)", (batch,))
        rollback_second = cur.fetchone()[0]
        assert_true(rollback_first == rollback_second and rollback_first["rolled_back"] == 2, "idempotent rollback")
        cur.execute("select count(*) from public.vehicle_work_items wi join public.legacy_stage_reconciliation_receipts r on r.applied_work_item_id=wi.id where r.batch_id=%s and wi.required", (batch,))
        assert_true(cur.fetchone()[0] == 0, "rollback disables without deleting")
        cur.execute("select count(*) from public.audit_events where metadata->>'source'='legacy_pmb_stage_reconciliation_rollback' and metadata->>'batch_id'=%s", (batch,))
        assert_true(cur.fetchone()[0] == 2, "rollback audit events")
        result["checks"].append("non_destructive_idempotent_rollback")

        # PMB/YH/IT and all-eight-station canonical authority.
        eligibility = {}
        for station in STATIONS:
            vid = vehicle(station, "PMB"); work(vid, station); eligibility[station] = vid
        yh = vehicle("HOIST", "YH"); work(yh, "HOIST")
        it_ok = vehicle("HOIST", "IT", date(2026, 7, 24)); work(it_ok, "HOIST")
        it_missing = vehicle("HOIST", "IT"); work(it_missing, "HOIST")
        other = vehicle("HOIST", "OTHER"); work(other, "HOIST")
        for station, vid in eligibility.items():
            cur.execute("select vehicle_id::text from public.workshop_station_eligibility(%s) where vehicle_id=%s", (station, vid))
            assert_true(cur.fetchone() == (vid,), f"canonical candidate missing for {station}")
        cur.execute("select vehicle_id::text,schedule_enabled,disabled_reason from public.workshop_station_eligibility('HOIST') where vehicle_id=any(%s::uuid[])", ([yh, it_ok, it_missing, other],))
        loc = {r[0]: (r[1], r[2]) for r in cur.fetchall()}
        assert_true(loc[yh] == (True, None), "YH immediate")
        assert_true(loc[it_ok] == (True, None), "IT valid ETA")
        assert_true(loc[it_missing] == (False, "missing_eta"), "IT missing ETA visible but disabled")
        assert_true(other not in loc, "other location excluded")

        mutation_vehicle = vehicle("HOIST", "PMB"); mutation_work = work(mutation_vehicle, "HOIST"); mutation_booking = booking(mutation_vehicle, "HOIST")
        cur.execute("update public.vehicle_work_items set required=false where id=%s", (mutation_work,))
        for target in (None, "HOIST"):
            cur.execute("savepoint canonical_booking_guard")
            blocked = False
            try:
                cur.execute("select public.workshop_require_booking_schedule_eligibility(%s,%s)", (mutation_booking, target))
            except Exception:
                blocked = True
                cur.execute("rollback to savepoint canonical_booking_guard")
            cur.execute("release savepoint canonical_booking_guard")
            assert_true(blocked, "same-station booking mutation survived completed/missing canonical requirement")
        result["checks"].append("same_station_move_resize_bay_change_require_current_work")

        # Exercise the real atomic cascade path: a queued booking without a
        # current work requirement must make the whole cascade fail before any
        # timestamp/history change survives.
        cur.execute("select b.id::text,b.bay_number from public.workshop_bays b join public.workshop_stages s on s.id=b.stage_id where s.code='HOIST' and b.is_active order by b.bay_number limit 1")
        cascade_bay = cur.fetchone()
        assert_true(cascade_bay, "active Hoist bay required for cascade fixture")
        shifted_vehicle = vehicle("HOIST", "PMB"); shifted_work = work(shifted_vehicle, "HOIST")
        shifted_booking = str(uuid.uuid4())
        cur.execute(
            "insert into public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by) "
            "values(%s,%s,%s,%s,'planned','2036-07-23 01:00:00+00','2036-07-23 04:00:00+00',180,%s,%s)",
            (shifted_booking, shifted_vehicle, stage_ids["HOIST"][0], cascade_bay[0], admin[0], admin[0]),
        )
        cur.execute("update public.vehicle_work_items set required=false where id=%s", (shifted_work,))
        cascade_target = vehicle("HOIST", "PMB"); work(cascade_target, "HOIST")
        cur.execute("select version from public.vehicles where id=%s", (cascade_target,)); target_version = cur.fetchone()[0]
        cur.execute("select scheduled_start_at,scheduled_end_at,version from public.workshop_bookings where id=%s", (shifted_booking,)); cascade_before = cur.fetchone()
        cur.execute("select count(*) from public.workshop_booking_history where booking_id=%s", (shifted_booking,)); history_before = cur.fetchone()[0]
        cur.execute("savepoint canonical_cascade_guard")
        cascade_blocked = False
        try:
            cur.execute(
                "select public.cascade_workshop_schedule('insert',%s,%s,'HOIST',%s,'2036-07-23 01:00:00+00',180,null,180,%s,'{}'::jsonb)",
                (cascade_target, target_version, cascade_bay[1], "rollback-only canonical authority test"),
            )
        except Exception:
            cascade_blocked = True
            cur.execute("rollback to savepoint canonical_cascade_guard")
        cur.execute("release savepoint canonical_cascade_guard")
        cur.execute("select scheduled_start_at,scheduled_end_at,version from public.workshop_bookings where id=%s", (shifted_booking,)); cascade_after = cur.fetchone()
        cur.execute("select count(*) from public.workshop_booking_history where booking_id=%s", (shifted_booking,)); history_after = cur.fetchone()[0]
        assert_true(cascade_blocked, "cascade shifted a booking without current canonical work")
        assert_true(cascade_after == cascade_before and history_after == history_before, "blocked cascade left timestamp/version/history changes")
        result["checks"].append("cascade_shifts_require_current_work_and_are_atomic")

        cur.execute("select count(*) from public.workshop_station_eligibility('SUBLET')")
        assert_true(cur.fetchone()[0] == 0, "Sublet planner excluded")
        result["checks"].append("pmb_yh_it_eta_all_eight_sublet")

        # Legacy pmb_stage alone is never authority.
        legacy_only = vehicle("TYRE", "PMB"); evidence(legacy_only, "TYRE")
        cur.execute("select count(*) from public.workshop_station_eligibility('TYRE') where vehicle_id=%s", (legacy_only,))
        assert_true(cur.fetchone()[0] == 0, "legacy stage leaked into eligibility")
        result["checks"].append("legacy_stage_not_authority")

        # Realtime station revision creation/removal and separate count semantics.
        rev_vehicle = vehicle("PIT_INSPECTION", "PMB")
        cur.execute("select revision from public.workshop_station_revision where stage_code='PIT_INSPECTION'")
        before_rev = cur.fetchone()[0]
        rev_work = work(rev_vehicle, "PIT_INSPECTION")
        cur.execute("select revision from public.workshop_station_revision where stage_code='PIT_INSPECTION'")
        created_rev = cur.fetchone()[0]
        cur.execute("update public.vehicle_work_items set required=false,updated_at=now() where id=%s", (rev_work,))
        cur.execute("select revision from public.workshop_station_revision where stage_code='PIT_INSPECTION'")
        removed_rev = cur.fetchone()[0]
        assert_true(before_rev < created_rev < removed_rev, "station revision did not invalidate on requirement create/remove")
        result["checks"].append("realtime_revision_requirement_create_remove")

        # Date-independent outstanding candidates versus selected-date bookings.
        count_a = vehicle("FABRICATION", "PMB"); work(count_a, "FABRICATION"); work(count_a, "SUBLET")
        count_b = vehicle("FABRICATION", "PMB"); work(count_b, "FABRICATION"); booking(count_b, "FABRICATION")
        grid_only = vehicle("FABRICATION", "PMB"); wg = work(grid_only, "FABRICATION"); booking(grid_only, "FABRICATION"); cur.execute("update public.vehicle_work_items set required=false where id=%s", (wg,))
        completed_grid = vehicle("FABRICATION", "PMB"); completed_grid_work = work(completed_grid, "FABRICATION"); completed_booking = booking(completed_grid, "FABRICATION")
        cur.execute("update public.vehicle_work_items set completed=true,completed_at=now() where id=%s", (completed_grid_work,))
        cur.execute("update public.workshop_bookings set status='completed',actual_start_at=scheduled_start_at,actual_end_at=scheduled_end_at where id=%s", (completed_booking,))
        cur.execute("select public.get_station_workshop_snapshot('FABRICATION','2026-07-23','2026-07-23')")
        snapshot = cur.fetchone()[0]
        candidate_ids = {x["vehicle_id"] for x in snapshot["outstanding_candidates"]}
        assert_true({count_a, count_b}.issubset(candidate_ids), "outstanding candidates not discoverable")
        assert_true(grid_only not in candidate_ids, "booking-only vehicle became outstanding candidate")
        count_a_row = next(x for x in snapshot["outstanding_candidates"] if x["vehicle_id"] == count_a)
        requirement_keys = {x["work_key"] for x in count_a_row["requirements"]}
        assert_true({stage_ids["FABRICATION"][1], stage_ids["SUBLET"][1]}.issubset(requirement_keys), "sanitized left-column requirements omitted Sublet")
        assert_true(all(set(x) == {"vehicle_id", "work_key", "required", "completed", "completed_at"} for x in count_a_row["requirements"]), "requirements DTO leaked fields")
        assert_true(snapshot["counts"]["outstanding_candidates"] >= 2, "outstanding count")
        assert_true(snapshot["counts"]["unscheduled_candidates"] >= 1, "unscheduled count")
        selected_ids = {x["vehicle_id"] for x in snapshot["bookings"]}
        assert_true({count_b, grid_only, completed_grid}.issubset(selected_ids), "selected-date grid booking set")
        assert_true(snapshot["counts"]["selected_date_bookings"] == len(snapshot["bookings"]), "selected-date authoritative count excludes completed booking")
        result["checks"].append("outstanding_unscheduled_selected_date_semantics")

        # Service-only reconciliation authority and sanitized durable data.
        cur.execute("select has_function_privilege('authenticated','public.preview_legacy_stage_reconciliation(uuid[])','execute'),has_function_privilege('authenticated','public.apply_legacy_stage_reconciliation(text,uuid[])','execute'),has_function_privilege('authenticated','public.rollback_legacy_stage_reconciliation(text)','execute'),has_table_privilege('authenticated','public.legacy_stage_reconciliation_receipts','select')")
        assert_true(cur.fetchone() == (False, False, False, False), "reconciliation privilege closure")
        cur.execute("select count(*) from public.legacy_stage_reconciliation_receipts where evidence ?| array['customer_name','notes','note_text']")
        assert_true(cur.fetchone()[0] == 0, "receipt contains prohibited fields")
        result["checks"].append("service_only_sanitized_receipts")

        conn.rollback()
        result["transaction_rolled_back"] = True
        result["status"] = "passed"
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        conn.rollback()
        result["transaction_rolled_back"] = True
        result["status"] = "failed"
        result["error"] = f"{type(exc).__name__}: {exc}"
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
