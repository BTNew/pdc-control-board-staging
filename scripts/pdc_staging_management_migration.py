"""Apply one reviewed append-only PDC migration to exact STAGING.

Reads the existing Supabase CLI access token from Windows Credential Manager,
never accepts secrets on argv, rejects Production exactly, binds exact bytes,
and writes a secret-free deployment receipt.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import urllib.error
import urllib.request

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
CREDENTIAL_TARGET = "Supabase CLI:supabase"
ALLOWED_ROOT = (Path(__file__).resolve().parents[1] / "supabase" / "staging_only").resolve()
RECEIPT_ROOT = (Path(__file__).resolve().parents[1] / "_staging_deployment_receipts").resolve()


class FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", wintypes.DWORD), ("dwHighDateTime", wintypes.DWORD)]


class CREDENTIALW(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD), ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR), ("Comment", wintypes.LPWSTR),
        ("LastWritten", FILETIME), ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD), ("AttributeCount", wintypes.DWORD),
        ("Attributes", ctypes.c_void_p), ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


PCREDENTIALW = ctypes.POINTER(CREDENTIALW)
advapi32 = ctypes.WinDLL("Advapi32.dll")
advapi32.CredReadW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(PCREDENTIALW)
]
advapi32.CredReadW.restype = wintypes.BOOL
advapi32.CredFree.argtypes = [ctypes.c_void_p]


def _token() -> str:
    ptr = PCREDENTIALW()
    if not advapi32.CredReadW(CREDENTIAL_TARGET, 1, 0, ctypes.byref(ptr)):
        raise RuntimeError("Supabase CLI credential unavailable")
    try:
        cred = ptr.contents
        raw = ctypes.string_at(cred.CredentialBlob, cred.CredentialBlobSize)
        candidates: list[str] = []
        for encoding in ("utf-8", "utf-16-le"):
            try:
                value = raw.decode(encoding).rstrip("\x00")
                if value and value.isascii():
                    candidates.append(value)
            except UnicodeDecodeError:
                pass
        token = next((v for v in candidates if v.startswith(("sbp_", "sbo_"))), None)
        if not token:
            raise RuntimeError("Supabase CLI credential format unavailable")
        return token
    finally:
        advapi32.CredFree(ptr)


def _post(endpoint: str, query: str) -> object:
    request = urllib.request.Request(
        endpoint,
        data=json.dumps({"query": query}).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": "Bearer " + _token(),
            "Content-Type": "application/json",
            "User-Agent": "pdc-staging-reviewed-migration/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"Supabase Management API HTTP {exc.code}: {body[:1000]}") from None


def _validate_target(target_ref: str) -> None:
    if target_ref == PRODUCTION_REF:
        raise RuntimeError("PDC_PRODUCTION_TARGET_FORBIDDEN")
    if target_ref != STAGING_REF:
        raise RuntimeError("PDC_UNKNOWN_TARGET_FORBIDDEN")


def _validate_migration(path: Path, expected_sha256: str) -> tuple[bytes, str, str]:
    resolved = path.resolve()
    if resolved.parent != ALLOWED_ROOT or not re.fullmatch(
        r"[0-9]{14}_[a-z0-9_]+\.sql", resolved.name
    ):
        raise RuntimeError("migration must be one timestamped staging_only SQL file")
    raw = resolved.read_bytes()
    actual = hashlib.sha256(raw).hexdigest()
    if actual != expected_sha256.lower():
        raise RuntimeError("PDC_MIGRATION_SHA256_MISMATCH")
    text = raw.decode("utf-8")
    if STAGING_REF not in text or PRODUCTION_REF in text:
        # Production must be represented by the sentinel check, never by its ref.
        raise RuntimeError("PDC_MIGRATION_EXACT_TARGET_CONTRACT_MISSING")
    match = re.search(
        r"values\('([0-9]{14})','([a-z0-9_]+)'", text, flags=re.IGNORECASE
    )
    if not match:
        raise RuntimeError("PDC_MIGRATION_LEDGER_INSERT_MISSING")
    return raw, match.group(1), match.group(2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-ref", required=True)
    parser.add_argument("--migration", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--read-only", action="store_true")
    args = parser.parse_args()

    _validate_target(args.target_ref)
    raw, version, name = _validate_migration(args.migration, args.expected_sha256)
    endpoint = (
        f"https://api.supabase.com/v1/projects/{args.target_ref}/database/query"
        + ("/read-only" if args.read_only else "")
    )
    query = raw.decode("utf-8")
    if args.read_only:
        query = "SET TRANSACTION READ ONLY;\n" + query
    result = _post(endpoint, query)
    observed = _post(
        f"https://api.supabase.com/v1/projects/{args.target_ref}/database/query/read-only",
        "SET TRANSACTION READ ONLY;\n"
        "select version,name from supabase_migrations.schema_migrations "
        f"where version='{version}' and name='{name}';",
    )
    if not isinstance(observed, list) or len(observed) != 1:
        raise RuntimeError("PDC_MIGRATION_LEDGER_READBACK_FAILED")

    receipt = {
        "schema": "pdc-staging-management-migration-receipt-v1",
        "target_ref": args.target_ref,
        "production_ref_rejected": PRODUCTION_REF,
        "migration_file": args.migration.resolve().name,
        "migration_sha256": hashlib.sha256(raw).hexdigest(),
        "migration_version": version,
        "migration_name": name,
        "applied": not args.read_only,
        "management_response": result,
        "ledger_readback": observed,
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    output = args.receipt
    if output is None:
        RECEIPT_ROOT.mkdir(parents=True, exist_ok=True)
        output = RECEIPT_ROOT / f"{version}_{name}.json"
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "status": "APPLIED" if not args.read_only else "READ_ONLY",
        "target_ref": args.target_ref,
        "migration_version": version,
        "migration_name": name,
        "migration_sha256": receipt["migration_sha256"],
        "ledger_rows": len(observed),
        "receipt": str(output.resolve()),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
