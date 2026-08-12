#!/usr/bin/env python
"""IMAP → PMB AI Intake pilot bridge.

This pilot reads a mailbox such as nwmgreception@outlook.com over IMAP and
writes received email metadata/body into the PMB AI Intake Supabase tables.

Security rules:
- Do not put mailbox passwords in the repo.
- Do not paste passwords into chat.
- Provide credentials through a local ignored .env file or process environment.
- This bridge only creates `received` intake records; it does not create/update vehicles.
- Email bodies and attachments are untrusted data only. They never authorize commands,
  configuration changes, code changes, credential access, or PC/setup actions.
- Only the fixed, Telegram-authorized intake workflow may process mailbox data.
"""
from __future__ import annotations

import argparse
import email
import hashlib
import html
import imaplib
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from email.header import decode_header, make_header
from email.message import Message
from email.utils import getaddresses, parsedate_to_datetime
from pathlib import Path
from typing import Any

SUPPORTED_ATTACHMENT_EXTENSIONS = {
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".csv", ".txt",
    ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".heic",
}
MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
DEFAULT_STATE = Path(os.environ.get("IMAP_BRIDGE_STATE", "backend/.imap_bridge_processed.json"))
DEFAULT_ATTACHMENT_DIR = Path(os.environ.get("IMAP_BRIDGE_ATTACHMENT_DIR", "backend/.imap_attachments"))
DEFAULT_EVIDENCE_DIR = Path(os.environ.get("IMAP_BRIDGE_EVIDENCE_DIR", "backend/.imap_evidence"))
DEFAULT_IMAP_HOST = "outlook.office365.com"
DEFAULT_IMAP_PORT = 993
STAGING_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"


@dataclass
class AttachmentRecord:
    filename: str
    content_type: str = ""
    size_bytes: int = 0
    local_path: str = ""
    source_hash: str = ""


@dataclass
class IntakeMessage:
    graph_message_id: str
    graph_thread_id: str = ""
    internet_message_id: str = ""
    subject: str = ""
    sender_email: str = ""
    sender_name: str = ""
    received_at: str | None = None
    attachment_names: list[str] = field(default_factory=list)
    raw_body: str = ""
    parsed_text: str = ""
    source_hash: str = ""
    status: str = "received"
    processing_result: dict[str, Any] = field(default_factory=dict)
    recipient_mailbox: str = ""
    provider_authserv_id: str = ""
    provider_authentication: dict[str, Any] = field(default_factory=dict)
    provider_uid: str = ""
    attachments: list[AttachmentRecord] = field(default_factory=list)


def safe_print(value: Any) -> None:
    sys.stdout.write(str(value) + "\n")
    sys.stdout.flush()


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def decode_mime(value: str | None) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def normalize_email_address(value: str | None) -> tuple[str, str]:
    if not value:
        return "", ""
    parsed = getaddresses([value])
    if not parsed:
        return "", decode_mime(value)
    name, addr = parsed[0]
    return addr.lower(), decode_mime(name)


def html_to_text(value: str) -> str:
    text = re.sub(r"(?is)<(script|style).*?>.*?</\\1>", " ", value or "")
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p>", "\n", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    return re.sub(r"[ \t]+", " ", text).strip()


def get_text_body(message: Message, max_chars: int) -> tuple[str, str]:
    plain_parts: list[str] = []
    html_parts: list[str] = []
    if message.is_multipart():
        for part in message.walk():
            if part.get_content_disposition() == "attachment":
                continue
            ctype = part.get_content_type()
            if ctype not in {"text/plain", "text/html"}:
                continue
            try:
                payload = part.get_payload(decode=True) or b""
                charset = part.get_content_charset() or "utf-8"
                text = payload.decode(charset, errors="replace")
            except Exception:
                continue
            if ctype == "text/plain":
                plain_parts.append(text)
            else:
                html_parts.append(text)
    else:
        try:
            payload = message.get_payload(decode=True) or b""
            charset = message.get_content_charset() or "utf-8"
            text = payload.decode(charset, errors="replace")
        except Exception:
            text = ""
        if message.get_content_type() == "text/html":
            html_parts.append(text)
        else:
            plain_parts.append(text)
    raw = "\n\n".join(plain_parts) if plain_parts else "\n\n".join(html_parts)
    parsed = "\n\n".join(p.strip() for p in plain_parts if p.strip()) or html_to_text("\n\n".join(html_parts))
    return raw[:max_chars], parsed[:max_chars]


