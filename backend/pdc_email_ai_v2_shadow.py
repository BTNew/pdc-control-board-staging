"""Zero-write shadow comparison for the isolated PDC Email AI v2 lane.

The comparator consumes the frozen-100 taxonomy audit as reviewed input. It does
not mutate Board, Supabase, mailbox, or legacy state. Unknown and ambiguous
instructions are retained with an explicit REVIEW disposition rather than being
silently omitted.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable, Mapping

DEFAULT_HANDOFF = Path(r"C:/Users/nwmgr/HermesWorkspaces/development/pdc_email_ai_v2_taxonomy_handoff.md")
REVIEW = "REVIEW"
PLANNED = "PLANNED"
UNSUPPORTED = "UNSUPPORTED"
CONFLICT = "CONFLICT"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_description(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9]+", " ", str(value or "").upper())
    return re.sub(r"\s+", " ", value).strip()


def _path_from_handoff(raw: str, base: Path) -> Path:
    text = raw.strip().strip("`")
    path = Path(text)
    if path.is_absolute():
        return path
    return (base / path).resolve()


def load_frozen_taxonomy_audit(handoff_path: Path = DEFAULT_HANDOFF) -> dict[str, Any]:
    """Load and verify the exact frozen-100 handoff and audit artifact."""
    handoff = Path(handoff_path).resolve()
    if not handoff.is_file():
        raise FileNotFoundError(f"taxonomy handoff is missing: {handoff}")
    text = handoff.read_text(encoding="utf-8")
    match = re.search(r"- `([^`]*classification-consistency-audit\.json)`", text)
    if not match:
        raise ValueError("taxonomy handoff does not name the frozen audit JSON")
    audit_path = _path_from_handoff(match.group(1), handoff.parent)
    if not audit_path.is_file():
        raise FileNotFoundError(f"frozen taxonomy audit is missing: {audit_path}")
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    scope = audit.get("scope") or {}
    if audit.get("audit_status") != "complete_read_only_audit" or scope.get("physical_messages") != 100 or scope.get("mailbox_mutated") is not False:
        raise ValueError("frozen taxonomy audit is not a complete immutable 100-message audit")
    proposal = audit.get("proposed_authoritative_taxonomy") or {}
    if proposal.get("status") != "proposal_only_not_installed":
        raise ValueError("taxonomy input is not proposal-only")
    required = {str(row.get("fixture_id")) for row in audit.get("required_regression_fixtures", []) if row.get("fixture_id")}
    required_ids = {"fmg-decals-gvm-negative-hoist", "reflective-stripes-without-sublet-negative"}
    if not required_ids.issubset(required):
        raise ValueError("frozen audit is missing mandatory negative fixtures")
    return {
        "handoff_path": str(handoff),
        "handoff_sha256": _sha256(handoff),
        "audit_path": str(audit_path),
        "audit_sha256": _sha256(audit_path),
        "audit": audit,
    }


def _sublet_evidence(explicit_job_card_sublet: bool, authorized_provider: bool, authorized_booking: bool) -> bool:
    return bool(explicit_job_card_sublet or authorized_provider or authorized_booking)


def classify_shadow_description(
    description: str,
    *,
    explicit_job_card_sublet: bool = False,
    authorized_provider: bool = False,
    authorized_booking: bool = False,
) -> dict[str, Any]:
    """Classify one line using reviewed v2 precedence and typed disposition."""
    source = str(description or "").strip()
    canonical = _canonical_description(source)
    if not canonical:
        return {"work_group": None, "disposition": UNSUPPORTED, "reason": "empty_description", "sublet_eligible": False}
    # This guard must precede the generic GVM/Hoist family. The mixed FMG line
    # is the mandatory frozen-100 negative regression.
    signage = bool(re.search(r"\b(FMG|SIGNAGE|STRIP(?:ING|P(?:E|ING))|LOGO|DECAL|TARE|GCM|SAFETY)\b", canonical))
    gvm_tokens = bool(re.search(r"\bGVM\b|\bGCM\b|\bTARE\b", canonical))
    if signage and (gvm_tokens or "SIGNAGE" in canonical or "DECAL" in canonical or "STRIP" in canonical):
        eligible = _sublet_evidence(explicit_job_card_sublet, authorized_provider, authorized_booking)
        return {
            "work_group": "SUBLET" if eligible else None,
            "disposition": PLANNED if eligible else REVIEW,
            "reason": "explicit_sublet_evidence" if eligible else "mixed_fmg_signage_gvm_decal_not_hoist",
            "sublet_eligible": eligible,
            "normalized_description": canonical,
        }
    if re.search(r"\b(FIRE EXT|FIRE EXTINGUISHER|FIRE EXTINUISER|EXTIN(GUISHER|UISER))\b", canonical):
        if re.search(r"\b(DECAL|DECALS|LABEL|LABELS|STICKER|STICKERS)\b", canonical) and not re.search(r"\b(KG|CARGO|BARRIER|MOUNT|FLOOR|HEAD BOARD|HEADBOARD)\b", canonical):
            return {"work_group": None, "disposition": REVIEW, "reason": "fire_extinguisher_decal_excluded_from_hardware_rule", "sublet_eligible": False, "normalized_description": canonical}
        return {"work_group": "FABRICATION", "disposition": PLANNED, "reason": "frozen_audit_fire_extinguisher_hardware_rule", "sublet_eligible": False, "normalized_description": canonical}
    if re.search(r"WHEEL NUT INDICATOR", canonical):
        return {"work_group": "TYRE", "disposition": PLANNED, "reason": "frozen_audit_wheel_nut_indicator_rule", "sublet_eligible": False, "normalized_description": canonical}
    if re.search(r"REFLECTIVE STRIPE|\bSIGNAGE\b|\bDECAL\b", canonical):
        eligible = _sublet_evidence(explicit_job_card_sublet, authorized_provider, authorized_booking)
        return {
            "work_group": "SUBLET" if eligible else None,
            "disposition": PLANNED if eligible else REVIEW,
            "reason": "explicit_sublet_evidence" if eligible else "reflective_signage_requires_sublet_evidence",
            "sublet_eligible": eligible,
            "normalized_description": canonical,
        }
    if re.search(r"LONG RANGE|LONG RANGER|ARB FRONTIER", canonical) and re.search(r"TANK|FUEL", canonical):
        return {"work_group": "HOIST", "disposition": PLANNED, "reason": "frozen_audit_long_range_tank_rule", "sublet_eligible": False, "normalized_description": canonical}
    if re.search(r"\bGVM\b|WEIGHT UPGRADE|SUSPENSION|LIFT KIT|OME .*NITRO", canonical):
        return {"work_group": "HOIST", "disposition": PLANNED, "reason": "gvm_or_suspension_upgrade_rule", "sublet_eligible": False, "normalized_description": canonical}
    if re.search(r"TOW ?BAR|TOWBAR|BULL ?BAR|BULBAR|RECOVERY POINT|BONNET PROTECTOR|WEATHER SHIELD|HEADLAMP COVER|HEADLIGHT COVER|SEAT COVER|PRE DELIVERY", canonical):
        return {"work_group": "FITTING", "disposition": PLANNED, "reason": "approved_fitting_rule", "sublet_eligible": False, "normalized_description": canonical}
    return {"work_group": None, "disposition": REVIEW, "reason": "no_reviewed_taxonomy_rule", "sublet_eligible": False, "normalized_description": canonical}


def compare_shadow(
    instructions: Iterable[Mapping[str, Any]],
    *,
    incumbent_lines: Iterable[Mapping[str, Any]] = (),
    handoff_path: Path = DEFAULT_HANDOFF,
) -> dict[str, Any]:
    """Compare v2 classifications to incumbent output without operational writes."""
    frozen = load_frozen_taxonomy_audit(handoff_path)
    incumbent = {}
    for row in incumbent_lines:
        item = dict(row)
        key = str(item.get("source_line_id") or item.get("line_id") or "")
        if key:
            incumbent[key] = item
    decisions: list[dict[str, Any]] = []
    for index, raw in enumerate(instructions, 1):
        item = dict(raw)
        description = str(item.get("description") or item.get("complete_source_description") or "")
        source_hash = str(item.get("source_hash") or item.get("attachment_hash") or "unknown")
        operation_no = str(item.get("operation_no") or item.get("source_row_no") or index)
        normalized = _canonical_description(description)
        source_line_id = hashlib.sha256(f"{source_hash}|{operation_no}|{normalized}".encode("utf-8")).hexdigest()
        result = classify_shadow_description(
            description,
            explicit_job_card_sublet=bool(item.get("explicit_job_card_sublet")),
            authorized_provider=bool(item.get("authorized_provider")),
            authorized_booking=bool(item.get("authorized_booking")),
        )
        old = incumbent.get(source_line_id, {})
        old_group = old.get("work_group", old.get("observed_group"))
        decisions.append({
            "instruction_id": str(item.get("instruction_id") or f"shadow-instruction-{index:04d}"),
            "source_line_id": source_line_id,
            "description": description,
            "operation_no": operation_no,
            "source_hash": source_hash,
            "attachment_hash": item.get("attachment_hash"),
            "stock": item.get("stock"),
            "job_card": item.get("job_card") or item.get("job_card_number"),
            "v2_work_group": result["work_group"],
            "incumbent_work_group": old_group,
            "changed_from_incumbent": bool(old_group and old_group != result["work_group"]),
            "disposition": result["disposition"],
            "reason": result["reason"],
            "evidence_refs": [f"source:{source_hash}"] + ([f"attachment:{item['attachment_hash']}"] if item.get("attachment_hash") else []),
        })
    changed = sum(1 for row in decisions if row["changed_from_incumbent"])
    counts: dict[str, int] = {}
    for row in decisions:
        counts[row["disposition"]] = counts.get(row["disposition"], 0) + 1
    return {
        "schema_version": "pdc-email-ai-v2-shadow-comparison-v1",
        "mode": "SHADOW_ZERO_WRITE",
        "frozen_taxonomy": {key: value for key, value in frozen.items() if key != "audit"},
        "decisions": decisions,
        "counts": counts,
        "changed_from_incumbent": changed,
        "instruction_count": len(decisions),
        "all_instructions_accounted": True,
        "operational_writes_attempted": False,
        "mailbox_mutated": False,
        "production_touched": False,
        "legacy_runtime_touched": False,
    }


def write_shadow_receipt(path: Path, comparison: Mapping[str, Any]) -> str:
    """Write a deterministic, non-secret shadow receipt and return its digest."""
    payload = json.dumps(dict(comparison), sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n"
    destination = Path(path).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(payload, encoding="utf-8")
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


__all__ = ["CONFLICT", "DEFAULT_HANDOFF", "PLANNED", "REVIEW", "UNSUPPORTED", "classify_shadow_description", "compare_shadow", "load_frozen_taxonomy_audit", "write_shadow_receipt"]
