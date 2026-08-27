#!/usr/bin/env python3
"""Guarded active-mode preflight successor for sealed Monitor release .44.

The sealed .44 bundle remains byte-for-byte immutable. This successor is an
external, protected control artifact: it reads the profile-owned runtime env,
reads the external planner/trust files from the protected trust root, verifies
both against the exact live 670/671 commissioning digests, and then performs
the same narrow staging attestation before the credential gate. It never opens
IMAP, starts a task, changes a mailbox, or writes Production.
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

EXPECTED_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_PROJECT_REF = "vjdtsswhroyguxyfjdkt"
EXPECTED_URL = f"https://{EXPECTED_PROJECT_REF}.supabase.co"
EXPECTED_RELEASE_VERSION = "2026.08.44"
EXPECTED_RELEASE_NAME = "pdc-monitor-staging-m502-2026.08.44"
EXPECTED_RELEASE_SERIES = "pdc-monitor-staging-m502"
EXPECTED_HEAD = 503
EXPECTED_GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
EXPECTED_ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EXPECTED_ACTOR_EMAIL = "sales@broometoyota.com.au"
EXPECTED_INTERFACE = "pmb-pdc-agentic-email-plan-v1"
EXPECTED_PLANNER_SHA256 = "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"
EXPECTED_TRUST_SHA256 = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
# 670 commissioned the predecessor; 671 is the only accepted active digest.
PREDECESSOR_PLANNER_SHA256 = "d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a"
PREDECESSOR_TRUST_SHA256 = "639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65"
EXPECTED_MANIFEST_KEYS = {
    "release_name": EXPECTED_RELEASE_NAME,
    "release_version": EXPECTED_RELEASE_VERSION,
    "supported_migration_head": EXPECTED_HEAD,
    "gateway_instance_id": EXPECTED_GATEWAY,
    "active_actor_id": EXPECTED_ACTOR_ID,
    "active_actor_email": EXPECTED_ACTOR_EMAIL,
    "agentic_active_planner_interface": EXPECTED_INTERFACE,
}
REQUIRED_ENV = (
    "SUPABASE_URL", "SUPABASE_ANON_KEY", "PDC_MONITOR_ACCESS_TOKEN",
    "PDC_SUPERVISED_MONITOR_JWT", "PDC_MONITOR_ACTOR_EMAIL",
    "PDC_MONITOR_GATEWAY_INSTANCE_ID", "PDC_MONITOR_RELEASE_NAME",
    "IMAP_BRIDGE_HOST", "IMAP_BRIDGE_USERNAME", "IMAP_BRIDGE_PASSWORD",
    "IMAP_BRIDGE_FOLDER", "IMAP_BRIDGE_MINIMUM_UID", "IMAP_BRIDGE_UIDVALIDITY",
    "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID", "IMAP_BRIDGE_MARK_READ",
    "PDC_OUTBOUND_EMAIL_ENABLED", "PDC_AGENTIC_EMAIL_ENABLED",
    "PDC_AGENTIC_PLANNER_COMMAND", "PDC_AGENTIC_PLANNER_SHA256",
    "PDC_AGENTIC_PLANNER_TRUST_RECEIPT", "PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256",
)
FORBIDDEN_ENV = (
    "SUPABASE_SERVICE_ROLE_KEY", "SERVICE_ROLE_KEY", "SUPABASE_DB_URL",
    "DATABASE_URL", "PDC_SUPERVISED_ACTOR_JWT", "PDC_ADMIN_JWT",
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


class CompatibilityError(RuntimeError):
    """A fail-closed compatibility or credential-gate error."""


def fail(message: str) -> None:
    raise CompatibilityError(message)


def sha256_file(path: Path) -> str:
    try:
        if path.is_symlink() or not path.is_file():
            fail(f"controlled file is missing or not regular: {path.name}")
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        fail(f"controlled file cannot be read: {path.name}")
        raise AssertionError from exc


def assert_no_reparse(path: Path, label: str) -> None:
    probe = path
    while probe != probe.parent:
        try:
            if probe.exists() and (probe.is_symlink() or bool(getattr(probe.stat(), "st_file_attributes", 0) & 0x400)):
                fail(f"{label} contains a reparse point")
        except OSError:
            fail(f"{label} cannot be inspected")
        probe = probe.parent


def child_path(root: Path, name: str, label: str) -> Path:
    if not root.is_absolute() or not name or Path(name).name != name or name in {".", ".."}:
        fail(f"{label} path is not an exact relative child")
    assert_no_reparse(root, label)
    path = root / name
    try:
        resolved_root = root.resolve(strict=True)
        resolved = path.resolve(strict=True)
    except OSError:
        fail(f"{label} path is missing")
    if resolved.parent != resolved_root or resolved != path.absolute():
        fail(f"{label} path escaped its protected root")
    assert_no_reparse(path, label)
    return path


def validate_acl_snapshot(sddl: str, *, require_local_service_read: bool = True) -> None:
    """Validate the narrow ACL shape emitted by the staging installer.

    This parser deliberately accepts only protected DACLs with SYSTEM and
    Administrators full control, plus LOCAL SERVICE read/execute. It is also
    used by unit tests with synthetic SDDL, so ACL policy is testable without
    changing Windows ACLs.
    """
    if not isinstance(sddl, str) or "D:P" not in sddl:
        fail("protected compatibility ACL is required")
    aces = re.findall(r"\(A;[^;]*;([^;]*);;;([A-Za-z0-9-]+)\)", sddl)
    if not aces or any(sid not in {"SY", "BA", "LS"} for _rights, sid in aces):
        fail("compatibility ACL grants an unapproved principal")
    principals = {sid for _rights, sid in aces}
    if not {"SY", "BA"}.issubset(principals) or (require_local_service_read and "LS" not in principals):
        fail("compatibility ACL is missing its required principals")
    for rights, sid in aces:
        if sid in {"SY", "BA"} and rights not in {"FA", "0x1f01ff"}:
            fail("SYSTEM/Administrators compatibility ACL is not full control")
        if sid == "LS" and rights not in {"0x1200a9", "RX", "0x1200a9"}:
            fail("LOCAL SERVICE compatibility ACL is not read/execute only")


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
                          parse_constant=lambda value: fail(f"non-finite JSON value in {label}: {value}"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON in {label}: {exc}")
        raise AssertionError from exc


def load_env(path: Path) -> dict[str, str]:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        fail("protected runtime environment file is missing")
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.strip() and not raw.lstrip().startswith("#") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def jwt_payload(token: str) -> Mapping[str, Any]:
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise ValueError("JWT segment count")
        payload = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
        result = json.loads(base64.urlsafe_b64decode(payload).decode("utf-8"))
        if not isinstance(result, dict):
            raise ValueError("JWT payload object required")
        return result
    except (ValueError, TypeError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        fail("scoped token is not a parseable JWT")
        raise AssertionError from exc


def exact_url(value: str) -> bool:
    try:
        parsed = urllib.parse.urlsplit(value)
    except ValueError:
        return False
    return (parsed.scheme == "https" and parsed.hostname == f"{EXPECTED_PROJECT_REF}.supabase.co"
            and parsed.port is None and not (parsed.username or parsed.password or parsed.query or parsed.fragment)
            and parsed.path in {"", "/"})


def validate_external_paths(release_root: Path, trust_root: Path, compatibility_path: Path) -> dict[str, Path]:
    if not release_root.is_absolute() or not trust_root.is_absolute() or not compatibility_path.is_absolute():
        fail("compatibility paths must be absolute")
    if release_root.resolve(strict=True) == trust_root.resolve(strict=True):
        fail("trust root must be outside the sealed release")
    if trust_root.resolve(strict=True) in release_root.resolve(strict=True).parents:
        fail("trust root must not be inside the sealed release")
    if release_root.resolve(strict=True) in trust_root.resolve(strict=True).parents:
        fail("sealed release must not be inside the trust root")
    assert_no_reparse(release_root, "sealed release")
    assert_no_reparse(trust_root, "external trust root")
    assert_no_reparse(compatibility_path, "compatibility successor")
    planner = child_path(trust_root, "pdc_active_semantic_planner.py", "external planner")
    receipt = child_path(trust_root, "pdc-active-semantic-planner-trust-receipt.json", "trust receipt")
    if compatibility_path.resolve(strict=True) == release_root.resolve(strict=True) / "preflight.py":
        fail("compatibility successor cannot replace sealed preflight")
    return {"planner": planner, "receipt": receipt}


def validate_release(release_root: Path, trust_root: Path) -> tuple[dict[str, Any], dict[str, Path]]:
    paths = validate_external_paths(release_root, trust_root, Path(__file__).resolve())
    manifest_path = child_path(release_root, "release-manifest.json", "release manifest")
    manifest_hash_path = child_path(trust_root, "MANIFEST_SHA256", "manifest trust anchor")
    expected_manifest_hash = manifest_hash_path.read_text(encoding="ascii").strip().lower()
    if not SHA256_RE.fullmatch(expected_manifest_hash) or sha256_file(manifest_path) != expected_manifest_hash:
        fail("sealed release manifest hash mismatch")
    manifest = strict_json(manifest_path.read_bytes(), "release manifest")
    if not isinstance(manifest, dict) or any(manifest.get(key) != value for key, value in EXPECTED_MANIFEST_KEYS.items()):
        fail("sealed .44 release binding mismatch")
    if manifest.get("active_actor_email_prefix") != "sales@" or manifest.get("agentic_active_planner_trust_receipt_sha256") is not None:
        fail("sealed .44 metadata binding mismatch")
    return manifest, paths


def validate_external_planner(env: Mapping[str, str], paths: Mapping[str, Path], manifest: Mapping[str, Any]) -> dict[str, str]:
    planner = paths["planner"]
    receipt = paths["receipt"]
    planner_digest = sha256_file(planner)
    receipt_digest = sha256_file(receipt)
    if planner_digest != EXPECTED_PLANNER_SHA256 or receipt_digest != EXPECTED_TRUST_SHA256:
        fail("external planner/trust digest does not match commissioned 671 artifact")
    command = env.get("PDC_AGENTIC_PLANNER_COMMAND", "").strip()
    argv = strict_json(command.encode("utf-8"), "planner command")
    if (not isinstance(argv, list) or not argv or
            any(not isinstance(value, str) or not value for value in argv)):
        fail("planner command must be a nonempty JSON argv array")
    if not Path(argv[0]).is_absolute():
        fail("planner executable must be absolute")
    script_args = [Path(value) for value in argv[1:] if value.lower().endswith(".py")]
    if len(script_args) != 1 or script_args[0].resolve(strict=True) != planner.resolve(strict=True):
        fail("planner command is not bound to the protected external planner")
    if env.get("PDC_AGENTIC_PLANNER_SHA256", "").strip().lower() != planner_digest:
        fail("planner environment digest mismatch")
    receipt_env = env.get("PDC_AGENTIC_PLANNER_TRUST_RECEIPT", "").strip()
    try:
        receipt_env_path = Path(receipt_env).resolve(strict=True)
    except OSError:
        fail("planner trust receipt path is missing")
    if receipt_env_path != receipt.resolve(strict=True):
        fail("planner trust receipt path mismatch")
    if env.get("PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256", "").strip().lower() != receipt_digest:
        fail("planner trust receipt environment digest mismatch")
    trust = strict_json(receipt.read_bytes(), "active planner trust receipt")
    if (not isinstance(trust, dict) or set(trust) != {"approved_at", "approved_by", "contract", "planner_interface", "planner_sha256", "release_series"}
            or trust.get("contract") != "pdc-active-semantic-planner-trust-v1"
            or trust.get("planner_interface") != EXPECTED_INTERFACE
            or trust.get("planner_sha256") != planner_digest
            or trust.get("release_series") != manifest.get("release_series")):
        fail("active planner trust receipt content is not release-bound")
    return {"planner_sha256": planner_digest, "trust_receipt_sha256": receipt_digest}


def planner_smoke(env: Mapping[str, str]) -> None:
    argv = strict_json(env["PDC_AGENTIC_PLANNER_COMMAND"].encode("utf-8"), "planner command")
    safe_env = {key: os.environ[key] for key in ("SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "TEMP", "TMP") if os.environ.get(key)}
    safe_env["PYTHONDONTWRITEBYTECODE"] = "1"
    if Path(argv[0]).name.casefold() in {"python.exe", "python"} and "-B" not in argv[1:]:
        argv = [argv[0], "-B", *argv[1:]]
    smoke = {
        "contract_version": "pmb-pdc-agentic-planner-request-v1",
        "evidence": {"evidence_hash": "1" * 64, "instruction_candidates": [{"instruction_id": "ins-smoke", "evidence_ref": "body", "text": "Stock 1001: mark parts complete"}]},
        "vehicle_contexts": [{"vehicle_id": "11111111-1111-1111-1111-111111111111", "identity": {"stock_number": "1001", "vin": "", "job_card_number": "", "customer": ""}}],
    }
    try:
        completed = subprocess.run(argv, input=json.dumps(smoke, separators=(",", ":")).encode("utf-8"),
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10, check=False,
                                   shell=False, env=safe_env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"active planner semantic smoke failed: {type(exc).__name__}")
    if completed.returncode != 0 or len(completed.stdout) > 1_048_576:
        fail("active planner semantic smoke failed")
    plan = strict_json(completed.stdout, "active planner semantic smoke")
    if (not isinstance(plan, dict) or plan.get("contract_version") != "pmb-pdc-agentic-email-plan-v1"
            or not isinstance(plan.get("vehicles"), list) or len(plan["vehicles"]) != 1
            or plan["vehicles"][0].get("vehicle_id") != "11111111-1111-1111-1111-111111111111"
            or not plan["vehicles"][0].get("actions")
            or not isinstance(plan.get("instructions"), list)
            or plan["instructions"][0].get("disposition") != "ACTIONABLE"):
        fail("active planner semantic smoke did not produce the strict actionable plan")


def rpc(env: Mapping[str, str], name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
    url = env["SUPABASE_URL"].rstrip("/")
    request = urllib.request.Request(
        f"{url}/rest/v1/rpc/{name}",
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={"apikey": env["SUPABASE_ANON_KEY"], "Authorization": f"Bearer {env['PDC_MONITOR_ACCESS_TOKEN']}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            value = strict_json(response.read(1_048_577), f"RPC {name} response")
            if not isinstance(value, dict):
                fail(f"scoped preflight RPC {name} returned a non-object")
            return value
    except urllib.error.HTTPError as exc:
        exc.read(4096)
        fail(f"CREDENTIAL_GATE_REJECTED_HTTP_{exc.code}")
    except urllib.error.URLError:
        fail(f"scoped preflight RPC {name} network failure")


def validate_env(env: Mapping[str, str]) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    for name in FORBIDDEN_ENV:
        if env.get(name, "").strip():
            fail(f"broad or actor credential is forbidden: {name}")
    missing = [name for name in REQUIRED_ENV if not env.get(name, "").strip()]
    if missing:
        fail("CREDENTIAL_GATE_MISSING_PROTECTED_VALUES:" + ",".join(missing))
    if not exact_url(env["SUPABASE_URL"].rstrip("/")) or PRODUCTION_PROJECT_REF in env["SUPABASE_URL"]:
        fail("exact staging Supabase URL required")
    exacts = {
        "PDC_MONITOR_ACTOR_EMAIL": EXPECTED_ACTOR_EMAIL,
        "PDC_MONITOR_GATEWAY_INSTANCE_ID": EXPECTED_GATEWAY,
        "PDC_MONITOR_RELEASE_NAME": EXPECTED_RELEASE_NAME,
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
        fail("CREDENTIAL_GATE_ENVIRONMENT_BINDING_MISMATCH")
    token_claims = jwt_payload(env["PDC_MONITOR_ACCESS_TOKEN"])
    supervised_claims = jwt_payload(env["PDC_SUPERVISED_MONITOR_JWT"])
    if token_claims.get("role") != "pdc_email_monitor" or supervised_claims.get("role") in {"service_role", "supabase_admin"}:
        fail("CREDENTIAL_GATE_NARROW_IDENTITY_REQUIRED")
    if token_claims.get("sub") != EXPECTED_ACTOR_ID or supervised_claims.get("sub") != EXPECTED_ACTOR_ID:
        fail("CREDENTIAL_GATE_ACTOR_SUBJECT_MISMATCH")
    if str(token_claims.get("email", "")).lower() != EXPECTED_ACTOR_EMAIL or str(supervised_claims.get("email", "")).lower() != EXPECTED_ACTOR_EMAIL:
        fail("CREDENTIAL_GATE_ACTOR_EMAIL_MISMATCH")
    return token_claims, supervised_claims


def validate_live(env: Mapping[str, str], manifest: Mapping[str, Any], planner: Mapping[str, str], require_terminal_uid514: bool) -> dict[str, Any]:
    token_claims, _supervised_claims = validate_env(env)
    attestation = rpc(env, "verify_pdc_monitor_runtime_binding_503", {
        "p_mode": "active", "p_gateway_instance_id": EXPECTED_GATEWAY,
        "p_release_name": EXPECTED_RELEASE_NAME, "p_source_sha": manifest["source_sha"],
        "p_manifest_sha256": env["PDC_EXPECTED_MANIFEST_SHA256"],
        "p_semantic_planner_sha256": planner["planner_sha256"],
        "p_semantic_planner_trust_receipt_sha256": planner["trust_receipt_sha256"],
    })
    if any((attestation.get("ok") is not True, attestation.get("migration_head") != EXPECTED_HEAD,
            attestation.get("mode") != "active", attestation.get("actor_id") != token_claims.get("sub"),
            attestation.get("gateway_instance_id") != EXPECTED_GATEWAY, attestation.get("release_name") != EXPECTED_RELEASE_NAME,
            attestation.get("manifest_sha256") != env["PDC_EXPECTED_MANIFEST_SHA256"],
            attestation.get("source_sha") != manifest.get("source_sha"),
            attestation.get("semantic_planner_sha256") != planner["planner_sha256"],
            attestation.get("semantic_planner_trust_receipt_sha256") != planner["trust_receipt_sha256"],
            attestation.get("planner_commissioned") is not True, attestation.get("writer_active") is not True,
            attestation.get("operational") is not True, attestation.get("activation_ready") is not True,
            attestation.get("production_writes") is not False)):
        fail("live 670/671 planner or actor attestation mismatch")
    receipt = rpc(env, "read_pdc_uid514_transaction_receipt_257", {"p_recovery_event_id": 25751401})
    if any(key in receipt for key in {"attempt_metadata", "original_extracted_values", "actor_email"}):
        fail("UID514 readback exposed protected evidence")
    if (receipt.get("recovery_event_id") != 25751401 or receipt.get("mailbox") != "pmbcontroller@gmail.com"
            or receipt.get("folder") != "Inbox" or receipt.get("uidvalidity") != 1 or receipt.get("uid") != 514):
        fail("UID514 recovery readback scope mismatch")
    if require_terminal_uid514 and (receipt.get("code") != "uid514_receipt_terminal" or receipt.get("terminal") is not True):
        fail("terminal UID514 receipt is required before monitoring")
    return {"attestation": attestation, "uid514_receipt_status": {key: receipt.get(key) for key in ("ok", "code", "terminal", "recovery_event_id")}}


def validate(args: argparse.Namespace) -> dict[str, Any]:
    manifest, paths = validate_release(args.release_root, args.trust_root)
    env = load_env(args.env_file)
    env = dict(env)
    env["PDC_EXPECTED_MANIFEST_SHA256"] = sha256_file(child_path(args.release_root, "release-manifest.json", "release manifest"))
    planner = validate_external_planner(env, paths, manifest)
    planner_smoke(env)
    result: dict[str, Any] = {
        "ok": True, "compatibility_successor": True, "active_mode": True,
        "release_name": EXPECTED_RELEASE_NAME, "release_version": EXPECTED_RELEASE_VERSION,
        "manifest_sha256": env["PDC_EXPECTED_MANIFEST_SHA256"], "migration_head": EXPECTED_HEAD,
        "project_ref": EXPECTED_PROJECT_REF, "planner": planner,
        "commissioning_source": {"migration_670_predecessor_planner_sha256": PREDECESSOR_PLANNER_SHA256,
                                  "migration_670_predecessor_trust_receipt_sha256": PREDECESSOR_TRUST_SHA256,
                                  "migration_671_planner_sha256": EXPECTED_PLANNER_SHA256,
                                  "migration_671_trust_receipt_sha256": EXPECTED_TRUST_SHA256},
        "credential_gate_reached": False, "mailbox_contacted": False,
        "production_contacted": False, "task_started": False,
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
    parser.add_argument("--compatibility-path", required=False, type=Path, default=Path(__file__).resolve())
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--require-terminal-uid514", action="store_true")
    args = parser.parse_args()
    if args.require_terminal_uid514 and not args.live:
        fail("terminal UID514 gate requires live preflight")
    # The explicit path is checked so the protected control runner cannot point
    # at the sealed preflight or at an arbitrary user-writable location.
    if args.compatibility_path.resolve(strict=True) != Path(__file__).resolve(strict=True):
        fail("compatibility successor path binding mismatch")
    print(json.dumps(validate(args), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CompatibilityError as exc:
        print(json.dumps({"ok": False, "compatibility_successor": True, "error": str(exc),
                          "mailbox_contacted": False, "production_contacted": False,
                          "task_started": False}, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(1)
