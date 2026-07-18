"""Delete only the exact Stage 2A browser-acceptance technician fixture."""
from __future__ import annotations

import json
import sys
import uuid

from staging_conn import get_conn


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: cleanup_stage2a_assignment_acceptance.py <technician-uuid> <synthetic-prefix>")
    technician_id = str(uuid.UUID(sys.argv[1]))
    prefix = sys.argv[2]
    if not prefix.startswith("S2A-ASSIGN-"):
        raise SystemExit("refusing cleanup for an unexpected synthetic prefix")
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "delete from public.audit_events where row_id = %s or before_data::text like %s or after_data::text like %s or metadata::text like %s",
                (technician_id, f"%{prefix}%", f"%{prefix}%", f"%{prefix}%"),
            )
            audit_deleted = cur.rowcount
            cur.execute(
                "delete from public.workshop_technicians where id = %s and name like %s and not exists "
                "(select 1 from public.workshop_booking_assignments where technician_id = %s)",
                (technician_id, prefix + "%", technician_id),
            )
            technician_deleted = cur.rowcount
            cur.execute(
                "select (select count(*) from public.workshop_technicians where id = %s) + "
                "(select count(*) from public.workshop_booking_assignments where technician_id = %s)",
                (technician_id, technician_id),
            )
            remaining = int(cur.fetchone()[0])
        conn.commit()
    result = {"audit_deleted": audit_deleted, "technician_deleted": technician_deleted, "remaining": remaining}
    print(json.dumps(result, sort_keys=True))
    if remaining:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
