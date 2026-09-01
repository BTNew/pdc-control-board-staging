"""Deterministic v2 work taxonomy with Craig-rule precedence and fail-closed output."""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from .pdc_email_ai_v2_rules import CraigRuleStore


@dataclass(frozen=True)
class Classification:
    work_key: str | None
    disposition: str
    reason: str
    rule_id: str | None = None
    ruleset_version: str = "rules-v2"

    def as_dict(self) -> dict[str, Any]:
        return {
            "work_key": self.work_key,
            "disposition": self.disposition,
            "reason": self.reason,
            "rule_id": self.rule_id,
            "ruleset_version": self.ruleset_version,
        }


def _norm(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9]+", " ", str(value or "").upper())
    return re.sub(r"\s+", " ", value).strip()


def classify_operation(
    description: str,
    *,
    rules: CraigRuleStore | None = None,
    explicit_sublet: bool = False,
    mounted: bool = False,
    loose: bool = False,
) -> Classification:
    """Classify one source line; unknown/unsafe meaning is never guessed."""
    store = rules or CraigRuleStore.default()
    text = _norm(description)
    if not text:
        return Classification(None, "UNSUPPORTED", "empty_description", ruleset_version=store.ruleset_version)

    # These descriptions need an explicit reviewed rule before they can be
    # promoted. Do not infer an Electrical/Fitting group from an unresolved
    # historical label in the shadow or live successor lane.
    if ("12V" in text and "SOCKET" in text) or "SAFETY TRIANGLE" in text or "WEATHER SHIELD" in text:
        return Classification(None, "REVIEW", "durable_rule_pending_review", ruleset_version=store.ruleset_version)

    # Negative cross-domain evidence must win over the generic GVM/Hoist family.
    if ("FMG" in text or "SIGNAGE" in text or "LOGO" in text) and any(token in text for token in ("GVM", "GCM", "TARE", "DECAL", "STRIP")):
        return Classification(None, "REVIEW", "mixed_fmg_signage_gvm_decal_not_hoist", ruleset_version=store.ruleset_version)
    if "FIRE EXT" in text or "FIRE EXTINGUISH" in text or "FIRE EXTINUIS" in text:
        if "DECAL" in text or "LABEL" in text or "STICKER" in text:
            return Classification(None, "REVIEW", "fire_extinguisher_decal_only", ruleset_version=store.ruleset_version)
        rule = store.resolve("FIRE EXT")
        if mounted or any(token in text for token in ("MOUNT", "CARGO BARRIER", "HEADBOARD", "HARDWARE")):
            return Classification("FABRICATION", "PLANNED", "fire_extinguisher_hardware", rule["rule_id"] if rule else None, store.ruleset_version)
        if loose:
            return Classification("FITTING", "PLANNED", "loose_safety_item_fitting", "craig-pdi-seat-cover-fitting", store.ruleset_version)
        return Classification("FABRICATION", "PLANNED", "fire_extinguisher_hardware", rule["rule_id"] if rule else None, store.ruleset_version)
    if "WHEEL NUT INDICATOR" in text:
        return Classification("TYRE", "PLANNED", "wheel_nut_indicator", ruleset_version=store.ruleset_version)

    rule = store.resolve(text)
    if rule:
        if rule["destination"] == "SUBLET":
            if explicit_sublet:
                return Classification("SUBLET", "PLANNED", "explicit_sublet_evidence", rule["rule_id"], store.ruleset_version)
            return Classification(None, "REVIEW", "reflective_stripes_requires_explicit_sublet_evidence", rule["rule_id"], store.ruleset_version)
        # These mappings were discussed but are not proven as installed in the
        # authoritative rule store for this commissioning lane. Preserve the
        # instruction for supervised review rather than silently routing it.
        if rule["rule_id"] in {"craig-accessory-electrical", "craig-protection-fitting", "craig-pdi-seat-cover-fitting"} and any(token in text for token in ("12V", "SOCKET", "WEATHER SHIELD", "SAFETY TRIANGLE")):
            return Classification(None, "REVIEW", "taxonomy_rule_requires_authoritative_rule_proof", rule["rule_id"], store.ruleset_version)
        return Classification(rule["destination"], "PLANNED", "craig_approved_rule", rule["rule_id"], store.ruleset_version)

    # Specific phrases not represented as aliases remain in this deterministic
    # layer so the AI planner cannot turn supplier prose into a work area.
    if re.search(r"\b(GVM|WEIGHT UPGRADE|SUSPENSION|LIFT KIT|OME .*NITRO)\b", text):
        return Classification("HOIST", "PLANNED", "gvm_or_suspension_upgrade", ruleset_version=store.ruleset_version)
    if "12V" in text and any(token in text for token in ("SOCKET", "PLUG", "ACCESSORY")):
        return Classification(None, "REVIEW", "taxonomy_rule_requires_authoritative_rule_proof", "craig-accessory-electrical", store.ruleset_version)
    if any(token in text for token in ("BCDC", "XRS 370C", "NAVMAN IVMS", "CARDEX", "ARB BATTERY BOX")):
        return Classification("ELECTRICAL", "PLANNED", "approved_electrical_accessory", "craig-accessory-electrical", store.ruleset_version)
    if "TINT" in text and not any(token in text for token in ("BONNET PROTECTOR", "WEATHER SHIELD")):
        return Classification("TINT", "PLANNED", "genuine_window_tint", ruleset_version=store.ruleset_version)
    return Classification(None, "REVIEW", "no_reviewed_taxonomy_rule", ruleset_version=store.ruleset_version)


__all__ = ["Classification", "classify_operation"]
