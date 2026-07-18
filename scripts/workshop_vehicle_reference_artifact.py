"""Strict, deterministic migration-031 workshop vehicle reference artifacts."""

from __future__ import annotations

import hashlib
import json
import re
from copy import deepcopy
from datetime import datetime

ARTIFACT_SCHEMA_VERSION = "pdc.workshop.vehicle-reference/v2"
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SOURCE_ENV_RE = re.compile(r"^(staging|test):[a-z0-9][a-z0-9-]{2,127}$")
ISO_UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$")
MAX_SAFE_INTEGER = 2**53 - 1
ITEM_KEYS = {"vehicle_id", "version", "is_archived", "identifiers"}
IDENTIFIER_KEYS = {"identifier_type", "value", "normalized_value", "source_system", "origin"}
CONFLICT_KEYS = {"classification", "identifier_type", "normalized_value", "source_system", "vehicle_ids", "candidates"}
CANDIDATE_KEYS = {"vehicle_id", "origin", "value"}
IDENTIFIER_TYPES = {"stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number", "source_record_id"}
ORIGINS = {"canonical", "alias", "source_evidence"}
ALIAS_TYPES = {"stock_number", "vin", "job_card_number", "toyota_order_number", "source_record_id"}
CONFLICT_CLASSES = {"canonical_alias_conflict", "canonical_source_evidence_conflict", "ambiguous_normalized_identity"}


class VehicleReferenceArtifactError(RuntimeError):
    pass


class VehicleReferenceArtifactStale(VehicleReferenceArtifactError):
    pass


def _exact_keys(value, allowed, label):
    if not isinstance(value, dict):
        raise VehicleReferenceArtifactError(f"{label} must be an object")
    missing = allowed - set(value)
    if missing:
        raise VehicleReferenceArtifactError(f"{label} is missing required field: {sorted(missing)[0].replace('_', ' ')}")
    extras = set(value) - allowed
    if extras:
        raise VehicleReferenceArtifactError(f"{label} contains prohibited field: {sorted(extras)[0]}")


def _canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _canonical_bytes(value):
    return _canonical_json(value).encode("utf-8")


def _normalize_legacy_stock(value):
    return re.sub(r"[\s-]+", "", str(value or "").strip().upper())


def _is_real_legacy_stock(value):
    raw = str(value or "").strip().upper()
    normalized = _normalize_legacy_stock(value)
    return bool(normalized) and normalized not in {"0", "TBA", "TBD", "UNKNOWN", "NA", "N/A", "NONE", "UNASSIGNED"} \
        and not any(raw.startswith(prefix) for prefix in ("NEW-", "PD-", "PENDING-", "TEMP-"))


def artifact_logical_payload(artifact):
    return {
        "schema_version": artifact.get("schema_version"),
        "resolver_revision": artifact.get("resolver_revision"),
        "source_environment": artifact.get("source_environment"),
        "item_count": artifact.get("item_count"),
        "completion": artifact.get("completion"),
        "items": artifact.get("items"),
        "conflicts": artifact.get("conflicts"),
    }


def artifact_checksum(artifact):
    return hashlib.sha256(_canonical_json(artifact_logical_payload(artifact)).encode("utf-8")).hexdigest()


def _claim_key(claim):
    return (claim["identifier_type"], claim.get("source_system") or "", claim["normalized_value"], claim["origin"], claim["value"])


