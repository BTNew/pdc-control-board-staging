"""Guarded live-staging Stage 2B C3 synthetic pilot.

Hermes may run this script explicitly.  Importing it is offline and safe.  The
pilot refuses unless both the linked Supabase ref and the direct PostgreSQL DSN
identify the one approved staging project.  Evidence is written only after a
successful run and contains allow-listed metadata, never source payloads.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
SOURCE_SYSTEM = "stage2b_c3_synthetic_pilot"
SOURCE_BATCH_ID = "C3-SYNTHETIC-PILOT-V1"
FIXTURE_PATH = ROOT / "backend" / "fixtures" / "stage2b_c3_synthetic_pilot.json"
PROJECT_REF_PATH = ROOT / "supabase" / ".temp" / "project-ref"

sys.path.insert(0, str(ROOT / "scripts"))
from stage2b_c3_reconciliation import (  # noqa: E402
    build_operation_evidence,
    build_reconciliation_report,
    canonical_json,
    validate_reconciliation_report,
)
from workshop_legacy_import import (  # noqa: E402
    VehicleIdentityExportStale,
    classify,
    fetch_reference_data,
    run_import,
)

EVIDENCE_FILES = {
    "pilot": "c3-pilot-summary.json",
    "preview": "c3-preview-actions.json",
    "artifact": "c3-artifact-metadata.json",
    "reconciliation": "c3-reconciliation.json",
    "rollback": "c3-rollback.json",
    "cleanup": "c3-cleanup.json",
}
SAFE_PREVIEW_KEYS = {"scenario_id", "ok", "code", "action", "changed", "version", "request_fingerprint"}
SAFE_SUMMARY_KEYS = {
    "schema_version", "source_system", "source_batch_id", "scenario_count",
    "preview_deterministic", "preview_apply_parity", "exact_apply_replay",
    "response_loss_replay", "validator_cli", "c2b_dry_run", "evidence_files",
}
ARTIFACT_EVIDENCE_KEYS = {
    "schema_version", "resolver_revision", "item_count", "checksum",
    "deterministic_regeneration", "stale_revision_refused", "malformed_refused", "truncated_refused",
}
ROLLBACK_EVIDENCE_KEYS = {
    "rollback_used", "exact_revision_lock", "stale_rollback_refused", "synthetic_apply_receipt_replayed",
}
CLEANUP_EVIDENCE_KEYS = {
    "baseline_counts", "after_counts", "baseline_restored", "unresolved_synthetic_conflicts",
    "temp_schemas", "temp_roles", "synthetic_residue_counts",
}
COUNT_TABLES = (
    "vehicles", "vehicle_aliases", "vehicle_master_source_records",
    "vehicle_master_history", "vehicle_master_identity_conflicts",
    "vehicle_master_operation_receipts", "audit_events", "import_runs",
    "workshop_bookings", "workshop_booking_assignments", "workshop_booking_history",
)


class C3PilotRefusal(RuntimeError):
    """A fail-closed pilot guard or invariant failed."""


def _sha(value) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def assert_exact_project_guard(project_ref_path=PROJECT_REF_PATH, database_url=None):
    """Require independent exact identities from the CLI link and direct DSN."""
    path = Path(project_ref_path)
    if not path.is_file() or path.read_text(encoding="utf-8").strip() != STAGING_REF:
        raise C3PilotRefusal("refusing C3 pilot: Supabase link is not exact staging")
    raw = str(database_url or "").strip()
    if not raw:
        raise C3PilotRefusal("refusing C3 pilot: direct staging DSN is required")
    parsed = urlparse(raw)
    host = (parsed.hostname or "").lower()
    user = unquote(parsed.username or "").lower()
    direct = host == f"db.{STAGING_REF}.supabase.co" and user == "postgres"
    pooled = host.endswith(".pooler.supabase.com") and user == f"postgres.{STAGING_REF}"
    if parsed.scheme not in {"postgres", "postgresql"} or not (direct or pooled):
        raise C3PilotRefusal("refusing C3 pilot: direct DSN does not identify exact staging ref")
    return True


def load_fixture(path=FIXTURE_PATH):
    fixture = json.loads(Path(path).read_text(encoding="utf-8"))
    if fixture.get("source_system") != SOURCE_SYSTEM or fixture.get("source_batch_id") != SOURCE_BATCH_ID:
        raise C3PilotRefusal("synthetic fixture namespace or fixed batch is invalid")
    rows = fixture.get("scenarios")
    if not isinstance(rows, list) or not rows or len({r.get("id") for r in rows}) != len(rows):
        raise C3PilotRefusal("synthetic fixture scenarios are missing or duplicated")
    return fixture


def sanitize_preview(scenario_id, response):
    """Reduce an RPC response to non-payload evidence with a stable fingerprint."""
    if not isinstance(response, dict):
        raise C3PilotRefusal("migration 029 returned a non-object preview")
    data = response.get("data") if isinstance(response.get("data"), dict) else {}
    safe = {
        "scenario_id": scenario_id,
        "ok": response.get("ok") is True,
        "code": str(response.get("code") or ""),
        "action": data.get("action"),
        "changed": data.get("changed"),
        "version": data.get("version"),
        "request_fingerprint": data.get("request_fingerprint"),
    }
    return {key: safe[key] for key in sorted(SAFE_PREVIEW_KEYS)}


def immutable_receipt_projection(response):
    if not isinstance(response, dict):
        raise C3PilotRefusal("receipt response is not an object")
    return {key: value for key, value in response.items() if key != "replayed"}


def validate_evidence_bundle(bundle):
    if not isinstance(bundle, dict) or set(bundle) != set(EVIDENCE_FILES):
        raise C3PilotRefusal("evidence bundle is incomplete")
    summary = bundle["pilot"]
    if not isinstance(summary, dict) or set(summary) != SAFE_SUMMARY_KEYS:
        raise C3PilotRefusal("pilot evidence schema is invalid")
    if summary["source_system"] != SOURCE_SYSTEM or summary["source_batch_id"] != SOURCE_BATCH_ID:
        raise C3PilotRefusal("pilot evidence escaped synthetic namespace")
    if summary["scenario_count"] != 20 or summary["evidence_files"] != sorted(EVIDENCE_FILES.values()):
        raise C3PilotRefusal("pilot evidence inventory is invalid")
    proof_flags = ("preview_deterministic", "preview_apply_parity", "exact_apply_replay",
                   "response_loss_replay", "validator_cli", "c2b_dry_run")
    if not all(summary[key] is True for key in proof_flags):
        raise C3PilotRefusal("pilot proof flags are incomplete")
    previews = bundle["preview"]
    if not isinstance(previews, list) or any(not isinstance(row, dict) or set(row) != SAFE_PREVIEW_KEYS for row in previews):
        raise C3PilotRefusal("preview evidence schema is invalid")

    artifact = bundle["artifact"]
    if not isinstance(artifact, dict) or set(artifact) != ARTIFACT_EVIDENCE_KEYS:
        raise C3PilotRefusal("artifact evidence schema is invalid")
    checksum = artifact.get("checksum")
    artifact_flags = ("deterministic_regeneration", "stale_revision_refused", "malformed_refused", "truncated_refused")
    if (artifact.get("schema_version") != "pdc.workshop.vehicle-reference/v2"
            or not isinstance(artifact.get("resolver_revision"), int)
            or not isinstance(artifact.get("item_count"), int) or artifact["item_count"] < 1
            or not isinstance(checksum, dict) or set(checksum) != {"algorithm", "value"}
            or checksum.get("algorithm") != "sha256"
            or not re.fullmatch(r"[0-9a-f]{64}", str(checksum.get("value") or ""))
            or not all(artifact[key] is True for key in artifact_flags)):
        raise C3PilotRefusal("artifact evidence semantics are invalid")

    rollback = bundle["rollback"]
    if (not isinstance(rollback, dict) or set(rollback) != ROLLBACK_EVIDENCE_KEYS
            or not isinstance(rollback.get("exact_revision_lock"), int)
            or rollback["exact_revision_lock"] != artifact["resolver_revision"]
            or not all(rollback[key] is True for key in (
                "rollback_used", "stale_rollback_refused", "synthetic_apply_receipt_replayed"))):
        raise C3PilotRefusal("rollback evidence semantics are invalid")

    cleanup = bundle["cleanup"]
    if not isinstance(cleanup, dict) or set(cleanup) != CLEANUP_EVIDENCE_KEYS:
        raise C3PilotRefusal("cleanup evidence schema is invalid")
    baseline = cleanup.get("baseline_counts")
    after = cleanup.get("after_counts")
    residue = cleanup.get("synthetic_residue_counts")
    if (not isinstance(baseline, dict) or set(baseline) != set(COUNT_TABLES)
            or not isinstance(after, dict) or set(after) != set(COUNT_TABLES)
            or baseline != after or cleanup.get("baseline_restored") is not True
            or any(not isinstance(value, int) or value < 0 for value in [*baseline.values(), *after.values()])
            or not isinstance(residue, dict) or not residue
            or any(not isinstance(value, int) or value != 0 for value in residue.values())
            or cleanup.get("unresolved_synthetic_conflicts") != 0
            or cleanup.get("temp_schemas") != 0 or cleanup.get("temp_roles") != 0):
        raise C3PilotRefusal("cleanup evidence semantics are invalid")

    validate_reconciliation_report(bundle["reconciliation"])
    encoded = canonical_json(bundle).lower()
    forbidden = ("customer", "email", "password", "database_url", "postgres://", "postgresql://", "source_payload")
    if any(word in encoded for word in forbidden):
        raise C3PilotRefusal("evidence contains a prohibited payload or credential field")
    return True


def write_evidence(evidence_dir, bundle):
    """Write deterministic files only after every validation has succeeded."""
    validate_evidence_bundle(bundle)
    target = Path(evidence_dir).resolve()
    target.mkdir(parents=True, exist_ok=True)
    for key, filename in EVIDENCE_FILES.items():
        (target / filename).write_text(canonical_json(bundle[key]) + "\n", encoding="utf-8")


def _as_admin(cur, email, user_id):
    cur.execute("set local role authenticated")
    cur.execute("select set_config('request.jwt.claims', %s, true)",
                (json.dumps({"email": email, "sub": str(user_id), "role": "authenticated"}),))


def _reset_role(cur):
    cur.execute("reset role")


def _rpc(conn, sql, params, admin):
    cur = conn.cursor()
    _as_admin(cur, *admin)
    try:
        cur.execute(sql, params)
        return cur.fetchone()[0]
    finally:
        _reset_role(cur)


def _admin(conn):
    cur = conn.cursor()
    cur.execute("""select r.email, u.id::text from public.pdc_user_roles r
                   join auth.users u on lower(u.email)=lower(r.email)
                   where r.active and r.role='administrator' order by r.email limit 1""")
    row = cur.fetchone()
    if not row:
        raise C3PilotRefusal("staging administrator fixture is unavailable")
    return row


def _counts(conn):
    cur = conn.cursor()
    result = {}
    for table in COUNT_TABLES:
        cur.execute("select count(*) from public." + table)
        result[table] = cur.fetchone()[0]
    return result


def _synthetic_residue_counts(conn):
    cur = conn.cursor()
    checks = {
        "vehicles": ("select count(*) from public.vehicles where source_system=%s or source_batch_id=%s", (SOURCE_SYSTEM, SOURCE_BATCH_ID)),
        "aliases": ("select count(*) from public.vehicle_aliases where source_system=%s or source_batch_id=%s", (SOURCE_SYSTEM, SOURCE_BATCH_ID)),
        "source_records": ("select count(*) from public.vehicle_master_source_records where source_system=%s or source_batch_id=%s", (SOURCE_SYSTEM, SOURCE_BATCH_ID)),
        "receipts": ("select count(*) from public.vehicle_master_operation_receipts where scope_key=%s", (SOURCE_SYSTEM,)),
        "bookings": ("select count(*) from public.workshop_bookings where metadata_legacy_plan_id like 'C3-PILOT-%%'", ()),
        "import_runs": ("select count(*) from public.import_runs where summary::text like '%%C3-PILOT-%%'", ()),
        "history": ("select count(*) from public.vehicle_master_history where coalesce(before_data::text,'')||coalesce(after_data::text,'')||metadata::text ilike any(%s::text[])", (["%" + SOURCE_SYSTEM + "%", "%" + SOURCE_BATCH_ID + "%", "%C3-PILOT-DURABLE-RECEIPT%"],)),
        "audit": ("select count(*) from public.audit_events where coalesce(before_data::text,'')||coalesce(after_data::text,'')||metadata::text ilike any(%s::text[])", (["%" + SOURCE_SYSTEM + "%", "%" + SOURCE_BATCH_ID + "%", "%C3-PILOT-DURABLE-RECEIPT%"],)),
        "identity_conflicts": ("select count(*) from public.vehicle_master_identity_conflicts where evidence::text ilike %s", ("%" + SOURCE_SYSTEM + "%",)),
    }
    result = {}
    for name, (sql, params) in checks.items():
        cur.execute(sql, params)
        result[name] = cur.fetchone()[0]
    return result


def discover_synthetic_ids(conn):
    """Find only IDs owned by the unmistakable C3 namespace/batch."""
    cur = conn.cursor()
    cur.execute(
        """select distinct id::text from public.vehicles
           where source_system=%s and source_batch_id=%s
           union
           select distinct vehicle_id::text from public.vehicle_master_source_records
           where vehicle_id is not null and source_system=%s
             and (source_batch_id=%s or source_record_id like 'C3-%%')
           union
           select distinct vehicle_id::text from public.vehicle_aliases
           where vehicle_id is not null and source_batch_id=%s""",
        (SOURCE_SYSTEM, SOURCE_BATCH_ID, SOURCE_SYSTEM, SOURCE_BATCH_ID, SOURCE_BATCH_ID),
    )
    return {row[0] for row in cur.fetchall()}


def cleanup_synthetic(conn, vehicle_ids, import_fingerprints):
    """Delete captured C3 rows in FK-safe order; every predicate is narrow."""
    ids = sorted(set(vehicle_ids) | discover_synthetic_ids(conn))
    hashes = sorted(set(import_fingerprints))
    cur = conn.cursor()
    if ids:
        # Booking children precede bookings. Prefix plus captured vehicle IDs
        # prevents cleanup from touching unrelated legacy imports.
        cur.execute("""delete from public.workshop_booking_assignments where booking_id in
                       (select id from public.workshop_bookings where metadata_legacy_plan_id like 'C3-PILOT-%%'
                        and vehicle_id = any(%s::uuid[]))""", (ids,))
        cur.execute("""delete from public.workshop_booking_history where booking_id in
                       (select id from public.workshop_bookings where metadata_legacy_plan_id like 'C3-PILOT-%%'
                        and vehicle_id = any(%s::uuid[]))""", (ids,))
        cur.execute("""delete from public.workshop_bookings where metadata_legacy_plan_id like 'C3-PILOT-%%'
                       and vehicle_id = any(%s::uuid[])""", (ids,))
    import_run_ids = []
    if hashes:
        cur.execute("select id::text from public.import_runs where source_hash = any(%s::text[])", (hashes,))
        import_run_ids.extend(row[0] for row in cur.fetchall())
    cur.execute("select id::text from public.import_runs where summary::text like '%%C3-PILOT-%%'")
    import_run_ids.extend(row[0] for row in cur.fetchall())
    if import_run_ids:
        cur.execute("delete from public.audit_events where table_name='import_runs' and row_id = any(%s::uuid[])", (sorted(set(import_run_ids)),))
        cur.execute("delete from public.import_runs where id = any(%s::uuid[])", (sorted(set(import_run_ids)),))
    # Also remove a receipt left with vehicle_id NULL after the deliberate hard
    # deletion. Import receipts are scoped to the exact normalized source;
    # manual-edit receipts are scoped to a captured UUID.
    if ids:
        cur.execute("""delete from public.vehicle_master_operation_receipts
                       where scope_key=%s or scope_key = any(%s::text[]) or vehicle_id = any(%s::uuid[])""",
                    (SOURCE_SYSTEM, ids, ids))
        cur.execute("delete from public.vehicle_master_identity_conflicts where vehicle_ids && %s::uuid[]", (ids,))
        cur.execute("delete from public.vehicle_aliases where vehicle_id = any(%s::uuid[]) and (source_system=%s or source_batch_id=%s or source_system='manual_edit')", (ids, SOURCE_SYSTEM, SOURCE_BATCH_ID))
        cur.execute("delete from public.vehicle_master_source_records where vehicle_id = any(%s::uuid[])", (ids,))
        cur.execute("delete from public.audit_events where vehicle_id = any(%s::uuid[]) and metadata->>'stage'='stage2b_029'", (ids,))
        cur.execute("delete from public.vehicles where id = any(%s::uuid[]) and source_system=%s and source_batch_id=%s", (ids, SOURCE_SYSTEM, SOURCE_BATCH_ID))
        # Vehicle deletion can itself write history; remove history only after
        # all fixture vehicles are gone.
        cur.execute("delete from public.vehicle_master_history where vehicle_id = any(%s::uuid[]) or entity_id = any(%s::uuid[])", (ids, ids))
    cur.execute("""delete from public.vehicle_master_source_records
                   where source_system=%s and (source_batch_id=%s or source_record_id like 'C3-%%')""",
                (SOURCE_SYSTEM, SOURCE_BATCH_ID))
    # Final content-bounded sweep catches history/audit rows whose vehicle FK
    # was nulled by the deliberate hard delete or whose entity is an alias/
    # source row. The three literals are unique to this synthetic pilot.
    for table in ("vehicle_master_history", "audit_events"):
        cur.execute(
            "delete from public." + table + " where "
            "coalesce(before_data::text,'')||coalesce(after_data::text,'')||metadata::text ilike %s "
            "or coalesce(before_data::text,'')||coalesce(after_data::text,'')||metadata::text ilike %s "
            "or coalesce(before_data::text,'')||coalesce(after_data::text,'')||metadata::text ilike %s",
            ("%" + SOURCE_SYSTEM + "%", "%" + SOURCE_BATCH_ID + "%",
             "%C3-PILOT-DURABLE-RECEIPT%"),
        )
    # Defensive exact-prefix cleanup for an importer receipt whose booking was
    # already removed during a prior interrupted run.
    cur.execute("delete from public.import_runs where summary::text like '%%C3-PILOT-%%'")
    conn.commit()


def _booking(vehicle_key, stage_code):
    return {"legacy_plan_id": "C3-PILOT-DURABLE-RECEIPT", "legacy_vehicle_key": vehicle_key,
            "stage_code": stage_code, "bay_number": None, "assignee": "",
            "scheduled_start_at": "2026-07-18T08:00:00Z", "scheduled_end_at": "2026-07-18T09:00:00Z",
            "duration_minutes": 60, "status": "planned", "raw_legacy_record": {"synthetic": True}}


def _validator_cli(extract, reference, expected_revision, temp_dir):
    extract_path = temp_dir / "extract.json"
    reference_path = temp_dir / "reference.json"
    extract_path.write_text(canonical_json(extract), encoding="utf-8")
    reference_path.write_text(canonical_json(reference), encoding="utf-8")
    completed = subprocess.run(
        ["node", str(ROOT / "scripts" / "workshop_planner_legacy_validate.js"),
         str(extract_path), str(reference_path), "--expected-revision", str(expected_revision)],
        cwd=ROOT, text=True, capture_output=True, check=False,
    )
    if completed.returncode:
        raise C3PilotRefusal("Node legacy validator refused the synthetic temp files")
    return {"passed": True, "output_sha256": hashlib.sha256(completed.stdout.encode()).hexdigest()}


def _preview(conn, admin, record_id, payload, expected_version=None):
    return _rpc(
        conn,
        "select public.preview_vehicle_master_import(%s,%s,%s,%s::jsonb,%s)",
        (SOURCE_SYSTEM, SOURCE_BATCH_ID, record_id, json.dumps(payload), expected_version),
        admin,
    )


def _apply(conn, admin, record_id, payload, expected_version, key):
    return _rpc(
        conn,
        "select public.apply_vehicle_master_import(%s,%s,%s,%s::jsonb,%s,%s)",
        (SOURCE_SYSTEM, SOURCE_BATCH_ID, record_id, json.dumps(payload), expected_version, key),
        admin,
    )


def _edit(conn, admin, vehicle_id, expected_version, changes, reason, key):
    return _rpc(
        conn,
        "select public.edit_vehicle_master(%s,%s,%s::jsonb,%s,%s)",
        (vehicle_id, expected_version, json.dumps(changes), reason, key),
        admin,
    )


def _prove_preview_apply(conn, admin, scenario_id, record_id, payload, expected_version,
                         key, previews, captured_ids, *, response_loss=False, get_conn=None):
    first = _preview(conn, admin, record_id, payload, expected_version)
    second = _preview(conn, admin, record_id, payload, expected_version)
    if first != second:
        raise AssertionError(f"repeated migration 029 preview differed for {scenario_id}")
    previews.append(sanitize_preview(scenario_id, first))
    if not first.get("ok"):
        raise AssertionError(f"migration 029 preview refused safe scenario {scenario_id}: {first.get('code')}")
    applied = _apply(conn, admin, record_id, payload, expected_version, key)
    if not applied.get("ok") or applied.get("data", {}).get("preview") != first.get("data"):
        raise AssertionError(f"migration 029 preview/apply parity failed for {scenario_id}")
    vehicle_id = applied["data"]["vehicle_id"]
    captured_ids.add(vehicle_id)
    conn.commit()
    if response_loss:
        # The committed response is deliberately discarded at the transport
        # boundary; a new connection must recover the exact durable receipt.
        expected_response = applied
        conn.close()
        conn = get_conn()
        conn.autocommit = False
        admin = _admin(conn)
        replay = _apply(conn, admin, record_id, payload, expected_version, key)
        conn.commit()
        if replay != expected_response:
            raise AssertionError("migration 029 response-loss replay did not return the exact durable receipt")
    else:
        replay = _apply(conn, admin, record_id, payload, expected_version, key)
        conn.commit()
        if replay != applied:
            raise AssertionError(f"migration 029 exact idempotent replay failed for {scenario_id}")
    return conn, admin, first, applied


def _typed_artifact_refusals(extract, reference, revision):
    stale_refused = malformed_refused = truncated_refused = False
    try:
        classify(extract, reference, expected_revision=revision + 1)
    except VehicleIdentityExportStale:
        stale_refused = True
    malformed = json.loads(json.dumps(reference))
    malformed["vehicleIdentityArtifact"]["items"][0]["prohibited"] = True
    try:
        classify(extract, malformed, expected_revision=revision)
    except Exception:
        malformed_refused = True
    truncated = json.loads(json.dumps(reference))
    truncated["vehicleIdentityArtifact"]["completion"]["complete"] = False
    try:
        classify(extract, truncated, expected_revision=revision)
    except Exception:
        truncated_refused = True
    if not (stale_refused and malformed_refused and truncated_refused):
        raise AssertionError("stale, malformed, or truncated typed artifact was not refused")
    return {"stale_revision_refused": True, "malformed_refused": True, "truncated_refused": True}


def run_pilot(evidence_dir, database_url):
    assert_exact_project_guard(database_url=database_url)
    fixture = load_fixture()
    rows = {row["id"]: row for row in fixture["scenarios"]}
    sys.path.insert(0, str(ROOT / "_staging_test_tools"))
    from staging_conn import get_conn

    conn = get_conn()
    conn.autocommit = False
    captured_ids, import_fingerprints = set(), set()
    baseline = bundle = None
    try:
        cleanup_synthetic(conn, discover_synthetic_ids(conn), set())
        baseline = _counts(conn)
        admin = _admin(conn)
        previews, operation_results = [], {}

        def operation_evidence(scenario_id, **result):
            record = {**rows[scenario_id], "source_system": SOURCE_SYSTEM}
            return build_operation_evidence(record, **result)

        def apply_scenario(scenario_id, payload=None, expected_version=None,
                           key_suffix=None, response_loss=False, record_id=None):
            nonlocal conn, admin
            row = rows.get(scenario_id, {})
            rid = record_id or row.get("source_record_id") or ("C3-SETUP-" + scenario_id.upper())
            body = payload if payload is not None else row.get("payload", {})
            key = "C3-029-" + (key_suffix or scenario_id).upper().replace("_", "-")
            conn, admin, preview, applied = _prove_preview_apply(
                conn, admin, scenario_id, rid, body, expected_version, key,
                previews, captured_ids, response_loss=response_loss, get_conn=get_conn)
            vehicle_id = applied["data"]["vehicle_id"]
            if scenario_id in rows:
                operation_results[scenario_id] = operation_evidence(
                    scenario_id, action=preview["data"]["action"], vehicle_id=vehicle_id)
            return vehicle_id

        apply_scenario("new_stock_only")
        apply_scenario("new_vin_only", response_loss=True)
        apply_scenario("stock_vin_job_match")
        apply_scenario("alias_match")
        apply_scenario("alias_match", {"stock_number": "C3-ALIAS-NEW"}, 1, "alias-canonical-update")
        operation_results.pop("alias_match", None)
        apply_scenario("retained_source_evidence_match", {"stock_number": "C3-STK-SOURCE-EVIDENCE"})
        operation_results.pop("retained_source_evidence_match", None)

        manual_id = apply_scenario("manual_edit_after_import")
        edited = _edit(conn, admin, manual_id, 1, {"model": "Synthetic Manual Edit"},
                       "C3 synthetic manual divergence", "C3-EDIT-MANUAL")
        if not edited.get("ok"):
            raise AssertionError("synthetic manual edit failed")
        conn.commit()
        replay_edit = _edit(conn, admin, manual_id, 1, {"model": "Synthetic Manual Edit"},
                            "C3 synthetic manual divergence", "C3-EDIT-MANUAL")
        if replay_edit != edited:
            raise AssertionError("manual-edit receipt replay was not exact")
        conn.commit()
        operation_results.pop("manual_edit_after_import", None)

        stale_id = apply_scenario("stale_optimistic_version")
        if not _edit(conn, admin, stale_id, 1, {"model": "Synthetic Version Two"},
                     "C3 synthetic version bump", "C3-EDIT-STALE").get("ok"):
            raise AssertionError("stale-version setup failed")
        conn.commit()
        stale_payload = {"stock_number": "C3-STK-STALE", "model": "Synthetic Stale Import"}
        stale_preview = _preview(conn, admin, rows["stale_optimistic_version"]["source_record_id"], stale_payload, 1)
        if stale_preview != _preview(conn, admin, rows["stale_optimistic_version"]["source_record_id"], stale_payload, 1):
            raise AssertionError("stale preview was not deterministic")
        previews.append(sanitize_preview("stale_optimistic_version", stale_preview))
        stale_apply = _apply(conn, admin, rows["stale_optimistic_version"]["source_record_id"],
                             stale_payload, 1, "C3-029-STALE-REFUSAL")
        if stale_apply.get("ok") or stale_apply.get("code") != "stale_version":
            raise AssertionError("stale optimistic import was not refused")
        conn.rollback()
        operation_results["stale_optimistic_version"] = operation_evidence(
            "stale_optimistic_version", code="stale_version", vehicle_id=stale_id, actual_version=2)

        apply_scenario("unchanged_replay")
        unchanged_id = apply_scenario("unchanged_replay", expected_version=1, key_suffix="unchanged-no-change")
        operation_results["unchanged_replay"] = operation_evidence(
            "unchanged_replay", action="no_change", vehicle_id=unchanged_id)
        updated_id = apply_scenario("updated_import", {"stock_number": "C3-STK-UPDATED", "model": "Synthetic Original"})
        apply_scenario("updated_import", expected_version=1, key_suffix="updated-second")
        operation_results["updated_import"] = operation_evidence(
            "updated_import", action="update", vehicle_id=updated_id)

        archived_id = apply_scenario("archived_vehicle")
        deleted_id = apply_scenario("deleted_retained_source_evidence", {"stock_number": "C3-STK-DELETED"})
        apply_scenario("missing_in_legacy")
        operation_results.pop("missing_in_legacy", None)
        cur = conn.cursor()
        cur.execute("update public.vehicles set deleted_at=now() where id=%s returning id::text", (archived_id,))
        if not cur.fetchone():
            raise AssertionError("archived vehicle setup failed")
        cur.execute("delete from public.vehicles where id=%s", (deleted_id,))
        conn.commit()
        deleted_preview = _preview(conn, admin, rows["deleted_retained_source_evidence"]["source_record_id"], {}, None)
        previews.append(sanitize_preview("deleted_retained_source_evidence", deleted_preview))
        if deleted_preview.get("code") != "unlinked_source_evidence":
            raise AssertionError("deleted source evidence was not retained")
        operation_results["deleted_retained_source_evidence"] = operation_evidence(
            "deleted_retained_source_evidence", code="unlinked_source_evidence")

        apply_scenario("duplicate_normalized_stock", {"stock_number": "C3-DUP-STOCK"})
        dup_stock_b = apply_scenario("setup_dup_stock_b", {"vin": "JTNAA3BB4C5000011"}, record_id="C3-SETUP-DUP-STOCK-B")
        apply_scenario("duplicate_normalized_job_card", {"job_card_number": "C3-DUP-JOB"})
        dup_job_b = apply_scenario("setup_dup_job_b", {"vin": "JTNAA3BB4C5000012"}, record_id="C3-SETUP-DUP-JOB-B")
        apply_scenario("canonical_alias_conflict")
        canon_alias_b = apply_scenario("setup_canon_alias_b", {"vin": "JTNAA3BB4C5000013"}, record_id="C3-SETUP-CANON-ALIAS-B")
        apply_scenario("canonical_source_evidence_conflict")
        source_b = apply_scenario("setup_source_conflict_b", {"vin": "JTNAA3BB4C5000014"}, record_id="C3-SETUP-SOURCE-CONFLICT-B")
        cur = conn.cursor()
        # These three pre-foundation conflict shapes cannot be created through
        # current guarded APIs. Disable triggers only inside this transaction;
        # SET LOCAL resets automatically at commit/rollback.
        cur.execute("set local session_replication_role = replica")
        cur.execute("""insert into public.vehicle_aliases
                       (vehicle_id, alias_type, alias_value, source_system, source_batch_id)
                       values (%s,'stock_number','C3-DUP-STOCK',%s,%s),
                              (%s,'stock_number','C3-CANON-ALIAS',%s,%s)""",
                    (dup_stock_b, SOURCE_SYSTEM, SOURCE_BATCH_ID, canon_alias_b, SOURCE_SYSTEM, SOURCE_BATCH_ID))
        cur.execute("update public.vehicles set job_card_number='C3-DUP-JOB' where id=%s", (dup_job_b,))
        cur.execute("""insert into public.vehicle_master_source_records
                       (vehicle_id, source_system, source_record_id, source_batch_id,
                        source_metadata, original_evidence)
                       values (%s,%s,%s,%s,'{}'::jsonb,'{}'::jsonb)""",
                    (source_b, SOURCE_SYSTEM, rows["canonical_source_evidence_conflict"]["source_record_id"], SOURCE_BATCH_ID))
        conn.commit()

        refusal_codes = {
            "duplicate_normalized_stock": "duplicate_normalized_claim",
            "duplicate_normalized_job_card": "duplicate_normalized_claim",
            "canonical_alias_conflict": "canonical_alias_conflict",
            "canonical_source_evidence_conflict": "canonical_source_evidence_conflict",
            "ambiguous_identity": "ambiguous_match"}
        for scenario_id, reason in refusal_codes.items():
            row = rows[scenario_id]
            response = _preview(conn, admin, row["source_record_id"], row["payload"], None)
            if response != _preview(conn, admin, row["source_record_id"], row["payload"], None):
                raise AssertionError(f"refusal preview differed for {scenario_id}")
            previews.append(sanitize_preview(scenario_id, response))
            if response.get("ok") or response.get("code") != "ambiguous_match":
                raise AssertionError(f"029 did not refuse {scenario_id}")
            operation_results[scenario_id] = operation_evidence(scenario_id, code=reason)

        for scenario_id in ("malformed_vin", "placeholder_stock", "missing_identity"):
            row = rows[scenario_id]
            response = _preview(conn, admin, row["source_record_id"], row["payload"], None)
            if response != _preview(conn, admin, row["source_record_id"], row["payload"], None):
                raise AssertionError(f"invalid preview differed for {scenario_id}")
            previews.append(sanitize_preview(scenario_id, response))
        conn.rollback()

        reference = fetch_reference_data(conn, actor_email=admin[0], page_size=7, generated_at="2026-07-18T12:00:00Z")
        repeated = fetch_reference_data(conn, actor_email=admin[0], page_size=7, generated_at="2026-07-18T12:00:00Z")
        if reference != repeated:
            raise AssertionError("031 artifact regeneration was not deterministic")
        artifact = reference["vehicleIdentityArtifact"]
        legacy=[]
        for row in fixture["scenarios"]:
            if row.get("exclude_from_legacy"):
                continue
            record={**row,"source_system":SOURCE_SYSTEM}
            if row["id"] in {"retained_source_evidence_match","deleted_retained_source_evidence"}:
                record["allow_source_evidence_only"]=True
            if row["id"]=="manual_edit_after_import":
                record["desired_fields"]={"model":"Synthetic Original"}
            legacy.append(record)
        cur=conn.cursor()
        cur.execute("select id::text, model from public.vehicles where id = any(%s::uuid[])",(sorted(captured_ids),))
        actual_fields={vehicle_id:{"model":model} for vehicle_id,model in cur.fetchall()}
        report=build_reconciliation_report(artifact=artifact,legacy_records=legacy,
            operation_results=operation_results,actual_vehicle_fields=actual_fields,
            expected_resolver_revision=artifact["resolver_revision"])
        validate_reconciliation_report(report)
        required={row["expected_outcome"] for row in fixture["scenarios"]}
        actual={row["outcome"] for row in report["results"]}
        if not required <= actual:
            raise AssertionError(f"reconciliation omitted {sorted(required-actual)}")
        for expected_row in fixture["scenarios"]:
            candidates = [result for result in report["results"]
                          if result["scenario_id"] == expected_row["id"]]
            if not candidates and expected_row.get("exclude_from_legacy"):
                candidates = [result for result in report["results"]
                              if result["source_record_id"] == expected_row["source_record_id"]]
            if not any(result["outcome"] == expected_row["expected_outcome"]
                       and result["reason_code"] == expected_row["reason_code"]
                       for result in candidates):
                raise AssertionError(f"reconciliation mismatch for {expected_row['id']}: {candidates}")

        stage_code=reference["stages"][0]["code"]
        extract={"source_backup_type":"workshop_planner_legacy_export","exported_at":SOURCE_BATCH_ID,
                 "bookings":[_booking(rows["new_stock_only"]["payload"]["stock_number"],stage_code)]}
        revision=artifact["resolver_revision"]
        buckets=classify(extract,reference,expected_revision=revision)
        if len(buckets["safely_matched"])!=1:
            raise AssertionError("C2b classifier did not resolve synthetic booking")
        dry=run_import(conn,extract,reference,apply=False)
        typed_refusals=_typed_artifact_refusals(extract,reference,revision)
        with tempfile.TemporaryDirectory(prefix="pdc-c3-") as temp:
            validator=_validator_cli(extract,reference,revision,Path(temp))

        rollback_reference=fetch_reference_data(conn,actor_email=admin[0],vehicle_export_rollback=True)
        rollback_revision=rollback_reference["vehicleIdentityExport"]["export_revision"]
        rb=classify(extract,rollback_reference,expected_revision=rollback_revision,legacy_reference_rollback=True)
        if len(rb["safely_matched"])!=1:
            raise AssertionError("rollback export did not resolve synthetic booking")
        rollback_dry=run_import(conn,extract,rollback_reference,apply=False,vehicle_export_rollback=True)
        stale_ref=json.loads(json.dumps(rollback_reference))
        stale_ref["vehicleIdentityExport"]["export_revision"]=rollback_revision+1
        try:
            run_import(conn,extract,stale_ref,apply=False,vehicle_export_rollback=True)
        except VehicleIdentityExportStale:
            stale_refused=True
        else:
            stale_refused=False
        if not stale_refused:
            raise AssertionError("stale rollback was not refused")

        durable=run_import(conn,extract,reference,apply=True,commit_apply=True)
        import_fingerprints.add(durable["request_fingerprint"])
        conn.close()
        conn=get_conn(); conn.autocommit=False; admin=_admin(conn)
        replay=run_import(conn,extract,reference,apply=True,commit_apply=True)
        if durable.get("replayed") or not replay.get("replayed") or (
                immutable_receipt_projection(replay) != immutable_receipt_projection(durable)):
            raise AssertionError("C2b response-loss replay failed")

        bundle={
          "pilot":{"schema_version":"pdc.stage2b.c3-pilot-evidence/v1","source_system":SOURCE_SYSTEM,
            "source_batch_id":SOURCE_BATCH_ID,"scenario_count":len(fixture["scenarios"]),
            "preview_deterministic":True,"preview_apply_parity":True,"exact_apply_replay":True,
            "response_loss_replay":True,"validator_cli":validator["passed"],
            "c2b_dry_run":not dry["apply"] and not rollback_dry["apply"],
            "evidence_files":sorted(EVIDENCE_FILES.values())},
          "preview":sorted(previews,key=lambda item:(item["scenario_id"],item.get("action") or "")),
          "artifact":{"schema_version":artifact["schema_version"],"resolver_revision":revision,
            "item_count":artifact["item_count"],"checksum":artifact["checksum"],
            "deterministic_regeneration":True,**typed_refusals},
          "reconciliation":report,
          "rollback":{"rollback_used":True,"exact_revision_lock":rollback_revision,
            "stale_rollback_refused":True,"synthetic_apply_receipt_replayed":True},
          "cleanup":{}}
    finally:
        if conn.closed:
            conn=get_conn(); conn.autocommit=False
        conn.rollback()
        cleanup_synthetic(conn,captured_ids,import_fingerprints)
        after=_counts(conn) if baseline is not None else None
        if bundle is not None:
            cur=conn.cursor()
            cur.execute("select count(*) from public.vehicle_master_identity_conflicts where resolved_at is null and vehicle_ids && %s::uuid[]",(sorted(captured_ids),))
            unresolved=cur.fetchone()[0]
            cur.execute("select count(*) from pg_namespace where nspname like 'c3_pilot_%%'")
            temp_schemas=cur.fetchone()[0]
            cur.execute("select count(*) from pg_roles where rolname like 'c3_pilot_%%'")
            temp_roles=cur.fetchone()[0]
            restored=baseline==after
            residue = _synthetic_residue_counts(conn)
            bundle["cleanup"]={"baseline_counts":baseline,"after_counts":after,
              "baseline_restored":restored,"unresolved_synthetic_conflicts":unresolved,
              "temp_schemas":temp_schemas,"temp_roles":temp_roles,
              "synthetic_residue_counts":residue}
            if not restored or unresolved or temp_schemas or temp_roles or any(residue.values()):
                bundle=None
                raise AssertionError("C3 cleanup did not restore baseline")
        conn.close()
    if bundle is None:
        raise C3PilotRefusal("pilot did not complete")
    write_evidence(evidence_dir,bundle)
    return bundle["pilot"]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", required=True)
    args = parser.parse_args(argv)
    database_url = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    summary = run_pilot(args.evidence_dir, database_url)
    print(canonical_json(summary))


if __name__ == "__main__":
    main()
