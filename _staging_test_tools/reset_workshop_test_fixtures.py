"""Reset only the two documented synthetic workshop integration fixtures.

This helper is intentionally ID-scoped and staging-guarded. It never truncates
or touches arbitrary operational rows. Run before and after
``test_workshop_staging_integration.py`` because that historical integration
test is not self-cleaning.
"""
import json

from staging_conn import get_conn

VEHICLE_IDS = [
    "8debaf15-2344-4617-aada-f39728c5c0de",  # STK-STAGE-001
    "9fbd5a06-db70-4922-9bf1-49559d74583f",  # STK-STAGE-002
]


def main() -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "delete from public.workshop_booking_assignments where booking_id in "
                "(select id from public.workshop_bookings where vehicle_id = any(%s::uuid[]))",
                (VEHICLE_IDS,),
            )
            assignments = cur.rowcount
            cur.execute(
                "delete from public.workshop_booking_history where booking_id in "
                "(select id from public.workshop_bookings where vehicle_id = any(%s::uuid[]))",
                (VEHICLE_IDS,),
            )
            history = cur.rowcount
            cur.execute(
                "delete from public.workshop_parts_overrides where vehicle_id = any(%s::uuid[])",
                (VEHICLE_IDS,),
            )
            overrides = cur.rowcount
            cur.execute(
                "delete from public.workshop_bookings where vehicle_id = any(%s::uuid[])",
                (VEHICLE_IDS,),
            )
            bookings = cur.rowcount
            cur.execute(
                "delete from public.vehicle_parts_updates where vehicle_id = any(%s::uuid[])",
                (VEHICLE_IDS,),
            )
            parts = cur.rowcount
            cur.execute(
                "update public.vehicle_work_items set completed=false, completed_by=null, "
                "completed_at=null, updated_at=now() where vehicle_id=any(%s::uuid[]) "
                "and work_key='FITTING'",
                (VEHICLE_IDS,),
            )
            cur.execute(
                "update public.vehicles set version=1, workshop_status='queued', "
                "active_workshop_booking_id=null where id=any(%s::uuid[])",
                (VEHICLE_IDS,),
            )
            cur.execute(
                "select count(*) from public.workshop_bookings where vehicle_id=any(%s::uuid[])",
                (VEHICLE_IDS,),
            )
            remaining = cur.fetchone()[0]
        conn.commit()
    print(json.dumps({
        "assignments_deleted": assignments,
        "history_deleted": history,
        "overrides_deleted": overrides,
        "bookings_deleted": bookings,
        "parts_updates_deleted": parts,
        "remaining_controlled_bookings": remaining,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
