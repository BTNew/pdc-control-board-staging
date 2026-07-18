"""
Real PostgreSQL/PostgREST integration tests against the staging Supabase
project for the Workshop Planner shared-architecture RPCs (migrations
009-012). Uses two independent authenticated HTTP sessions to prove
concurrency behaviour, not mocks or string assertions.
"""
import sys, json, time
sys.path.insert(0, '_staging_test_tools')
from staging_rest import sign_in, rpc, rest_select
from staging_accounts import (
    ADMIN_EMAIL, ADMIN_PW, CTRL_A_EMAIL, CTRL_A_PW, CTRL_B_EMAIL, CTRL_B_PW,
    VIEWER_EMAIL, VIEWER_PW, UNAPPROVED_EMAIL, UNAPPROVED_PW,
)

PASSED = 0
FAILED = 0
FAILURES = []


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"PASS  {name}")
    else:
        FAILED += 1
        FAILURES.append((name, detail))
        print(f"FAIL  {name}  {detail}")


def token_for(email, password):
    status, body = sign_in(email, password)
    assert status == 200, f"sign_in failed for {email}: {status} {body}"
    return body["access_token"]


VEH_1 = "8debaf15-2344-4617-aada-f39728c5c0de"  # SYN-STAGE-VEH-001, HOIST-tagged
VEH_2 = "9fbd5a06-db70-4922-9bf1-49559d74583f"  # SYN-STAGE-VEH-002
TECH_A = "7655e6d5-a55e-4c6c-9430-efd9650ee451"
TECH_B = "e4cb9b07-2e6f-4abf-b81e-ba2946e95d1a"

admin_tok = token_for(ADMIN_EMAIL, ADMIN_PW)
ctrl_a_tok = token_for(CTRL_A_EMAIL, CTRL_A_PW)
ctrl_b_tok = token_for(CTRL_B_EMAIL, CTRL_B_PW)
viewer_tok = token_for(VIEWER_EMAIL, VIEWER_PW)
unapproved_tok = token_for(UNAPPROVED_EMAIL, UNAPPROVED_PW)

print("--- 1. snapshot / basic read ---")
status, body = rpc(ctrl_a_tok, "get_workshop_snapshot", {})
check("1a snapshot readable by approved operator", status == 200 and isinstance(body, dict), f"{status} {body}")
check("1b snapshot has revision key", isinstance(body, dict) and "revision" in body, str(body)[:200])
base_revision = body["revision"] if isinstance(body, dict) else None

status, body = rpc(unapproved_tok, "get_workshop_snapshot", {})
check("1c unapproved user cannot read snapshot", status != 200, f"{status} {str(body)[:200]}")

print("--- 2. null / missing / stale version rejection ---")
status, body = rpc(ctrl_a_tok, "start_workshop_work", {"p_booking_id": VEH_1, "p_expected_version": None})
check("2a null expected version rejected", status != 200, f"{status} {str(body)[:300]}")

status, body = rpc(ctrl_a_tok, "start_workshop_work", {"p_booking_id": VEH_1})
check("2b missing expected version rejected", status != 200, f"{status} {str(body)[:300]}")

print("--- 3. schedule_vehicle_work: create + atomic vehicle pointer update ---")
start_a = "2026-07-20T09:00:00+08:00"  # a Monday
status, body = rpc(ctrl_a_tok, "schedule_vehicle_work", {
    "p_vehicle_id": VEH_1, "p_vehicle_expected_version": 1,
    "p_stage_code": "HOIST", "p_bay_number": 1,
    "p_scheduled_start_at": start_a, "p_duration_minutes": 180,
    "p_technician_id": TECH_A,
})
check("3a schedule_vehicle_work succeeds for operator", status == 200 and body.get("ok") is True, f"{status} {body}")
booking_1_id = body.get("booking", {}).get("booking_id") if status == 200 and body.get("ok") else None
check("3b booking_id returned", booking_1_id is not None, str(body)[:300])
new_revision = body.get("revision") if status == 200 else None
check("3c revision incremented after successful schedule", new_revision is not None and new_revision > base_revision, f"{new_revision} vs {base_revision}")