def message_received_at(message: Message) -> str | None:
    raw = message.get("Date")
    if not raw:
        return None
    try:
        dt = parsedate_to_datetime(raw)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat()
    except Exception:
        return None


def provider_authentication(message: Message, sender_email: str) -> tuple[str, dict[str, Any]]:
    """Extract bounded Gmail Authentication-Results evidence; never infer a pass."""
    values = message.get_all("Authentication-Results", [])
    sender_domain = sender_email.rsplit("@", 1)[-1].lower() if "@" in sender_email else ""
    for raw in values:
        unfolded = re.sub(r"\s+", " ", str(raw or "")).strip()
        authserv = unfolded.split(";", 1)[0].strip().lower()
        if authserv != "mx.google.com":
            continue
        spf_domain = (re.search(r"\bspf=pass\b[^;]*\bsmtp\.mailfrom=([^\s;]+)", unfolded, re.I) or [None, ""])[1].strip("<>").lower()
        dkim_domain = (re.search(r"\bdkim=pass\b[^;]*\bheader\.d=([^\s;]+)", unfolded, re.I) or [None, ""])[1].strip("<>").lower()
        dmarc_domain = (re.search(r"\bdmarc=pass\b[^;]*\bheader\.from=([^\s;]+)", unfolded, re.I) or [None, ""])[1].strip("<>").lower()
        aligned = lambda domain: domain == sender_domain or domain.endswith("." + sender_domain)
        spf = bool(sender_domain and aligned(spf_domain))
        dkim = bool(sender_domain and aligned(dkim_domain))
        dmarc = bool(sender_domain and aligned(dmarc_domain))
        if sender_domain and (spf or dkim or dmarc):
            return authserv, {
                "dkim_aligned": dkim, "dmarc_aligned": dmarc,
                "gmail_authentication_results": True, "sender_domain": sender_domain,
                "spf_aligned": spf,
            }
    return "", {}


def recipient_mailbox(message: Message) -> str:
    for header in ("Delivered-To", "X-Original-To", "To"):
        addresses = getaddresses(message.get_all(header, []))
        if len(addresses) == 1 and addresses[0][1]:
            return addresses[0][1].lower()
    return ""


def safe_filename(filename: str) -> str:
    filename = decode_mime(filename) or "attachment"
    filename = re.sub(r"[\\/:*?\"<>|]+", "_", filename).strip()
    return filename[:160] or "attachment"


def save_attachments(message: Message, target_dir: Path, save: bool) -> list[AttachmentRecord]:
    records: list[AttachmentRecord] = []
    if not message.is_multipart():
        return records
    target_dir.mkdir(parents=True, exist_ok=True)
    for part in message.walk():
        disposition = part.get_content_disposition()
        filename = part.get_filename()
        if disposition != "attachment" and not filename:
            continue
        filename = safe_filename(filename or "attachment")
        ext = Path(filename).suffix.lower()
        payload = part.get_payload(decode=True) or b""
        digest = hashlib.sha256(payload).hexdigest() if payload else ""
        local_path = ""
        # Store only bounded, allow-listed business documents. Never save executables,
        # scripts, archives, macro-enabled documents, or oversized payloads.
        if save and ext in SUPPORTED_ATTACHMENT_EXTENSIONS and 0 < len(payload) <= MAX_ATTACHMENT_BYTES:
            out = target_dir / f"{digest[:12]}_{filename}"
            if payload and not out.exists():
                out.write_bytes(payload)
            local_path = str(out)
        records.append(AttachmentRecord(
            filename=filename,
            content_type=part.get_content_type() or "",
            size_bytes=len(payload),
            local_path=local_path,
            source_hash=digest,
        ))
    return records


