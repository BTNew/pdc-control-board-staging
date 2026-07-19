"""Preview and apply the guarded 25-vehicle C6 import before post-apply rollback backup creation."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import stage2b_c6_operational_rehearsal as c6


def _logical_with_checksum(value):
    return {**value, "checksum": {"algorithm": "sha256", "value": c6.canonical_sha(value)}}


def prepare(c4_zip, backup_manifest, restore_report, evidence_dir, database_url,
            apply=False, approved_preview_sha=None):
    c6.assert_exact_project_guard(database_url=database_url)
    backup = c6.validate_backup_evidence(backup_manifest, restore_report)
    payload, summary = c6.load_approved_c4(c4_zip)
    selected = c6.select_records(payload)
    selection = c6.selected_manifest(selected, summary["source_assessment_sha256"])
    batch_id = "C6-REAL-PILOT-" + summary["source_assessment_sha256"][:12].upper()
    keys = {
        row["record_ref"]: f"C6-029-{index:02d}-{row['record_ref'].replace(':', '-').upper()}"
        for index, row in enumerate(selected, 1)
    }

    conn = c6._connect_guarded(database_url)
    conn.autocommit = False
    ledger = c6._migration_ledger(conn)
    if ledger[-1:] != ["031"]:
        conn.close()
        raise c6.C6PilotRefusal("staging migration ledger is not exactly through 031")
    initial_counts = {key: backup["backup_row_counts"][key] for key in c6.COUNT_TABLES}
    if c6._counts(conn) != initial_counts:
        conn.close()
        raise c6.C6PilotRefusal("public row counts drifted after the approved pre-rehearsal backup")
    admin = c6._admin(conn)
    cur = conn.cursor()
    cur.execute("""select count(*) from public.vehicle_master_operation_receipts
                   where operation_kind='import_apply' and scope_key=%s
                     and idempotency_key=any(%s::text[])""", (c6.SOURCE_SYSTEM, list(keys.values())))
    if cur.fetchone()[0] != 0:
        conn.close()
        raise c6.C6PilotRefusal("C6 prepare/apply refuses pre-existing receipts")

    safe_rows = []
    raw_previews = {}
    raw_proof = {}
    for row in selected:
        body = c6.source_payload(row)
        first = c6._preview(conn, admin, batch_id, row["record_ref"], body)
        second = c6._preview(conn, admin, batch_id, row["record_ref"], body)
        safe = c6.validate_preview_response(row["record_ref"], first, second)
        if safe["action"] != "insert":
            conn.close()
            raise c6.C6PilotRefusal(f"fresh C6 preview expected insert: {row['record_ref']}")
        safe_rows.append(safe)
        raw_previews[row["record_ref"]] = first
        raw_proof[row["record_ref"]] = {"approved_preview": first, "repeated_preview": second}

    preview_logical = {
        "schema": "pdc.stage2b.c6-preview/v1",
        "source_system": c6.SOURCE_SYSTEM,
        "source_batch_id": batch_id,
        "selected_manifest_checksum": selection["checksum"],
        "preview_count": len(safe_rows),
        "actions": safe_rows,
        "deterministic_repreview": True,
        "zero_ambiguity": all(row["candidate_count"] <= 1 for row in safe_rows),
        "zero_conflict": True,
    }
    preview = _logical_with_checksum(preview_logical)
    files = {
        "selected-record-manifest.json": selection,
        "preview-result.json": preview,
        "approval-manifest.md": c6.render_approval_manifest(selection, preview),
        "preimport-baseline.json": {
            "schema": "pdc.stage2b.c6-preimport-baseline/v1",
            "migration_ledger": ledger,
            "row_counts": initial_counts,
            "backup_restore": backup,
            "unrelated_vehicle_full_row_sha256": c6._backup_vehicle_hash(backup_manifest),
        },
    }
    c6.write_evidence(evidence_dir, files)
    if not apply:
        conn.rollback()
        conn.close()
        return {"phase": "preview", "selected_count": len(selected), "preview_sha256": preview["checksum"]["value"]}
    if not approved_preview_sha or approved_preview_sha != preview["checksum"]["value"]:
        conn.close()
        raise c6.C6PilotRefusal("apply requires the exact freshly approved preview checksum")

    applied_rows = []
    replay_rows = []
    raw_apply = {}
    raw_replay = {}
    selected_ids = []
    response_loss_ref = selected[0]["record_ref"]
    for row in selected:
        ref = row["record_ref"]
        body = c6.source_payload(row)
        approved = raw_previews[ref]
        expected_version = approved["data"]["expected_version"]
        applied = c6._apply(conn, admin, batch_id, ref, body, expected_version, keys[ref])
        if (applied.get("ok") is not True or applied.get("code") != "applied"
                or applied.get("data", {}).get("preview") != approved.get("data")):
            conn.rollback(); conn.close()
            raise c6.C6PilotRefusal(f"C6 preview/apply parity failed: {ref}")
        conn.commit()
        vehicle_id = applied["data"]["vehicle_id"]
        selected_ids.append(vehicle_id)
        raw_apply[ref] = applied
        if ref == response_loss_ref:
            conn.close()
            conn = c6._connect_guarded(database_url)
            conn.autocommit = False
            admin = c6._admin(conn)
        replay = c6._apply(conn, admin, batch_id, ref, body, expected_version, keys[ref])
        conn.commit()
        if replay != applied:
            conn.close()
            raise c6.C6PilotRefusal(f"C6 durable replay differed: {ref}")
        raw_replay[ref] = replay
        applied_rows.append({
            "record_ref": ref, "vehicle_id": vehicle_id, "action": applied["data"]["action"],
            "version": applied["data"]["version"], "request_fingerprint": applied["data"]["request_fingerprint"],
            "preview_checksum": c6.canonical_sha(approved["data"]),
            "apply_embedded_preview_checksum": c6.canonical_sha(applied["data"]["preview"]),
        })
        replay_rows.append({
            "record_ref": ref, "vehicle_id": vehicle_id,
            "request_fingerprint": applied["data"]["request_fingerprint"],
            "identical_complete_response": True,
            "fresh_connection_after_response_loss": ref == response_loss_ref,
        })

    after_counts = c6._counts(conn)
    unrelated_after = c6._unrelated_vehicle_hash(conn, selected_ids)
    unrelated_before = c6._backup_vehicle_hash(backup_manifest)
    if unrelated_after != unrelated_before:
        conn.close()
        raise c6.C6PilotRefusal("unrelated vehicle changed during C6 import")
    expected_delta = after_counts["vehicles"] - initial_counts["vehicles"]
    if expected_delta != c6.SELECTED_COUNT:
        conn.close()
        raise c6.C6PilotRefusal("C6 vehicle delta is not exactly 25")
    namespace = c6._selected_namespace_counts(conn, selected_ids, batch_id)
    if namespace["vehicles"] != c6.SELECTED_COUNT or namespace["source_records"] != c6.SELECTED_COUNT or namespace["receipts"] != c6.SELECTED_COUNT or namespace["unresolved_conflicts"]:
        conn.close()
        raise c6.C6PilotRefusal("C6 selected namespace counts are invalid")
    conn.close()

    row_counts = {
        "schema": "pdc.stage2b.c6-row-counts/v1",
        "before": initial_counts,
        "after": after_counts,
        "deltas": {key: after_counts[key] - initial_counts[key] for key in c6.COUNT_TABLES},
        "selected_namespace_counts": namespace,
        "unrelated_vehicle_full_row_sha256_before": unrelated_before,
        "unrelated_vehicle_full_row_sha256_after": unrelated_after,
        "unrelated_vehicles_unchanged": True,
    }
    c6.write_evidence(evidence_dir, {
        **files,
        "apply-result.json": {"schema": "pdc.stage2b.c6-apply/v1", "applied_count": len(applied_rows), "preview_apply_parity": True, "actions": applied_rows},
        "replay-evidence.json": {"schema": "pdc.stage2b.c6-replay/v1", "replay_count": len(replay_rows), "response_loss_record_ref": response_loss_ref, "fresh_connection_response_loss_replay": True, "complete_response_identity": True, "duplicate_vehicles_created": 0, "results": replay_rows},
        "before-after-row-counts.json": row_counts,
        "import-operational-proof.json": c6._strip_prohibited_evidence_fields({"schema": "pdc.stage2b.c6-import-proof/v1", "preview_responses": raw_proof, "apply_responses": raw_apply, "replay_responses": raw_replay}),
    })
    return {"phase": "apply", "selected_count": len(selected_ids), "preview_sha256": approved_preview_sha, "retained_vehicle_ids": sorted(selected_ids)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--c4-zip", required=True)
    parser.add_argument("--backup-manifest", required=True)
    parser.add_argument("--restore-report", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--approved-preview-sha")
    args = parser.parse_args(argv)
    print(c6.canonical_json(prepare(
        args.c4_zip, args.backup_manifest, args.restore_report, args.evidence_dir,
        os.environ.get("PDC_STAGING_DATABASE_URL", ""), args.apply, args.approved_preview_sha,
    )))


if __name__ == "__main__":
    main()
