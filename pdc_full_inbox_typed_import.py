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
AUTHORIZED_PROVIDER_UIDS = frozenset({
    "1:21", "1:22", "1:23", "1:26", "1:40", "1:57", "1:85", "1:93",
    "1:95", "1:96", "1:133", "1:134", "1:137", "1:168", "1:172",
})
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
RELEASE_NAME = "pdc-monitor-staging-m502-2026.08.44"
RELEASE_SOURCE_SHA = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
RELEASE_MANIFEST_SHA256 = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
RPC_NAME = "submit_pdc_historical_reconciliation_778"
STAGING_HOST = "cdsmnqxtyyoeoznmbidd.supabase.co"
PROPOSAL_REVIEW_CODES = frozenset({
    "historical_proposal_tuple_conflict",
    "historical_proposal_terminal_conflict",
    "historical_proposal_payload_conflict",
    "historical_proposal_observation_review_required",
})


class Historical777Error(RuntimeError):
    """Sanitized bounded-run failure."""


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _required(row: Mapping[str, Any], key: str) -> Any:
    value = row.get(key)
    if value is None or value == "":
        raise Historical777Error(f"historical row missing {key}")
    return value


def _validate_frozen_manifest_row(row: Mapping[str, Any]) -> None:
    """Require explicit typed frozen manifest and source UID evidence."""
    expected_manifest_fields = {
        "manifest_uidvalidity": MANIFEST_UIDVALIDITY,
        "manifest_high_water_uid": MANIFEST_HIGH_WATER_UID,
        "manifest_uid_count": MANIFEST_UID_COUNT,
    }
    for key, expected in expected_manifest_fields.items():
        value = row.get(key)
        if type(value) is not int or value != expected:
            raise Historical777Error(f"historical {key} mismatch")
    provider_uid = row.get("provider_uid")
    if type(provider_uid) is not str or provider_uid not in AUTHORIZED_PROVIDER_UIDS:
        raise Historical777Error("historical provider UID mismatch")
    source_value = row.get("source_metadata")
    if not isinstance(source_value, Mapping):
        raise Historical777Error("historical source metadata type mismatch")
    source_uidvalidity = source_value.get("uidvalidity")
    if type(source_uidvalidity) is not int or source_uidvalidity != MANIFEST_UIDVALIDITY:
        raise Historical777Error("historical source UIDVALIDITY mismatch")
    source_uid = source_value.get("uid")
    expected_source_uid = int(provider_uid.split(":", 1)[1])
    if type(source_uid) is not int or source_uid != expected_source_uid:
        raise Historical777Error("historical source UID mismatch")
    if provider_uid == EXCLUDED_PROVIDER_UID or str(row.get("stock_number", "")) == EXCLUDED_STOCK:
        raise Historical777Error("historical reference row is excluded")


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
    """Require exactly the immutable frozen cohort; never filter extras away."""
    if not isinstance(rows, list) or len(rows) != len(AUTHORIZED_PROVIDER_UIDS):
        raise Historical777Error("historical authorized cohort count mismatch")
    if any(not isinstance(row, Mapping) for row in rows):
        raise Historical777Error("historical authorized cohort row type mismatch")
    provider_uids = [str(row.get("provider_uid", "")) for row in rows]
    if len(set(provider_uids)) != len(AUTHORIZED_PROVIDER_UIDS) or set(provider_uids) != AUTHORIZED_PROVIDER_UIDS:
        raise Historical777Error("historical authorized cohort UID mismatch")
    for row in rows:
        _validate_frozen_manifest_row(row)
        if str(row.get("manifest_sha256", "")).lower() != MANIFEST_SHA256:
            raise Historical777Error("historical row manifest mismatch")
    return rows


def build_historical_request(row: Mapping[str, Any]) -> dict[str, Any]:
    """Build one UUID-free request; attachment children are keyed by SHA-256."""
    if not isinstance(row, Mapping):
        raise Historical777Error("historical row type mismatch")
    _validate_frozen_manifest_row(row)
    if str(_required(row, "manifest_sha256")).lower() != MANIFEST_SHA256:
        raise Historical777Error("historical row manifest mismatch")
    provider_uid = str(_required(row, "provider_uid"))
    stock = str(_required(row, "stock_number"))
    if provider_uid == EXCLUDED_PROVIDER_UID or stock == EXCLUDED_STOCK:
        raise Historical777Error("historical reference row is excluded")
    source = row["source_metadata"]
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
    conn.execute("create table historical_778_outbox (provider_uid text primary key, request_json text not null, request_sha256 text not null, state text not null, response_json text, attempt_count integer not null default 0, last_error_code text, review_required integer not null default 0, created_at text not null, updated_at text not null)")
    conn.commit()
    return conn