def _normalize_claim(claim, label):
    _exact_keys(claim, IDENTIFIER_KEYS, f"{label} identifier")
    identifier_type = claim.get("identifier_type")
    origin = claim.get("origin")
    if identifier_type not in IDENTIFIER_TYPES:
        raise VehicleReferenceArtifactError(f"{label} identifier type is invalid")
    if origin not in ORIGINS:
        raise VehicleReferenceArtifactError(f"{label} identifier origin is invalid")
    if origin == "alias" and identifier_type == "permanent_vehicle_id":
        raise VehicleReferenceArtifactError("permanent-vehicle-ID aliases are not authoritative")
    if origin == "alias" and identifier_type not in ALIAS_TYPES:
        raise VehicleReferenceArtifactError(f"{label} contains a prohibited alias type")
    if not isinstance(claim.get("value"), str) or not claim["value"].strip():
        raise VehicleReferenceArtifactError(f"{label} identifier value is invalid")
    if not isinstance(claim.get("normalized_value"), str) or not claim["normalized_value"].strip():
        raise VehicleReferenceArtifactError(f"{label} normalized identifier is invalid")
    expected_normalized = (_normalize_legacy_stock(claim["value"]) if identifier_type in {"stock_number", "vin"}
                           else claim["value"].strip().upper())
    if claim["normalized_value"] != expected_normalized:
        raise VehicleReferenceArtifactError(f"{label} normalized identifier does not match SQL normalization")
    if identifier_type == "stock_number" and not _is_real_legacy_stock(claim["value"]):
        raise VehicleReferenceArtifactError(f"{label} placeholder stock identifier is invalid")
    if identifier_type == "vin" and not re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", expected_normalized):
        raise VehicleReferenceArtifactError(f"{label} VIN identifier is invalid")
    scoped = identifier_type in {"job_card_number", "toyota_order_number", "source_record_id"}
    source_system = claim.get("source_system")
    if scoped and (not isinstance(source_system, str) or not source_system.strip()
                   or source_system != source_system.strip().lower()):
        raise VehicleReferenceArtifactError(f"{label} scoped identifier lacks normalized source_system")
    if not scoped and source_system is not None:
        raise VehicleReferenceArtifactError(f"{label} unscoped identifier has source_system")
    if origin == "source_evidence" and identifier_type != "source_record_id":
        raise VehicleReferenceArtifactError(f"{label} source evidence type is invalid")
    return {key: claim[key] for key in ("identifier_type", "value", "normalized_value", "source_system", "origin")}


def _normalize_item(item):
    _exact_keys(item, ITEM_KEYS, "vehicle item")
    vehicle_id = str(item.get("vehicle_id") or "").lower()
    if not UUID_RE.fullmatch(vehicle_id):
        raise VehicleReferenceArtifactError("vehicle item has no valid canonical UUID")
    if isinstance(item.get("version"), bool) or not isinstance(item.get("version"), int) or not 1 <= item["version"] <= MAX_SAFE_INTEGER:
        raise VehicleReferenceArtifactError("vehicle item version is invalid")
    if not isinstance(item.get("is_archived"), bool):
        raise VehicleReferenceArtifactError("vehicle item archived state is invalid")
    if not isinstance(item.get("identifiers"), list):
        raise VehicleReferenceArtifactError("vehicle item identifiers are malformed")
    claims = sorted((_normalize_claim(row, f"vehicle {vehicle_id}") for row in item["identifiers"]), key=_canonical_bytes)
    if len({_claim_key(row) for row in claims}) != len(claims):
        raise VehicleReferenceArtifactError(f"vehicle {vehicle_id} contains duplicate identifier evidence")
    return {"vehicle_id": vehicle_id, "version": item["version"], "is_archived": item["is_archived"], "identifiers": claims}


def _normalize_conflict(conflict):
    _exact_keys(conflict, CONFLICT_KEYS, "conflict evidence")
    if conflict.get("classification") not in CONFLICT_CLASSES:
        raise VehicleReferenceArtifactError("conflict classification is invalid")
    if conflict.get("identifier_type") not in IDENTIFIER_TYPES:
        raise VehicleReferenceArtifactError("conflict identifier type is invalid")
    if not isinstance(conflict.get("normalized_value"), str) or not conflict["normalized_value"].strip():
        raise VehicleReferenceArtifactError("conflict normalized value is invalid")
    if conflict.get("source_system") is not None and not isinstance(conflict.get("source_system"), str):
        raise VehicleReferenceArtifactError("conflict source system is invalid")
    ids = [str(value).lower() for value in conflict.get("vehicle_ids", [])] if isinstance(conflict.get("vehicle_ids"), list) else []
    if len(ids) < 2 or len(set(ids)) != len(ids) or any(not UUID_RE.fullmatch(value) for value in ids):
        raise VehicleReferenceArtifactError("conflict vehicle IDs are invalid")
    candidates = conflict.get("candidates")
    if not isinstance(candidates, list) or len(candidates) < 2:
        raise VehicleReferenceArtifactError("conflict candidates are malformed")
    clean_candidates = []
    for candidate in candidates:
        _exact_keys(candidate, CANDIDATE_KEYS, "conflict candidate")
        candidate_id = str(candidate.get("vehicle_id") or "").lower()
        if not UUID_RE.fullmatch(candidate_id) or candidate.get("origin") not in ORIGINS or not isinstance(candidate.get("value"), str) or not candidate["value"].strip():
            raise VehicleReferenceArtifactError("conflict candidate is invalid")
        clean_candidates.append({"vehicle_id": candidate_id, "origin": candidate["origin"], "value": candidate["value"]})
    clean_candidates.sort(key=_canonical_bytes)
    return {
        "classification": conflict["classification"],
        "identifier_type": conflict["identifier_type"],
        "normalized_value": conflict["normalized_value"],
        "source_system": conflict.get("source_system"),
        "vehicle_ids": sorted(ids),
        "candidates": clean_candidates,
    }