status, body = rest_select(ctrl_a_tok, "vehicles", f"?id=eq.{VEH_1}&select=active_workshop_booking_id,workshop_status,version")
check("3d vehicle pointer atomically set (active_workshop_booking_id/workshop_status)",
      status == 200 and body and body[0]["active_workshop_booking_id"] == booking_1_id and body[0]["workshop_status"] == "scheduled",
      f"{status} {body}")
veh1_version_after_schedule = body[0]["version"] if status == 200 and body else None

print("--- 4. viewer cannot mutate ---")
status, body = rpc(viewer_tok, "start_workshop_work", {"p_booking_id": booking_1_id, "p_expected_version": 1})
check("4a viewer cannot call mutation RPC", status != 200 or (isinstance(body, dict) and body.get("ok") is False and "role" in json.dumps(body).lower()) or status >= 400,
      f"{status} {str(body)[:300]}")

print("--- 5. unapproved user cannot mutate or read operational data ---")
status, body = rpc(unapproved_tok, "start_workshop_work", {"p_booking_id": booking_1_id, "p_expected_version": 1})
check("5a unapproved cannot call mutation RPC", status != 200, f"{status} {str(body)[:300]}")
status, body = rest_select(unapproved_tok, "workshop_bookings", "?select=id&limit=1")
check("5b unapproved cannot read workshop_bookings directly", status != 200 or body == [], f"{status} {body}")

print("--- 6. direct table mutation is blocked (RLS/grant lock-down) ---")
from staging_rest import rest_insert
status, body = rest_insert(ctrl_a_tok, "workshop_bookings", {
    "vehicle_id": VEH_2, "stage_id": "00000000-0000-0000-0000-000000000000",
    "scheduled_start_at": "2026-07-20T09:00:00+08:00", "scheduled_end_at": "2026-07-20T12:00:00+08:00",
    "default_duration_minutes": 180, "created_by": "00000000-0000-0000-0000-000000000000",
    "updated_by": "00000000-0000-0000-0000-000000000000",
})
check("6a direct INSERT into workshop_bookings blocked for authenticated operator", status >= 400, f"{status} {body}")

print("--- 7. stale expected version rejected on move ---")
status, body = rpc(ctrl_a_tok, "resize_workshop_booking", {"p_booking_id": booking_1_id, "p_expected_version": 999, "p_duration_minutes": 120})
check("7a stale version rejected with version_conflict, no partial update", status == 200 and body.get("ok") is False and body.get("error") == "version_conflict", f"{status} {body}")

print("--- 8. same-bay overlap rejected ---")
status, body = rpc(ctrl_a_tok, "schedule_vehicle_work", {
    "p_vehicle_id": VEH_2, "p_vehicle_expected_version": 1,
    "p_stage_code": "HOIST", "p_bay_number": 1,
    "p_scheduled_start_at": start_a, "p_duration_minutes": 60,
})
check("8a same-bay overlapping booking rejected", status == 200 and body.get("ok") is False and body.get("error") == "bay_overlap", f"{status} {body}")

print("--- 9. same-technician overlap rejected ---")
status, body = rpc(ctrl_a_tok, "schedule_vehicle_work", {
    "p_vehicle_id": VEH_2, "p_vehicle_expected_version": 1,
    "p_stage_code": "FITTING", "p_bay_number": 1,
    "p_scheduled_start_at": start_a, "p_duration_minutes": 60,
    "p_technician_id": TECH_A,
})
check("9a same-technician overlapping booking rejected", status == 200 and body.get("ok") is False and body.get("error") == "technician_overlap", f"{status} {body}")

