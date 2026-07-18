"""
Real PostgreSQL/PostgREST integration tests against the staging Supabase
project for the QC-complete -> RFT -> Collected workflow and the
notification outbox (migration 016). Uses real HTTP RPC calls (not mocks)
against the staging project, and cleans up its own synthetic fixture rows.
"""
import sys, uuid
sys.path.insert(0, '_staging_test_tools')
from staging_rest import sign_in, rpc
from staging_conn import get_conn
from staging_accounts import ADMIN_EMAIL, ADMIN_PW, CTRL_A_EMAIL, CTRL_A_PW, VIEWER_EMAIL, VIEWER_PW

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


admin_tok = token_for(ADMIN_EMAIL, ADMIN_PW)
ctrl_a_tok = token_for(CTRL_A_EMAIL, CTRL_A_PW)
viewer_tok = token_for(VIEWER_EMAIL, VIEWER_PW)

conn = get_conn()
cur = conn.cursor()

test_vehicle_id = None
salesperson_id = None

try:
    # --- fixture setup: a synthetic vehicle + salesperson, real DB rows ---
    salesperson_id = str(uuid.uuid4())
    cur.execute(
        "insert into public.salespeople (id, name, email, active) values (%s, %s, %s, true)",
        (salesperson_id, "QA Salesperson", "qa-salesperson@staging.pdc-workshop.example.com"),
    )
    test_vehicle_id = str(uuid.uuid4())
    cur.execute(
        """insert into public.vehicles (
             id, permanent_vehicle_id, stock_number, job_card_number, customer_name,
             salesperson_id, make, model, pmb_key_tag, current_location, pmb_stage,
             lifecycle_state, visible_on_board, version
           ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'active', true, 1)""",
        (
            test_vehicle_id, "QA-QC-RFT-001", "QA-QC-RFT-001", "JC-QA-001", "QA Test Customer",
            salesperson_id, "Toyota", "HiLux", "K-901", "PMB", "ELECTRICAL",
        ),
    )
    cur.execute(
        "insert into public.vehicle_work_items (vehicle_id, work_key, required, completed) values (%s, 'QC', true, false)",
        (test_vehicle_id,),
    )
    conn.commit()

    print("--- 1. viewer cannot QC-complete ---")
    status, body = rpc(viewer_tok, "qc_complete_vehicle", {
        "p_vehicle_id": test_vehicle_id, "p_expected_version": 1, "p_work_item_key": "QC",
    })
    check("1a viewer cannot call qc_complete_vehicle", status != 200 or (isinstance(body, dict) and body.get("ok") is False), f"{status} {body}")

    print("--- 2. qc_complete_vehicle atomically completes QC + work item + enqueues notification ---")
    status, body = rpc(ctrl_a_tok, "qc_complete_vehicle", {
        "p_vehicle_id": test_vehicle_id, "p_expected_version": 1, "p_work_item_key": "QC",
        "p_completed_summary": "Final electrical test",
    })
    check("2a qc_complete_vehicle succeeds", status == 200 and body.get("ok") is True, f"{status} {body}")
    notification_id = body.get("notification_id") if status == 200 and body.get("ok") else None
    check("2b notification enqueued with a recipient (salesperson email present)", body.get("notification_has_recipient") is True, str(body)[:300])
    veh_version_after_qc = body.get("vehicle", {}).get("version") if status == 200 else None
    check("2c vehicle version incremented", veh_version_after_qc == 2, f"{veh_version_after_qc}")

    cur.execute("select completed from public.vehicle_work_items where vehicle_id = %s and work_key = 'QC'", (test_vehicle_id,))
    row = cur.fetchone()
    check("2d QC work item marked completed", row is not None and row[0] is True, str(row))

    cur.execute("select status, subject, recipient_email, idempotency_key from public.vehicle_notifications where vehicle_id = %s", (test_vehicle_id,))
    notif_rows = cur.fetchall()
    check("2e exactly one notification row created", len(notif_rows) == 1, str(notif_rows))
    check("2f notification idempotency key is vehicle-scoped", notif_rows and notif_rows[0][3] == f"qc_complete:{test_vehicle_id}", str(notif_rows))
    check("2g notification recipient is the vehicle's salesperson", notif_rows and notif_rows[0][2] == "qa-salesperson@staging.pdc-workshop.example.com", str(notif_rows))

    print("--- 3. double-click / retry does not create a duplicate notification ---")
    status, body = rpc(ctrl_a_tok, "qc_complete_vehicle", {
        "p_vehicle_id": test_vehicle_id, "p_expected_version": veh_version_after_qc, "p_work_item_key": "QC",
    })
    check("3a second qc_complete_vehicle call reports already_qc_complete, not a fresh success", status == 200 and body.get("ok") is False and body.get("error") == "already_qc_complete", f"{status} {body}")
    cur.execute("select count(*) from public.vehicle_notifications where vehicle_id = %s", (test_vehicle_id,))
    check("3b still exactly one notification row after retry", cur.fetchone()[0] == 1, "")

    print("--- 4. rft_transfer_vehicle requires QC complete and moves lifecycle_state ---")
    other_vehicle_id = str(uuid.uuid4())
    cur.execute(
        """insert into public.vehicles (id, permanent_vehicle_id, stock_number, lifecycle_state, visible_on_board, version)
           values (%s, %s, %s, 'active', true, 1)""",
        (other_vehicle_id, "QA-QC-RFT-002", "QA-QC-RFT-002"),
    )
    conn.commit()
    status, body = rpc(ctrl_a_tok, "rft_transfer_vehicle", {"p_vehicle_id": other_vehicle_id, "p_expected_version": 1})
    check("4a RFT transfer rejected without QC complete", status == 200 and body.get("ok") is False and body.get("error") == "qc_not_complete", f"{status} {body}")

    status, body = rpc(ctrl_a_tok, "rft_transfer_vehicle", {"p_vehicle_id": test_vehicle_id, "p_expected_version": veh_version_after_qc})
    check("4b RFT transfer succeeds once QC is complete", status == 200 and body.get("ok") is True, f"{status} {body}")
    veh_version_after_rft = body.get("vehicle", {}).get("version") if status == 200 else None
    check("4c lifecycle_state is rft", body.get("vehicle", {}).get("lifecycle_state") == "rft", str(body)[:300])
    check("4d current_location is RFT", body.get("vehicle", {}).get("current_location") == "RFT", str(body)[:300])

    print("--- 5. viewer cannot collect ---")
    status, body = rpc(viewer_tok, "rft_collect_vehicle", {"p_vehicle_id": test_vehicle_id, "p_expected_version": veh_version_after_rft})
    check("5a viewer cannot call rft_collect_vehicle", status != 200 or (isinstance(body, dict) and body.get("ok") is False), f"{status} {body}")

    print("--- 6. rft_collect_vehicle atomically moves RFT -> Completed ---")
    status, body = rpc(ctrl_a_tok, "rft_collect_vehicle", {"p_vehicle_id": test_vehicle_id, "p_expected_version": veh_version_after_rft})
    check("6a rft_collect_vehicle succeeds", status == 200 and body.get("ok") is True, f"{status} {body}")
    check("6b lifecycle_state is completed", body.get("vehicle", {}).get("lifecycle_state") == "completed", str(body)[:300])
    check("6c vehicle hidden from active board (visible_on_board=false)", body.get("vehicle", {}).get("visible_on_board") is False, str(body)[:300])
    veh_version_after_collect = body.get("vehicle", {}).get("version") if status == 200 else None

    print("--- 7. duplicate collection is rejected, not double-processed ---")
    status, body = rpc(ctrl_a_tok, "rft_collect_vehicle", {"p_vehicle_id": test_vehicle_id, "p_expected_version": veh_version_after_collect})
    check("7a second collect call reports already_collected", status == 200 and body.get("ok") is False and body.get("error") == "already_collected", f"{status} {body}")

    print("--- 8. stale version is rejected on every new RPC ---")
    status, body = rpc(ctrl_a_tok, "qc_complete_vehicle", {"p_vehicle_id": other_vehicle_id, "p_expected_version": 999, "p_work_item_key": "QC"})
    check("8a stale version rejected on qc_complete_vehicle", status == 200 and body.get("ok") is False and body.get("error") == "vehicle_version_conflict", f"{status} {body}")

    print("--- 9. notification worker claim/mark-result lifecycle ---")
    cur.execute("select claim_pending_vehicle_notifications from public.claim_pending_vehicle_notifications(50) where (claim_pending_vehicle_notifications).vehicle_id = %s", (test_vehicle_id,))
    claimed = cur.fetchall()
    check("9a service-role worker can claim the pending notification", len(claimed) == 1, str(claimed))
    cur.execute("select mark_vehicle_notification_result from public.mark_vehicle_notification_result(%s, true, null)", (notification_id,))
    conn.commit()
    cur.execute("select status, sent_at, attempts from public.vehicle_notifications where id = %s", (notification_id,))
    row = cur.fetchone()
    check("9b marking success sets status=sent with a timestamp", row is not None and row[0] == "sent" and row[1] is not None and row[2] == 1, str(row))

    print("--- 10. failed delivery + admin retry ---")
    retry_notification_id = str(uuid.uuid4())
    cur.execute(
        """insert into public.vehicle_notifications (id, vehicle_id, notification_type, idempotency_key, subject, body, status, attempts, max_attempts)
           values (%s, %s, 'test', %s, 'test', 'test', 'pending', 4, 5)""",
        (retry_notification_id, test_vehicle_id, f"retry-test:{test_vehicle_id}"),
    )
    conn.commit()
    cur.execute("select mark_vehicle_notification_result from public.mark_vehicle_notification_result(%s, false, 'smtp timeout')", (retry_notification_id,))
    conn.commit()
    cur.execute("select status, attempts, last_error from public.vehicle_notifications where id = %s", (retry_notification_id,))
    row = cur.fetchone()
    check("10a exhausting max_attempts marks the notification failed with the error recorded", row is not None and row[0] == "failed" and row[1] == 5 and row[2] == "smtp timeout", str(row))

    status, body = rpc(ctrl_a_tok, "retry_vehicle_notification", {"p_notification_id": retry_notification_id})
    check("10b non-administrator cannot retry a failed notification", status != 200 or (isinstance(body, dict) and body.get("ok") is False), f"{status} {body}")

    status, body = rpc(admin_tok, "retry_vehicle_notification", {"p_notification_id": retry_notification_id, "p_recipient_email": "corrected@staging.pdc-workshop.example.com"})
    check("10c administrator can retry with a corrected recipient", status == 200 and body.get("ok") is True, f"{status} {body}")
    cur.execute("select status, recipient_email from public.vehicle_notifications where id = %s", (retry_notification_id,))
    row = cur.fetchone()
    check("10d retry resets status to pending and updates the recipient", row == ("pending", "corrected@staging.pdc-workshop.example.com"), str(row))

    print("--- 11. missing salesperson email is visibly flagged, state is still preserved ---")
    no_sales_vehicle_id = str(uuid.uuid4())
    cur.execute(
        """insert into public.vehicles (id, permanent_vehicle_id, stock_number, lifecycle_state, visible_on_board, version)
           values (%s, %s, %s, 'active', true, 1)""",
        (no_sales_vehicle_id, "QA-QC-RFT-003", "QA-QC-RFT-003"),
    )
    conn.commit()
    status, body = rpc(ctrl_a_tok, "qc_complete_vehicle", {"p_vehicle_id": no_sales_vehicle_id, "p_expected_version": 1, "p_work_item_key": "QC"})
    check("11a QC completes even with no salesperson mapped", status == 200 and body.get("ok") is True, f"{status} {body}")
    check("11b notification_has_recipient is false so the frontend can flag it", body.get("notification_has_recipient") is False, str(body)[:300])
    cur.execute("delete from public.vehicles where id = %s", (no_sales_vehicle_id,))
    conn.commit()

