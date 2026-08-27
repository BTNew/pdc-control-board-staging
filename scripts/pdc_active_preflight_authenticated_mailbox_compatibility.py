#!/usr/bin/env python3
"""Authenticated active preflight for the guarded .44 mailbox transition 674.

The sealed .44 release and the 672/673 proof paths remain unchanged. This
external successor uses only the exact standard authenticated actor and the
674 RPCs, which additionally prove that exactly the pre-provisioned staging
mailbox is active. It never fetches mail, starts a task, processes UID514,
mutates vehicles, sends email, or writes Production.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Mapping

_CORE_NAMES = ("pdc_active_preflight_compatibility.py", "active-preflight-compatibility.py")
_AUTH_NAMES = (
    "pdc_active_preflight_authenticated_compatibility.py",
    "active-preflight-authenticated-compatibility.py",
)
_CORE_PATH = next((Path(__file__).with_name(name) for name in _CORE_NAMES if Path(__file__).with_name(name).is_file()), None)
_AUTH_PATH = next((Path(__file__).with_name(name) for name in _AUTH_NAMES if Path(__file__).with_name(name).is_file()), None)
if _CORE_PATH is None or _AUTH_PATH is None:
    raise RuntimeError("authenticated compatibility predecessors are missing")
_SPEC = importlib.util.spec_from_file_location("pdc_active_preflight_compatibility_core", _CORE_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("active compatibility core cannot load")
base = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(base)
_AUTH_SPEC = importlib.util.spec_from_file_location("pdc_active_preflight_authenticated_compatibility_base", _AUTH_PATH)
if _AUTH_SPEC is None or _AUTH_SPEC.loader is None:
    raise RuntimeError("authenticated compatibility predecessor cannot load")
auth = importlib.util.module_from_spec(_AUTH_SPEC)
_AUTH_SPEC.loader.exec_module(auth)

AUTHENTICATED_VERIFY_RPC = "verify_pdc_monitor_runtime_binding_authenticated_674"
AUTHENTICATED_UID514_RPC = "read_pdc_uid514_transaction_receipt_authenticated_674"
EXPECTED_COMPATIBILITY_HEAD = 674
EXPECTED_URL = base.EXPECTED_URL
EXPECTED_ACTOR_ID = base.EXPECTED_ACTOR_ID
EXPECTED_ACTOR_EMAIL = base.EXPECTED_ACTOR_EMAIL
EXPECTED_GATEWAY = base.EXPECTED_GATEWAY
EXPECTED_RELEASE_NAME = base.EXPECTED_RELEASE_NAME
EXPECTED_HEAD = base.EXPECTED_HEAD
EXPECTED_PLANNER_SHA256 = base.EXPECTED_PLANNER_SHA256
EXPECTED_TRUST_SHA256 = base.EXPECTED_TRUST_SHA256
CompatibilityError = base.CompatibilityError


def validate_env(env: Mapping[str, str]) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    """Reuse the predecessor's exact environment and standard-JWT gates."""
    return auth.validate_env(env)


