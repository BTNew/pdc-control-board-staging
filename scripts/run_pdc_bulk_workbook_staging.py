#!/usr/bin/env python3
"""Administrator-credential-only staging Preview/Apply runner for bulk workbook import."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

try:
    from scripts.pdc_bulk_workbook_adapter import STAGE_MAPPING_POLICY, adapt_workbook, add_assertion_arguments, assert_expected
except ModuleNotFoundError:  # direct execution from scripts/
    from pdc_bulk_workbook_adapter import STAGE_MAPPING_POLICY, adapt_workbook, add_assertion_arguments, assert_expected

EXPECTED_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_URL = f"https://{EXPECTED_PROJECT_REF}.supabase.co"
ENV_PATH = Path(__file__).resolve().parents[1] / "_staging_test_tools" / ".env"
SHA_RE = re.compile(r"^[a-f0-9]{64}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)


class RunnerError(RuntimeError):
    """Sanitized operational failure."""


def load_env(path: Path = ENV_PATH) -> None:
    if not path.is_file():
        return
    for raw in path.read_text("utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        os.environ.setdefault(name.strip(), value.strip())


def staging_environment(env: dict[str, str] | None = None) -> dict[str, str]:
    source = os.environ if env is None else env
    required = ("PDC_STAGING_SUPABASE_URL", "PDC_STAGING_ANON_KEY", "PDC_STAGING_ADMIN_EMAIL", "PDC_STAGING_ADMIN_PASSWORD")
    missing = [name for name in required if not source.get(name, "").strip()]
    if missing:
        raise RunnerError("required staging administrator environment is incomplete")
    values = {name: source[name].strip() for name in required}
    if values["PDC_STAGING_SUPABASE_URL"].rstrip("/") != EXPECTED_URL:
        raise RunnerError("staging target guard rejected project URL")
    anon = values["PDC_STAGING_ANON_KEY"]
    forbidden = [source.get(name, "").strip() for name in (
        "PDC_STAGING_SERVICE_ROLE_KEY", "SUPABASE_SERVICE_ROLE_KEY", "PDC_STAGING_VIEWER_PASSWORD", "PDC_STAGING_VIEWER_EMAIL"
    )]
    if anon in {value for value in forbidden if value}:
        raise RunnerError("anon key conflicts with a forbidden credential")
    return values


def _post(url: str, anon_key: str, path: str, body: dict[str, Any], token: str | None = None) -> dict[str, Any]:
    headers = {"apikey": anon_key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url + path, data=json.dumps(body, separators=(",", ":")).encode("utf-8"), headers=headers, method="POST")
    try:
        with urlopen(request, timeout=180) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        raise RunnerError(f"staging HTTP request failed with status {exc.code}") from None
    except (URLError, TimeoutError):
        raise RunnerError("staging HTTP request failed") from None
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise RunnerError("staging HTTP response was not valid JSON") from None
    if not isinstance(parsed, dict):
        raise RunnerError("staging HTTP response had an invalid envelope")
    return parsed


def _binding(data: Any, field: str, pattern: re.Pattern[str]) -> str:
    value = data.get(field) if isinstance(data, dict) else None
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise RunnerError(f"Preview response missing valid {field}")
    return value.lower()


def execute(
    args: argparse.Namespace,
    env: dict[str, str] | None = None,
    post: Callable[[str, str, str, dict[str, Any], str | None], dict[str, Any]] = _post,
) -> dict[str, Any]:
    config = staging_environment(env)
    stage_policy = getattr(args, "stage_map_policy", None)
    adapted = adapt_workbook(args.workbook, stage_mapping_policy=stage_policy)
    assert_expected(adapted.evidence, args)
    confirm_stage_policy = getattr(args, "confirm_stage_mapping_policy", None)
    confirmations = (args.confirm_preview_id, args.confirm_workbook_sha256, args.confirm_payload_sha256)
    if not args.apply and (any(value is not None for value in confirmations) or confirm_stage_policy is not None):
        raise RunnerError("Apply confirmations require --apply")
    if args.apply:
        structurally_valid = (
            isinstance(args.confirm_preview_id, str) and UUID_RE.fullmatch(args.confirm_preview_id)
            and isinstance(args.confirm_workbook_sha256, str) and SHA_RE.fullmatch(args.confirm_workbook_sha256)
            and isinstance(args.confirm_payload_sha256, str) and SHA_RE.fullmatch(args.confirm_payload_sha256)
        )
        if not structurally_valid:
            raise RunnerError("Apply requires all three exact Preview confirmations")
        if stage_policy and confirm_stage_policy != stage_policy:
            raise RunnerError("Apply requires the exact workshop-stage mapping policy confirmation")
        if args.confirm_workbook_sha256 != adapted.evidence["workbook_sha256"]:
            raise RunnerError("Apply workbook confirmation does not match the current workbook")
    url, key = config["PDC_STAGING_SUPABASE_URL"], config["PDC_STAGING_ANON_KEY"]

    # Authorization is deliberately performed only with the named administrator
    # email/password and the anon key. No Viewer or service-role variable is read.
    auth = post(url, key, "/auth/v1/token?grant_type=password", {
        "email": config["PDC_STAGING_ADMIN_EMAIL"],
        "password": config["PDC_STAGING_ADMIN_PASSWORD"],
    }, None)
    token = auth.get("access_token")
    if not isinstance(token, str) or not token:
        raise RunnerError("staging administrator authorization failed")

    if stage_policy:
        authorization_path = "/rest/v1/rpc/authorize_pdc_bulk_stock_stage_workbook"
        authorization_body = {
            "p_workbook_sha256": adapted.evidence["workbook_sha256"],
            "p_payload_sha256": adapted.evidence["payload_sha256"],
            "p_expected_pair_count": adapted.evidence["jc_stock_pair_count"],
            "p_expected_operation_count": adapted.evidence["operation_count"],
            "p_stage_mapping_policy": stage_policy,
        }
        authorization_codes = ("stock_stage_authorized", "exact_stock_stage_authorization_replay")
    else:
        authorization_path = "/rest/v1/rpc/authorize_pdc_bulk_jc_stock_workbook"
        authorization_body = {
            "p_workbook_sha256": adapted.evidence["workbook_sha256"],
            "p_expected_pair_count": adapted.evidence["jc_stock_pair_count"],
            "p_expected_operation_count": adapted.evidence["operation_count"],
        }
        authorization_codes = ("authorized", "exact_authorization_replay")
    authorization = post(url, key, authorization_path, authorization_body, token)
    authorization_code = authorization.get("code")
    if authorization.get("ok") is not True or authorization_code not in authorization_codes:
        safe_code = authorization_code if isinstance(authorization_code, str) and re.fullmatch(r"[a-z0-9_]{1,80}", authorization_code) else "authorization_failed"
        raise RunnerError(f"Workbook authorization did not succeed ({safe_code})")
    authorization_data = authorization.get("data") if isinstance(authorization.get("data"), dict) else {}
    if authorization_data.get("workbook_sha256") != adapted.evidence["workbook_sha256"]:
        raise RunnerError("Workbook authorization binding mismatch")
    if stage_policy and (authorization_data.get("payload_sha256") != adapted.evidence["payload_sha256"] or authorization_data.get("stage_mapping_policy") != stage_policy):
        raise RunnerError("Workbook stock/stage authorization binding mismatch")

    preview_path = "/rest/v1/rpc/preview_pdc_bulk_stock_stage_workbook" if stage_policy else "/rest/v1/rpc/preview_pdc_bulk_jc_stock_workbook"
    preview_body = {"p_workbook_sha256": adapted.evidence["workbook_sha256"], "p_payload": adapted.payload}
    if stage_policy:
        preview_body["p_authorized_payload_sha256"] = adapted.evidence["payload_sha256"]
        preview_body["p_stage_mapping_policy"] = stage_policy
    preview = post(url, key, preview_path, preview_body, token)
    code = preview.get("code")
    preview_codes = ("stock_stage_preview_ready", "exact_stock_stage_preview_replay") if stage_policy else ("preview_ready", "exact_preview_replay")
    if preview.get("ok") is not True or code not in preview_codes:
        safe_code = code if isinstance(code, str) and re.fullmatch(r"[a-z0-9_]{1,80}", code) else "preview_failed"
        raise RunnerError(f"Preview did not succeed ({safe_code})")
    data = preview.get("data")
    preview_id = _binding(data, "preview_id", UUID_RE)
    workbook_sha = _binding(data, "workbook_sha256", SHA_RE)
    payload_sha = _binding(data, "payload_sha256", SHA_RE)
    if workbook_sha != adapted.evidence["workbook_sha256"]:
        raise RunnerError("Preview workbook binding mismatch")
    server_counts = {}
    for field in ("row_count", "operation_count", "accepted_count", "quarantine_count", "operation_quarantine_count", "blocked_count"):
        value = data.get(field) if isinstance(data, dict) else None
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise RunnerError(f"Preview aggregate binding missing ({field})")
        server_counts[field] = value
    if server_counts["row_count"] != adapted.evidence["jc_stock_pair_count"] or server_counts["operation_count"] != adapted.evidence["operation_count"]:
        raise RunnerError("Preview aggregate binding mismatch")
    if server_counts["accepted_count"] + server_counts["quarantine_count"] != server_counts["row_count"]:
        raise RunnerError("Preview vehicle classification mismatch")
    if server_counts["operation_quarantine_count"] > server_counts["operation_count"] or server_counts["blocked_count"] != 0:
        raise RunnerError("Preview quarantine/blocking mismatch")
    accepted_stock_count = None
    if stage_policy:
        accepted_stock_count = data.get("accepted_stock_count") if isinstance(data, dict) else None
        if not isinstance(accepted_stock_count, int) or isinstance(accepted_stock_count, bool) or not 0 <= accepted_stock_count <= server_counts["accepted_count"]:
            raise RunnerError("Preview stock aggregate binding mismatch")
        if data.get("stage_mapping_policy") != stage_policy:
            raise RunnerError("Preview workshop-stage mapping policy mismatch")
    applyable = data.get("applyable") if isinstance(data, dict) else None
    if not isinstance(applyable, bool) or applyable != (server_counts["accepted_count"] > 0):
        raise RunnerError("Preview Apply eligibility mismatch")

    output = {
        "code": code,
        "authorization_code": authorization_code,
        "preview_id": preview_id,
        "workbook_sha256": workbook_sha,
        "payload_sha256": payload_sha,
        "local_payload_file_sha256": adapted.evidence["payload_sha256"],
        "jc_stock_pair_count": adapted.evidence["jc_stock_pair_count"],
        "operation_count": adapted.evidence["operation_count"],
        "estimated_hours_count": adapted.evidence["estimated_hours_count"],
        "missing_hours_count": adapted.evidence["missing_hours_count"],
        "max_operations_per_pair": adapted.evidence["max_operations_per_pair"],
        "stage_mapping_policy": stage_policy,
        "stage_counts": adapted.evidence.get("stage_counts", {}),
        "stock_only_rows": adapted.evidence.get("stock_only_rows", 0),
        "accepted_stock_count": accepted_stock_count,
        **server_counts,
        "applyable": applyable,
    }
    if not args.apply:
        output["apply_performed"] = False
        return output
    if not applyable:
        raise RunnerError("Preview is not Apply-able")

    if confirmations != (preview_id, workbook_sha, payload_sha):
        raise RunnerError("Apply confirmations do not exactly match Preview bindings")
    apply_path = "/rest/v1/rpc/apply_pdc_bulk_stock_stage_workbook" if stage_policy else "/rest/v1/rpc/apply_pdc_bulk_jc_stock_workbook"
    apply_body = {
        "p_preview_id": preview_id,
        "p_workbook_sha256": workbook_sha,
        "p_payload_sha256": payload_sha,
    }
    if stage_policy:
        apply_body["p_stage_mapping_policy"] = stage_policy
    applied = post(url, key, apply_path, apply_body, token)
    apply_code = applied.get("code")
    apply_codes = ("stock_stage_applied", "exact_stock_stage_replay") if stage_policy else ("applied", "exact_replay")
    if applied.get("ok") is not True or apply_code not in apply_codes:
        safe_code = apply_code if isinstance(apply_code, str) and re.fullmatch(r"[a-z0-9_]{1,80}", apply_code) else "apply_failed"
        raise RunnerError(f"Apply did not succeed ({safe_code})")
    apply_data = applied.get("data") if isinstance(applied.get("data"), dict) else {}
    output.update({
        "code": apply_code,
        "apply_performed": True,
        "receipt_hash": apply_data.get("receipt_hash") if SHA_RE.fullmatch(str(apply_data.get("receipt_hash", ""))) else None,
        "accepted_count": apply_data.get("accepted_count") if isinstance(apply_data.get("accepted_count"), int) else None,
        "quarantine_count": apply_data.get("quarantine_count") if isinstance(apply_data.get("quarantine_count"), int) else None,
        "operation_quarantine_count": apply_data.get("operation_quarantine_count") if isinstance(apply_data.get("operation_quarantine_count"), int) else None,
        "operation_lines_added": apply_data.get("operation_lines_added") if isinstance(apply_data.get("operation_lines_added"), int) else None,
        "work_items_added": apply_data.get("work_items_added") if isinstance(apply_data.get("work_items_added"), int) else None,
        "unique_stock_count": apply_data.get("unique_stock_count") if isinstance(apply_data.get("unique_stock_count"), int) else None,
        "vehicles_created": apply_data.get("vehicles_created") if isinstance(apply_data.get("vehicles_created"), int) else None,
        "zero_add_replay": apply_data.get("zero_add_replay") if isinstance(apply_data.get("zero_add_replay"), bool) else None,
    })
    return output


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("workbook", type=Path)
    result.add_argument("--apply", action="store_true", help="explicitly request durable Apply after successful Preview")
    result.add_argument("--confirm-preview-id")
    result.add_argument("--confirm-workbook-sha256")
    result.add_argument("--confirm-payload-sha256")
    result.add_argument("--stage-map-policy", choices=[STAGE_MAPPING_POLICY])
    result.add_argument("--confirm-stage-mapping-policy", choices=[STAGE_MAPPING_POLICY])
    add_assertion_arguments(result)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        load_env()
        print(json.dumps(execute(args), sort_keys=True, separators=(",", ":")))
        return 0
    except Exception as exc:
        # Never include transport bodies, tokens, request bodies, or arbitrary
        # exception representations. Known contract errors carry sanitized text.
        message = str(exc) if isinstance(exc, (RunnerError, ValueError, OSError)) else "unexpected runner failure"
        print(json.dumps({"code": "staging_runner_failed", "error": message}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
