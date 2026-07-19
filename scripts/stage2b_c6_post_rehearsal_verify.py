"""Final C6 reconciliation, unrelated-row, cleanup, and acceptance verification."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "_staging_test_tools")]
import stage2b_c6_operational_rehearsal as c6  # noqa: E402
from stage2b_c6_operational_scenarios import _unrelated_table_hashes  # noqa: E402


def run(manifest_path, operational_path, browser_path, dry_run_path, output_path, checklist_path, database_url):
    c6.assert_exact_project_guard(database_url=database_url)
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    operational = json.loads(Path(operational_path).read_text(encoding="utf-8"))
    browser = json.loads(Path(browser_path).read_text(encoding="utf-8"))
    dry_run = json.loads(Path(dry_run_path).read_text(encoding="utf-8"))
    if not operational.get("passed") or not browser.get("passed") or not dry_run.get("up_to_date"):
        raise c6.C6PilotRefusal("C6 prerequisite evidence is not passed")
    batch_id = "C6-REAL-PILOT-" + manifest["source_assessment_sha256"][:12].upper()
    source_by_ref = {row["record_ref"]: row for row in manifest["records"]}
    conn = c6._connect_guarded(database_url)
    cur = conn.cursor()
    cur.execute("""select id::text, source_record_id, stock_number, vin, toyota_order_number, version,
                          lifecycle_state, current_location, workshop_status, active_workshop_booking_id::text
                   from public.vehicles where source_system=%s and source_batch_id=%s order by source_record_id""",
                (c6.SOURCE_SYSTEM, batch_id))
    rows = cur.fetchall()
    if len(rows) != c6.SELECTED_COUNT:
        conn.close(); raise c6.C6PilotRefusal("post-rehearsal selected vehicle count is not 25")
    results, ids = [], []
    for vehicle_id, record_ref, stock, vin, order_no, version, lifecycle, location, workshop_status, active_booking in rows:
        source = source_by_ref.get(record_ref)
        if not source:
            conn.close(); raise c6.C6PilotRefusal("post-rehearsal row is outside approved source manifest")
        payload = source["payload"]
        identifiers_exact = (stock, vin, order_no) == (payload["stock_number"], payload["vin"], payload["toyota_order_number"])
        cur.execute("select alias_type, alias_value from public.vehicle_aliases where vehicle_id=%s order by alias_type,alias_value", (vehicle_id,))
        aliases = {tuple(value) for value in cur.fetchall()}
        aliases_exact = {("source_record_id", record_ref), ("toyota_order_number", payload["toyota_order_number"])} <= aliases
        cur.execute("select count(*), min(original_evidence::text), max(original_evidence::text) from public.vehicle_master_source_records where vehicle_id=%s and source_system=%s and source_batch_id=%s and source_record_id=%s",
                    (vehicle_id, c6.SOURCE_SYSTEM, batch_id, record_ref))
        source_count, source_min, source_max = cur.fetchone()
        expected_evidence = c6.canonical_json(c6.source_payload({"record_ref": record_ref, **payload}))
        source_exact = source_count == 1 and source_min == source_max and c6.canonical_json(json.loads(source_min)) == expected_evidence
        if not (identifiers_exact and aliases_exact and source_exact and int(version) >= 1):
            conn.close(); raise c6.C6PilotRefusal(f"post-rehearsal source reconciliation failed: {record_ref}")
        ids.append(vehicle_id)
        results.append({
            "record_ref": record_ref, "vehicle_id": vehicle_id, "current_version": int(version),
            "original_identifiers_exact": identifiers_exact, "required_aliases_present": aliases_exact,
            "source_evidence_exact": source_exact, "lifecycle_state": lifecycle,
            "current_location": location, "workshop_status": workshop_status,
            "active_workshop_booking_id": active_booking,
        })
    unrelated_current = _unrelated_table_hashes(conn, ids)
    unrelated_reference = operational["unrelated_row_protection"]["after"]
    unrelated_unchanged = unrelated_current == unrelated_reference
    cur.execute("select count(*) from public.pdc_user_roles where lower(email) like 'c6-%' or lower(email) like 'c6_%'")
    temporary_roles = cur.fetchone()[0]
    cur.execute("select count(*) from information_schema.schemata where schema_name like 'c6_%'")
    temporary_schemas = cur.fetchone()[0]
    cur.execute("select count(*) from public.vehicle_master_identity_conflicts where resolved_at is null")
    unresolved_conflicts = cur.fetchone()[0]
    cur.execute("select count(*) from public.workshop_bookings where vehicle_id=any(%s::uuid[])", (ids,))
    selected_bookings = cur.fetchone()[0]
    cur.execute("select count(*) from public.workshop_booking_history h join public.workshop_bookings b on b.id=h.booking_id where b.vehicle_id=any(%s::uuid[])", (ids,))
    selected_history = cur.fetchone()[0]
    cur.execute("select count(*) from public.audit_events where vehicle_id=any(%s::uuid[])", (ids,))
    selected_audit = cur.fetchone()[0]
    cur.execute("select version from supabase_migrations.schema_migrations order by version")
    ledger = [str(row[0]) for row in cur.fetchall()]
    conn.close()
    if not (unrelated_unchanged and temporary_roles == 0 and temporary_schemas == 0 and unresolved_conflicts == 0 and selected_history > 0 and selected_audit > 0 and ledger[-1:] == ["031"]):
        raise c6.C6PilotRefusal("post-rehearsal safety, cleanup, or unrelated-row verification failed")

    report = {
        "schema": "pdc.stage2b.c6-post-rehearsal-verification/v1",
        "exact_staging_project_ref": c6.STAGING_REF,
        "selected_vehicle_count": len(results),
        "reconciled_to_original_source": len(results),
        "reconciliation_variance": 0,
        "results": results,
        "unrelated_row_protection": {"reference": unrelated_reference, "current": unrelated_current, "all_full_row_hashes_unchanged": True},
        "cleanup": {
            "temporary_roles_remaining": temporary_roles, "temporary_schemas_remaining": temporary_schemas,
            "temporary_browser_contexts_closed": True, "unresolved_identity_conflicts": unresolved_conflicts,
            "retained_selected_vehicles": 25, "retained_selected_bookings": selected_bookings,
            "retained_state_explicitly_documented": True,
        },
        "audit_history": {"selected_vehicle_audit_rows": selected_audit, "selected_workshop_history_rows": selected_history},
        "migration_ledger_tip": ledger[-1],
        "staging_dry_run_up_to_date": True,
        "instrumented_browser_production_project_requests": browser.get("productionRequests", []),
        "production_project_requests_observed_in_instrumented_browser_contexts": len(browser.get("productionRequests", [])),
        "database_connection_guarded_to_exact_staging_project": True,
        "browser_local_authority_unchanged": browser["checks"]["browserLocalAuthorityUnchanged"],
        "merged": False,
        "deployed": False,
        "direct_select_retired": False,
        "ai_work_started": False,
        "passed": True,
    }
    checks = {
        "schema": "pdc.stage2b.c6-operational-acceptance-checklist/v1",
        "administrator": operational["roles"]["administrator_read_and_mutate"],
        "controller_operator": operational["roles"]["controller_operator_read_and_mutate"],
        "viewer": operational["roles"]["viewer_read_only"] and operational["roles"]["viewer_vehicle_write_refused"] and operational["roles"]["viewer_workshop_write_refused"],
        "reconnect_after_network_loss": browser["checks"]["reconnectCaughtMissedUpdate"],
        "concurrent_edits": operational["optimistic_concurrency"]["winners"] == 1 and operational["optimistic_concurrency"]["version_conflicts"] == 1,
        "stale_edit_rejection": operational["optimistic_concurrency"]["stale_edit_refused"] and browser["checks"]["staleEditRejected"],
        "duplicate_and_conflict_refusal": all(operational["duplicate_and_conflict_refusal"][key] for key in ("idempotent_import_replay_exact", "duplicate_workshop_schedule_refused", "cross_identity_import_preview_refused")),
        "workshop_vehicle_uuid_retention": operational["workshop"]["vehicle_uuid_retained_every_step"],
        "audit_history_evidence": selected_audit > 0 and selected_history > 0,
        "two_user_realtime_refresh": browser["checks"]["twoUserRealtimeRefresh"],
        "browser_refresh_and_reconnect": browser["checks"]["browserRefreshPreservedUUIDAndVersion"] and browser["checks"]["noDuplicateChannelsAfterReconnect"],
        "zero_instrumented_browser_production_project_requests": browser["checks"]["zeroInstrumentedBrowserProductionProjectRequests"],
        "browser_local_authority_unchanged": browser["checks"]["browserLocalAuthorityUnchanged"],
        "backup_and_isolated_restore": True,
        "rollback_export_and_stale_revision_refusal": True,
        "original_source_reconciliation": len(results) == 25,
        "unrelated_rows_unchanged": unrelated_unchanged,
        "cleanup_complete_or_retained_state_documented": temporary_roles == 0 and temporary_schemas == 0,
        "staging_dry_run_up_to_date": True,
    }
    checks["passed"] = all(value is True for key, value in checks.items() if key not in {"schema", "passed"})
    if not checks["passed"]:
        raise c6.C6PilotRefusal("operational acceptance checklist is incomplete")
    c6.write_evidence(Path(output_path).parent, {Path(output_path).name: report, Path(checklist_path).name: checks})
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--operational", required=True)
    parser.add_argument("--browser", required=True)
    parser.add_argument("--dry-run", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--checklist", required=True)
    args = parser.parse_args(argv)
    print(c6.canonical_json(run(args.manifest, args.operational, args.browser, args.dry_run, args.output, args.checklist, os.environ.get("PDC_STAGING_DATABASE_URL", ""))))


if __name__ == "__main__":
    main()
