from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
STAGING_HOST = f"{EXPECTED_REF}.supabase.co"
BUCKET = "pdc-email-intake-private"
TARGETS = (
    "d89a3bbd-590b-493b-84a8-ce557bbfe512",
    "6836f01c-080f-4289-90a4-df8667a49ac9",
)
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRET = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")


def load_db_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap loader unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRET.read_bytes()).decode("utf-8"))
    module.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project reference mismatch")
    return values


def base_url() -> str:
    value = (os.environ.get("PDC_STAGING_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or "").rstrip("/")
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != "https" or parsed.hostname != STAGING_HOST or parsed.port is not None or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
        raise RuntimeError("refusing non-staging Supabase URL")
    return f"https://{STAGING_HOST}"


def post_json(url: str, payload: object, anon_key: str, bearer: str) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={"apikey": anon_key, "Authorization": f"Bearer {bearer}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read(1_048_577)
            if len(raw) > 1_048_576:
                raise RuntimeError("response exceeded bound")
            result = json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read(4096)
        detail = ""
        try:
            body = json.loads(raw.decode("utf-8"))
            if isinstance(body, dict):
                detail = json.dumps({key: body[key] for key in ("code", "message", "details", "hint") if key in body}, sort_keys=True)[:400]
        except (UnicodeDecodeError, json.JSONDecodeError):
            detail = ""
        raise RuntimeError(f"RPC failed HTTP {exc.code} {detail}") from exc
    if not isinstance(result, dict):
        raise RuntimeError("RPC returned invalid JSON")
    return result


def authenticate(base: str, anon_key: str) -> str:
    email = os.environ.get("PDC_STAGING_ADMIN_EMAIL", "").strip()
    password = os.environ.get("PDC_STAGING_ADMIN_PASSWORD", "")
    if not email or not password:
        raise RuntimeError("approved staging administrator credential is unavailable")
    result = post_json(f"{base}/auth/v1/token?grant_type=password", {"email": email, "password": password}, anon_key, anon_key)
    token = result.get("access_token")
    if not isinstance(token, str) or len(token) < 8 or token == anon_key:
        raise RuntimeError("administrator authentication returned no scoped token")
    return token


def storage_probe(base: str, anon_key: str, bearer: str, object_path: str) -> tuple[str, int]:
    request = urllib.request.Request(
        f"{base}/storage/v1/object/authenticated/{BUCKET}/{urllib.parse.quote(object_path, safe='/')}",
        headers={"apikey": anon_key, "Authorization": f"Bearer {bearer}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read(10 * 1024 * 1024 + 1)
            if len(body) > 10 * 1024 * 1024:
                raise RuntimeError("storage object exceeds bound")
            return hashlib.sha256(body).hexdigest(), len(body)
    except urllib.error.HTTPError as exc:
        body = exc.read(4096)
        if exc.code in (400, 404):
            return "missing", 0
        raise RuntimeError(f"storage probe failed HTTP {exc.code}") from exc


def safe_name(filename: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", filename)[:120]
    return name or "attachment"


def main() -> int:
    evidence = ROOT / "review-evidence" / "email-monitor-735" / "reconcile-requeue.json"
    event: dict[str, object] = {
        "ok": False,
        "production_touched": False,
        "mailbox_contacted": False,
        "task_enabled": False,
        "targets": list(TARGETS),
    }
    try:
        import psycopg2

        values = load_db_values()
        base = base_url()
        anon_key = (os.environ.get("PDC_STAGING_ANON_KEY") or os.environ.get("SUPABASE_ANON_KEY") or "").strip()
        if not anon_key:
            raise RuntimeError("staging anon key is unavailable")
        admin_token = authenticate(base, anon_key)
        conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], connect_timeout=15, application_name="pdc_email_monitor_735_custody", sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"])
        try:
            cur = conn.cursor()
            cur.execute("select current_user,session_user,to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone() != ("postgres", "postgres", False):
                raise RuntimeError("database custody target mismatch")
            cur.execute(
                """select i.id::text,i.status::text,i.permanent_failure,a.id::text,a.file_name,a.source_hash,a.storage_path
                   from public.ai_email_intake i join public.ai_email_attachments a on a.intake_id=i.id
                   where i.id = any(%s::uuid[]) order by i.id,a.created_at,a.id""",
                (list(TARGETS),),
            )
            rows = cur.fetchall()
            if not rows:
                raise RuntimeError("exact target attachments not found")
            reconcile_results = []
            for intake_id, status, permanent, attachment_id, filename, source_hash, original_path in rows:
                if intake_id not in TARGETS or status != "failed" or permanent is not True:
                    raise RuntimeError("exact failed/permanent precondition changed")
                if not isinstance(source_hash, str) or re.fullmatch(r"[a-f0-9]{64}", source_hash) is None:
                    raise RuntimeError("attachment source hash is invalid")
                canonical_object = f"{source_hash}/{safe_name(filename)}"
                observed_hash, observed_bytes = storage_probe(base, anon_key, admin_token, canonical_object)
                if observed_hash == source_hash:
                    outcome = "canonical_verified"
                    canonical_path = f"{BUCKET}/{canonical_object}"
                elif observed_hash == "missing":
                    outcome = "permanent_fail_closed"
                    canonical_path = None
                else:
                    raise RuntimeError("storage object hash mismatch")
                evidence_hash = hashlib.sha256(json.dumps({"intake_id": intake_id, "attachment_id": attachment_id, "original_storage_path": original_path, "canonical_storage_path": canonical_path, "source_hash": source_hash, "outcome": outcome, "observed_bytes": observed_bytes}, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
                result = post_json(
                    f"{base}/rest/v1/rpc/admin_reconcile_pdc_email_attachment_storage_735",
                    {"p_intake_id": intake_id, "p_attachment_id": attachment_id, "p_original_storage_path": original_path, "p_canonical_storage_path": canonical_path, "p_outcome": outcome, "p_evidence_hash": evidence_hash},
                    anon_key,
                    admin_token,
                )
                if result.get("ok") is not True:
                    raise RuntimeError("storage reconciliation RPC returned failure")
                reconcile_results.append({"intake_id": intake_id, "attachment_id": attachment_id, "outcome": outcome, "observed_bytes": observed_bytes, "original_path_preserved": True, "rpc_code": result.get("code")})
            requeue_results = []
            for intake_id in TARGETS:
                request_key = f"pdc-email-monitor-735:{intake_id}"
                result = post_json(
                    f"{base}/rest/v1/rpc/admin_requeue_pdc_email_intake_735",
                    {"p_intake_id": intake_id, "p_request_key": request_key, "p_reason": "authorised staging remediation for exact failed intake"},
                    anon_key,
                    admin_token,
                )
                if result.get("ok") is not True:
                    raise RuntimeError("exact-ID requeue RPC returned failure")
                requeue_results.append({"intake_id": intake_id, "request_key": request_key, "rpc_code": result.get("code"), "status": result.get("status")})
            conn.commit()
            event["reconciliations"] = reconcile_results
            event["requeues"] = requeue_results
            cur.execute(
                """select jsonb_agg(jsonb_build_object('id',i.id,'provider_uid',i.provider_uid,'status',i.status,'permanent_failure',i.permanent_failure,'queue_attempts',i.queue_attempts,'last_error_code',i.last_error_code) order by i.id) from public.ai_email_intake i where i.id = any(%s::uuid[])""",
                (list(TARGETS),),
            )
            event["post_requeue"] = cur.fetchone()[0]
            cur.execute("select count(*) from public.pdc_email_monitor_storage_reconciliations_735 where intake_id = any(%s::uuid[])", (list(TARGETS),))
            event["reconciliation_receipt_count"] = cur.fetchone()[0]
            cur.execute("select count(*) from public.pdc_email_monitor_requeue_receipts_735 where intake_id = any(%s::uuid[])", (list(TARGETS),))
            event["requeue_receipt_count"] = cur.fetchone()[0]
            event["ok"] = True
        finally:
            conn.close()
    except Exception as exc:
        event["error"] = str(exc)[:500]
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