def _validate_completion(completion, items):
    _exact_keys(completion, {"complete", "page_count", "terminal_cursor", "pages"}, "completion evidence")
    if completion.get("complete") is not True:
        raise VehicleReferenceArtifactError("artifact is truncated")
    pages = completion.get("pages")
    if isinstance(completion.get("page_count"), bool) or not isinstance(completion.get("page_count"), int) or completion["page_count"] < 1:
        raise VehicleReferenceArtifactError("page count is invalid")

    if not isinstance(pages, list) or len(pages) != completion["page_count"]:
        raise VehicleReferenceArtifactError("page evidence is incomplete")
    prior_end = None
    total = 0
    for index, page in enumerate(pages):
        _exact_keys(page, {"after_cursor", "end_cursor", "item_count", "has_more", "next_cursor"}, f"page {index + 1}")
        if page.get("after_cursor") != prior_end:
            raise VehicleReferenceArtifactError(f"page {index + 1} cursor chain is invalid")
        count = page.get("item_count")
        if isinstance(count, bool) or not isinstance(count, int) or count < 0 or not isinstance(page.get("has_more"), bool):
            raise VehicleReferenceArtifactError(f"page {index + 1} metadata is invalid")
        end_cursor = page.get("end_cursor")
        if (count == 0 and end_cursor is not None) or (count and not UUID_RE.fullmatch(str(end_cursor or ""))):
            raise VehicleReferenceArtifactError(f"page {index + 1} end cursor is invalid")
        if total + count > len(items):
            raise VehicleReferenceArtifactError("page item counts exceed artifact items")
        expected_page_end = items[total + count - 1]["vehicle_id"] if count else None
        if end_cursor != expected_page_end:
            raise VehicleReferenceArtifactError(f"page {index + 1} boundary does not match artifact items")
        if page["has_more"]:
            if count < 1 or page.get("next_cursor") != end_cursor:
                raise VehicleReferenceArtifactError(f"page {index + 1} continuation cursor is invalid")
        elif index != len(pages) - 1 or page.get("next_cursor") is not None:
            raise VehicleReferenceArtifactError(f"page {index + 1} terminal evidence is invalid")
        prior_end = end_cursor
        total += count
    expected_terminal = items[-1]["vehicle_id"] if items else None
    if pages[-1]["has_more"] is not False or completion["terminal_cursor"] != expected_terminal or prior_end != expected_terminal:
        raise VehicleReferenceArtifactError("terminal cursor does not match artifact items")
    if total != len(items):
        raise VehicleReferenceArtifactError("page item counts do not match artifact items")


def _validate_conflict_semantics(items, conflicts):
    claims_by_key = {}
    for item in items:
        for claim in item["identifiers"]:
            key = (claim["identifier_type"], claim.get("source_system") or "", claim["normalized_value"])
            claims_by_key.setdefault(key, []).append({"vehicle_id": item["vehicle_id"], "origin": claim["origin"], "value": claim["value"]})
    seen = set()
    for conflict in conflicts:
        key = (conflict["identifier_type"], conflict.get("source_system") or "", conflict["normalized_value"])
        if key in seen:
            raise VehicleReferenceArtifactError("duplicate conflict evidence group")
        seen.add(key)
        expected = sorted(claims_by_key.get(key, []), key=_canonical_bytes)
        actual = sorted(conflict["candidates"], key=_canonical_bytes)
        if expected != actual:
            raise VehicleReferenceArtifactError("conflict candidates do not match artifact claims")
        expected_ids = sorted({row["vehicle_id"] for row in expected})
        if len(expected_ids) < 2 or expected_ids != conflict["vehicle_ids"]:
            raise VehicleReferenceArtifactError("conflict vehicle IDs do not match artifact claims")
        origins = {row["origin"] for row in expected}
        expected_class = ("canonical_alias_conflict" if {"canonical", "alias"} <= origins
                          else "canonical_source_evidence_conflict" if {"canonical", "source_evidence"} <= origins
                          else "ambiguous_normalized_identity")
        if conflict["classification"] != expected_class:
            raise VehicleReferenceArtifactError("conflict classification does not match artifact claims")


