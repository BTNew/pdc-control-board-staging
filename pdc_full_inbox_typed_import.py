#!/usr/bin/env python3
"""Sanitized caller for the exact frozen 773-derived 777 staging contract.

The ordinary pdc-emails worker may import this module, but must invoke it only
with a pre-frozen, locally resolved row. It never reads the mailbox, changes
flags, invents database UUIDs, or selects the normal/global pilot path. The
server-owned RPC creates/reuses the intake and derives attachment IDs by hash.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Mapping

from pdc_historical_778_caller import canonical_request_bytes, canonical_request_digest

MANIFEST_SHA256 = "aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018"
MANIFEST_UIDVALIDITY = 1
MANIFEST_HIGH_WATER_UID = 685
MANIFEST_UID_COUNT = 669
EXCLUDED_PROVIDER_UID = "1:197"
EXCLUDED_STOCK = "13056899"
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
RELEASE_NAME = "pdc-monitor-staging-m502-2026.08.44"
RELEASE_SOURCE_SHA = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
RELEASE_MANIFEST_SHA256 = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
RPC_NAME = "submit_pdc_historical_reconciliation_778"
STAGING_HOST = "cdsmnqxtyyoeoznmbidd.supabase.co"


class Historical777Error(RuntimeError):
    """Sanitized bounded-run failure."""


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _required(row: Mapping[str, Any], key: str) -> Any:
    value = row.get(key)
    if value is None or value == "":
        raise Historical777Error(f"historical row missing {key}")
    return value


def _is_ambiguous_job_card(evidence: Any) -> bool:
    if not isinstance(evidence, Mapping):
        return True
    vehicle = evidence.get("email_vehicle") if isinstance(evidence.get("email_vehicle"), Mapping) else {}
    conflicts = evidence.get("conflicts")
    if conflicts is None:
        conflicts = vehicle.get("conflicts") or []
    stocks = evidence.get("stocks")
    if stocks is None:
        stocks = vehicle.get("stock_numbers") or []
    vins = evidence.get("vins")
    if vins is None:
        vins = vehicle.get("vins") or []
    job_cards = evidence.get("job_cards")
    if job_cards is None:
        job_cards = [vehicle.get("job_card_number")] if vehicle.get("job_card_number") else []
    return bool(conflicts) or len(stocks) > 1 or len(vins) > 1 or len(job_cards) != 1


def select_authorized_rows(rows: list[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    """Keep only the frozen manifest cohort; the server performs the full tuple gate."""
    return [
        row for row in rows
        if str(row.get("manifest_sha256", "")).lower() == MANIFEST_SHA256
        and str(row.get("provider_uid", "")) != EXCLUDED_PROVIDER_UID
        and str(row.get("stock_number", "")) != EXCLUDED_STOCK
    ]


def build_historical_request(row: Mapping[str, Any]) -> dict[str, Any]:
    """Build one UUID-free request; attachment children are keyed by SHA-256."""
    if str(_required(row, "manifest_sha256")).lower() != MANIFEST_SHA256:
        raise Historical777Error("historical row manifest mismatch")
    provider_uid = str(_required(row, "provider_uid"))
    stock = str(_required(row, "stock_number"))
    if provider_uid == EXCLUDED_PROVIDER_UID or stock == EXCLUDED_STOCK:
        raise Historical777Error("historical reference row is excluded")
    source = row.get("source_metadata") or {}
    received_at = str(_required(row, "source_received_at"))
    if source and str(source.get("received_at")) != received_at:
        raise Historical777Error("historical received time mismatch")

    attachments = list(_required(row, "attachments"))
    manifest: list[dict[str, Any]] = []
    attachment_by_hash: dict[str, list[int]] = {}
    for attachment in attachments:
        if not isinstance(attachment, Mapping):
            raise Historical777Error("historical attachment is not an object")
        digest = str(_required(attachment, "sha256")).lower()
        metadata = {
            "content_type": str(_required(attachment, "content_type")),
            "filename": str(_required(attachment, "filename")),
            "ordinal": int(attachment.get("ordinal", len(manifest) + 1)),
            "sha256": digest,
            "size": _required(attachment, "size"),
            "attachment_kind": attachment.get("attachment_kind") or "non_job_card_sibling",
        }
        manifest.append(metadata)
        attachment_by_hash.setdefault(digest, []).append(len(manifest) - 1)

    raw_children = row.get("job_card_children")
    if raw_children is None:
        raw_children = []
        for attachment in attachments:
            evidence = attachment.get("extraction") or attachment.get("evidence") or {}
            if attachment.get("attachment_kind") in ("job_card", "ambiguous_job_card"):
                raw_children.append({"attachment_hash": attachment["sha256"], "attachment_kind": attachment["attachment_kind"], "extraction_hash": attachment.get("extraction_hash", ""), "extraction": evidence})
    if not isinstance(raw_children, list):
        raise Historical777Error("historical job-card children are not an array")
    children: list[dict[str, Any]] = []
    for child in raw_children:
        if not isinstance(child, Mapping):
            raise Historical777Error("historical job-card child is not an object")
        digest = str(_required(child, "attachment_hash")).lower()
        matches = attachment_by_hash.get(digest, [])
        if len(matches) != 1:
            raise Historical777Error("historical child attachment occurrence is ambiguous")
        metadata = manifest[matches[0]]
        evidence = child.get("extraction") or child.get("evidence") or {}
        kind = str(child.get("attachment_kind") or metadata["attachment_kind"])
        if kind == "job_card" and _is_ambiguous_job_card(evidence):
            kind = "ambiguous_job_card"
        if kind not in ("job_card", "ambiguous_job_card"):
            raise Historical777Error("historical child kind is not a Job Card kind")
        metadata["attachment_kind"] = kind
        children.append({
            "attachment_hash": digest,
            "attachment_ordinal": metadata["ordinal"],
            "extraction_hash": str(_required(child, "extraction_hash")).lower(),
            "extraction": evidence if isinstance(evidence, Mapping) else {},
            "attachment_kind": kind,
        })

    attachment_names = [item["filename"] for item in manifest]
    if source and source.get("attachment_names") not in (None, attachment_names):
        raise Historical777Error("historical attachment name manifest mismatch")
    request = {
        "manifest_sha256": MANIFEST_SHA256,
        "manifest_uidvalidity": MANIFEST_UIDVALIDITY,
        "manifest_high_water_uid": MANIFEST_HIGH_WATER_UID,
        "manifest_uid_count": MANIFEST_UID_COUNT,
        "gateway_instance_id": GATEWAY,
        "release_name": RELEASE_NAME,
        "release_source_sha": RELEASE_SOURCE_SHA,
        "release_manifest_sha256": RELEASE_MANIFEST_SHA256,

        "provider_uid": provider_uid,
        "parent_source_hash": str(_required(row, "parent_source_hash")).lower(),
        "sender_email": str(_required(row, "sender_email")).lower(),
        "authentication": _required(row, "authentication"),
        "stock_number": stock,
        "subject": str(_required(row, "subject")),
        "action_type": str(_required(row, "action_type")),
        "summary": str(_required(row, "summary")),
        "evidence_hash": str(_required(row, "evidence_hash")).lower(),
        "observations": _required(row, "observations"),
        "source_metadata": source,
        "attachment_manifest": manifest,
        "job_card_children": children,
    }
    request["canonical_request_utf8"] = canonical_request_bytes(request).decode("utf-8")
    return request


def _staging_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value.rstrip("/"))
    if parsed.scheme != "https" or parsed.hostname != STAGING_HOST or parsed.port is not None \
            or parsed.username or parsed.password or parsed.query or parsed.fragment \
            or parsed.path not in ("", "/"):
        raise Historical777Error("staging URL binding mismatch")
    return f"https://{STAGING_HOST}"


def _jwt_claims(token: str) -> Mapping[str, Any]:
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        claims = json.loads(base64.urlsafe_b64decode(part.encode()).decode())
    except (IndexError, ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Historical777Error("current Monitor token is not a JWT") from exc
    if not isinstance(claims, dict) or claims.get("sub") != ACTOR_ID \
            or str(claims.get("email", "")).lower() != ACTOR_EMAIL \
            or claims.get("role") != "authenticated":
        raise Historical777Error("current Monitor token binding mismatch")
    return claims


def invoke_historical_rpc(request: Mapping[str, Any], *, url: str, anon_key: str, actor_token: str) -> dict[str, Any]:
    """Invoke only the dedicated authenticated staging RPC."""
    _jwt_claims(actor_token)
    body = json.dumps({"p_request": dict(request)}, separators=(",", ":"), allow_nan=False).encode("utf-8")
    http_request = urllib.request.Request(
        f"{_staging_url(url)}/rest/v1/rpc/{RPC_NAME}", data=body, method="POST",
        headers={"apikey": anon_key, "Authorization": f"Bearer {actor_token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(http_request, timeout=60) as response:
            result = json.loads(response.read(1_048_576).decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Historical777Error("historical 777 RPC transport failure") from exc
    if not isinstance(result, dict):
        raise Historical777Error("historical 777 RPC returned non-object")
    return result


def prepare_fresh_outbox(path: Path) -> sqlite3.Connection:
    """Create a new local outbox without touching the ordinary monitor store."""
    if path.exists():
        raise Historical777Error("fresh historical outbox path already exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute("create table historical_778_outbox (provider_uid text primary key, request_json text not null, request_sha256 text not null, state text not null, response_json text, created_at text not null)")
    conn.commit()
    return conn


def run_bounded_historical(rows: list[Mapping[str, Any]], outbox: sqlite3.Connection,
                           rpc_call: Callable[[Mapping[str, Any]], dict[str, Any]]) -> list[dict[str, Any]]:
    """Run only supplied frozen rows; never discovers additional mailbox messages."""
    results = []
    for row in select_authorized_rows(rows):
        request = build_historical_request(row)
        provider_uid = request["provider_uid"]
        request_json = json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        request_hash = canonical_request_digest(request)
        outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,created_at) values(?,?,?,?,datetime('now'))", (provider_uid, request_json, request_hash, "pending"))
        outbox.commit()
        response = rpc_call(request)
        state = "imported" if response.get("ok") is True else "retry"
        outbox.execute("update historical_778_outbox set state=?,response_json=? where provider_uid=?", (state, json.dumps(response, sort_keys=True), provider_uid))
        outbox.commit()
        results.append({"provider_uid": provider_uid, "state": state, "code": response.get("code")})
    return results


def _load_rows(path: Path) -> list[Mapping[str, Any]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Historical777Error("historical evidence export is unreadable") from exc
    rows = document.get("rows") if isinstance(document, dict) else document
    if not isinstance(rows, list):
        raise Historical777Error("historical evidence export rows are invalid")
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="bounded staging-only historical 778 caller")
    parser.add_argument("--rows-json", required=True, type=Path)
    parser.add_argument("--outbox", required=True, type=Path)
    parser.add_argument("--live-probe", action="store_true", help="call only the first selected row")
    parser.add_argument("--bounded-caller", action="store_true", help="explicitly call all supplied rows")
    args = parser.parse_args(argv)
    if args.live_probe and args.bounded_caller:
        raise Historical777Error("choose live probe or bounded caller, not both")
    if not args.live_probe and not args.bounded_caller:
        raise Historical777Error("no bounded caller mode selected")
    rows = select_authorized_rows(_load_rows(args.rows_json))
    if not rows:
        raise Historical777Error("no exact 773-derived rows supplied")
    if args.live_probe:
        rows = rows[:1]
    url = os.environ.get("PDC_STAGING_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or ""
    anon_key = os.environ.get("PDC_STAGING_SUPABASE_ANON_KEY") or os.environ.get("SUPABASE_ANON_KEY") or ""
    actor_token = os.environ.get("PDC_MONITOR_ACCESS_TOKEN") or ""
    gateway = os.environ.get("PDC_MONITOR_GATEWAY_INSTANCE_ID") or GATEWAY
    if gateway != GATEWAY or not url or not anon_key or not actor_token:
        raise Historical777Error("current Monitor staging bindings are incomplete")
    outbox = prepare_fresh_outbox(args.outbox)
    try:
        results = run_bounded_historical(rows, outbox, lambda request: invoke_historical_rpc(request, url=url, anon_key=anon_key, actor_token=actor_token))
    finally:
        outbox.close()
    print(json.dumps({"ok": all(item["state"] == "imported" for item in results), "rpc": RPC_NAME, "rows": results}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Historical777Error as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True), file=sys.stderr)
        raise SystemExit(1)
