"""Expose the controlled staging vehicle via one completed synthetic booking."""
from __future__ import annotations

import json
import uuid

from staging_conn import get_conn

VEHICLE_ID = "8debaf15-2344-4617-aada-f39728c5c0de"
BOOKING_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-stage2a-assignment-acceptance-history"))


def main() -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("select u.id from public.pdc_user_roles r join auth.users u on lower(u.email)=r.email where r.active and r.role in ('operator','administrator') order by case r.role when 'operator' then 0 else 1 end limit 1")
            actor = cur.fetchone()[0]
            cur.execute("select id from public.workshop_stages where code='HOIST' and active limit 1")
            stage = cur.fetchone()[0]
            cur.execute("select id from public.workshop_bays where stage_id=%s and bay_number=1 and is_active limit 1", (stage,))
            bay = cur.fetchone()[0]
            cur.execute("delete from public.workshop_bookings where id=%s", (BOOKING_ID,))
            cur.execute(
                "insert into public.workshop_bookings "
                "(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,actual_start_at,actual_end_at,actual_duration_minutes,source,created_by,updated_by) "
                "values (%s,%s,%s,%s,'completed','2026-07-18T08:00:00+08:00','2026-07-18T09:00:00+08:00',60,'2026-07-18T08:00:00+08:00','2026-07-18T09:00:00+08:00',60,'stage2a-assignment-acceptance',%s,%s)",
                (BOOKING_ID, VEHICLE_ID, stage, bay, actor, actor),
            )
            cur.execute("update public.vehicles set version=1, workshop_status='queued', active_workshop_booking_id=null where id=%s", (VEHICLE_ID,))
        conn.commit()
    print(json.dumps({"booking_id": BOOKING_ID, "vehicle_id": VEHICLE_ID, "prepared": True}, sort_keys=True))


if __name__ == "__main__":
    main()