def validate_vehicle_reference_artifact(artifact, *, expected_resolver_revision):
    _exact_keys(artifact, {"schema_version", "resolver_revision", "generated_at", "source_environment", "item_count", "completion", "items", "conflicts", "checksum"}, "vehicle identity artifact")
    if artifact.get("schema_version") != ARTIFACT_SCHEMA_VERSION:
        raise VehicleReferenceArtifactError("unsupported vehicle reference artifact schema")
    revision = artifact.get("resolver_revision")
    if isinstance(revision, bool) or not isinstance(revision, int) or not 0 <= revision <= MAX_SAFE_INTEGER:
        raise VehicleReferenceArtifactError("resolver revision is invalid")
    if isinstance(expected_resolver_revision, bool) or not isinstance(expected_resolver_revision, int) or not 0 <= expected_resolver_revision <= MAX_SAFE_INTEGER:
        raise VehicleReferenceArtifactError("current resolver revision is required to validate an offline artifact")
    if revision != expected_resolver_revision:
        raise VehicleReferenceArtifactStale("vehicle reference artifact is stale; regenerate it")
    if not isinstance(artifact.get("generated_at"), str) or not ISO_UTC_RE.fullmatch(artifact["generated_at"]):
        raise VehicleReferenceArtifactError("generation timestamp is invalid")
    try:
        datetime.fromisoformat(str(artifact.get("generated_at") or "").replace("Z", "+00:00"))
    except ValueError as exc:
        raise VehicleReferenceArtifactError("generation timestamp is invalid") from exc
    if not isinstance(artifact.get("source_environment"), str) or not SOURCE_ENV_RE.fullmatch(artifact["source_environment"]):
        raise VehicleReferenceArtifactError("source environment identifier is invalid")
    if not isinstance(artifact.get("items"), list) or not isinstance(artifact.get("conflicts"), list):
        raise VehicleReferenceArtifactError("artifact items or conflicts are malformed")
    items = sorted((_normalize_item(item) for item in artifact["items"]), key=lambda row: row["vehicle_id"])
    if len({row["vehicle_id"] for row in items}) != len(items):
        raise VehicleReferenceArtifactError("artifact contains duplicate canonical UUIDs")
    if isinstance(artifact.get("item_count"), bool) or artifact.get("item_count") != len(items):
        raise VehicleReferenceArtifactError("artifact item count is incorrect")
    _validate_completion(artifact.get("completion"), items)
    conflicts = sorted((_normalize_conflict(row) for row in artifact["conflicts"]), key=_canonical_bytes)
    _validate_conflict_semantics(items, conflicts)
    normalized = {**deepcopy(artifact), "items": items, "conflicts": conflicts}
    checksum = artifact.get("checksum")
    if not isinstance(checksum, dict) or set(checksum) != {"algorithm", "value"} or checksum.get("algorithm") != "sha256" or not SHA256_RE.fullmatch(str(checksum.get("value") or "")):
        raise VehicleReferenceArtifactError("artifact checksum metadata is invalid")
    if artifact_checksum(normalized) != checksum["value"]:
        raise VehicleReferenceArtifactError("artifact checksum mismatch")
    owners = {}
    for item in items:
        for claim in item["identifiers"]:
            key = (claim["identifier_type"], claim.get("source_system") or "", claim["normalized_value"])
            owners.setdefault(key, set()).add(item["vehicle_id"])
    for (identifier_type, source_system, normalized_value), vehicle_ids in owners.items():
        if len(vehicle_ids) < 2:
            continue
        if not any(row["identifier_type"] == identifier_type and (row.get("source_system") or "") == source_system and row["normalized_value"] == normalized_value and set(row["vehicle_ids"]) == vehicle_ids for row in conflicts):
            raise VehicleReferenceArtifactError("duplicate normalized identifier lacks explicit conflict evidence")
    return normalized