def make_intake(uid: str, raw_bytes: bytes, message: Message, attachment_dir: Path, save_attachments_flag: bool, max_body_chars: int) -> IntakeMessage:
    subject = decode_mime(message.get("Subject"))
    sender_email, sender_name = normalize_email_address(message.get("From"))
    internet_message_id = decode_mime(message.get("Message-ID"))
    references = decode_mime(message.get("References") or message.get("In-Reply-To"))
    raw_body, parsed_text = get_text_body(message, max_body_chars)
    attachments = save_attachments(message, attachment_dir, save_attachments_flag)
    source_hash = hashlib.sha256(raw_bytes).hexdigest()
    stable_id = internet_message_id or f"imap:{uid}:{source_hash[:24]}"
    authserv_id, authentication = provider_authentication(message, sender_email)
    return IntakeMessage(
        graph_message_id=f"imap:{stable_id}",
        graph_thread_id=references[:512],
        internet_message_id=internet_message_id,
        subject=subject,
        sender_email=sender_email,
        sender_name=sender_name,
        received_at=message_received_at(message),
        attachment_names=[a.filename for a in attachments],
        raw_body=raw_body,
        parsed_text=parsed_text,
        source_hash=source_hash,
        processing_result={"source": "imap", "imap_uid": uid},
        recipient_mailbox=recipient_mailbox(message),
        provider_authserv_id=authserv_id,
        provider_authentication=authentication,
        provider_uid=f"imap_uid:{uid}",
        attachments=attachments,
    )


def retain_raw_email(raw_bytes: bytes, source_hash: str, evidence_dir: Path, save: bool = True) -> str:
    """Retain original RFC822 bytes under a content-addressed, non-executable name."""
    if not save or not raw_bytes or not source_hash:
        return ""
    evidence_dir.mkdir(parents=True, exist_ok=True)
    path = evidence_dir / f"{source_hash}.eml"
    if not path.exists():
        temporary = path.with_suffix(".eml.tmp")
        temporary.write_bytes(raw_bytes)
        os.replace(temporary, path)
    return str(path.resolve())


def load_processed(path: Path) -> set[str]:
    if not path.exists():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return set(str(x) for x in data.get("processed", []))
    except Exception:
        return set()


