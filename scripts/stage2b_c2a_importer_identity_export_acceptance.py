"""Guarded synthetic C2a importer acceptance; all mutations are rolled back."""
from __future__ import annotations

import json
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
if (ROOT / "supabase" / ".temp" / "project-ref").read_text(encoding="utf-8").strip() != STAGING_REF:
    raise SystemExit("refusing C2a acceptance outside guarded staging")

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
from scripts.pdc_staging_runtime import get_conn  # noqa: E402
from workshop_legacy_import import classify, fetch_reference_data, run_import  # noqa: E402


def booking(key, token, stage_code):
    return {
        "legacy_plan_id": f"C2A-PLAN-{token}",
        "legacy_vehicle_key": key,
        "stage_code": stage_code,
        "bay_number": None,
        "assignee": "",
        "scheduled_start_at": "2026-07-18T08:00:00Z",
        "scheduled_end_at": "2026-07-18T09:00:00Z",
        "duration_minutes": 60,
        "status": "planned",
        "raw_legacy_record": {"synthetic": True, "token": token},
    }


def main():
    conn = get_conn()
    conn.autocommit = False
    token = uuid.uuid4().hex[:10].upper()
    batch = f"C2A-ACCEPT-{token}"
    source = "stage2b_c2a_acceptance"
    vehicle_a, vehicle_b = str(uuid.uuid4()), str(uuid.uuid4())
    stock_a = f"C2A-SAFE-{token}"
    conflict_value = f"C2A-CONFLICT-{token}"
    alias_value = f"C2A-ALIAS-{token}"
    try:
        cur = conn.cursor()
        cur.execute(
            """
            select r.email
            from public.pdc_user_roles r
            join auth.users u on lower(u.email)=lower(r.email)
            where r.active and r.role='administrator'
            order by r.email
            """
        )
        admin_rows = cur.fetchall()
        if not admin_rows:
            raise RuntimeError("staging administrator fixture missing")
        admin_email = admin_rows[0][0]

        for vehicle_id, stock, index in ((vehicle_a, stock_a, 1), (vehicle_b, conflict_value, 2)):
            cur.execute(
                """
                insert into public.vehicles (
                  id, permanent_vehicle_id, stock_number, vin, job_card_number,
                  toyota_order_number, source_system, source_batch_id,
                  source_record_id, lifecycle_state, version, visible_on_board
                ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,'active',1,false)
                """,
                (
                    vehicle_id, f"PERM-{token}-{index}", stock,
                    ("JTN" + token + str(index) * 20)[:17], f"JC-{token}-{index}",
                    f"ORDER-{token}-{index}", source, batch, f"ROW-{token}-{index}",
                ),
            )
        cur.execute(
            """
            insert into public.vehicle_aliases (
              vehicle_id, alias_type, alias_value, active, source_system, source_batch_id
            ) values (%s,'stock_number',%s,true,%s,%s)
            """,
            (vehicle_a, alias_value, source, batch),
        )
        cur.execute("set local session_replication_role=replica")
        try:
            cur.execute(
                """
                insert into public.vehicle_aliases (
                  vehicle_id, alias_type, alias_value, active, source_system, source_batch_id
                ) values (%s,'stock_number',%s,true,%s,%s)
                """,
                (vehicle_a, conflict_value, source, batch),
            )
        finally:
            cur.execute("set local session_replication_role=origin")

        reference = fetch_reference_data(conn, actor_email=admin_email, page_size=1)
        artifact = reference["vehicleIdentityArtifact"]
        stage_code = reference["stages"][0]["code"]

        identity_results = {}
        for label, key in (
            ("stock", stock_a.lower().replace("-", " ")),
            ("vin", ("JTN" + token + "1" * 20)[:17].lower()),
            ("job_card", f" jc-{token.lower()}-1 "),
            ("alias", alias_value.lower().replace("-", " ")),
        ):
            buckets = classify({"bookings": [booking(key, token, stage_code)]}, reference, expected_revision=artifact["resolver_revision"])
            safe = buckets["safely_matched"]
            if len(safe) != 1 or safe[0]["resolved"]["vehicle_id"] != vehicle_a:
                raise AssertionError(f"{label} did not retain canonical UUID")
            identity_results[label] = safe[0]["resolved"]["vehicle_id"]

        ambiguous = classify(
            {"bookings": [booking(conflict_value, token + "-CONFLICT", stage_code)]},
            reference,
            expected_revision=artifact["resolver_revision"],
        )
        if len(ambiguous["conflicting_vehicle_identity"]) != 1 or ambiguous["safely_matched"]:
            raise AssertionError("canonical-versus-alias conflict was not refused")

        extract = {
            "source_backup_type": "workshop_planner_legacy_export",
            "exported_at": f"C2A-{token}",
            "bookings": [booking(stock_a, token, stage_code)],
        }
        applied = run_import(conn, extract, reference, apply=True, commit_apply=False)
        cur.execute(
            """
            select vehicle_id::text from public.workshop_bookings
            where source='legacy_migration' and metadata_legacy_plan_id=%s
            """,
            (f"C2A-PLAN-{token}",),
        )
        rows = cur.fetchall()
        if rows != [(vehicle_a,)]:
            raise AssertionError(f"imported booking UUID mismatch: {rows!r}")
        if applied["inserted"] != 1:
            raise AssertionError(f"synthetic importer did not insert exactly one booking: {applied!r}")
        cur.execute(
            "select count(*) from public.workshop_booking_history where booking_id in "
            "(select id from public.workshop_bookings where metadata_legacy_plan_id=%s)",
            (f"C2A-PLAN-{token}",),
        )
        history_before_replay = cur.fetchone()[0]
        cur.execute("select count(*) from public.import_runs where source_hash=%s", (applied["request_fingerprint"],))
        receipts_before_replay = cur.fetchone()[0]
        # Simulate an unrelated resolver revision advancing after the first
        # commit but before a caller retries following response loss. The
        # exact durable receipt must still win before stale-reference checks.
        cur.execute(
            "update public.vehicle_lifecycle_resolver_revision "
            "set revision=revision+1, updated_at=now() where singleton"
        )
        replayed = run_import(conn, extract, reference, apply=True, commit_apply=False)
        cur.execute(
            "select count(*) from public.workshop_booking_history where booking_id in "
            "(select id from public.workshop_bookings where metadata_legacy_plan_id=%s)",
            (f"C2A-PLAN-{token}",),
        )
        history_after_replay = cur.fetchone()[0]
        cur.execute("select count(*) from public.import_runs where source_hash=%s", (applied["request_fingerprint"],))
        receipts_after_replay = cur.fetchone()[0]
        if not replayed.get("replayed") or replayed.get("receipt_id") != applied.get("receipt_id"):
            raise AssertionError(f"exact retry did not return the original receipt: {replayed!r}")
        if (history_before_replay, receipts_before_replay) != (history_after_replay, receipts_after_replay):
            raise AssertionError("response-loss retry repeated history or receipt writes")

        result = {
            "canonical_vehicle_uuid": vehicle_a,
            "identity_results": identity_results,
            "ambiguous_refused": True,
            "rollback_used": False,
            "export_revision": artifact["resolver_revision"],
            "exported_vehicle_count": artifact["item_count"],
            "artifact_checksum": artifact["checksum"]["value"],
            "import_result": applied,
            "response_loss_retry": {
                "replayed": True,
                "same_receipt": True,
                "history_rows": history_after_replay,
                "receipt_rows": receipts_after_replay,
                "succeeds_after_revision_advance": True,
            },
        }
    finally:
        conn.rollback()
        conn.close()

    verify = get_conn()
    try:
        q = verify.cursor()
        q.execute("select count(*) from public.vehicles where source_system=%s and source_batch_id=%s", (source, batch))
        vehicles = q.fetchone()[0]
        q.execute("select count(*) from public.vehicle_aliases where source_batch_id=%s", (batch,))
        aliases = q.fetchone()[0]
        q.execute("select count(*) from public.workshop_bookings where metadata_legacy_plan_id like %s", (f"C2A-PLAN-{token}%",))
        bookings = q.fetchone()[0]
        q.execute(
            "select count(*) from public.import_runs where source_hash=%s",
            (result["import_result"]["request_fingerprint"],),
        )
        receipts = q.fetchone()[0]
        cleanup = {"vehicles": vehicles, "aliases": aliases, "bookings": bookings, "receipts": receipts}
        if any(cleanup.values()):
            raise AssertionError(f"synthetic C2a cleanup failed: {cleanup}")
        result["cleanup"] = cleanup
    finally:
        verify.close()

    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
