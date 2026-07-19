"""Controlled Stage 2B C6 real-data pilot for the exact guarded staging project.

This module is import-safe. Live execution requires --apply, the approved C4 ZIP,
a fresh encrypted-backup manifest, and a passed isolated restore report. It does
not read or modify browser storage, frontend files, deployments, or production.
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
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
APPROVED_C4_SHA256 = "980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016"
APPROVED_C4_HEAD = "1a73e3a1d1bf6c3abd2b8a349e2f1c2e0f7490ac"
SOURCE_SYSTEM = "browser_local_c4"
SELECTED_COUNT = 25
PROJECT_REF_PATH = ROOT / "supabase" / ".temp" / "project-ref"
COUNT_TABLES = (
    "vehicles", "vehicle_aliases", "vehicle_master_source_records",
    "vehicle_master_history", "vehicle_master_identity_conflicts",
    "vehicle_master_operation_receipts", "audit_events", "import_runs",
    "workshop_bookings", "workshop_booking_assignments", "workshop_booking_history",
)
ROLLBACK_TABLES = (
    "vehicles", "vehicle_aliases", "vehicle_master_source_records",
    "vehicle_master_operation_receipts", "vehicle_master_history", "audit_events",
)

sys.path.insert(0, str(ROOT / "scripts"))
from stage2b_c4_assessment import assess_export, canonical_json  # noqa: E402
from workshop_legacy_import import classify, fetch_reference_data  # noqa: E402
from workshop_vehicle_reference_artifact import build_vehicle_reference_artifact  # noqa: E402


class C6PilotRefusal(RuntimeError):
    pass


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_sha(value) -> str:
    return sha256_bytes(canonical_json(value).encode("utf-8"))


def assert_exact_project_guard(project_ref_path=PROJECT_REF_PATH, database_url=None):
    path = Path(project_ref_path)
    if not path.is_file() or path.read_text(encoding="utf-8").strip() != STAGING_REF:
        raise C6PilotRefusal("refusing C6 pilot: linked project is not exact staging")
    parsed = urlparse(str(database_url or "").strip())
    host = (parsed.hostname or "").lower()
    user = unquote(parsed.username or "")
    direct = host == f"db.{STAGING_REF}.supabase.co" and user == "postgres"
    pooler_host = bool(re.fullmatch(r"aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com", host))
    pooled = pooler_host and user == f"postgres.{STAGING_REF}"
    if (parsed.scheme not in {"postgres", "postgresql"} or parsed.path != "/postgres"
            or not (direct or pooled)):
        raise C6PilotRefusal("refusing C6 pilot: DSN does not identify exact staging")
    return True


def load_approved_c4(zip_path):
    path = Path(zip_path)
    raw = path.read_bytes()
    if sha256_bytes(raw) != APPROVED_C4_SHA256:
        raise C6PilotRefusal("C4 package checksum is not the approved checksum")
    with zipfile.ZipFile(path) as archive:
        payload = json.loads(archive.read("STAGE-2B-C4-SANITIZED-ASSESSMENT.json"))
    summary, _details, manual_rows = assess_export(payload)
    if summary["classification_counts"]["clean"] != 192:
        raise C6PilotRefusal("approved C4 clean-record count changed")
    return payload, summary


def select_records(payload):
    summary, _details, manual_rows = assess_export(payload)
    excluded_refs = {row["record_ref"] for row in manual_rows if row["record_type"] == "vehicle"}
    workflow_keys = {row["legacy_vehicle_key"] for row in payload["workflow_records"]}
    deleted_keys = {row["legacy_vehicle_key"] for row in payload["deleted_records"]}
    booking_keys = {row["legacy_vehicle_key"] for row in payload["bookings"]}
    eligible = []
    for row in sorted(payload["vehicles"], key=lambda item: item["record_ref"]):
        if row["record_ref"] in excluded_refs:
            continue
        if row["legacy_vehicle_key"] in workflow_keys | deleted_keys | booking_keys:
            continue
        if row["workflow_field_names"] or row["parts_task_count"] or row["parts_file_count"]:
            continue
        eligible.append(row)
    selected = eligible[5:5 + SELECTED_COUNT]
    if len(selected) != SELECTED_COUNT or summary["classification_counts"]["clean"] != 192:
        raise C6PilotRefusal("C6 deterministic clean selection is unavailable")
    return selected


def source_payload(row):
    payload = {
        "stock_number": row["stock_number"],
        "vin": row["vin"],
        "toyota_order_number": row["toyota_order_number"],
    }
    if not all(isinstance(value, str) and value.strip() for value in payload.values()):
        raise C6PilotRefusal(f"selected source identity is incomplete: {row['record_ref']}")
    return payload


def selected_manifest(selected, source_assessment_sha256):
    rows = []
    for row in selected:
        payload = source_payload(row)
        rows.append({
            "record_ref": row["record_ref"],
            "source_family": row["source_family"],
            "legacy_vehicle_key": row["legacy_vehicle_key"],
            "payload": payload,
            "payload_sha256": canonical_sha(payload),
            "inclusion_reason": (
                "C4 clean and deterministic; unique valid stock/VIN/Toyota-order claims; "
                "no ambiguity, conflict, malformed/placeholder identity, deletion/archive, "
                "manual-review row, workflow/Parts/booking attachment, orphan, or parse error"
            ),
        })
    logical = {
        "schema": "pdc.stage2b.c6-selected-records/v1",
        "approved_c4_sha256": APPROVED_C4_SHA256,
        "approved_c4_head": APPROVED_C4_HEAD,
        "source_assessment_sha256": source_assessment_sha256,
        "selection_rule": "UTF-8 record_ref ascending; eligible clean attachment-free records 6 through 30",
        "selected_count": len(rows),
        "records": rows,
    }
    return {**logical, "checksum": {"algorithm": "sha256", "value": canonical_sha(logical)}}


def validate_backup_evidence(manifest_path, restore_report_path):
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    restore = json.loads(Path(restore_report_path).read_text(encoding="utf-8"))
    manifest_path = Path(manifest_path)
    if not manifest_path.name.endswith(".manifest.json"):
        raise C6PilotRefusal("backup manifest filename is invalid")
    backup_file = manifest_path.with_name(manifest_path.name.removesuffix(".manifest.json"))
    if not backup_file.is_file() or sha256_bytes(backup_file.read_bytes()) != manifest.get("file_sha256"):
        raise C6PilotRefusal("fresh encrypted backup checksum verification failed")
    if manifest.get("environment") != "staging" or manifest.get("migration_version") != "031" or manifest.get("encrypted") is not True:
        raise C6PilotRefusal("backup environment, ledger, or encryption evidence is invalid")
    if (restore.get("backup_run_id") != manifest.get("backup_run_id")
            or restore.get("backup_environment") != "staging"
            or restore.get("migration_version") != "031"
            or restore.get("all_checks_passed") is not True
            or restore.get("row_count_mismatches") != []
            or restore.get("foreign_keys_skipped") != []):
        raise C6PilotRefusal("isolated backup restore test did not pass exactly")
    finished = datetime.fromisoformat(manifest["finished_at"])
    age_seconds = (datetime.now(timezone.utc) - finished).total_seconds()
    if age_seconds < 0 or age_seconds > 6 * 60 * 60:
        raise C6PilotRefusal("backup is not fresh enough for this C6 execution")
    return {
        "schema": "pdc.stage2b.c6-backup-restore/v1",
        "backup_run_id": manifest["backup_run_id"],
        "backup_file_name": manifest["file_name"],
        "backup_file_size_bytes": manifest["file_size_bytes"],
        "backup_file_sha256": manifest["file_sha256"],
        "encrypted": True,
        "migration_version": "031",
        "backup_row_counts": manifest["row_counts"],
        "decrypt_and_manifest_verified": True,
        "isolated_restore_all_checks_passed": True,
        "foreign_keys_discovered": restore["foreign_keys_discovered"],
        "foreign_keys_added": restore["foreign_keys_added"],
        "foreign_keys_skipped": [],
        "restore_schema_removed": True,
    }


def _admin(conn):
    cur = conn.cursor()
    cur.execute("""select r.email, u.id::text from public.pdc_user_roles r
                   join auth.users u on lower(u.email)=lower(r.email)
                   where r.active and r.role='administrator' order by r.email limit 1""")
    row = cur.fetchone()
    if not row:
        raise C6PilotRefusal("staging administrator fixture is unavailable")
    return row


def _rpc(conn, sql, params, admin):
    cur = conn.cursor()
    cur.execute("set local role authenticated")
    cur.execute("select set_config('request.jwt.claims', %s, true)",
                (json.dumps({"email": admin[0], "sub": admin[1], "role": "authenticated"}),))
    try:
        cur.execute(sql, params)
        return cur.fetchone()[0]
    finally:
        cur.execute("reset role")


def _preview(conn, admin, batch_id, record_id, payload, expected_version=None):
    return _rpc(conn, "select public.preview_vehicle_master_import(%s,%s,%s,%s::jsonb,%s)",
                (SOURCE_SYSTEM, batch_id, record_id, json.dumps(payload), expected_version), admin)


def _apply(conn, admin, batch_id, record_id, payload, expected_version, key):
    return _rpc(conn, "select public.apply_vehicle_master_import(%s,%s,%s,%s::jsonb,%s,%s)",
                (SOURCE_SYSTEM, batch_id, record_id, json.dumps(payload), expected_version, key), admin)


def _counts(conn):
    cur = conn.cursor()
    result = {}
    for table in COUNT_TABLES:
        cur.execute("select count(*) from public." + table)
        result[table] = cur.fetchone()[0]
    return result


def _migration_ledger(conn):
    cur = conn.cursor()
    cur.execute("select version from supabase_migrations.schema_migrations order by version")
    return [str(row[0]) for row in cur.fetchall()]


def _unrelated_vehicle_hash(conn, excluded_ids=()):
    cur = conn.cursor()
    cur.execute("""select coalesce(jsonb_agg(to_jsonb(v) order by v.id), '[]'::jsonb)
                   from public.vehicles v where not (v.id = any(%s::uuid[]))""", (list(excluded_ids),))
    return canonical_sha(cur.fetchone()[0])


def _backup_vehicle_hash(manifest_path):
    from pdc_backup import decrypt_backup
    manifest_path = Path(manifest_path)
    backup_file = manifest_path.with_name(manifest_path.name.removesuffix(".manifest.json"))
    key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY", "")
    if not key:
        raise C6PilotRefusal("backup encryption key is required for baseline comparison")
    data = decrypt_backup(backup_file, key.encode())
    rows = list(data["tables"]["vehicles"]["rows"])
    rows.sort(key=lambda row: row["id"])
    return canonical_sha(rows)


def _connect_guarded(database_url):
    # Bind the driver to the exact DSN which passed the project-ref, host,
    # database, and user guard; never re-resolve the connection environment.
    import psycopg2
    return psycopg2.connect(database_url)


def _selected_namespace_counts(conn, vehicle_ids, batch_id):
    ids = list(vehicle_ids)
    cur = conn.cursor()
    checks = {
        "vehicles": ("select count(*) from public.vehicles where id=any(%s::uuid[]) and source_system=%s and source_batch_id=%s", (ids, SOURCE_SYSTEM, batch_id)),
        "aliases": ("select count(*) from public.vehicle_aliases where vehicle_id=any(%s::uuid[])", (ids,)),
        "source_records": ("select count(*) from public.vehicle_master_source_records where vehicle_id=any(%s::uuid[]) and source_system=%s and source_batch_id=%s", (ids, SOURCE_SYSTEM, batch_id)),
        "receipts": ("select count(*) from public.vehicle_master_operation_receipts where vehicle_id=any(%s::uuid[]) and scope_key=%s", (ids, SOURCE_SYSTEM)),
        "unresolved_conflicts": ("select count(*) from public.vehicle_master_identity_conflicts where resolved_at is null and vehicle_ids && %s::uuid[]", (ids,)),
    }
    out = {}
    for key, (sql, params) in checks.items():
        cur.execute(sql, params)
        out[key] = cur.fetchone()[0]
    return out


def _safe_preview(record_ref, response):
    data = response.get("data", {}) if isinstance(response, dict) else {}
    return {
        "record_ref": record_ref,
        "ok": response.get("ok") is True,
        "code": response.get("code"),
        "action": data.get("action"),
        "vehicle_id": data.get("vehicle_id"),
        "expected_version": data.get("expected_version"),
        "proposed_version": (data.get("proposed") or {}).get("version"),
        "candidate_count": len(data.get("candidate_ids") or []),
        "request_fingerprint": data.get("request_fingerprint"),
    }


def validate_preview_response(record_ref, first, second):
    if first != second:
        raise C6PilotRefusal(f"preview is not deterministic: {record_ref}")
    data = first.get("data", {}) if isinstance(first, dict) else {}
    if first.get("ok") is not True or first.get("code") != "ok":
        raise C6PilotRefusal(f"preview refused selected record: {record_ref}: {first.get('code')}")
    if data.get("action") not in {"insert", "update", "no_change"}:
        raise C6PilotRefusal(f"preview action is invalid: {record_ref}")
    candidate_sets = data.get("candidate_sets") or {}
    candidates = data.get("candidate_ids") or []
    if len(candidates) > 1 or any(len(value or []) > 1 for value in candidate_sets.values()):
        raise C6PilotRefusal(f"preview contains ambiguity/conflict: {record_ref}")
    if data.get("action") != "insert" and data.get("expected_version") is None:
        raise C6PilotRefusal(f"update/no-op preview lacks version lock: {record_ref}")
    return _safe_preview(record_ref, first)


def _typed_item(reference, vehicle_id):
    items = reference["vehicleIdentityArtifact"]["items"]
    matches = [row for row in items if row["vehicle_id"] == vehicle_id]
    if len(matches) != 1:
        raise C6PilotRefusal(f"migration 031 artifact did not contain one selected UUID: {vehicle_id}")
    return matches[0]


def _validator_cli(extract, reference, revision):
    with tempfile.TemporaryDirectory(prefix="pdc-c6-validator-") as temp:
        temp = Path(temp)
        extract_path, reference_path = temp / "extract.json", temp / "reference.json"
        extract_path.write_text(canonical_json(extract), encoding="utf-8")
        reference_path.write_text(canonical_json(reference), encoding="utf-8")
        completed = subprocess.run(
            ["node", str(ROOT / "scripts" / "workshop_planner_legacy_validate.js"),
             str(extract_path), str(reference_path), "--expected-revision", str(revision)],
            cwd=ROOT, text=True, capture_output=True, check=False,
            env={**os.environ, "NODE_OPTIONS": "--no-warnings"},
        )
    if completed.returncode:
        raise C6PilotRefusal("C2b Node validator refused the selected batch")
    return sha256_bytes(completed.stdout.encode("utf-8"))


def _strip_prohibited_evidence_fields(value):
    if isinstance(value, dict):
        return {
            key: _strip_prohibited_evidence_fields(child)
            for key, child in value.items()
            if key not in {"customer_name", "actor_email"}
        }
    if isinstance(value, list):
        return [_strip_prohibited_evidence_fields(child) for child in value]
    return value


def _build_rollback_export(conn, vehicle_ids, batch_id, resolver_revision):
    ids = list(vehicle_ids)
    cur = conn.cursor()
    cur.execute("select revision from public.vehicle_master_revision where singleton")
    vehicle_master_revision = cur.fetchone()[0]
    tables = {}
    queries = {
        "vehicles": ("select to_jsonb(v)-'customer_name' from public.vehicles v where id=any(%s::uuid[]) order by id", (ids,)),
        "vehicle_aliases": ("select to_jsonb(a) from public.vehicle_aliases a where vehicle_id=any(%s::uuid[]) order by id", (ids,)),
        "vehicle_master_source_records": ("select to_jsonb(s) from public.vehicle_master_source_records s where vehicle_id=any(%s::uuid[]) order by id", (ids,)),
        "vehicle_master_operation_receipts": ("select to_jsonb(r)-'actor_email' from public.vehicle_master_operation_receipts r where vehicle_id=any(%s::uuid[]) order by id", (ids,)),
        "vehicle_master_history": ("select to_jsonb(h) from public.vehicle_master_history h where vehicle_id=any(%s::uuid[]) or entity_id=any(%s::uuid[]) order by id", (ids, ids)),
        "audit_events": ("select to_jsonb(a) from public.audit_events a where vehicle_id=any(%s::uuid[]) and metadata->>'stage'='stage2b_029' order by id", (ids,)),
    }
    for table, (sql, params) in queries.items():
        cur.execute(sql, params)
        tables[table] = [_strip_prohibited_evidence_fields(row[0]) for row in cur.fetchall()]
    logical = {
        "schema": "pdc.stage2b.c6-rollback-export/v1",
        "source_system": SOURCE_SYSTEM,
        "source_batch_id": batch_id,
        "resolver_revision": resolver_revision,
        "vehicle_master_revision": vehicle_master_revision,
        "vehicle_ids": sorted(ids),
        "tables": tables,
    }
    return {**logical, "checksum": {"algorithm": "sha256", "value": canonical_sha(logical)}}


def validate_rollback_export(export, expected_revision):
    logical = {key: export[key] for key in (
        "schema", "source_system", "source_batch_id", "resolver_revision",
        "vehicle_master_revision", "vehicle_ids", "tables"
    )}
    if (export.get("schema") != "pdc.stage2b.c6-rollback-export/v1"
            or export.get("source_system") != SOURCE_SYSTEM
            or export.get("resolver_revision") != expected_revision
            or set(export.get("tables", {})) != set(ROLLBACK_TABLES)
            or export.get("checksum") != {"algorithm": "sha256", "value": canonical_sha(logical)}):
        raise C6PilotRefusal("rollback export revision, schema, or checksum is invalid")
    return True


def _lock_restored_vehicle_master_revision(cur, schema, expected_revision):
    cur.execute(f'select revision from "{schema}".vehicle_master_revision where singleton for update')
    row = cur.fetchone()
    if not row or row[0] != expected_revision:
        raise C6PilotRefusal("rollback export is stale against restored database revision")
    return row[0]


def _lock_restored_resolver_revision(cur, schema, expected_revision):
    cur.execute(f'select revision from "{schema}".vehicle_lifecycle_resolver_revision where singleton for update')
    row = cur.fetchone()
    if not row or row[0] != expected_revision:
        raise C6PilotRefusal("rollback export is stale against restored resolver revision")
    return row[0]


def _prove_independent_revision_advance_refusal(cur, schema, revision_kind, expected_revision):
    definitions = {
        "vehicle_master": ("vehicle_master_revision", _lock_restored_vehicle_master_revision),
        "lifecycle_resolver": ("vehicle_lifecycle_resolver_revision", _lock_restored_resolver_revision),
    }
    if revision_kind not in definitions:
        raise C6PilotRefusal("unknown rollback revision kind")
    table, lock = definitions[revision_kind]
    savepoint = f"c6_{revision_kind}_advance"
    cur.execute(f"savepoint {savepoint}")
    try:
        cur.execute(f'update "{schema}"."{table}" set revision=revision+1 where singleton returning revision')
        advanced = cur.fetchone()
        if not advanced or advanced[0] != expected_revision + 1:
            raise C6PilotRefusal(f"{revision_kind} revision did not independently advance")
        refused = False
        try:
            lock(cur, schema, expected_revision)
        except C6PilotRefusal:
            refused = True
        if not refused:
            raise C6PilotRefusal(f"saved rollback accepted advanced {revision_kind} revision")
    finally:
        cur.execute(f"rollback to savepoint {savepoint}")
        cur.execute(f"release savepoint {savepoint}")
    locked_after_rollback = lock(cur, schema, expected_revision)
    return {
        "authoritative_revision_before": expected_revision,
        "authoritative_revision_advanced_to": expected_revision + 1,
        "saved_rollback_refused_after_advance": True,
        "advance_rolled_back_before_apply": locked_after_rollback == expected_revision,
    }


def viewer_contract_evidence(vehicle, booking):
    vehicle_fields = sorted(vehicle)
    booking_fields = sorted(booking)
    expected_vehicle_fields = sorted((
        "active_workshop_booking_id", "current_location", "id", "lifecycle_state",
        "version", "workshop_status",
    ))
    expected_booking_fields = sorted(("id", "status", "vehicle_id", "version"))
    prohibited = {
        "actor_email", "customer_email", "customer_name", "email", "file_content",
        "name", "notes", "technician_id", "technician_name",
    }
    exact = vehicle_fields == expected_vehicle_fields and booking_fields == expected_booking_fields
    prohibited_absent = not (set(vehicle_fields) | set(booking_fields)) & prohibited
    if not exact or not prohibited_absent:
        raise C6PilotRefusal("viewer evidence contract returned broad or prohibited fields")
    return {
        "vehicle_contract": "sanitized_vehicle_core_lifecycle_projection",
        "vehicle_fields_returned": vehicle_fields,
        "workshop_contract": "narrow_workshop_booking_projection",
        "workshop_fields_returned": booking_fields,
        "prohibited_fields_checked": sorted(prohibited),
        "prohibited_fields_absent": True,
        "broad_direct_vehicle_projection_used": False,
        "technician_or_sensitive_data_retained": False,
    }


def _bounded_reference_artifact(reference, selected_ids):
    selected = set(selected_ids)
    source = reference.get("vehicleIdentityArtifact", {})
    items = sorted(
        (item for item in source.get("items", []) if item.get("vehicle_id") in selected),
        key=lambda item: item["vehicle_id"],
    )
    if len(items) != SELECTED_COUNT or {item.get("vehicle_id") for item in items} != selected:
        raise C6PilotRefusal("bounded identity artifact is incomplete")
    conflicts = []
    for conflict in source.get("conflicts", []):
        vehicle_ids = set(conflict.get("vehicle_ids", []))
        if not vehicle_ids & selected:
            continue
        if not vehicle_ids <= selected:
            raise C6PilotRefusal("identity conflict crosses the approved vehicle boundary")
        conflicts.append(conflict)
    terminal = items[-1]["vehicle_id"]
    completion = {
        "complete": True,
        "page_count": 1,
        "terminal_cursor": terminal,
        "pages": [{
            "after_cursor": None,
            "end_cursor": terminal,
            "item_count": len(items),
            "has_more": False,
            "next_cursor": None,
        }],
    }
    return build_vehicle_reference_artifact({
        "outcome": "exported",
        "export_revision": source.get("resolver_revision"),
        "completion": completion,
        "items": items,
        "conflicts": conflicts,
    }, generated_at=source.get("generated_at"), source_environment=source.get("source_environment"))


def _selected_reference_evidence(reference, selected_ids):
    selected = set(selected_ids)
    artifact = reference.get("vehicleIdentityArtifact", {})
    items = [item for item in artifact.get("items", []) if item.get("vehicle_id") in selected]
    if len(items) != SELECTED_COUNT or {item.get("vehicle_id") for item in items} != selected:
        raise C6PilotRefusal("migration 031 selected-only evidence is incomplete")
    return {
        "schema": "pdc.stage2b.c6-selected-migration-031-identity-evidence/v1",
        "source_rpc": "public.export_workshop_legacy_vehicle_identities",
        "selection": "exact_selected_vehicle_ids",
        "resolver_revision": artifact.get("resolver_revision"),
        "item_count": len(items),
        "items": items,
        "unrelated_vehicle_records_retained": 0,
        "staff_records_retained": 0,
    }


def rehearse_rollback(conn, export, schema, restore_report):
    resolver_revision = export["resolver_revision"]
    revision = export["vehicle_master_revision"]
    validate_rollback_export(export, resolver_revision)
    if (not re.fullmatch(r"c6_full_rollback_[0-9a-f]{12}", schema or "")
            or restore_report.get("schema_name") != schema
            or restore_report.get("all_checks_passed") is not True
            or restore_report.get("foreign_keys_skipped") != []):
        raise C6PilotRefusal("full rollback restore schema/report is invalid")
    ids = export["vehicle_ids"]
    predicates = {
        "vehicles": ("id=any(%s::uuid[])", (ids,)),
        "vehicle_aliases": ("vehicle_id=any(%s::uuid[])", (ids,)),
        "vehicle_master_source_records": ("vehicle_id=any(%s::uuid[])", (ids,)),
        "vehicle_master_operation_receipts": ("vehicle_id=any(%s::uuid[])", (ids,)),
        "vehicle_master_history": ("vehicle_id=any(%s::uuid[]) or entity_id=any(%s::uuid[])", (ids, ids)),
        "audit_events": ("vehicle_id=any(%s::uuid[]) and metadata->>'stage'='stage2b_029'", (ids,)),
    }
    cur = conn.cursor()
    before, after, unrelated_before, unrelated_after = {}, {}, {}, {}
    try:
        resolver_advance = _prove_independent_revision_advance_refusal(
            cur, schema, "lifecycle_resolver", resolver_revision)
        resolver_stale_refused = resolver_advance["saved_rollback_refused_after_advance"]
        database_resolver_revision = _lock_restored_resolver_revision(cur, schema, resolver_revision)
        vehicle_master_advance = _prove_independent_revision_advance_refusal(
            cur, schema, "vehicle_master", revision)
        stale_refused = vehicle_master_advance["saved_rollback_refused_after_advance"]
        database_revision = _lock_restored_vehicle_master_revision(cur, schema, revision)
        cur.execute("""select count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace
                       where n.nspname=%s and c.contype='f' and c.convalidated""", (schema,))
        validated_foreign_keys = cur.fetchone()[0]
        cur.execute("""select count(*) from pg_indexes where schemaname=%s""", (schema,))
        restored_indexes = cur.fetchone()[0]
        if validated_foreign_keys != restore_report.get("foreign_keys_added") or restored_indexes < 1:
            raise C6PilotRefusal("restored schema constraints/indexes are incomplete")
        for table in ROLLBACK_TABLES:
            where, params = predicates[table]
            cur.execute(f'select to_jsonb(t) from "{schema}"."{table}" t where {where} order by id', params)
            selected_rows = [_strip_prohibited_evidence_fields(row[0]) for row in cur.fetchall()]
            before[table] = len(selected_rows)
            if selected_rows != export["tables"][table]:
                raise C6PilotRefusal(f"restored rollback rows differ from export: {table}")
            cur.execute(f"""select coalesce(jsonb_agg(to_jsonb(t) order by id), '[]'::jsonb)
                            from "{schema}"."{table}" t where not ({where})""", params)
            unrelated_before[table] = canonical_sha(cur.fetchone()[0])
        for table in (
            "audit_events", "vehicle_master_history", "vehicle_master_operation_receipts",
            "vehicle_master_source_records", "vehicle_aliases", "vehicles",
        ):
            where, params = predicates[table]
            cur.execute(f'delete from "{schema}"."{table}" where {where}', params)
            if cur.rowcount != before[table]:
                raise C6PilotRefusal(f"full rollback deleted an unexpected row count: {table}")
        cur.execute("set constraints all immediate")
        for table in ROLLBACK_TABLES:
            where, params = predicates[table]
            cur.execute(f'select count(*) from "{schema}"."{table}" where {where}', params)
            after[table] = cur.fetchone()[0]
            cur.execute(f"""select coalesce(jsonb_agg(to_jsonb(t) order by id), '[]'::jsonb)
                            from "{schema}"."{table}" t where not ({where})""", params)
            unrelated_after[table] = canonical_sha(cur.fetchone()[0])
        if any(after.values()) or unrelated_before != unrelated_after:
            raise C6PilotRefusal("full isolated rollback left selected residue or changed unrelated rows")
        final_database_resolver_revision = _lock_restored_resolver_revision(cur, schema, resolver_revision)
        final_database_revision = _lock_restored_vehicle_master_revision(cur, schema, revision)
        if final_database_resolver_revision != database_resolver_revision or final_database_revision != database_revision:
            raise C6PilotRefusal("rollback revisions changed during apply")
        conn.commit()
    finally:
        conn.rollback()
        cur = conn.cursor()
        cur.execute(f'drop schema if exists "{schema}" cascade')
        conn.commit()
    return {
        "schema": "pdc.stage2b.c6-rollback-report/v2",
        "rollback_export_checksum": export["checksum"],
        "exact_revision_lock": revision,
        "resolver_revision": resolver_revision,
        "database_resolver_revision_lock": database_resolver_revision,
        "resolver_revision_lock_verified": True,
        "resolver_independent_advance_test": resolver_advance,
        "resolver_stale_revision_attempted": resolver_revision + 1,
        "resolver_stale_revision_database_query_executed": True,
        "resolver_stale_revision_refused": True,
        "database_revision_lock_verified": True,
        "vehicle_master_independent_advance_test": vehicle_master_advance,
        "stale_revision_attempted": revision + 1,
        "stale_revision_database_query_executed": True,
        "stale_revision_refused": True,
        "isolated_schema": schema,
        "restored_schema_all_checks_passed": True,
        "validated_foreign_keys": validated_foreign_keys,
        "restored_indexes": restored_indexes,
        "copied_row_counts": before,
        "after_rollback_counts": after,
        "unrelated_restored_rows_unchanged": unrelated_before == unrelated_after,
        "full_isolated_rollback_passed": True,
        "temporary_schema_removed": True,
        "public_pilot_rows_changed_by_rehearsal": 0,
        "revisions_unchanged_through_apply": True,
    }


def _contains_non_null_key(value, target):
    if isinstance(value, dict):
        return any((key == target and child is not None) or _contains_non_null_key(child, target)
                   for key, child in value.items())
    if isinstance(value, list):
        return any(_contains_non_null_key(child, target) for child in value)
    return False


def _json_safe(value):
    if isinstance(value, dict):
        return {key: _json_safe(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(child) for child in value]
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def write_evidence(evidence_dir, files):
    target = Path(evidence_dir)
    target.mkdir(parents=True, exist_ok=True)
    for name, value in files.items():
        encoded = value if isinstance(value, str) else canonical_json(value)
        lowered = encoded.lower()
        if any(token in lowered for token in ("postgresql://", "postgres://", "password", "service_role")):
            raise C6PilotRefusal(f"prohibited credential token in evidence: {name}")
        if "customer_name" in lowered:
            parsed = json.loads(encoded)
            if _contains_non_null_key(parsed, "customer_name"):
                raise C6PilotRefusal(f"prohibited broad-data value in evidence: {name}")
        (target / name).write_text(encoded + "\n", encoding="utf-8")


def render_approval_manifest(selection, preview_result):
    selected = {row["record_ref"]: row for row in selection["records"]}
    lines = [
        "# Stage 2B C6 — Controlled Real-Data Staging Pilot Approval Manifest",
        "",
        f"- Exact staging project: `{STAGING_REF}`",
        f"- Approved C4 package SHA-256: `{APPROVED_C4_SHA256}`",
        f"- Selected records: `{selection['selected_count']}`",
        f"- Preview checksum: `{preview_result['checksum']['value']}`",
        f"- Zero ambiguity: `{str(preview_result['zero_ambiguity']).lower()}`",
        f"- Zero conflict: `{str(preview_result['zero_conflict']).lower()}`",
        "- Approval basis: Craig's direct C6 instruction; apply is permitted only while this exact preview remains unchanged.",
        "",
        "| Source record ID | Legacy key | Proposed action | Expected version | Proposed version | Vehicle UUID | Inclusion reason |",
        "|---|---|---|---:|---:|---|---|",
    ]
    for action in preview_result["actions"]:
        source = selected[action["record_ref"]]
        lines.append(
            f"| `{action['record_ref']}` | `{source['legacy_vehicle_key']}` | `{action['action']}` | "
            f"`{action['expected_version']}` | `{action['proposed_version']}` | `{action['vehicle_id']}` | "
            f"{source['inclusion_reason']} |"
        )
    lines += [
        "",
        "**Apply gate:** all 25 previews are deterministic inserts with zero ambiguity, zero conflict, and no manual-review or attached-record dependency.",
    ]
    return "\n".join(lines)


def run_pilot(c4_zip, backup_manifest, restore_report, rollback_restore_report,
              rollback_schema, pilot_window_counts_report, evidence_dir, database_url):
    assert_exact_project_guard(database_url=database_url)
    backup = validate_backup_evidence(backup_manifest, restore_report)
    rollback_restore = json.loads(Path(rollback_restore_report).read_text(encoding="utf-8"))
    pilot_window_counts = json.loads(Path(pilot_window_counts_report).read_text(encoding="utf-8"))
    payload, c4_summary = load_approved_c4(c4_zip)
    selected = select_records(payload)
    selection = selected_manifest(selected, c4_summary["source_assessment_sha256"])
    batch_id = "C6-REAL-PILOT-" + c4_summary["source_assessment_sha256"][:12].upper()

    conn = _connect_guarded(database_url)
    conn.autocommit = False
    initial_counts = {key: backup["backup_row_counts"][key] for key in COUNT_TABLES}
    ledger = _migration_ledger(conn)
    if ledger[-1:] != ["031"]:
        conn.close()
        raise C6PilotRefusal("staging migration ledger is not exactly through 031")
    unrelated_before = _backup_vehicle_hash(backup_manifest)
    admin = _admin(conn)

    idempotency_keys = {
        row["record_ref"]: f"C6-029-{index:02d}-{row['record_ref'].replace(':', '-').upper()}"
        for index, row in enumerate(selected, 1)
    }
    cur = conn.cursor()
    cur.execute("""select idempotency_key, response from public.vehicle_master_operation_receipts
                   where operation_kind='import_apply' and scope_key=%s
                     and idempotency_key=any(%s::text[])""",
                (SOURCE_SYSTEM, list(idempotency_keys.values())))
    existing_receipts = {key: response for key, response in cur.fetchall()}
    if existing_receipts and set(existing_receipts) != set(idempotency_keys.values()):
        conn.close()
        raise C6PilotRefusal("partial prior C6 receipt set requires manual review")
    recovering_completed_apply = bool(existing_receipts)

    preview_rows, raw_previews, preview_proof = [], {}, {}
    for row in selected:
        body = source_payload(row)
        first = _preview(conn, admin, batch_id, row["record_ref"], body)
        second = _preview(conn, admin, batch_id, row["record_ref"], body)
        current_first, current_second = first, second
        current_safe = validate_preview_response(row["record_ref"], first, second)
        if recovering_completed_apply:
            receipt = existing_receipts[idempotency_keys[row["record_ref"]]]
            original = {"ok": True, "code": "ok", "data": receipt.get("data", {}).get("preview")}
            safe = validate_preview_response(row["record_ref"], original, original)
            if current_safe["action"] != "no_change" or safe["action"] != "insert":
                conn.close()
                raise C6PilotRefusal(f"completed C6 recovery state is not exact: {row['record_ref']}")
            first = original
        else:
            safe = current_safe
            if safe["action"] != "insert":
                conn.close()
                raise C6PilotRefusal(f"fresh C6 pilot expected insert, got {safe['action']}: {row['record_ref']}")
        preview_rows.append(safe)
        raw_previews[row["record_ref"]] = first
        preview_proof[row["record_ref"]] = {
            "approved_preview": first,
            "current_repreview_first": current_first,
            "current_repreview_second": current_second,
        }
    preview_logical = {
        "schema": "pdc.stage2b.c6-preview/v1",
        "source_system": SOURCE_SYSTEM,
        "source_batch_id": batch_id,
        "selected_manifest_checksum": selection["checksum"],
        "preview_count": len(preview_rows),
        "actions": preview_rows,
        "deterministic_repreview": True,
        "zero_ambiguity": all(row["candidate_count"] <= 1 for row in preview_rows),
        "zero_conflict": True,
    }
    preview_result = {**preview_logical, "checksum": {"algorithm": "sha256", "value": canonical_sha(preview_logical)}}

    applied_rows, replay_rows, selected_ids = [], [], []
    raw_apply_responses, raw_replay_responses = {}, {}
    response_loss_ref = selected[0]["record_ref"]
    for index, row in enumerate(selected, 1):
        body = source_payload(row)
        preview = raw_previews[row["record_ref"]]
        expected_version = preview["data"]["expected_version"]
        key = idempotency_keys[row["record_ref"]]
        applied = _apply(conn, admin, batch_id, row["record_ref"], body, expected_version, key)
        if (applied.get("ok") is not True or applied.get("code") != "applied"
                or applied.get("data", {}).get("preview") != preview.get("data")):
            conn.rollback(); conn.close()
            raise C6PilotRefusal(f"preview/apply parity failed: {row['record_ref']}")
        conn.commit()
        selected_ids.append(applied["data"]["vehicle_id"])
        safe_apply = {
            "record_ref": row["record_ref"], "action": applied["data"]["action"],
            "vehicle_id": applied["data"]["vehicle_id"], "version": applied["data"]["version"],
            "request_fingerprint": applied["data"]["request_fingerprint"],
            "preview_checksum": canonical_sha(preview["data"]),
            "apply_embedded_preview_checksum": canonical_sha(applied["data"]["preview"]),
        }
        applied_rows.append(safe_apply)
        raw_apply_responses[row["record_ref"]] = applied
        if row["record_ref"] == response_loss_ref:
            expected_response = applied
            conn.close()
            conn = _connect_guarded(database_url); conn.autocommit = False; admin = _admin(conn)
            replay = _apply(conn, admin, batch_id, row["record_ref"], body, expected_version, key)
        else:
            replay = _apply(conn, admin, batch_id, row["record_ref"], body, expected_version, key)
        conn.commit()
        if replay != applied:
            conn.close()
            raise C6PilotRefusal(f"durable receipt replay differed: {row['record_ref']}")
        raw_replay_responses[row["record_ref"]] = replay
        replay_rows.append({
            "record_ref": row["record_ref"], "vehicle_id": applied["data"]["vehicle_id"],
            "request_fingerprint": applied["data"]["request_fingerprint"],
            "identical_complete_response": True,
            "fresh_connection_after_response_loss": row["record_ref"] == response_loss_ref,
        })

    current_counts = _counts(conn)
    if (pilot_window_counts.get("schema") != "pdc.stage2b.c6-row-counts/v1"
            or pilot_window_counts.get("before") != initial_counts
            or pilot_window_counts.get("deltas", {}).get("vehicles") != SELECTED_COUNT):
        conn.close()
        raise C6PilotRefusal("original C6 pilot-window counts are invalid")
    after_counts = pilot_window_counts["after"]
    unrelated_after = _unrelated_vehicle_hash(conn, selected_ids)
    if unrelated_before != unrelated_after:
        conn.close()
        raise C6PilotRefusal("an unrelated vehicle changed during C6")
    namespace_counts = _selected_namespace_counts(conn, selected_ids, batch_id)
    if (namespace_counts["vehicles"] != SELECTED_COUNT
            or namespace_counts["source_records"] != SELECTED_COUNT
            or namespace_counts["receipts"] != SELECTED_COUNT
            or namespace_counts["unresolved_conflicts"] != 0):
        conn.close()
        raise C6PilotRefusal("selected namespace counts or conflict count are invalid")

    generated_at = "2026-07-19T01:00:00Z"
    reference = fetch_reference_data(conn, actor_email=admin[0], page_size=7, generated_at=generated_at)
    repeated_reference = fetch_reference_data(conn, actor_email=admin[0], page_size=7, generated_at=generated_at)
    if reference != repeated_reference:
        conn.close()
        raise C6PilotRefusal("migration 031 artifact was not deterministic")
    artifact = reference["vehicleIdentityArtifact"]
    revision = artifact["resolver_revision"]
    bounded_classifier_artifact = _bounded_reference_artifact(reference, selected_ids)
    bounded_reference = {**reference, "vehicleIdentityArtifact": bounded_classifier_artifact}
    bounded_artifact = _selected_reference_evidence(bounded_reference, selected_ids)
    source_by_ref = {row["record_ref"]: row for row in selected}
    apply_by_ref = {row["record_ref"]: row for row in applied_rows}

    cur = conn.cursor()
    cur.execute("""select id::text, permanent_vehicle_id, stock_number, vin, toyota_order_number,
                          version, source_system, source_batch_id, source_record_id
                   from public.vehicles where id=any(%s::uuid[]) order by id""", (selected_ids,))
    db_rows = {row[0]: row for row in cur.fetchall()}
    cur.execute("""select vehicle_id::text, source_system, source_batch_id, source_record_id,
                          original_evidence, version
                   from public.vehicle_master_source_records
                   where vehicle_id=any(%s::uuid[]) and source_system=%s""", (selected_ids, SOURCE_SYSTEM))
    evidence_rows = {row[0]: row for row in cur.fetchall()}

    reconciliation_rows = []
    for record_ref in sorted(source_by_ref):
        source = source_by_ref[record_ref]
        applied = apply_by_ref[record_ref]
        vehicle_id = applied["vehicle_id"]
        db = db_rows[vehicle_id]
        evidence = evidence_rows[vehicle_id]
        item = _typed_item(reference, vehicle_id)
        claims = {(c["identifier_type"], c.get("source_system"), c["normalized_value"], c["origin"]) for c in item["identifiers"]}
        expected_claims = {
            ("stock_number", None, re.sub(r"[\s-]+", "", source["stock_number"].upper()), "canonical"),
            ("vin", None, re.sub(r"[\s-]+", "", source["vin"].upper()), "canonical"),
            ("toyota_order_number", SOURCE_SYSTEM, source["toyota_order_number"].strip().upper(), "canonical"),
            ("source_record_id", SOURCE_SYSTEM, record_ref.upper(), "canonical"),
            ("source_record_id", SOURCE_SYSTEM, record_ref.upper(), "source_evidence"),
        }
        exact = (
            db[2] == source["stock_number"] and db[3] == source["vin"].upper()
            and db[4] == source["toyota_order_number"] and db[5] == 1
            and db[6] == SOURCE_SYSTEM and db[7] == batch_id and db[8] == record_ref
            and evidence[1] == SOURCE_SYSTEM and evidence[2] == batch_id and evidence[3] == record_ref
            and evidence[4] == source_payload(source) and evidence[5] == 1
            and item["version"] == 1 and not item["is_archived"]
            and expected_claims <= claims
        )
        if not exact:
            conn.close()
            raise C6PilotRefusal(f"source/UUID/version/evidence reconciliation failed: {record_ref}")
        reconciliation_rows.append({
            "record_ref": record_ref, "vehicle_id": vehicle_id, "version": 1,
            "permanent_vehicle_id": db[1], "action": applied["action"],
            "matched_claim_types": ["source_record_id", "stock_number", "toyota_order_number", "vin"],
            "source_evidence_retained": True, "all_original_identifiers_retained": True,
            "typed_artifact_exact": True, "browser_source_exact": True,
        })

    stage_code = reference["stages"][0]["code"]
    extract = {
        "source_backup_type": "workshop_planner_legacy_export",
        "exported_at": batch_id,
        "bookings": [{
            "legacy_plan_id": f"C6-C2B-{index:02d}",
            "legacy_vehicle_key": row["stock_number"], "stage_code": stage_code,
            "bay_number": None, "assignee": "", "scheduled_start_at": "2026-07-20T08:00:00Z",
            "scheduled_end_at": "2026-07-20T09:00:00Z", "duration_minutes": 60,
            "status": "planned", "raw_legacy_record": {"c6_reference_only": True},
        } for index, row in enumerate(selected, 1)],
    }
    classified = classify(extract, bounded_reference, expected_revision=revision)
    if len(classified["safely_matched"]) != SELECTED_COUNT or any(
            classified[key] for key in classified if key != "safely_matched"):
        conn.close()
        raise C6PilotRefusal("C2b classifier did not safely match exactly the imported batch")
    validator_hash = _validator_cli(extract, bounded_reference, revision)

    reconciliation_logical = {
        "schema": "pdc.stage2b.c6-reconciliation/v1",
        "source_system": SOURCE_SYSTEM, "source_batch_id": batch_id,
        "resolver_revision": revision, "result_count": len(reconciliation_rows),
        "matched": len(reconciliation_rows), "variance": 0,
        "c2b_safely_matched": len(classified["safely_matched"]),
        "c2b_refused_or_review": 0, "c2b_node_validator_passed": True,
        "c2b_node_output_sha256": validator_hash,
        "results": reconciliation_rows,
    }
    reconciliation = {**reconciliation_logical, "checksum": {"algorithm": "sha256", "value": canonical_sha(reconciliation_logical)}}

    rollback_export = _build_rollback_export(conn, selected_ids, batch_id, revision)
    rollback = rehearse_rollback(conn, rollback_export, rollback_schema, rollback_restore)
    retained_counts = _selected_namespace_counts(conn, selected_ids, batch_id)
    if retained_counts != namespace_counts:
        conn.close()
        raise C6PilotRefusal("isolated rollback rehearsal changed retained public pilot rows")
    cur = conn.cursor()
    cur.execute("select count(*) from pg_namespace where nspname like 'c6_full_rollback_%'")
    if cur.fetchone()[0] != 0:
        conn.close()
        raise C6PilotRefusal("temporary C6 schema remained after rehearsal")
    conn.close()

    apply_result = {
        "schema": "pdc.stage2b.c6-apply/v1", "source_system": SOURCE_SYSTEM,
        "source_batch_id": batch_id, "applied_count": len(applied_rows),
        "preview_apply_parity": True, "actions": applied_rows,
    }
    replay_evidence = {
        "schema": "pdc.stage2b.c6-replay/v1", "replay_count": len(replay_rows),
        "duplicate_vehicles_created": 0, "complete_response_identity": True,
        "response_loss_record_ref": response_loss_ref,
        "fresh_connection_response_loss_replay": True, "results": replay_rows,
    }
    row_counts = {
        "schema": "pdc.stage2b.c6-row-counts/v1", "before": initial_counts,
        "after": after_counts,
        "deltas": {key: after_counts[key] - initial_counts[key] for key in COUNT_TABLES},
        "current_revalidation_after": current_counts,
        "post_pilot_non_vehicle_drift": {
            key: current_counts[key] - after_counts[key]
            for key in COUNT_TABLES if current_counts[key] != after_counts[key]
        },
        "selected_namespace_counts": namespace_counts,
        "unrelated_vehicle_full_row_sha256_before": unrelated_before,
        "unrelated_vehicle_full_row_sha256_after": unrelated_after,
        "unrelated_vehicles_unchanged": True,
    }
    safety = {
        "schema": "pdc.stage2b.c6-safety/v1", "exact_staging_project_ref": STAGING_REF,
        "migration_ledger": ledger, "migration_ledger_tip": "031",
        "database_connection_guarded_to_exact_staging_project": True,
        "browser_local_authority_unchanged": True, "browser_local_records_modified": 0,
        "frontend_reads_switched": False, "direct_select_retired": False,
        "deployed": False, "merged": False, "ai_work_started": False,
        "pilot_records_retained": True, "retained_vehicle_ids": sorted(selected_ids),
        "unrelated_vehicles_changed": 0, "identity_conflicts_created": 0,
        "temporary_schemas_remaining": 0,
    }
    summary = {
        "schema": "pdc.stage2b.c6-pilot-summary/v1", "selected_count": SELECTED_COUNT,
        "preview": {"insert": SELECTED_COUNT, "update": 0, "no_change": 0, "refused": 0},
        "apply": {"insert": SELECTED_COUNT, "update": 0, "no_change": 0, "failed": 0},
        "replay_exact": SELECTED_COUNT, "response_loss_replay_exact": 1,
        "reconciled": SELECTED_COUNT, "reconciliation_variance": 0,
        "rollback_rehearsal_passed": True, "backup_restore_passed": True,
        "pilot_records_retained": True,
    }
    operational_proof = {
        "schema": "pdc.stage2b.c6-operational-proof/v1",
        "selected_manifest_checksum": selection["checksum"],
        "preview_responses": preview_proof,
        "apply_responses": raw_apply_responses,
        "replay_responses": raw_replay_responses,
        "response_loss_record_ref": response_loss_ref,
        "migration_031_reference": _json_safe(bounded_artifact),
        "c2b_classification": _json_safe(classified),
        "c2b_extract": _json_safe(extract),
        "preapply_restore_report": json.loads(Path(restore_report).read_text(encoding="utf-8")),
        "rollback_restore_report": rollback_restore,
        "original_pilot_window_counts": pilot_window_counts,
    }
    files = {
        "selected-record-manifest.json": selection,
        "approval-manifest.md": render_approval_manifest(selection, preview_result),
        "preview-result.json": preview_result,
        "apply-result.json": apply_result,
        "replay-evidence.json": replay_evidence,
        "reconciliation-report.json": reconciliation,
        "rollback-export.json": rollback_export,
        "rollback-report.json": rollback,
        "before-after-row-counts.json": row_counts,
        "backup-restore-evidence.json": backup,
        "safety.json": safety,
        "pilot-summary.json": summary,
        "operational-proof.json": operational_proof,
    }
    write_evidence(evidence_dir, files)
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--c4-zip", required=True)
    parser.add_argument("--backup-manifest", required=True)
    parser.add_argument("--restore-report", required=True)
    parser.add_argument("--rollback-restore-report", required=True)
    parser.add_argument("--rollback-schema", required=True)
    parser.add_argument("--pilot-window-counts-report", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    if not args.apply:
        raise C6PilotRefusal("live staging C6 execution requires explicit --apply")
    result = run_pilot(
        args.c4_zip, args.backup_manifest, args.restore_report,
        args.rollback_restore_report, args.rollback_schema, args.pilot_window_counts_report, args.evidence_dir,
        os.environ.get("PDC_STAGING_DATABASE_URL", ""),
    )
    print(canonical_json(result))


if __name__ == "__main__":
    main()