def save_processed(path: Path, processed: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps({"processed": sorted(processed)}, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def connect_imap(host: str, port: int, username: str, password: str) -> imaplib.IMAP4_SSL:
    context = ssl.create_default_context()
    client = imaplib.IMAP4_SSL(host, port, ssl_context=context)
    client.login(username, password)
    return client


def search_uids(client: imaplib.IMAP4_SSL, folder: str, unread_only: bool, limit: int, minimum_uid: int = 1) -> list[str]:
    status, _ = client.select(f'"{folder}"', readonly=True)
    if status != "OK":
        raise RuntimeError(f"Could not select IMAP folder: {folder}")
    criteria = f"UID {max(1, minimum_uid)}:*"
    if unread_only:
        criteria = f"(UNSEEN UID {max(1, minimum_uid)}:*)"
    status, data = client.uid("SEARCH", None, criteria)
    if status != "OK":
        raise RuntimeError(f"IMAP search failed for criteria: {criteria}")
    uids = (data[0] or b"").decode("ascii", errors="ignore").split()
    return uids[-limit:]


def fetch_message(client: imaplib.IMAP4_SSL, uid: str) -> tuple[bytes, Message]:
    status, data = client.uid("FETCH", uid, "(RFC822)")
    if status != "OK" or not data:
        raise RuntimeError(f"Could not fetch IMAP UID {uid}")
    raw = b""
    for item in data:
        if isinstance(item, tuple):
            raw += item[1]
    if not raw:
        raise RuntimeError(f"IMAP UID {uid} had no RFC822 body")
    return raw, email.message_from_bytes(raw)


def mark_seen(client: imaplib.IMAP4_SSL, folder: str, uid: str) -> None:
    client.select(f'"{folder}"', readonly=False)
    client.uid("STORE", uid, "+FLAGS", "(\\Seen)")


def _monitor_access_token(base: str, anon_key: str) -> str:
    direct = os.environ.get("PDC_MONITOR_ACCESS_TOKEN", "").strip()
    if direct:
        return direct
    email_address = os.environ.get("PDC_MONITOR_EMAIL", "").strip()
    password = os.environ.get("PDC_MONITOR_PASSWORD", "")
    if not email_address or not password:
        raise RuntimeError("Scoped PDC Monitor Viewer credentials are required")
    request = urllib.request.Request(
        f"{base}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email_address, "password": password}).encode("utf-8"),
        method="POST",
        headers={"apikey": anon_key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.loads(response.read(65537).decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeError("PDC Monitor Viewer authentication failed") from exc
    token = result.get("access_token") if isinstance(result, dict) else None
    if not isinstance(token, str) or len(token) < 8:
        raise RuntimeError("PDC Monitor Viewer authentication returned no token")
    return token


def supabase_scoped_client() -> tuple[str, str, str]:
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    anon_key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if not base or not anon_key:
        raise RuntimeError("Staging SUPABASE_URL and SUPABASE_ANON_KEY are required")
    if STAGING_PROJECT_REF not in (urllib.parse.urlparse(base).hostname or ""):
        raise RuntimeError(f"Refusing non-staging Supabase project; required project is {STAGING_PROJECT_REF}")
    token = _monitor_access_token(base, anon_key)
    if token == anon_key:
        raise RuntimeError("Scoped Monitor token must differ from anon key")
    return base, anon_key, token


def _upload_attachment(base: str, anon_key: str, token: str, attachment: AttachmentRecord) -> str:
    if not attachment.local_path or not attachment.source_hash:
        return ""
    path = Path(attachment.local_path)
    if not path.is_file() or path.stat().st_size > 10 * 1024 * 1024:
        return ""
    safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", attachment.filename)[:120] or "attachment"
    object_path = f"{attachment.source_hash}/{safe_name}"
    quoted = urllib.parse.quote(object_path, safe="/")
    request = urllib.request.Request(
        f"{base}/storage/v1/object/pdc-email-intake-private/{quoted}",
        data=path.read_bytes(), method="POST",
        headers={"apikey": anon_key, "Authorization": f"Bearer {token}",
                 "Content-Type": attachment.content_type or "application/octet-stream", "x-upsert": "false"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status not in {200, 201}:
                raise RuntimeError(f"Attachment upload returned HTTP {response.status}")
    except urllib.error.HTTPError as exc:
        if exc.code != 409:
            exc.read(4096)
            raise RuntimeError(f"Attachment upload failed HTTP {exc.code}") from exc
    return f"pdc-email-intake-private/{object_path}"


def post_to_supabase(intake: IntakeMessage) -> None:
    base, anon_key, token = supabase_scoped_client()
    attachments: list[dict[str, Any]] = []
    for attachment in intake.attachments:
        if not attachment.source_hash:
            continue
        storage_path = _upload_attachment(base, anon_key, token, attachment)
        attachments.append({
            "file_name": attachment.filename,
            "content_type": attachment.content_type,
            "size_bytes": attachment.size_bytes,
            "source_hash": attachment.source_hash,
            "storage_path": storage_path,
        })
    message = asdict(intake)
    message.pop("attachments", None)
    message.pop("status", None)
    message.pop("processing_result", None)
    message["provider_uid"] = intake.provider_uid
    request = urllib.request.Request(
        f"{base}/rest/v1/rpc/enqueue_pdc_email_intake",
        data=json.dumps({"p_message": message, "p_attachments": attachments}, default=str).encode("utf-8"),
        method="POST",
        headers={"apikey": anon_key, "Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.loads(response.read(1048577).decode("utf-8"))
    except urllib.error.HTTPError as exc:
        exc.read(4096)
        raise RuntimeError(f"Scoped Supabase enqueue failed HTTP {exc.code}") from exc
    if not isinstance(result, dict) or result.get("ok") is not True:
        raise RuntimeError("Scoped Supabase enqueue returned an invalid response")

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read Outlook.com/IMAP email into PMB AI Intake")
    parser.add_argument("--env-file", default="backend/.env", help="Optional local env file; must stay git-ignored")
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--username", default=None)
    parser.add_argument("--password", default=None)
    parser.add_argument("--folder", default=None)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--state", default=str(DEFAULT_STATE))
    parser.add_argument("--attachment-dir", default=str(DEFAULT_ATTACHMENT_DIR))
    parser.add_argument("--evidence-dir", default=str(DEFAULT_EVIDENCE_DIR))
    parser.add_argument("--max-body-chars", type=int, default=int(os.environ.get("IMAP_BRIDGE_MAX_BODY_CHARS", "50000")))
    parser.add_argument("--minimum-uid", type=int, default=None, help="Hard mailbox UID floor; staging pilot requires 471 or later")
    parser.add_argument("--all", action="store_true", help="Read all messages instead of unread only")
    parser.add_argument("--dry-run", action="store_true", help="Print parsed records; do not post to Supabase or update state")
    parser.add_argument("--probe", action="store_true", help="Only test login/folder/search and print counts")
    parser.add_argument("--mark-read", action="store_true", default=os.environ.get("IMAP_BRIDGE_MARK_READ", "false").lower() == "true")
    parser.add_argument("--no-save-attachments", action="store_true")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    load_dotenv(Path(args.env_file))
    # Re-read env-backed args after loading .env, unless explicitly provided.
    args.host = args.host or os.environ.get("IMAP_BRIDGE_HOST") or DEFAULT_IMAP_HOST
    args.port = args.port or int(os.environ.get("IMAP_BRIDGE_PORT", DEFAULT_IMAP_PORT))
    args.username = args.username or os.environ.get("IMAP_BRIDGE_USERNAME") or os.environ.get("OUTLOOK_IMAP_EMAIL") or ""
    args.password = args.password or os.environ.get("IMAP_BRIDGE_PASSWORD") or os.environ.get("OUTLOOK_IMAP_PASSWORD") or ""
    args.folder = args.folder or os.environ.get("IMAP_BRIDGE_FOLDER", "Inbox")
    args.limit = args.limit or int(os.environ.get("IMAP_BRIDGE_LIMIT", "10"))
    args.minimum_uid = args.minimum_uid or int(os.environ.get("IMAP_BRIDGE_MINIMUM_UID", "471"))
    if args.minimum_uid < 471:
        safe_print("Refusing mailbox UID floor below 471 for the staging pilot.")
        return 2
    if not args.username or not args.password:
        safe_print("Missing IMAP credentials. Set IMAP_BRIDGE_USERNAME and IMAP_BRIDGE_PASSWORD in backend/.env or the environment.")
        return 2
    try:
        client = connect_imap(args.host, args.port, args.username, args.password)
    except imaplib.IMAP4.error as exc:
        safe_print(f"IMAP login failed: {exc}")
        safe_print("For Gmail this usually requires IMAP access plus a Google App Password. For Outlook.com this may require IMAP to be enabled and/or an app password if MFA is enabled.")
        return 3
    try:
        uids = search_uids(client, args.folder, unread_only=not args.all, limit=args.limit, minimum_uid=args.minimum_uid)
        if args.probe:
            safe_print(json.dumps({
                "ok": True,
                "host": args.host,
                "folder": args.folder,
                "username": args.username,
                "mode": "all" if args.all else "unread_only",
                "minimum_uid": args.minimum_uid,
                "uids_found_limited": len(uids),
            }, indent=2))
            return 0
        processed = load_processed(Path(args.state))
        new_processed = set(processed)
        posted = 0
        skipped = 0
        records: list[dict[str, Any]] = []
        for uid in uids:
            raw, message = fetch_message(client, uid)
            intake = make_intake(
                uid,
                raw,
                message,
                Path(args.attachment_dir),
                save_attachments_flag=not args.no_save_attachments,
                max_body_chars=args.max_body_chars,
            )
            raw_evidence_path = retain_raw_email(
                raw,
                intake.source_hash,
                Path(args.evidence_dir),
                save=not args.no_save_attachments,
            )
            intake.processing_result.update({
                "raw_email_path": raw_evidence_path,
                "raw_email_sha256": intake.source_hash,
                "attachment_hashes": [item.source_hash for item in intake.attachments if item.source_hash],
            })
            dedupe = intake.graph_message_id or intake.source_hash
            if dedupe in processed:
                skipped += 1
                continue
            if args.dry_run:
                preview = asdict(intake)
                preview["raw_body"] = preview["raw_body"][:500]
                preview["parsed_text"] = preview["parsed_text"][:500]
                records.append(preview)
            else:
                post_to_supabase(intake)
                new_processed.add(dedupe)
                if args.mark_read:
                    mark_seen(client, args.folder, uid)
                posted += 1
        if args.dry_run:
            safe_print(json.dumps({"dry_run": True, "records": records, "skipped_processed": skipped}, indent=2, default=str))
        else:
            save_processed(Path(args.state), new_processed)
            safe_print(json.dumps({"posted": posted, "skipped_processed": skipped, "state": str(args.state)}, indent=2))
        return 0
    finally:
        try:
            client.logout()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
