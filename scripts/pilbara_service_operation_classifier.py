#!/usr/bin/env python3
"""Validate the bounded Pilbara Service operation classification manifest."""
from __future__ import annotations

import hashlib
from collections.abc import Iterable
from typing import Any

from backend.pdc_email_ai_v2_taxonomy import classify_operation
from scripts.pilbara_service_open_jobcards import IMPORTER_VERSION

CONTRACT = "pilbara_service_operation_classifier_v1"
CLASSIFIER_VERSION = "pilbara-service-classifier-2026-09-07.1"
MIN_ASSIGNED_CONFIDENCE = 0.80
CONTROLLED_KEYS = frozenset({
    "PARTS", "TINT", "BUS_4X4", "HOIST", "FITTING", "FABRICATION",
    "ELECTRICAL", "TYRE", "SUBLET", "REVIEW",
})
MANIFEST_KEYS = frozenset({
    "contract", "classifier_version", "source_importer_version", "source_batch_id",
    "source_hash", "generated_by", "classifications",
})
ROW_KEYS = frozenset({
    "natural_identity", "source_semantic_hash", "source_description_hash", "category",
    "method", "confidence", "rationale", "rule_id", "ruleset_version", "provider",
    "model", "run_id",
})


def source_description_hash(description: str) -> str:
    return hashlib.sha256(str(description).encode("utf-8")).hexdigest()


def _exact_keys(value: dict[str, Any], expected: frozenset[str], label: str) -> None:
    if frozenset(value) != expected:
        raise ValueError(f"{label} keys do not match strict schema")


def validate_manifest(
    manifest: dict[str, Any],
    source_rows: Iterable[dict[str, Any]],
    *,
    source_hash: str,
) -> list[dict[str, Any]]:
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be an object")
    _exact_keys(manifest, MANIFEST_KEYS, "manifest")
    if manifest["contract"] != CONTRACT or manifest["classifier_version"] != CLASSIFIER_VERSION:
        raise ValueError("classifier contract/version mismatch")
    if manifest["source_importer_version"] != IMPORTER_VERSION:
        raise ValueError("source importer version mismatch")
    if not isinstance(manifest["source_batch_id"], str) or not manifest["source_batch_id"]:
        raise ValueError("source batch is required")
    if manifest["source_hash"] != source_hash:
        raise ValueError("source hash mismatch")
    generated_by = manifest["generated_by"]
    if not isinstance(generated_by, dict) or frozenset(generated_by) != {"provider", "model", "run_id"}:
        raise ValueError("generator provenance is invalid")
    if generated_by != {"provider": "openai-codex", "model": "gpt-5.6-sol", "run_id": "141"}:
        raise ValueError("generator provenance does not identify the active model run")

    source_list = list(source_rows)
    source_identities = [tuple(row["natural_identity"]) for row in source_list]
    if len(source_identities) != 122 or len(set(source_identities)) != 122:
        raise ValueError("source identity set must contain exactly 122 unique operations")
    indexed = dict(zip(source_identities, source_list, strict=True))
    rows = manifest["classifications"]
    if not isinstance(rows, list) or len(rows) != 122:
        raise ValueError("manifest must classify exactly 122 operations")
    seen: set[tuple[Any, ...]] = set()
    validated: list[dict[str, Any]] = []
    for index, item in enumerate(rows):
        if not isinstance(item, dict):
            raise ValueError(f"classification {index} must be an object")
        _exact_keys(item, ROW_KEYS, f"classification {index}")
        identity = tuple(item["natural_identity"]) if isinstance(item["natural_identity"], list) else ()
        if len(identity) != 4 or identity in seen or identity not in indexed:
            raise ValueError(f"classification {index} natural identity is invalid")
        seen.add(identity)
        source = indexed[identity]
        if item["source_semantic_hash"] != source["semantic_hash"]:
            raise ValueError(f"classification {index} source semantic hash mismatch")
        expected_description_hash = source_description_hash(source["operation_description"])
        if item["source_description_hash"] != expected_description_hash:
            raise ValueError(f"classification {index} source description hash mismatch")
        category = item["category"]
        method = item["method"]
        confidence = item["confidence"]
        if category not in CONTROLLED_KEYS or method not in {"deterministic_rule", "ai_semantic", "review"}:
            raise ValueError(f"classification {index} category/method is invalid")
        if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
            raise ValueError(f"classification {index} confidence is invalid")
        if not isinstance(item["rationale"], str) or not item["rationale"].strip() or len(item["rationale"]) > 240:
            raise ValueError(f"classification {index} rationale is invalid")
        if category == "REVIEW":
            if method != "review" or confidence >= MIN_ASSIGNED_CONFIDENCE:
                raise ValueError(f"classification {index} review confidence/method is invalid")
        elif confidence < MIN_ASSIGNED_CONFIDENCE:
            raise ValueError(f"classification {index} confidence is below assignment threshold")

        deterministic = classify_operation(source["operation_description"])
        if deterministic.reason == "negated_or_non_work_description" and category != "REVIEW":
            raise ValueError(f"classification {index} cannot assign a negated or non-work description")
        if method == "deterministic_rule":
            if category == "REVIEW" or deterministic.work_key != category or deterministic.disposition != "PLANNED":
                raise ValueError(f"classification {index} deterministic result mismatch")
            if item["rule_id"] != deterministic.rule_id or item["ruleset_version"] != deterministic.ruleset_version:
                raise ValueError(f"classification {index} deterministic provenance mismatch")
            if item["provider"] is not None or item["model"] is not None or item["run_id"] is not None:
                raise ValueError(f"classification {index} deterministic row is mislabeled as model output")
        else:
            if item["rule_id"] is not None or item["ruleset_version"] is not None:
                raise ValueError(f"classification {index} semantic/review row has rule provenance")
            if (item["provider"], item["model"], item["run_id"]) != ("openai-codex", "gpt-5.6-sol", "141"):
                raise ValueError(f"classification {index} model provenance mismatch")
            if method == "ai_semantic" and category == "REVIEW":
                raise ValueError(f"classification {index} AI assignment cannot use REVIEW")
        validated.append(dict(item))
    if seen != set(source_identities):
        raise ValueError("source identity set does not exactly match manifest")
    return validated


__all__ = [
    "CLASSIFIER_VERSION", "CONTRACT", "CONTROLLED_KEYS", "MIN_ASSIGNED_CONFIDENCE",
    "source_description_hash", "validate_manifest",
]
