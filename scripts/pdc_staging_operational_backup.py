"""Create and verify an encrypted, staging-only operational recovery backup.

The script uses the Website Development Lead's isolated service credential and
backup key from its protected profile environment. Plaintext rows never touch
disk. Production and unknown project refs fail closed.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path
import secrets
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from pdc_staging_management_migration import _token

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PROFILE_ENV = Path(
    r"C:\Users\nwmgr\AppData\Local\hermes\profiles\website-development-lead\.env"
)
TABLES = (
    "vehicles",
    "workshop_bookings",
    "workshop_booking_assignments",
    "workshop_transition_authorizations",
    "workshop_booking_history",
    "workshop_booking_move_receipts",
    "workshop_parts_overrides",
    "vehicle_work_items",
    "vehicle_parts_updates",
    "vehicle_sublet_providers",
    "vehicle_workshop_line_adjustments",
    "pdc_sublet_bookings",
    "navision_board_activations",
)
PAGE_SIZE = 1000
AAD = b"pdc-staging-operational-recovery-v1:cdsmnqxtyyoeoznmbidd"


def _load_profile_env() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in PROFILE_ENV.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    required = (
        "PDC_STAGING_SUPABASE_URL",
        "PDC_STAGING_SERVICE_ROLE_KEY",
        "PDC_BACKUP_ENCRYPTION_KEY",
        "PDC_STAGING_PROJECT_REF",
    )
    if any(not values.get(key) for key in required):
        raise RuntimeError("PDC_STAGING_BACKUP_PROFILE_INPUT_MISSING")
    ref = values["PDC_STAGING_PROJECT_REF"]
    url = values["PDC_STAGING_SUPABASE_URL"]
    if ref == PRODUCTION_REF or PRODUCTION_REF in url:
        raise RuntimeError("PDC_PRODUCTION_TARGET_FORBIDDEN")
    if ref != STAGING_REF or STAGING_REF not in url:
        raise RuntimeError("PDC_UNKNOWN_TARGET_FORBIDDEN")
    return values


def _management_rows(table: str) -> list[dict]:
    if table not in TABLES:
        raise RuntimeError("PDC_BACKUP_TABLE_NOT_ALLOWLISTED")
    rows: list[dict] = []
    start = 0
    while True:
        sql = f'select * from public."{table}" order by 1 offset {start} limit {PAGE_SIZE};'
        request = urllib.request.Request(
            f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only",
            data=json.dumps({"query": "SET TRANSACTION READ ONLY;\n" + sql}).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": "Bearer " + _token(),
                "Content-Type": "application/json",
                "User-Agent": "pdc-staging-operational-recovery/1.0",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                page = json.load(response)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            raise RuntimeError(f"PDC_BACKUP_MANAGEMENT_READ_FAILED:{table}:HTTP{exc.code}:{body[:300]}") from None
        if not isinstance(page, list):
            raise RuntimeError(f"PDC_BACKUP_MANAGEMENT_READ_INVALID:{table}")
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            return rows
        start += PAGE_SIZE


def _request_rows(url: str, service_key: str, table: str) -> tuple[list[dict], str]:
    rows: list[dict] = []
    start = 0
    while True:
        endpoint = f"{url.rstrip('/')}/rest/v1/{urllib.parse.quote(table)}?select=*"
        request = urllib.request.Request(
            endpoint,
            headers={
                "apikey": service_key,
                "Authorization": "Bearer " + service_key,
                "Accept": "application/json",
                "Range": f"{start}-{start + PAGE_SIZE - 1}",
                "Range-Unit": "items",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                page = json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code == 403:
                return _management_rows(table), "management_read_only_fallback"
            body = exc.read().decode("utf-8", "replace")
            raise RuntimeError(f"PDC_BACKUP_READ_FAILED:{table}:HTTP{exc.code}:{body[:300]}") from None
        if not isinstance(page, list):
            raise RuntimeError(f"PDC_BACKUP_READ_INVALID:{table}")
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            return rows, "profile_service_role_rest"
        start += PAGE_SIZE


def _canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _key(secret_value: str) -> bytes:
    return hashlib.sha256(
        b"pdc-staging-operational-recovery-v1\x00" + secret_value.encode("utf-8")
    ).digest()


def backup(output_dir: Path) -> dict:
    env = _load_profile_env()
    payload_tables: dict[str, list[dict]] = {}
    table_counts: dict[str, int] = {}
    table_sha256: dict[str, str] = {}
    read_methods: dict[str, str] = {}
    for table in TABLES:
        rows, read_method = _request_rows(
            env["PDC_STAGING_SUPABASE_URL"],
            env["PDC_STAGING_SERVICE_ROLE_KEY"],
            table,
        )
        read_methods[table] = read_method
        rows.sort(key=lambda row: _canonical(row))
        payload_tables[table] = rows
        table_counts[table] = len(rows)
        table_sha256[table] = hashlib.sha256(_canonical(rows)).hexdigest()

    created_at = dt.datetime.now(dt.timezone.utc).isoformat()
    payload = {
        "schema": "pdc-staging-operational-recovery-v1",
        "project_ref": STAGING_REF,
        "created_at_utc": created_at,
        "tables": payload_tables,
    }
    raw = _canonical(payload)
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    nonce = secrets.token_bytes(12)
    encrypted = nonce + AESGCM(_key(env["PDC_BACKUP_ENCRYPTION_KEY"])).encrypt(
        nonce, compressed, AAD
    )
    encrypted_sha256 = hashlib.sha256(encrypted).hexdigest()
    gzip_sha256 = hashlib.sha256(compressed).hexdigest()
    raw_sha256 = hashlib.sha256(raw).hexdigest()
    manifest_payload = {
        "schema": "pdc-staging-operational-recovery-manifest-v1",
        "project_ref": STAGING_REF,
        "created_at_utc": created_at,
        "encryption": "AES-256-GCM",
        "aad": AAD.decode("ascii"),
        "raw_bytes": len(raw),
        "gzip_bytes": len(compressed),
        "encrypted_bytes": len(encrypted),
        "raw_sha256": raw_sha256,
        "backup_gzip_sha256": gzip_sha256,
        "encrypted_backup_sha256": encrypted_sha256,
        "table_counts": table_counts,
        "table_sha256": table_sha256,
        "read_methods": read_methods,
    }
    manifest_sha256 = hashlib.sha256(_canonical(manifest_payload)).hexdigest()
    manifest = dict(manifest_payload, backup_manifest_sha256=manifest_sha256)

    output_dir.mkdir(parents=True, exist_ok=True)
    encrypted_path = output_dir / f"pdc-staging-operational-{manifest_sha256}.json.gz.aesgcm"
    manifest_path = output_dir / f"pdc-staging-operational-{manifest_sha256}.manifest.json"
    encrypted_path.write_bytes(encrypted)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    verify(encrypted_path, manifest_path)
    return {
        "status": "BACKUP_VERIFIED",
        "project_ref": STAGING_REF,
        "backup_manifest_sha256": manifest_sha256,
        "backup_gzip_sha256": gzip_sha256,
        "encrypted_backup_sha256": encrypted_sha256,
        "raw_bytes": len(raw),
        "table_counts": table_counts,
        "encrypted_path": str(encrypted_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
    }


def verify(encrypted_path: Path, manifest_path: Path) -> dict:
    env = _load_profile_env()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_manifest = dict(manifest)
    recorded_manifest_sha = expected_manifest.pop("backup_manifest_sha256")
    if hashlib.sha256(_canonical(expected_manifest)).hexdigest() != recorded_manifest_sha:
        raise RuntimeError("PDC_BACKUP_MANIFEST_HASH_MISMATCH")
    encrypted = encrypted_path.read_bytes()
    if hashlib.sha256(encrypted).hexdigest() != manifest["encrypted_backup_sha256"]:
        raise RuntimeError("PDC_BACKUP_ENCRYPTED_HASH_MISMATCH")
    nonce, ciphertext = encrypted[:12], encrypted[12:]
    compressed = AESGCM(_key(env["PDC_BACKUP_ENCRYPTION_KEY"])).decrypt(
        nonce, ciphertext, AAD
    )
    if hashlib.sha256(compressed).hexdigest() != manifest["backup_gzip_sha256"]:
        raise RuntimeError("PDC_BACKUP_GZIP_HASH_MISMATCH")
    raw = gzip.decompress(compressed)
    if len(raw) != manifest["raw_bytes"] or hashlib.sha256(raw).hexdigest() != manifest["raw_sha256"]:
        raise RuntimeError("PDC_BACKUP_RAW_HASH_MISMATCH")
    payload = json.loads(raw)
    counts = {table: len(payload["tables"][table]) for table in TABLES}
    if counts != manifest["table_counts"]:
        raise RuntimeError("PDC_BACKUP_TABLE_COUNT_MISMATCH")
    for table in TABLES:
        if hashlib.sha256(_canonical(payload["tables"][table])).hexdigest() != manifest["table_sha256"][table]:
            raise RuntimeError(f"PDC_BACKUP_TABLE_HASH_MISMATCH:{table}")
    return {"status": "BACKUP_VERIFIED", "backup_manifest_sha256": recorded_manifest_sha, "table_counts": counts}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("create")
    create.add_argument("--output-dir", type=Path, required=True)
    check = sub.add_parser("verify")
    check.add_argument("--encrypted", type=Path, required=True)
    check.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    result = backup(args.output_dir) if args.command == "create" else verify(args.encrypted, args.manifest)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