def validate_live(
    env: Mapping[str, str],
    manifest: Mapping[str, Any],
    planner: Mapping[str, str],
    require_terminal_uid514: bool,
) -> dict[str, Any]:
    token_claims, _supervised_claims = validate_env(env)
    attestation = base.rpc(env, AUTHENTICATED_VERIFY_RPC, {
        "p_mode": "active",
        "p_gateway_instance_id": EXPECTED_GATEWAY,
        "p_release_name": EXPECTED_RELEASE_NAME,
        "p_source_sha": manifest["source_sha"],
        "p_manifest_sha256": env["PDC_EXPECTED_MANIFEST_SHA256"],
        "p_semantic_planner_sha256": planner["planner_sha256"],
        "p_semantic_planner_trust_receipt_sha256": planner["trust_receipt_sha256"],
    })
    required = (
        attestation.get("ok") is True,
        attestation.get("code") == "runtime_binding_verified_authenticated_674",
        attestation.get("migration_head") == EXPECTED_HEAD,
        attestation.get("compatibility_successor_head") == EXPECTED_COMPATIBILITY_HEAD,
        attestation.get("mode") == "active",
        attestation.get("actor_id") == token_claims.get("sub"),
        attestation.get("actor_email") == EXPECTED_ACTOR_EMAIL,
        attestation.get("jwt_role") == "authenticated",
        attestation.get("server_application_role") == "importer",
        attestation.get("gateway_instance_id") == EXPECTED_GATEWAY,
        attestation.get("release_name") == EXPECTED_RELEASE_NAME,
        attestation.get("manifest_sha256") == env["PDC_EXPECTED_MANIFEST_SHA256"],
        attestation.get("source_sha") == manifest.get("source_sha"),
        attestation.get("semantic_planner_sha256") == planner["planner_sha256"],
        attestation.get("semantic_planner_trust_receipt_sha256") == planner["trust_receipt_sha256"],
        attestation.get("planner_commissioned") is True,
        attestation.get("writer_active") is True,
        attestation.get("operational") is True,
        attestation.get("activation_ready") is True,
        attestation.get("mailbox_active") is True,
        attestation.get("active_mailbox_count") == 1,
        attestation.get("production_writes") is False,
        attestation.get("task_enabled") is False,
        attestation.get("mailbox_contacted") is False,
        attestation.get("uid514_processed") is False,
    )
    if not all(required):
        base.fail("live authenticated 674 actor, mailbox, or planner attestation mismatch")
    receipt = base.rpc(env, AUTHENTICATED_UID514_RPC, {"p_recovery_event_id": 25751401})
    if any(key in receipt for key in {"attempt_metadata", "original_extracted_values", "actor_email"}):
        base.fail("UID514 readback exposed protected evidence")
    if (
        receipt.get("ok") is not True
        or receipt.get("recovery_event_id") != 25751401
        or receipt.get("mailbox") != "pmbcontroller@gmail.com"
        or receipt.get("folder") != "Inbox"
        or receipt.get("uidvalidity") != 1
        or receipt.get("uid") != 514
    ):
        base.fail("UID514 recovery readback scope mismatch")
    if require_terminal_uid514 and (receipt.get("code") != "uid514_receipt_terminal" or receipt.get("terminal") is not True):
        base.fail("terminal UID514 receipt is required before monitoring")
    return {
        "attestation": attestation,
        "uid514_receipt_status": {
            key: receipt.get(key) for key in ("ok", "code", "terminal", "recovery_event_id")
        },
    }


def validate(args: argparse.Namespace) -> dict[str, Any]:
    manifest, paths = base.validate_release(args.release_root, args.trust_root)
    if args.compatibility_path.resolve(strict=True) != Path(__file__).resolve(strict=True):
        base.fail("authenticated mailbox compatibility successor path binding mismatch")
    env = dict(base.load_env(args.env_file))
    env["PDC_EXPECTED_MANIFEST_SHA256"] = base.sha256_file(
        base.child_path(args.release_root, "release-manifest.json", "release manifest")
    )
    planner = base.validate_external_planner(env, paths, manifest)
    base.planner_smoke(env)
    result: dict[str, Any] = {
        "ok": True,
        "authenticated_mailbox_compatibility_successor": True,
        "active_mode": True,
        "release_name": EXPECTED_RELEASE_NAME,
        "release_version": base.EXPECTED_RELEASE_VERSION,
        "manifest_sha256": env["PDC_EXPECTED_MANIFEST_SHA256"],
        "migration_head": EXPECTED_HEAD,
        "compatibility_successor_head": EXPECTED_COMPATIBILITY_HEAD,
        "project_ref": base.EXPECTED_PROJECT_REF,
        "planner": planner,
        "credential_gate_reached": False,
        "mailbox_contacted": False,
        "production_contacted": False,
        "task_started": False,
        "uid514_processed": False,
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
        print(json.dumps({
            "ok": False,
            "authenticated_mailbox_compatibility_successor": True,
            "error": str(exc),
            "mailbox_contacted": False,
            "production_contacted": False,
            "task_started": False,
            "uid514_processed": False,
        }, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(1)