finally:
    try:
        conn.rollback()
    except Exception:
        pass
    try:
        if test_vehicle_id:
            cur.execute("delete from public.vehicle_notifications where vehicle_id = %s", (test_vehicle_id,))
            cur.execute("delete from public.vehicle_movements where vehicle_id = %s", (test_vehicle_id,))
            cur.execute("delete from public.vehicle_work_items where vehicle_id = %s", (test_vehicle_id,))
            cur.execute("delete from public.audit_events where vehicle_id = %s", (test_vehicle_id,))
            cur.execute("delete from public.vehicles where id = %s", (test_vehicle_id,))
        if 'other_vehicle_id' in dir() and other_vehicle_id:
            cur.execute("delete from public.vehicle_movements where vehicle_id = %s", (other_vehicle_id,))
            cur.execute("delete from public.audit_events where vehicle_id = %s", (other_vehicle_id,))
            cur.execute("delete from public.vehicles where id = %s", (other_vehicle_id,))
        if salesperson_id:
            cur.execute("delete from public.salespeople where id = %s", (salesperson_id,))
        conn.commit()
    except Exception as cleanup_error:
        print("CLEANUP WARNING:", cleanup_error)
        conn.rollback()
    conn.close()

print(f"\nTOTAL: {PASSED} passed, {FAILED} failed")
if FAILURES:
    print("FAILURES:")
    for name, detail in FAILURES:
        print(f" - {name}: {detail}")
    sys.exit(1)