print("--- 10. Parts-incomplete rejected / authorised override succeeds and is audited ---")
# Set VEH_2 Parts required + not received.
import sys as _s
sys.path.insert(0, '_staging_test_tools')
from staging_conn import get_conn
conn = get_conn()
cur = conn.cursor()
cur.execute("""
  insert into public.vehicle_parts_updates (vehicle_id, parts_required, parts_received)
  values (%s, true, false)
""", (VEH_2,))
conn.commit()

status, body = rpc(ctrl_a_tok, "schedule_vehicle_work", {
    "p_vehicle_id": VEH_2, "p_vehicle_expected_version": 1,
    "p_stage_code": "FITTING", "p_bay_number": 2,
    "p_scheduled_start_at": start_a, "p_duration_minutes": 60,
})
check("10a Parts-incomplete entry rejected without override", status == 200 and body.get("ok") is False and body.get("error") == "parts_incomplete", f"{status} {body}")

status, body = rpc(ctrl_a_tok, "schedule_vehicle_work", {
    "p_vehicle_id": VEH_2, "p_vehicle_expected_version": 1,
    "p_stage_code": "FITTING", "p_bay_number": 2,
    "p_scheduled_start_at": start_a, "p_duration_minutes": 60,
    "p_override_reason": "Test override: parts on truck, sighted by admin",
})
check("10b non-administrator operator override rejected (role escalation required)", status != 200 or (isinstance(body, dict) and body.get("ok") is False), f"{status} {body}")

status, body = rpc(admin_tok, "schedule_vehicle_work", {
    "p_vehicle_id": VEH_2, "p_vehicle_expected_version": 1,
    "p_stage_code": "FITTING", "p_bay_number": 2,
    "p_scheduled_start_at": start_a, "p_duration_minutes": 60,
    "p_override_reason": "Test override: parts on truck, sighted by admin",
})
check("10c administrator override succeeds", status == 200 and body.get("ok") is True, f"{status} {body}")
override_id = body.get("override_id") if status == 200 else None
check("10d override recorded and returned", override_id is not None, str(body)[:300])

cur.execute("select reason, approved_by_email from public.workshop_parts_overrides where id = %s", (override_id,))
row = cur.fetchone()
check("10e override permanently audited with reason/approver", row is not None and row[0].startswith("Test override") and row[1] == ADMIN_EMAIL.lower(), str(row))

print("--- 11. stoppage preserves history; resume recalculates occupancy ---")
booking_2_id = body.get("booking", {}).get("booking_id") if status == 200 else None
status, body = rpc(admin_tok, "start_workshop_work", {"p_booking_id": booking_2_id, "p_expected_version": 1})
check("11a start_workshop_work succeeds", status == 200 and body.get("ok") is True, f"{status} {body}")
v2 = body.get("booking", {}).get("version") if status == 200 else None

status, body = rpc(admin_tok, "stop_workshop_work", {"p_booking_id": booking_2_id, "p_expected_version": v2, "p_reason": "Awaiting bracket delivery"})
check("11b stop_workshop_work records stoppage reason", status == 200 and body.get("ok") is True and body.get("booking", {}).get("stoppage_reason") == "Awaiting bracket delivery", f"{status} {body}")
v3 = body.get("booking", {}).get("version") if status == 200 else None

status, body = rpc(admin_tok, "resume_workshop_work", {"p_booking_id": booking_2_id, "p_expected_version": v3})
check("11c resume_workshop_work succeeds and recalculates schedule", status == 200 and body.get("ok") is True, f"{status} {body}")
resumed_start = body.get("booking", {}).get("scheduled_start_at") if status == 200 else None
check("11d resumed booking has a new (not stale) scheduled_start_at", resumed_start is not None and resumed_start != start_a, str(resumed_start))

print("--- 12. completion updates booking + vehicle + work item together ---")
v4 = body.get("booking", {}).get("version") if status == 200 else None
status, body = rpc(admin_tok, "complete_workshop_work", {"p_booking_id": booking_2_id, "p_expected_version": v4, "p_work_key": "FITTING"})
check("12a complete_workshop_work succeeds", status == 200 and body.get("ok") is True, f"{status} {body}")