def build_vehicle_reference_artifact(export_data, *, generated_at, source_environment):
    if not isinstance(export_data, dict) or export_data.get("outcome") != "exported":
        raise VehicleReferenceArtifactError("successful migration-031 export is required")
    artifact = {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "resolver_revision": export_data.get("export_revision"),
        "generated_at": generated_at,
        "source_environment": source_environment,
        "item_count": len(export_data.get("items", [])) if isinstance(export_data.get("items"), list) else -1,
        "completion": deepcopy(export_data.get("completion")),
        "items": deepcopy(export_data.get("items")),
        "conflicts": deepcopy(export_data.get("conflicts")),
        "checksum": {"algorithm": "sha256", "value": ""},
    }
    artifact["items"] = sorted((_normalize_item(item) for item in artifact["items"]), key=lambda row: row["vehicle_id"])
    artifact["conflicts"] = sorted((_normalize_conflict(row) for row in artifact["conflicts"]), key=_canonical_bytes)
    _validate_completion(artifact["completion"], artifact["items"])
    artifact["checksum"]["value"] = artifact_checksum(artifact)
    return validate_vehicle_reference_artifact(artifact, expected_resolver_revision=artifact["resolver_revision"])


def parse_workshop_reference(reference, *, expected_resolver_revision, allow_legacy_rollback=False, legacy_source_environment=None, diagnostic=lambda _message: None):
    if not isinstance(reference, dict):
        raise VehicleReferenceArtifactError("reference data must be an object")
    if "vehicleIdentityArtifact" in reference:
        artifact = validate_vehicle_reference_artifact(reference["vehicleIdentityArtifact"], expected_resolver_revision=expected_resolver_revision)
        parsed = dict(reference)
        parsed.update({
            "vehicles": artifact["items"],
            "vehicleIdentityExport": {
                "outcome": "exported", "export_revision": artifact["resolver_revision"],
                "conflicts": artifact["conflicts"], "rollback_used": False,
                "artifact_schema_version": artifact["schema_version"],
                "artifact_checksum": artifact["checksum"]["value"],
            },
        })
        return parsed
    if not allow_legacy_rollback:
        raise VehicleReferenceArtifactError("legacy workshop reference format is disabled; regenerate a typed artifact")
    if not isinstance(legacy_source_environment, str) or not SOURCE_ENV_RE.fullmatch(legacy_source_environment):
        raise VehicleReferenceArtifactError("legacy reference rollback is restricted to an explicit staging/test environment")
    diagnostic("WARNING: explicit staging/test legacy reference rollback is active")
    meta = reference.get("vehicleIdentityExport")
    if not isinstance(reference.get("vehicles"), list) or not isinstance(meta, dict) or meta.get("outcome") != "exported" or meta.get("export_revision") != expected_resolver_revision:
        raise VehicleReferenceArtifactError("legacy reference format failed explicit version validation")
    parsed = dict(reference)
    parsed_vehicles = []
    for row in reference["vehicles"]:
        identifiers = list(row["identifiers"]) if isinstance(row.get("identifiers"), list) and row["identifiers"] else []
        if not identifiers:
            if _is_real_legacy_stock(row.get("stock_number")):
                identifiers.append({"identifier_type": "stock_number", "value": row["stock_number"],
                                    "normalized_value": _normalize_legacy_stock(row["stock_number"]),
                                    "source_system": None, "origin": "canonical"})
            if isinstance(row.get("permanent_vehicle_id"), str) and row["permanent_vehicle_id"].strip():
                identifiers.append({"identifier_type": "permanent_vehicle_id", "value": row["permanent_vehicle_id"],
                                    "normalized_value": row["permanent_vehicle_id"].strip().upper(),
                                    "source_system": None, "origin": "canonical"})
        parsed_vehicles.append(_normalize_item({
            "vehicle_id": row.get("vehicle_id") or row.get("id"),
            "version": row.get("version"), "is_archived": row.get("is_archived"),
            "identifiers": identifiers,
        }))
    parsed["vehicles"] = parsed_vehicles
    return parsed
