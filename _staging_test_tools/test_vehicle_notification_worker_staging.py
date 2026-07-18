"""
Real (non-mocked) staging integration test for backend/vehicle_notification_worker.py.
Inserts a synthetic pending notification, runs the actual worker function
against staging Postgres, and asserts the resulting row state - proving the
outbox claim/send/mark-result lifecycle end-to-end, not just RPC-level
behaviour already covered by test_qc_rft_collected_staging.py.
"""
import sys
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "_staging_test_tools"))
sys.path.insert(0, str(REPO_ROOT / "backend"))

from staging_conn import get_conn
import vehicle_notification_worker as worker

PASSED = 0
FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"PASS  {name}")
    else:
        FAILED += 1
        print(f"FAIL  {name}  {detail}")


conn = get_conn()
cur = conn.cursor()
vehicle_id = str(uuid.uuid4())
notif_with_recipient = str(uuid.uuid4())
notif_without_recipient = str(uuid.uuid4())

try:
    cur.execute(
        "insert into public.vehicles (id, permanent_vehicle_id, stock_number, lifecycle_state, visible_on_board, version) values (%s,%s,%s,'active',true,1)",
        (vehicle_id, "QA-WORKER-TEST-001", "QA-WORKER-TEST-001"),
    )
    cur.execute(
        "insert into public.vehicle_notifications (id, vehicle_id, notification_type, idempotency_key, recipient_email, subject, body) values (%s,%s,'test',%s,%s,%s,%s)",
        (notif_with_recipient, vehicle_id, f"worker-integration-a:{vehicle_id}", "worker-int@staging.pdc-workshop.example.com", "Subject A", "Body A"),
    )
    cur.execute(
        "insert into public.vehicle_notifications (id, vehicle_id, notification_type, idempotency_key, recipient_email, subject, body) values (%s,%s,'test',%s,%s,%s,%s)",
        (notif_without_recipient, vehicle_id, f"worker-integration-b:{vehicle_id}", None, "Subject B", "Body B"),
    )
    conn.commit()

    sent, failed = worker.run(dry_run=True, limit=50)
    check("1a worker.run completes without raising", True, "")

    cur.execute("select status, sent_at, attempts from public.vehicle_notifications where id = %s", (notif_with_recipient,))
    row = cur.fetchone()
    check("1b notification with a recipient is marked sent by the dry-run worker", row is not None and row[0] == "sent" and row[1] is not None, str(row))
    check("1c attempts incremented exactly once", row is not None and row[2] == 1, str(row))

    cur.execute("select status, attempts from public.vehicle_notifications where id = %s", (notif_without_recipient,))
    row2 = cur.fetchone()
    check("1d notification with no recipient email is left pending (not silently dropped or marked sent)", row2 is not None and row2[0] == "pending" and row2[1] == 0, str(row2))

    # Idempotency: running the worker again on the already-sent row must not
    # re-claim/re-send it (status is no longer 'pending'/'failed').
    sent2, failed2 = worker.run(dry_run=True, limit=50)
    cur.execute("select attempts from public.vehicle_notifications where id = %s", (notif_with_recipient,))
    row3 = cur.fetchone()
    check("2a re-running the worker does not re-send an already-sent notification", row3 is not None and row3[0] == 1, str(row3))

finally:
    try:
        conn.rollback()
    except Exception:
        pass
    cur.execute("delete from public.vehicle_notifications where vehicle_id = %s", (vehicle_id,))
    cur.execute("delete from public.vehicles where id = %s", (vehicle_id,))
    conn.commit()
    conn.close()

print(f"\nTOTAL: {PASSED} passed, {FAILED} failed")
if FAILED:
    sys.exit(1)
