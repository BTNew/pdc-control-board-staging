"""Verify the final staging boundary is exactly the approved C6 25-vehicle set."""
from __future__ import annotations

import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import stage2b_c6_operational_rehearsal as c6

EVIDENCE = ROOT / "review-evidence" / "stage2b-c6"


def main():
    apply_result = json.loads((EVIDENCE / "apply-result.json").read_text(encoding="utf-8"))
    approved = sorted(row["vehicle_id"] for row in apply_result["actions"])
    if len(approved) != 25 or len(set(approved)) != 25:
        raise c6.C6PilotRefusal("approved apply result is not exactly 25 unique vehicles")
    conn = c6._connect_guarded(os.environ.get("PDC_STAGING_DATABASE_URL", ""))
    try:
        cur = conn.cursor()
        cur.execute("select id::text from public.vehicles where source_system=%s and source_batch_id=%s order by id",
                    (apply_result["source_system"], apply_result["source_batch_id"]))
        retained = [row[0] for row in cur.fetchall()]
        cur.execute("select count(*) from public.vehicles")
        total = int(cur.fetchone()[0])
        cur.execute("select revision from public.vehicle_master_revision where singleton")
        master = int(cur.fetchone()[0])
        cur.execute("select revision from public.vehicle_lifecycle_resolver_revision where singleton")
        resolver = int(cur.fetchone()[0])
        cur.execute("""select nspname from pg_namespace
                       where nspname like 'c6_full_%' or nspname like 'stage2a_backup_%'
                       order by nspname""")
        temp_schemas = [row[0] for row in cur.fetchall()]
    finally:
        conn.close()
    report = {
        "schema": "pdc.stage2b.c6-staging-final-boundary/v1",
        "exact_staging_project_ref": c6.STAGING_REF,
        "approved_vehicle_count": len(approved),
        "retained_vehicle_count": len(retained),
        "approved_vehicle_ids": approved,
        "approved_uuid_set_exact": retained == approved,
        "staging_total_vehicle_count": total,
        "additional_staging_vehicles_excluded_from_evidence": total - len(retained),
        "vehicle_master_revision": master,
        "lifecycle_resolver_revision": resolver,
        "temporary_c6_schemas": len(temp_schemas),
        "temporary_schema_names": temp_schemas,
        "passed": retained == approved and len(retained) == 25 and not temp_schemas,
    }
    (EVIDENCE / "staging-final-boundary-verification.json").write_text(
        json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"retained_vehicle_count": len(retained), "temporary_schemas": len(temp_schemas), "passed": report["passed"]}, sort_keys=True))
    if not report["passed"]:
        raise c6.C6PilotRefusal("final C6 staging boundary verification failed")


if __name__ == "__main__":
    main()
