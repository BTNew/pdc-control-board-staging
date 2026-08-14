#!/usr/bin/env python3
"""Fail-closed validation for the tracked production browser configuration."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

PRODUCTION_PROJECT_REF = "vjdtsswhroyguxyfjdkt"
PRODUCTION_URL = f"https://{PRODUCTION_PROJECT_REF}.supabase.co"
APPROVED_TOP_LEVEL_FIELDS = {
    "auth",
    "environment",
    "projectRef",
    "publishableKey",
    "url",
    "vehicleLifecycle",
    "workshop",
}
ASSIGNMENT_PREFIX = "window.PDC_SUPABASE_CONFIG = "
PUBLISHABLE_KEY_RE = re.compile(r"sb_publishable_[A-Za-z0-9_-]{20,}\Z")
FORBIDDEN_SOURCE_PATTERNS = (
    re.compile(r"sb_secret_", re.IGNORECASE),
    re.compile(r"service[_-]?role", re.IGNORECASE),
    re.compile(r"client[_-]?secret", re.IGNORECASE),
    re.compile(r'(?:["\']password["\']\s*:|password\s*=)', re.IGNORECASE),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----", re.IGNORECASE),
    re.compile(r"postgres(?:ql)?://", re.IGNORECASE),
    re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"),
    re.compile(r"bearer\s+", re.IGNORECASE),
    re.compile(r"access[_-]?token|refresh[_-]?token", re.IGNORECASE),
    re.compile(r"cdsmnqxtyyoeoznmbidd|pdc-control-board-staging", re.IGNORECASE),
)


class ConfigValidationError(ValueError):
    """The browser config is not the exact reviewed public schema."""


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ConfigValidationError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def load_and_validate_public_browser_config(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ConfigValidationError(f"cannot read production browser config: {exc}") from exc
    try:
        source = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigValidationError("production browser config is not UTF-8") from exc

    if source.startswith("\ufeff") or "\r" in source:
        raise ConfigValidationError("production browser config must be UTF-8 without BOM and LF-only")
    if not source.startswith(ASSIGNMENT_PREFIX) or not source.endswith(";\n"):
        raise ConfigValidationError("production browser config must be one canonical assignment")
    for pattern in FORBIDDEN_SOURCE_PATTERNS:
        if pattern.search(source):
            raise ConfigValidationError("production browser config contains a forbidden credential, token, staging or private marker")

    payload = source[len(ASSIGNMENT_PREFIX):-2]
    try:
        config = json.loads(payload, object_pairs_hook=_reject_duplicate_keys)
    except (json.JSONDecodeError, ConfigValidationError) as exc:
        raise ConfigValidationError(f"production browser config payload is not strict JSON: {exc}") from exc
    if not isinstance(config, dict):
        raise ConfigValidationError("production browser config payload must be an object")
    canonical = json.dumps(config, separators=(",", ":"), sort_keys=True)
    if payload != canonical:
        raise ConfigValidationError("production browser config JSON is not canonical")

    if set(config) != APPROVED_TOP_LEVEL_FIELDS:
        raise ConfigValidationError("production browser config has missing or unapproved top-level fields")
    if config.get("environment") != "production":
        raise ConfigValidationError("production browser config environment is not production")
    if config.get("projectRef") != PRODUCTION_PROJECT_REF:
        raise ConfigValidationError("production browser config projectRef is not the approved production project")
    if config.get("url") != PRODUCTION_URL:
        raise ConfigValidationError("production browser config URL is not the approved production endpoint")
    key = config.get("publishableKey")
    if not isinstance(key, str) or not PUBLISHABLE_KEY_RE.fullmatch(key):
        raise ConfigValidationError("production browser config key is not a modern publishable browser key")
    if config.get("auth") != {"mode": "password", "provider": "azure"}:
        raise ConfigValidationError("production browser auth fields are not the exact approved public contract")
    if config.get("workshop") != {"sharedData": True}:
        raise ConfigValidationError("production workshop config is not exactly sharedData=true")
    if config.get("vehicleLifecycle") != {"sharedData": True}:
        raise ConfigValidationError("production lifecycle config is not exactly sharedData=true")
    return config


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate_public_browser_config.py <config.js>", file=sys.stderr)
        return 2
    try:
        load_and_validate_public_browser_config(Path(argv[1]))
    except ConfigValidationError as exc:
        print(f"PUBLIC_BROWSER_CONFIG_BLOCKED: {exc}", file=sys.stderr)
        return 1
    print("PUBLIC_BROWSER_CONFIG_VALID")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
