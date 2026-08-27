#!/usr/bin/env python3
"""Authenticated-JWT active preflight successor for sealed Monitor release 2026.08.44.

The sealed .44 release remains immutable. This external successor keeps the
planner/trust and environment checks from the prior compatibility lane, but
uses exact-actor staging SECURITY DEFINER RPCs with a normal Supabase
``authenticated`` JWT. It never issues tokens, opens IMAP, starts a task,
changes a mailbox, processes UID514, or writes Production.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Mapping

_BASE_PATH = Path(__file__).with_name("pdc_active_preflight_compatibility.py")
if not _BASE_PATH.is_file():
    # Installed .44 keeps the predecessor under its historical protected name.
    _BASE_PATH = Path(__file__).with_name("active-preflight-compatibility.py")
_SPEC = importlib.util.spec_from_file_location("pdc_active_preflight_compatibility_base", _BASE_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("compatibility predecessor is missing")
base = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(base)

AUTHENTICATED_VERIFY_RPC = "verify_pdc_monitor_runtime_binding_authenticated_672"
AUTHENTICATED_UID514_RPC = "read_pdc_uid514_transaction_receipt_authenticated_672"
EXPECTED_COMPATIBILITY_HEAD = 672
EXPECTED_URL = base.EXPECTED_URL
EXPECTED_ACTOR_ID = base.EXPECTED_ACTOR_ID
EXPECTED_ACTOR_EMAIL = base.EXPECTED_ACTOR_EMAIL
EXPECTED_GATEWAY = base.EXPECTED_GATEWAY
EXPECTED_RELEASE_NAME = base.EXPECTED_RELEASE_NAME
EXPECTED_HEAD = base.EXPECTED_HEAD
EXPECTED_PLANNER_SHA256 = base.EXPECTED_PLANNER_SHA256
EXPECTED_TRUST_SHA256 = base.EXPECTED_TRUST_SHA256
CompatibilityError = base.CompatibilityError

# The successor proves that active mailboxes remain zero before any task path.


def validate_env(env: Mapping[str, str]) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    for name in base.FORBIDDEN_ENV:
        if env.get(name, "").strip():
            base.fail(f"broad or actor credential is forbidden: {name}")
    missing = [name for name in base.REQUIRED_ENV if not env.get(name, "").strip()]
    if missing:
        base.fail("CREDENTIAL_GATE_MISSING_PROTECTED_VALUES:" + ",".join(missing))
    if not base.exact_url(env["SUPABASE_URL"].rstrip("/")) or base.PRODUCTION_PROJECT_REF in env["SUPABASE_URL"]:
        base.fail("exact staging Supabase URL required")
    exacts = {
        "PDC_MONITOR_ACTOR_EMAIL": base.EXPECTED_ACTOR_EMAIL,
        "PDC_MONITOR_GATEWAY_INSTANCE_ID": base.EXPECTED_GATEWAY,
        "PDC_MONITOR_RELEASE_NAME": base.EXPECTED_RELEASE_NAME,
        "IMAP_BRIDGE_HOST": "imap.gmail.com",
        "IMAP_BRIDGE_USERNAME": "pmbcontroller@gmail.com",
        "IMAP_BRIDGE_FOLDER": "Inbox",
        "IMAP_BRIDGE_MINIMUM_UID": "515",
        "IMAP_BRIDGE_UIDVALIDITY": "1",
        "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID": "514",
        "IMAP_BRIDGE_MARK_READ": "false",
        "PDC_OUTBOUND_EMAIL_ENABLED": "false",
        "PDC_AGENTIC_EMAIL_ENABLED": "true",
    }
    if any(env.get(key, "").strip().lower() != value.lower() for key, value in exacts.items()):
        base.fail("CREDENTIAL_GATE_ENVIRONMENT_BINDING_MISMATCH")
    token_claims = base.jwt_payload(env["PDC_MONITOR_ACCESS_TOKEN"])
    supervised_claims = base.jwt_payload(env["PDC_SUPERVISED_MONITOR_JWT"])
    for claims in (token_claims, supervised_claims):
        if claims.get("role") != "authenticated":
            base.fail("CREDENTIAL_GATE_STANDARD_AUTHENTICATED_REQUIRED")
        if claims.get("sub") != base.EXPECTED_ACTOR_ID:
            base.fail("CREDENTIAL_GATE_ACTOR_SUBJECT_MISMATCH")
        if str(claims.get("email", "")).lower() != base.EXPECTED_ACTOR_EMAIL:
            base.fail("CREDENTIAL_GATE_ACTOR_EMAIL_MISMATCH")
    return token_claims, supervised_claims


def validate_live(env: Mapping[str, str], manifest: Mapping[str, Any], planner: Mapping[str, str], require_terminal_uid514: bool) -> dict[str, Any]:
    token_claims, _supervised_claims = validate_env(env)
    attestation = base.rpc(env, AUTHENTICATED_VERIFY_RPC, {
        "p_mode": "active", "p_gateway_instance_id": base.EXPECTED_GATEWAY,
        "p_release_name": base.EXPECTED_RELEASE_NAME, "p_source_sha": manifest["source_sha"],
        "p_manifest_sha256": env["PDC_EXPECTED_MANIFEST_SHA256"],
        "p_semantic_planner_sha256": planner["planner_sha256"],
        "p_semantic_planner_trust_receipt_sha256": planner["trust_receipt_sha256"],
    })
    required = (
        attestation.get("ok") is True,
        attestation.get("code") == "runtime_binding_verified_authenticated_672",
        attestation.get("migration_head") == base.EXPECTED_HEAD,
        attestation.get("compatibility_successor_head") == EXPECTED_COMPATIBILITY_HEAD,
        attestation.get("mode") == "active",
        attestation.get("actor_id") == token_claims.get("sub"),
        attestation.get("actor_email") == base.EXPECTED_ACTOR_EMAIL,
        attestation.get("jwt_role") == "authenticated",
        attestation.get("server_application_role") == "importer",
        attestation.get("gateway_instance_id") == base.EXPECTED_GATEWAY,
        attestation.get("release_name") == base.EXPECTED_RELEASE_NAME,
        attestation.get("manifest_sha256") == env["PDC_EXPECTED_MANIFEST_SHA256"],
        attestation.get("source_sha") == manifest.get("source_sha"),
        attestation.get("semantic_planner_sha256") == planner["planner_sha256"],
        attestation.get("semantic_planner_trust_receipt_sha256") == planner["trust_receipt_sha256"],
        attestation.get("planner_commissioned") is True,
        attestation.get("writer_active") is True,
        attestation.get("operational") is True,
        attestation.get("activation_ready") is True,
        attestation.get("production_writes") is False,
        attestation.get("task_enabled") is False,
        attestation.get("mailbox_contacted") is False,
        attestation.get("uid514_processed") is False,
    )
    if not all(required):
        base.fail("live authenticated 672 actor or planner attestation mismatch")
    receipt = base.rpc(env, AUTHENTICATED_UID514_RPC, {"p_recovery_event_id": 25751401})
    if any(key in receipt for key in {"attempt_metadata", "original_extracted_values"}):
        base.fail("UID514 readback exposed protected evidence")
    if (receipt.get("ok") is not True or receipt.get("recovery_event_id") != 25751401
            or receipt.get("mailbox") != "pmbcontroller@gmail.com" or receipt.get("folder") != "Inbox"
            or receipt.get("uidvalidity") != 1 or receipt.get("uid") != 514):
        base.fail("UID514 recovery readback scope mismatch")
    if require_terminal_uid514 and (receipt.get("code") != "uid514_receipt_terminal" or receipt.get("terminal") is not True):
        base.fail("terminal UID514 receipt is required before monitoring")
    return {
        "attestation": attestation,
        "uid514_receipt_status": {key: receipt.get(key) for key in ("ok", "code", "terminal", "recovery_event_id")},
    }


def validate(args: argparse.Namespace) -> dict[str, Any]:
    manifest, paths = base.validate_release(args.release_root, args.trust_root)
    if args.compatibility_path.resolve(strict=True) != Path(__file__).resolve(strict=True):
        base.fail("authenticated compatibility successor path binding mismatch")
    env = dict(base.load_env(args.env_file))
    env["PDC_EXPECTED_MANIFEST_SHA256"] = base.sha256_file(base.child_path(args.release_root, "release-manifest.json", "release manifest"))
    planner = base.validate_external_planner(env, paths, manifest)
    base.planner_smoke(env)
    result: dict[str, Any] = {
        "ok": True, "authenticated_compatibility_successor": True, "active_mode": True,
        "release_name": base.EXPECTED_RELEASE_NAME, "release_version": base.EXPECTED_RELEASE_VERSION,
        "manifest_sha256": env["PDC_EXPECTED_MANIFEST_SHA256"], "migration_head": base.EXPECTED_HEAD,
        "compatibility_successor_head": EXPECTED_COMPATIBILITY_HEAD, "project_ref": base.EXPECTED_PROJECT_REF,
        "planner": planner, "credential_gate_reached": False, "mailbox_contacted": False,
        "production_contacted": False, "task_started": False, "uid514_processed": False,
    }
    if args.live:
        result.update(validate_live(env, manifest, planner, args.require_terminal_uid514))
        result["credential_gate_reached"] = True
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-root", required=True, type=Path)
    parser.add_argument("--trust-root", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--compatibility-path", required=True, type=Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--require-terminal-uid514", action="store_true")
    args = parser.parse_args()
    if args.require_terminal_uid514 and not args.live:
        base.fail("terminal UID514 gate requires live preflight")
    print(json.dumps(validate(args), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.CompatibilityError as exc:
        print(json.dumps({"ok": False, "authenticated_compatibility_successor": True, "error": str(exc), "mailbox_contacted": False, "production_contacted": False, "task_started": False, "uid514_processed": False}, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(1)
