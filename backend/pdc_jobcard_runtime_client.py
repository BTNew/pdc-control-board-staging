#!/usr/bin/env python
"""Two-authority client for the staging PMB job-card attachment adapter.

This module does not read a mailbox or parse documents. The pdc-monitor owner
passes one already-retained, v2 extraction request. Provider attestation is
sent only with the Supabase service-role credential; operational processing is
sent only with the enrolled monitor user's authenticated JWT.
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

STAGING_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
ATTEST_RPC = "attest_pdc_provider_email_observation"
PROCESS_RPC = "process_email_intake_work"
SUCCESS_ATTEST_CODES = {"provider_observation_attested", "provider_observation_already_attested"}
HEX64 = set("0123456789abcdef")


class RuntimeContractError(RuntimeError):
    """Safe, bounded runtime/contract failure."""


@dataclass(frozen=True)
class RpcClient:
    url: str
    apikey: str
    bearer: str
    authority: str
    timeout: int = 60

    def rpc(self, name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        data = json.dumps(dict(payload), separators=(",", ":"), default=str).encode("utf-8")
        request = urllib.request.Request(
            f"{self.url.rstrip('/')}/rest/v1/rpc/{name}",
            data=data,
            method="POST",
            headers={
                "apikey": self.apikey,
                "Authorization": f"Bearer {self.bearer}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            # Do not echo provider bodies: they can contain database or request detail.
            exc.read()
            raise RuntimeContractError(f"{self.authority} RPC {name} failed HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeContractError(f"{self.authority} RPC {name} transport failed") from exc
        try:
            result = json.loads(raw) if raw else None
        except json.JSONDecodeError as exc:
            raise RuntimeContractError(f"{self.authority} RPC {name} returned invalid JSON") from exc
        if not isinstance(result, dict):
            raise RuntimeContractError(f"{self.authority} RPC {name} returned an invalid result")
        return result


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RuntimeContractError(f"{label} must be an object")
    return value


def _exact_keys(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    observed = set(value)
    if observed != expected:
        raise RuntimeContractError(f"{label} keys do not match the v2 contract")


def _hex64(value: Any, label: str) -> str:
    text = str(value or "").strip().lower()
    if len(text) != 64 or any(character not in HEX64 for character in text):
        raise RuntimeContractError(f"{label} must be a lowercase SHA-256 hex digest")
    return text


def validate_request(request: Mapping[str, Any]) -> dict[str, Any]:
    _exact_keys(
        request,
        {"intake_id", "expected_source_hash", "extraction_hash", "provider", "extraction"},
        "request",
    )
    provider = _object(request["provider"], "provider")
    extraction = _object(request["extraction"], "extraction")
    _exact_keys(
        provider,
        {"attachment_id", "provider_message_id", "provider_authserv_id", "authentication"},
        "provider",
    )
    _exact_keys(
        extraction,
        {
            "authentication", "canonical_attachment_id", "canonical_document_hash", "contract_version",
            "email_vehicle", "operation_lines", "required_work",
        },
        "extraction",
    )
    if extraction.get("contract_version") != "pmb-email-work-v2":
        raise RuntimeContractError("extraction contract_version must be pmb-email-work-v2")
    if str(provider.get("attachment_id") or "") != str(extraction.get("canonical_attachment_id") or ""):
        raise RuntimeContractError("provider and extraction attachment identities differ")
    if provider.get("authentication") != extraction.get("authentication"):
        raise RuntimeContractError("provider and extraction authentication evidence differ")
    auth = _object(provider.get("authentication"), "provider.authentication")
    _exact_keys(
        auth,
        {"dkim_aligned", "dmarc_aligned", "gmail_authentication_results", "sender_domain", "spf_aligned"},
        "provider.authentication",
    )
    if provider.get("provider_authserv_id") != "mx.google.com":
        raise RuntimeContractError("provider_authserv_id must be mx.google.com")
    if auth.get("gmail_authentication_results") is not True:
        raise RuntimeContractError("trusted Gmail Authentication-Results evidence is required")
    if not any(auth.get(key) is True for key in ("spf_aligned", "dkim_aligned", "dmarc_aligned")):
        raise RuntimeContractError("at least one aligned provider authentication result is required")
    if not isinstance(extraction.get("operation_lines"), list) or not 1 <= len(extraction["operation_lines"]) <= 50:
        raise RuntimeContractError("operation_lines must contain 1 to 50 source rows")
    return {
        "intake_id": str(request.get("intake_id") or ""),
        "source_hash": _hex64(request.get("expected_source_hash"), "expected_source_hash"),
        "extraction_hash": _hex64(request.get("extraction_hash"), "extraction_hash"),
        "attachment_hash": _hex64(extraction.get("canonical_document_hash"), "canonical_document_hash"),
        "provider": provider,
        "extraction": extraction,
    }


def execute_jobcard_request(
    service_client: RpcClient,
    actor_client: RpcClient,
    request: Mapping[str, Any],
) -> dict[str, Any]:
    if service_client.authority != "service_role" or actor_client.authority != "authenticated_monitor":
        raise RuntimeContractError("client authorities are not separated")
    if service_client.bearer == actor_client.bearer:
        raise RuntimeContractError("service-role and monitor actor credentials must differ")
    checked = validate_request(request)
    provider = checked["provider"]
    attested = service_client.rpc(ATTEST_RPC, {
        "p_intake_id": checked["intake_id"],
        "p_attachment_id": provider["attachment_id"],
        "p_expected_parent_hash": checked["source_hash"],
        "p_expected_attachment_hash": checked["attachment_hash"],
        "p_provider_message_id": provider["provider_message_id"],
        "p_provider_authserv_id": provider["provider_authserv_id"],
        "p_authentication": provider["authentication"],
    })
    if attested.get("ok") is not True or attested.get("code") not in SUCCESS_ATTEST_CODES:
        return {"ok": False, "phase": "provider_attestation", "code": str(attested.get("code") or "attestation_failed")}
    processed = actor_client.rpc(PROCESS_RPC, {
        "p_intake_id": checked["intake_id"],
        "p_expected_source_hash": checked["source_hash"],
        "p_extraction_hash": checked["extraction_hash"],
        "p_extraction": checked["extraction"],
        "p_actor": "pdc-monitor",
    })
    if processed.get("ok") is not True:
        return {"ok": False, "phase": "operational_processing", "code": str(processed.get("code") or "processing_failed")}
    data = processed.get("data") if isinstance(processed.get("data"), dict) else {}
    return {
        "ok": True,
        "phase": "complete",
        "attestation_code": attested.get("code"),
        "code": processed.get("code"),
        "receipt_id": data.get("receipt_id"),
        "vehicle_id": data.get("vehicle_id"),
        "operation_count": data.get("operation_count"),
        "estimated_hours_sum": data.get("estimated_hours_sum"),
    }


def _actor_access_token(url: str, anon_key: str) -> str:
    direct = os.environ.get("PDC_MONITOR_ACCESS_TOKEN", "").strip()
    if direct:
        return direct
    email = os.environ.get("PDC_MONITOR_EMAIL", "").strip()
    password = os.environ.get("PDC_MONITOR_PASSWORD", "")
    if not email or not password:
        raise RuntimeContractError("monitor actor credentials are unavailable")
    payload = json.dumps({"email": email, "password": password}).encode("utf-8")
    req = urllib.request.Request(
        f"{url.rstrip('/')}/auth/v1/token?grant_type=password",
        data=payload,
        method="POST",
        headers={"apikey": anon_key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode("utf-8", errors="replace"))
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeContractError("monitor actor authentication failed") from exc
    token = str(result.get("access_token") or "") if isinstance(result, dict) else ""
    if not token:
        raise RuntimeContractError("monitor actor authentication returned no access token")
    return token


def clients_from_environment() -> tuple[RpcClient, RpcClient]:
    url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    anon_key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if not url or not service_key or not anon_key:
        raise RuntimeContractError("staging Supabase URL, service-role key and anon key are required")
    hostname = urllib.parse.urlparse(url).hostname or ""
    if hostname != f"{STAGING_PROJECT_REF}.supabase.co":
        raise RuntimeContractError("refusing a non-staging Supabase project")
    actor_token = _actor_access_token(url, anon_key)
    return (
        RpcClient(url, service_key, service_key, "service_role"),
        RpcClient(url, anon_key, actor_token, "authenticated_monitor"),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute one retained PMB job-card v2 request using separated authorities")
    parser.add_argument("--request", required=True, help="Profile-owned retained v2 request JSON")
    args = parser.parse_args()
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8"))
        service_client, actor_client = clients_from_environment()
        result = execute_jobcard_request(service_client, actor_client, _object(request, "request"))
    except (OSError, json.JSONDecodeError, RuntimeContractError) as exc:
        result = {"ok": False, "phase": "preflight", "code": type(exc).__name__, "error": str(exc)}
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
