"""
Vehicle notification outbox worker (staging-only, migration 016).

Claims pending/retryable vehicle_notifications rows via the service-role-only
claim_pending_vehicle_notifications() RPC, attempts delivery through a
pluggable sender, and records the result via mark_vehicle_notification_result()
so success/failure/retry state lives in the database, not in this script's
memory. Designed to be run repeatedly (cron/manual) - safe to run twice
because claiming does not change status, and each row is only marked once
per invocation of this worker.

Usage:
    python backend/vehicle_notification_worker.py [--dry-run] [--limit N]

--dry-run (default): does not attempt any real network send. Instead logs
what WOULD be sent and marks the row 'sent' so staging tests/acceptance
walkthroughs can exercise the full outbox lifecycle without a real SMTP/API
credential. This mirrors the brief's requirement not to block the feature
on live mailbox credentials being unavailable, and never sends a real
external email during initial testing.

To wire a real sender later, implement `send_via_provider(notification)` and
call this script without --dry-run once a provider is configured and
approved - no other code needs to change.
"""
import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "_staging_test_tools"))


def send_via_provider(notification):
    """Real sender stub. Not implemented for staging - raises so a caller
    that forgets --dry-run without a configured provider fails loudly
    instead of silently doing nothing."""
    raise NotImplementedError(
        "No email provider is configured for this staging worker. "
        "Run with --dry-run for staging acceptance testing, or implement "
        "send_via_provider() once a provider is approved."
    )


def run(dry_run=True, limit=20):
    from staging_conn import get_conn

    conn = get_conn()
    cur = conn.cursor()
    sent = 0
    failed = 0
    try:
        cur.execute(
            "select id, vehicle_id, notification_type, recipient_email, recipient_name, subject, body, attempts, max_attempts "
            "from public.claim_pending_vehicle_notifications(%s)",
            (limit,),
        )
        rows = cur.fetchall()
        for row in rows:
            (notif_id, vehicle_id, notif_type, recipient_email, recipient_name, subject, body, attempts, max_attempts) = row

            if not recipient_email:
                print(f"SKIP  {notif_id}  no recipient email on file - leaving pending for manual correction/retry")
                continue

            try:
                if dry_run:
                    print(f"DRY-RUN SEND  to={recipient_email!r} subject={subject!r} attempts={attempts + 1}/{max_attempts}")
                else:
                    send_via_provider({
                        "id": notif_id, "recipient_email": recipient_email, "recipient_name": recipient_name,
                        "subject": subject, "body": body,
                    })
                cur.execute("select mark_vehicle_notification_result from public.mark_vehicle_notification_result(%s, true, null)", (notif_id,))
                conn.commit()
                sent += 1
                print(f"SENT  {notif_id}  -> {recipient_email}")
            except Exception as exc:  # noqa: BLE001 - worker must never crash on one bad row
                cur.execute("select mark_vehicle_notification_result from public.mark_vehicle_notification_result(%s, false, %s)", (notif_id, str(exc)[:500]))
                conn.commit()
                failed += 1
                print(f"FAIL  {notif_id}  {exc}")
    finally:
        conn.close()

    print(f"\nWorker summary: {sent} sent, {failed} failed, {len(rows) if 'rows' in dir() else 0} claimed")
    return sent, failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", default=True, help="Do not send real email (default for staging)")
    parser.add_argument("--live", dest="dry_run", action="store_false", help="Attempt real delivery via send_via_provider()")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()
    run(dry_run=args.dry_run, limit=args.limit)
