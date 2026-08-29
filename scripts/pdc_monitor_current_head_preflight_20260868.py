#!/usr/bin/env python3
"""Current-head 766 authenticated preflight for the external .68 control lane.

This verifier is read-only with respect to staging: it checks protected local
artifacts, performs the planner smoke test, then calls only the 766 runtime
attestation and the existing UID514 receipt reader. It never opens IMAP,
changes mailbox flags, enables a task, or writes Production.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Mapping

PROJECT = "cdsmnqxtyyoeoznmbidd"
URL = f"https://{PROJECT}.supabase.co"
PRODUCTION = "vjdtsswhroyguxyfjdkt"
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
SEALED_RELEASE = "pdc-monitor-staging-m502-2026.08.44"
SEALED_SOURCE = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
SEALED_MANIFEST = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
PLANNER_SHA = "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"
TRUST_SHA = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
REQUIRED = (
    "SUPABASE_URL", "SUPABASE_ANON_KEY", "PDC_MONITOR_ACCESS_TOKEN",
    "PDC_SUPERVISED_MONITOR_JWT", "PDC_MONITOR_ACTOR_EMAIL",
    "PDC_MONITOR_GATEWAY_INSTANCE_ID", "PDC_MONITOR_RELEASE_NAME",
    "IMAP_BRIDGE_HOST", "IMAP_BRIDGE_USERNAME", "IMAP_BRIDGE_FOLDER",
    "IMAP_BRIDGE_MINIMUM_UID", "IMAP_BRIDGE_UIDVALIDITY",
    "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID", "IMAP_BRIDGE_MARK_READ",
    "PDC_OUTBOUND_EMAIL_ENABLED", "PDC_AGENTIC_EMAIL_ENABLED",
    "PDC_AGENTIC_PLANNER_COMMAND", "PDC_AGENTIC_PLANNER_SHA256",
    "PDC_AGENTIC_PLANNER_TRUST_RECEIPT", "PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256",
)
FORBIDDEN = (
    "SUPABASE_SERVICE_ROLE_KEY", "SERVICE_ROLE_KEY", "SUPABASE_DB_URL",
    "DATABASE_URL", "PDC_SUPERVISED_ACTOR_JWT", "PDC_ADMIN_JWT",
)
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class PreflightError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise PreflightError(message)


def sha(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        fail("controlled file is missing or not regular")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strict_json(raw: bytes, label: str) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                fail(f"duplicate JSON key in {label}")
            result[key] = value
        return result
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                          parse_constant=lambda value: fail(f"non-finite JSON value in {label}"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON in {label}: {exc}")


def load_env(path: Path) -> dict[str, str]:
    if path.is_symlink() or not path.is_file():
        fail("protected runtime environment is missing")
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip().strip('"').strip("'")
    return result


def jwt_payload(token: str) -> Mapping[str, Any]:
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise ValueError
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        value = json.loads(base64.urlsafe_b64decode(payload.encode()).decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError
        return value
    except (ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PreflightError("scoped token is not a parseable JWT") from exc


def exact_url(value: str) -> bool:
    try:
        parsed = urllib.parse.urlsplit(value)
        return (parsed.scheme == "https" and parsed.hostname == f"{PROJECT}.supabase.co"
                and parsed.port is None and not (parsed.username or parsed.password or parsed.query or parsed.fragment)
                and parsed.path in ("", "/"))
    except ValueError:
        return False


def validate_local(bundle: Path, trust: Path, env: Mapping[str, str], compatibility: Path) -> tuple[dict[str, Any], dict[str, str]]:
    if not compatibility.is_file() or compatibility.resolve() != Path(__file__).resolve():
        fail("current-head compatibility path is not bound to this control file")
    if not bundle.is_absolute() or not trust.is_absolute() or trust.resolve() == bundle.resolve():
        fail("protected bundle/trust roots are invalid")
    manifest_path = bundle / "release-manifest.json"
    manifest = strict_json(manifest_path.read_bytes(), "successor manifest")
    if not isinstance(manifest, dict) or manifest.get("release_version") != "2026.08.68" \
            or manifest.get("release_name") != "pdc-monitor-staging-m502-2026.08.68" \
            or manifest.get("parent_release_version") != "2026.08.66" \
            or manifest.get("expected_staging_project_ref") != PROJECT \
            or manifest.get("current_staging_migration_head") != 766 \
            or manifest.get("sealed_parent_release_name") != SEALED_RELEASE \
            or manifest.get("sealed_parent_source_sha") != SEALED_SOURCE \
            or manifest.get("sealed_parent_manifest_sha256") != SEALED_MANIFEST \
            or manifest.get("outbound_email_enabled") is not False:
        fail("successor manifest binding mismatch")
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        fail("successor inventory is missing")
    actual = {item.relative_to(bundle).as_posix() for item in bundle.rglob("*") if item.is_file() and item.name != "release-manifest.json"}
    if actual != set(files):
        fail("successor complete inventory mismatch")
    for relative, metadata in files.items():
        path = (bundle / relative).resolve(strict=True)
        if bundle.resolve() not in path.parents or not isinstance(metadata, dict) \
                or sha(path) != metadata.get("sha256") or path.stat().st_size != metadata.get("bytes"):
            fail(f"successor inventory member mismatch: {relative}")
    for name in FORBIDDEN:
        if env.get(name, "").strip():
            fail(f"forbidden credential name present: {name}")
    missing = [name for name in REQUIRED if not env.get(name, "").strip()]
    if missing:
        fail("protected values missing: " + ",".join(missing))
    if not exact_url(env["SUPABASE_URL"].rstrip("/")) or PRODUCTION in env["SUPABASE_URL"]:
        fail("exact staging URL required")
    exact = {
        "PDC_MONITOR_ACTOR_EMAIL": ACTOR_EMAIL, "PDC_MONITOR_GATEWAY_INSTANCE_ID": GATEWAY,
        "PDC_MONITOR_RELEASE_NAME": SEALED_RELEASE, "IMAP_BRIDGE_HOST": "imap.gmail.com",
        "IMAP_BRIDGE_USERNAME": "pmbcontroller@gmail.com", "IMAP_BRIDGE_FOLDER": "Inbox",
        "IMAP_BRIDGE_MINIMUM_UID": "640", "IMAP_BRIDGE_UIDVALIDITY": "1",
        "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID": "514", "IMAP_BRIDGE_MARK_READ": "false",
        "PDC_OUTBOUND_EMAIL_ENABLED": "false", "PDC_AGENTIC_EMAIL_ENABLED": "true",
    }
    if any(env.get(key, "").strip().lower() != value.lower() for key, value in exact.items()):
        fail("protected environment binding mismatch")
    claims = jwt_payload(env["PDC_MONITOR_ACCESS_TOKEN"])
    supervised = jwt_payload(env["PDC_SUPERVISED_MONITOR_JWT"])
    for token_claims in (claims, supervised):
        if token_claims.get("role") != "authenticated" or token_claims.get("sub") != ACTOR_ID \
                or str(token_claims.get("email", "")).lower() != ACTOR_EMAIL:
            fail("standard authenticated actor binding mismatch")
    planner_path = trust / "pdc_active_semantic_planner.py"
    receipt_path = trust / "pdc-active-semantic-planner-trust-receipt.json"
    if sha(planner_path) != PLANNER_SHA or sha(receipt_path) != TRUST_SHA:
        fail("planner/trust digest mismatch")
    if env["PDC_AGENTIC_PLANNER_SHA256"].lower() != PLANNER_SHA \
            or Path(env["PDC_AGENTIC_PLANNER_TRUST_RECEIPT"]).resolve() != receipt_path.resolve() \
            or env["PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256"].lower() != TRUST_SHA:
        fail("planner environment binding mismatch")
    argv = strict_json(env["PDC_AGENTIC_PLANNER_COMMAND"].encode(), "planner command")
    if not isinstance(argv, list) or not argv or any(not isinstance(item, str) or not item for item in argv):
        fail("planner command must be a nonempty argv array")
    if len([item for item in argv[1:] if item.lower().endswith(".py")]) != 1 \
            or Path(next(item for item in argv[1:] if item.lower().endswith(".py"))).resolve() != planner_path.resolve():
        fail("planner command path mismatch")
    trust_doc = strict_json(receipt_path.read_bytes(), "planner trust receipt")
    if not isinstance(trust_doc, dict) or trust_doc.get("contract") != "pdc-active-semantic-planner-trust-v1" \
            or trust_doc.get("planner_interface") != "pmb-pdc-agentic-email-plan-v1" \
            or trust_doc.get("planner_sha256") != PLANNER_SHA:
        fail("planner trust receipt content mismatch")
    return manifest, {"planner_sha256": PLANNER_SHA, "trust_receipt_sha256": TRUST_SHA}


def planner_smoke(env: Mapping[str, str]) -> None:
    argv = strict_json(env["PDC_AGENTIC_PLANNER_COMMAND"].encode(), "planner command")
    safe_env = {key: os.environ[key] for key in ("SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "TEMP", "TMP") if os.environ.get(key)}
    safe_env["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        completed = subprocess.run(argv, input=json.dumps({
            "contract_version": "pmb-pdc-agentic-planner-request-v1",
            "evidence": {"evidence_hash": "1" * 64, "instruction_candidates": [{"instruction_id": "ins-smoke", "evidence_ref": "body", "text": "Stock 1001: mark parts complete"}]},
            "vehicle_contexts": [{"vehicle_id": "11111111-1111-1111-1111-111111111111", "identity": {"stock_number": "1001", "vin": "", "job_card_number": "", "customer": ""}}],
        }, separators=(",", ":")).encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10, check=False, shell=False, env=safe_env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"planner smoke failed: {type(exc).__name__}")
    plan = strict_json(completed.stdout, "planner smoke") if completed.returncode == 0 else None
    if not isinstance(plan, dict) or plan.get("contract_version") != "pmb-pdc-agentic-email-plan-v1" \
            or not isinstance(plan.get("vehicles"), list) or len(plan["vehicles"]) != 1 \
            or not plan["vehicles"][0].get("actions") or not isinstance(plan.get("instructions"), list) \
            or not plan["instructions"] or plan["instructions"][0].get("disposition") != "ACTIONABLE":
        fail("planner smoke did not produce a bounded actionable plan")


def rpc(env: Mapping[str, str], name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        env["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/" + name,
        data=json.dumps(payload, separators=(",", ":")).encode(), method="POST",
        headers={"apikey": env["SUPABASE_ANON_KEY"], "Authorization": "Bearer " + env["PDC_MONITOR_ACCESS_TOKEN"], "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=35) as response:
            result = strict_json(response.read(1_048_577), f"RPC {name} response")
            if not isinstance(result, dict):
                fail(f"RPC {name} response is not an object")
            return result
    except urllib.error.HTTPError as exc:
        exc.read(4096)
        fail(f"RPC {name} rejected HTTP {exc.code}")
    except urllib.error.URLError as exc:
        fail(f"RPC {name} transport failure: {type(exc).__name__}")


def live_check(env: Mapping[str, str], planner: Mapping[str, str], require_terminal: bool) -> dict[str, Any]:
    attestation = rpc(env, "verify_pdc_monitor_runtime_binding_authenticated_766", {
        "p_mode": "active", "p_gateway_instance_id": GATEWAY, "p_release_name": SEALED_RELEASE,
        "p_source_sha": SEALED_SOURCE, "p_manifest_sha256": SEALED_MANIFEST,
        "p_semantic_planner_sha256": planner["planner_sha256"],
        "p_semantic_planner_trust_receipt_sha256": planner["trust_receipt_sha256"],
    })
    if attestation.get("ok") is not True or attestation.get("code") != "runtime_binding_verified_authenticated_766" \
            or attestation.get("migration_head") != 766 or attestation.get("compatibility_successor_head") != 766 \
            or attestation.get("actor_id") != ACTOR_ID or attestation.get("actor_email") != ACTOR_EMAIL \
            or attestation.get("jwt_role") != "authenticated" or attestation.get("server_application_role") != "importer" \
            or attestation.get("gateway_instance_id") != GATEWAY or attestation.get("release_name") != SEALED_RELEASE \
            or attestation.get("source_sha") != SEALED_SOURCE or attestation.get("manifest_sha256") != SEALED_MANIFEST \
            or attestation.get("semantic_planner_sha256") != PLANNER_SHA \
            or attestation.get("semantic_planner_trust_receipt_sha256") != TRUST_SHA \
            or attestation.get("planner_commissioned") is not True or attestation.get("writer_active") is not True \
            or attestation.get("operational") is not True or attestation.get("activation_ready") is not True \
            or attestation.get("production_writes") is not False or attestation.get("task_enabled") is not False \
            or attestation.get("mailbox_contacted") is not False or attestation.get("uid514_processed") is not False:
        fail("current-head 766 attestation mismatch")
    receipt = rpc(env, "read_pdc_uid514_transaction_receipt_authenticated_674", {"p_recovery_event_id": 25751401})
    if any(key in receipt for key in ("attempt_metadata", "original_extracted_values")) \
            or receipt.get("recovery_event_id") != 25751401 or receipt.get("mailbox") != "pmbcontroller@gmail.com" \
            or receipt.get("folder") != "Inbox" or receipt.get("uidvalidity") != 1 or receipt.get("uid") != 514 \
            or (require_terminal and (receipt.get("code") != "uid514_receipt_terminal" or receipt.get("terminal") is not True)):
        fail("UID514 receipt gate mismatch")
    return {"attestation": {key: attestation.get(key) for key in ("code", "migration_head", "compatibility_successor_head", "operational", "activation_ready", "production_writes", "task_enabled", "mailbox_contacted", "uid514_processed")}, "uid514_receipt": {key: receipt.get(key) for key in ("code", "terminal", "recovery_event_id")}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-root", required=True, type=Path)
    parser.add_argument("--trust-root", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--compatibility-path", required=True, type=Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--require-terminal-uid514", action="store_true")
    args = parser.parse_args()
    if args.require_terminal_uid514 and not args.live:
        fail("terminal UID514 gate requires live preflight")
    env = load_env(args.env_file)
    manifest, planner = validate_local(args.bundle_root.resolve(strict=True), args.trust_root.resolve(strict=True), env, args.compatibility_path.resolve(strict=True))
    planner_smoke(env)
    result: dict[str, Any] = {"ok": True, "current_head_compatibility": True, "release": manifest["release_name"], "migration_head": 766, "planner": planner, "mailbox_contacted": False, "task_started": False, "uid514_processed": False, "production_contacted": False}
    if args.live:
        result["live"] = live_check(env, planner, args.require_terminal_uid514)
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PreflightError, OSError, KeyError) as exc:
        print(json.dumps({"ok": False, "current_head_compatibility": True, "error": str(exc), "mailbox_contacted": False, "production_contacted": False}, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(1)
