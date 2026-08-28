from __future__ import annotations

import importlib.util
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = "cdsmnqxtyyoeoznmbidd"
HOST = f"{REF}.supabase.co"
TARGETS = ["d89a3bbd-590b-493b-84a8-ce557bbfe512", "6836f01c-080f-4289-90a4-df8667a49ac9"]
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRET = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")


def db_values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap loader unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRET.read_bytes()).decode())
    module.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != REF:
        raise RuntimeError("staging project mismatch")
    return values


def base():
    value = (os.environ.get("PDC_STAGING_SUPABASE_URL") or "").rstrip("/")
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != "https" or parsed.hostname != HOST or parsed.port is not None or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
        raise RuntimeError("non-staging URL")
    return f"https://{HOST}"


def login(root, anon):
    email = os.environ.get("PDC_STAGING_ADMIN_EMAIL", "").strip()
    password = os.environ.get("PDC_STAGING_ADMIN_PASSWORD", "")
    request = urllib.request.Request(f"{root}/auth/v1/token?grant_type=password", data=json.dumps({"email": email, "password": password}).encode(), method="POST", headers={"apikey": anon, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=45) as response:
        token = json.loads(response.read(65537).decode())["access_token"]
    return token


def request(root, path, anon, bearer, method="GET", payload=None):
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
    req = urllib.request.Request(f"{root}{path}", data=body, method=method, headers={"apikey": anon, "Authorization": f"Bearer {bearer}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            raw = response.read(4097)
            return response.status, json.loads(raw.decode()) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read(4096)
        try:
            value = json.loads(raw.decode())
            value = {key: value[key] for key in ("code", "message", "details", "hint") if key in value} if isinstance(value, dict) else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            value = {}
        return exc.code, value


def main():
    evidence = ROOT / "review-evidence" / "email-monitor-735" / "live-verification.json"
    event = {"ok": False, "production_touched": False, "mailbox_contacted_by_verifier": False}
    try:
        import psycopg2
        values = db_values()
        root = base()
        anon = (os.environ.get("PDC_STAGING_ANON_KEY") or "").strip()
        admin = login(root, anon)
        negatives = {}
        for name, bearer, path, method, payload in (
            ("wrong_actor_requeue", admin, "/rest/v1/rpc/admin_requeue_pdc_email_intake_735", "POST", {"p_intake_id": "00000000-0000-0000-0000-000000000001", "p_request_key": "pdc-email-monitor-735:00000000-0000-0000-0000-000000000001", "p_reason": "negative"}),
            ("wrong_gateway_attachment", admin, "/rest/v1/rpc/get_pdc_monitor_intake_attachments_735", "POST", {"p_intake_id": TARGETS[0], "p_claim_token": "00000000-0000-0000-0000-000000000001", "p_gateway_instance_id": "wrong-gateway"}),
            ("anon_requeue", anon, "/rest/v1/rpc/admin_requeue_pdc_email_intake_735", "POST", {"p_intake_id": TARGETS[0], "p_request_key": f"pdc-email-monitor-735:{TARGETS[0]}", "p_reason": "negative"}),
            ("direct_protected_receipt_read", admin, "/rest/v1/pdc_email_monitor_requeue_receipts_735?select=*", "GET", None),
        ):
            status, body = request(root, path, anon, bearer, method, payload)
            negatives[name] = {"http_status": status, "body": body}
        conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], connect_timeout=15, application_name="pdc_email_monitor_735_readback", sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"])
        try:
            cur = conn.cursor()
            cur.execute("""select jsonb_build_object(
              'target',jsonb_build_object('database',current_database(),'user',current_user,'staging',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production',to_regclass('public.pdc_production_environment_sentinel') is not null),
              'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
              'targets',(select jsonb_agg(jsonb_build_object('id',i.id,'provider_uid',i.provider_uid,'status',i.status,'permanent_failure',i.permanent_failure,'queue_attempts',i.queue_attempts,'last_error_code',i.last_error_code) order by i.id) from public.ai_email_intake i where i.id = any(%s::uuid[])),
              'reconciliations',(select jsonb_agg(jsonb_build_object('intake_id',intake_id,'attachment_id',attachment_id,'outcome',outcome,'original_matches',(select a.storage_path is not distinct from r.original_storage_path from public.ai_email_attachments a where a.id=r.attachment_id)) order by intake_id,attachment_id) from public.pdc_email_monitor_storage_reconciliations_735 r where intake_id = any(%s::uuid[])),
              'requeue_receipts',(select jsonb_agg(jsonb_build_object('intake_id',intake_id,'before_status',before_status,'before_permanent_failure',before_permanent_failure,'after_status',after_status) order by intake_id) from public.pdc_email_monitor_requeue_receipts_735 where intake_id = any(%s::uuid[])),
              'counts',jsonb_build_object('uid514',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'active_vehicles',(select count(*) from public.vehicles where deleted_at is null),'active_work',(select count(*) from public.workshop_bookings),'jobcard_receipts',(select count(*) from public.pdc_jobcard_attachment_import_receipts),'monitor_status',(select to_jsonb(s) from public.pdc_email_monitor_status s where singleton),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'outbound_disabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and not outbound_email_enabled))
            )""", (TARGETS, TARGETS, TARGETS))
            event["readback"] = cur.fetchone()[0]
        finally:
            conn.close()
        event["negative_matrix"] = negatives
        target_rows = event["readback"].get("targets", [])
        event["ok"] = bool(target_rows) and all(row.get("status") == "failed" and row.get("permanent_failure") is True for row in target_rows)
    except Exception as exc:
        event["error"] = str(exc)[:500]
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