def run_bounded_historical(rows: list[Mapping[str, Any]], outbox: sqlite3.Connection,
                           rpc_call: Callable[[Mapping[str, Any]], dict[str, Any]], *,
                           limit: int | None = None) -> list[dict[str, Any]]:
    """Run only supplied frozen rows; never discovers additional mailbox messages."""
    results = []
    frozen_rows = select_authorized_rows(rows)
    if limit is not None:
        if not isinstance(limit, int) or limit < 1 or limit > len(frozen_rows):
            raise Historical777Error("historical bounded limit mismatch")
        frozen_rows = frozen_rows[:limit]
    for index, row in enumerate(frozen_rows, 1):
        try:
            request = build_historical_request(row)
        except Historical777Error as exc:
            provider_uid = str(row.get("provider_uid") or f"invalid-row-{index}")
            response = {"ok": False, "code": str(exc)}
            request_json = json.dumps({"provider_uid": provider_uid}, sort_keys=True)
            outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,attempt_count,last_error_code,review_required,created_at,updated_at) values(?,?,?,?,?,?,?,datetime('now'),datetime('now'))", (provider_uid, request_json, _sha256(request_json.encode("utf-8")), "retry", 1, response["code"], 0))
            outbox.commit()
            results.append({"provider_uid": provider_uid, "state": "retry", "code": response["code"], "ok": False})
            continue
        except Exception:
            provider_uid = str(row.get("provider_uid") or f"invalid-row-{index}")
            response = {"ok": False, "code": "historical_row_failure"}
            request_json = json.dumps({"provider_uid": provider_uid}, sort_keys=True)
            outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,attempt_count,last_error_code,review_required,created_at,updated_at) values(?,?,?,?,?,?,?,datetime('now'),datetime('now'))", (provider_uid, request_json, _sha256(request_json.encode("utf-8")), "retry", 1, response["code"], 0))
            outbox.commit()
            results.append({"provider_uid": provider_uid, "state": "retry", "code": response["code"], "ok": False})
            continue
        provider_uid = request["provider_uid"]
        request_json = json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        request_hash = canonical_request_digest(request)
        outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,attempt_count,last_error_code,review_required,created_at,updated_at) values(?,?,?,?,?,?,?,datetime('now'),datetime('now'))", (provider_uid, request_json, request_hash, "pending", 0, None, 0))
        outbox.commit()
        try:
            response = rpc_call(request)
        except Exception as exc:
            response = {"ok": False, "code": str(exc) if isinstance(exc, Historical777Error) else "historical_rpc_failure"}
        if not isinstance(response, Mapping):
            response = {"ok": False, "code": "historical_rpc_non_object"}
        raw_ok = response.get("ok") is True
        code = response.get("code") if isinstance(response.get("code"), str) else (None if raw_ok else "historical_unknown_failure")
        data = response.get("data") if isinstance(response.get("data"), Mapping) else {}
        review_required = code in PROPOSAL_REVIEW_CODES or data.get("review_required") is True
        ok = raw_ok and not review_required
        state = "imported" if ok else ("review" if review_required else "retry")
        outbox.execute("update historical_778_outbox set state=?,response_json=?,attempt_count=attempt_count+1,last_error_code=?,review_required=?,updated_at=datetime('now') where provider_uid=?", (state, json.dumps(response, sort_keys=True, ensure_ascii=False), code, int(review_required), provider_uid))
        outbox.commit()
        results.append({"provider_uid": provider_uid, "state": state, "code": code, "ok": ok})
    return results


def summarize_historical_results(results: list[Mapping[str, Any]]) -> dict[str, Any]:
    """Summarize durable outcomes; every non-ok row makes the process fail."""
    failures = [item for item in results if item.get("ok") is not True]
    return {
        "ok": not failures and bool(results),
        "rows": len(results),
        "imported": sum(item.get("state") == "imported" for item in results),
        "retry": sum(item.get("state") == "retry" for item in results),
        "review": sum(item.get("state") == "review" for item in results),
        "failed": len(failures),
        "exit_code": 0 if not failures and results else 1,
    }


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

    url = os.environ.get("PDC_STAGING_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or ""
    anon_key = os.environ.get("PDC_STAGING_SUPABASE_ANON_KEY") or os.environ.get("SUPABASE_ANON_KEY") or ""
    actor_token = os.environ.get("PDC_MONITOR_ACCESS_TOKEN") or ""
    gateway = os.environ.get("PDC_MONITOR_GATEWAY_INSTANCE_ID") or GATEWAY
    if gateway != GATEWAY or not url or not anon_key or not actor_token:
        raise Historical777Error("current Monitor staging bindings are incomplete")
    outbox = prepare_fresh_outbox(args.outbox)
    try:
        results = run_bounded_historical(rows, outbox, lambda request: invoke_historical_rpc(request, url=url, anon_key=anon_key, actor_token=actor_token), limit=1 if args.live_probe else None)
    finally:
        outbox.close()
    summary = summarize_historical_results(results)
    print(json.dumps({**summary, "rpc": RPC_NAME, "rows": results, "outbox": str(args.outbox)}, sort_keys=True))
    return int(summary["exit_code"])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Historical777Error as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True), file=sys.stderr)
        raise SystemExit(1)
