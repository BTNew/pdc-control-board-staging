"""Versioned Craig-approved business rules for the isolated v2 planner.

The rule catalog is immutable in-process data. A future authoritative rule-store
adapter may replace it, but planner decisions always retain the selected rule id
and version instead of hiding a mapping in model memory.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Rule:
    rule_id: str
    pattern: str
    destination: str
    original_instruction: str
    scope: str = "future_staging_intake"
    priority: int = 100
    aliases: tuple[str, ...] = ()
    active: bool = True
    version: str = "rules-v2"

    def as_dict(self) -> dict[str, Any]:
        return {
            "rule_id": self.rule_id,
            "pattern": self.pattern,
            "destination": self.destination,
            "original_instruction": self.original_instruction,
            "scope": self.scope,
            "priority": self.priority,
            "aliases": list(self.aliases),
            "active": self.active,
            "version": self.version,
        }


_DEFAULT_RULES = (
    Rule("craig-bullbar-fitting", "BULLBAR", "FITTING", "Bulbar, Bullbar and Bull Bar map to Fitting.", aliases=("BULBAR", "BULL BAR", "BULLBAR")),
    Rule("craig-towbar-fitting", "TOWBAR", "FITTING", "Towbars and Tow Bars map to Fitting.", aliases=("TOW BAR", "TOWBAR")),
    Rule("craig-reflective-stripes-sublet", "REFLECTIVE STRIPES", "SUBLET", "Reflective Stripes map to Sublet when explicit Sublet evidence exists.", aliases=("REFLECTIVE STRIPES - YELLOW",)),
    Rule("craig-long-range-tanks-hoist", "LONG RANGE TANK", "HOIST", "Long Range, Long Ranger and ARB Frontier tanks map to Hoist.", aliases=("LONG RANGER", "ARB FRONTIER")),
    Rule("craig-fire-extinguisher-hardware-fabrication", "FIRE EXTINGUISHER HARDWARE", "FABRICATION", "Fire extinguisher hardware or mounting maps to Fabrication.", aliases=("FIRE EXT", "FIRE EXTINUISER")),
    Rule("craig-accessory-electrical", "12V ACCESSORY", "ELECTRICAL", "12V sockets, plugs, ARB battery boxes, BCDC and XRS radio work map to Electrical.", aliases=("12V SOCKET", "ANDERSON PLUG", "ARB BATTERY BOX", "BCDC", "XRS 370C", "NAVMAN IVMS", "CARDEX")),
    Rule("craig-protection-fitting", "PROTECTION ACCESSORY", "FITTING", "Bonnet protectors, weather shields, headlamp covers and recovery points map to Fitting.", aliases=("BONNET PROTECTOR", "WEATHER SHIELD", "HEADLAMP COVER", "HEADLIGHT COVER", "RECOVERY POINT")),
    Rule("craig-pdi-seat-cover-fitting", "PDI ACCESSORY", "FITTING", "Pre-Delivery, seat-cover and approved loose safety-kit work maps to Fitting.", aliases=("PRE DELIVERY", "SEAT COVER", "SAFETY TRIANGLE", "FIRST AID")),
)


class CraigRuleStore:
    """Read-only versioned rule store used by the shadow/runtime lane."""

    def __init__(self, rules: tuple[Rule, ...], *, ruleset_version: str = "rules-v2") -> None:
        if not ruleset_version or not ruleset_version.startswith("rules-v"):
            raise ValueError("ruleset_version must be versioned")
        self.ruleset_version = ruleset_version
        self._rules = tuple(sorted((rule for rule in rules if rule.active), key=lambda rule: (-rule.priority, rule.rule_id)))

    @classmethod
    def default(cls) -> "CraigRuleStore":
        return cls(_DEFAULT_RULES)

    @property
    def rules(self) -> tuple[Rule, ...]:
        return self._rules

    def resolve(self, description: str) -> dict[str, Any] | None:
        normalized = " ".join(str(description or "").upper().replace("-", " ").split())
        for rule in self._rules:
            if rule.pattern in normalized or any(alias in normalized for alias in rule.aliases):
                return {**rule.as_dict(), "version": self.ruleset_version}
        return None

    def snapshot(self) -> dict[str, Any]:
        return {"ruleset_version": self.ruleset_version, "rules": [rule.as_dict() for rule in self._rules]}


__all__ = ["CraigRuleStore", "Rule"]