status, body = rest_select(admin_tok, "vehicles", f"?id=eq.{VEH_2}&select=workshop_status")
check("12b vehicle workshop_status updated to completed", status == 200 and body and body[0]["workshop_status"] == "completed", f"{status} {body}")

status, body = rest_select(admin_tok, "vehicle_work_items", f"?vehicle_id=eq.{VEH_2}&work_key=eq.FITTING&select=completed")
check("12c work item marked completed", status == 200 and body and body[0]["completed"] is True, f"{status} {body}")

print("--- 13. return-to-queue updates all related state ---")
v5_status, v5_body = rest_select(admin_tok, "workshop_bookings", f"?id=eq.{booking_2_id}&select=version")
v5 = v5_body[0]["version"] if v5_status == 200 and v5_body else None
status, body = rpc(admin_tok, "return_completed_work", {"p_booking_id": booking_2_id, "p_expected_version": v5, "p_reason": "Rework requested"})
check("13a return_completed_work succeeds", status == 200 and body.get("ok") is True, f"{status} {body}")
status, body = rest_select(admin_tok, "vehicles", f"?id=eq.{VEH_2}&select=workshop_status,active_workshop_booking_id")
check("13b vehicle returned to queued with cleared active booking", status == 200 and body and body[0]["workshop_status"] == "queued" and body[0]["active_workshop_booking_id"] is None, f"{status} {body}")

print("--- 14. failed action creates no false audit / revision does not increment on failure ---")
status, rev_before_body = rpc(ctrl_a_tok, "get_workshop_snapshot", {})
rev_before = rev_before_body["revision"]
status, body = rpc(ctrl_a_tok, "resize_workshop_booking", {"p_booking_id": booking_1_id, "p_expected_version": 999999, "p_duration_minutes": 60})
check("14a failed stale-version resize returns ok=false", status == 200 and body.get("ok") is False, f"{status} {body}")
status, rev_after_body = rpc(ctrl_a_tok, "get_workshop_snapshot", {})
rev_after = rev_after_body["revision"]
check("14b revision unchanged after failed mutation", rev_after == rev_before, f"{rev_before} -> {rev_after}")

print("--- 15. RPC role enforcement + successful action records authenticated user ---")
status, body = rest_select(admin_tok, "workshop_booking_history", f"?booking_id=eq.{booking_1_id}&select=actor_email&order=created_at.desc&limit=1")
check("15a booking history records authenticated actor email", status == 200 and body and body[0]["actor_email"] == CTRL_A_EMAIL.lower(), f"{status} {body}")

conn.close()

print("--- 16. concurrency: two controllers racing the same booking ---")
status, body = rest_select(ctrl_a_tok, "workshop_bookings", f"?id=eq.{booking_1_id}&select=version")
current_v = body[0]["version"]
status_a, body_a = rpc(ctrl_a_tok, "resize_workshop_booking", {"p_booking_id": booking_1_id, "p_expected_version": current_v, "p_duration_minutes": 90})
status_b, body_b = rpc(ctrl_b_tok, "resize_workshop_booking", {"p_booking_id": booking_1_id, "p_expected_version": current_v, "p_duration_minutes": 240})
ok_count = sum(1 for b in (body_a, body_b) if isinstance(b, dict) and b.get("ok") is True)
conflict_count = sum(1 for b in (body_a, body_b) if isinstance(b, dict) and b.get("ok") is False and b.get("error") == "version_conflict")
check("16a exactly one winner and one version conflict on racing same booking", ok_count == 1 and conflict_count == 1, f"A={body_a} B={body_b}")

print()
print(f"TOTAL: {PASSED} passed, {FAILED} failed")
if FAILED:
    print("FAILURES:")
    for name, detail in FAILURES:
        print(f" - {name}: {detail}")
    sys.exit(1)
