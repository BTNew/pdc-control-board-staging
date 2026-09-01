"""Evidence-only RFC822 capture for the isolated PDC successor.

This layer knows nothing about PDC vehicles, actions, SQL or workflow rules. It
retains bytes and transport metadata, then hands a receipt to the interpreter.
"""
from __future__ import annotations

import email
import hashlib
import html
import json
import os
import re
import tempfile
import uuid
from email.header import decode_header, make_header
from email.message import Message
from email.policy import default
from email.utils import getaddresses, parsedate_to_datetime
from pathlib import Path
from typing import Any, Mapping

MAX_EMAIL_BYTES = 25 * 1024 * 1024
MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
MAX_TEXT_CHARS = 500_000
_MATERIALIZABLE_EXTENSIONS = frozenset({
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".csv", ".txt",
    ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp",
})
_UNSAFE_EXTENSIONS = frozenset({
    ".bat", ".cmd", ".com", ".dll", ".exe", ".js", ".jse", ".msi",
    ".ps1", ".scr", ".sh", ".vbe", ".vbs", ".wsf", ".zip", ".7z",
})


class EvidenceConflict(ValueError):
    """The same source digest was presented with different receipt metadata."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def bounded_retry_delay(attempt: int) -> int:
    if isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 0:
        raise ValueError("attempt must be a non-negative integer")
    return min(300, 2**min(attempt, 9))


def decode_header_value(value: str | None) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except (LookupError, UnicodeError, ValueError):
        return str(value)


def safe_filename(value: str | None) -> str:
    """Return a leaf filename safe for a content-addressed evidence path."""
    text = decode_header_value(value) or "attachment"
    text = text.replace("/", "_").replace("\\", "_")
    text = re.sub(r"[^A-Za-z0-9._ -]+", "_", text).strip(" .")
    text = re.sub(r"\.{2,}", ".", text)
    return (text[:160] or "attachment").lstrip(".") or "attachment"


def _html_to_text(value: str) -> str:
    value = re.sub(r"(?is)<(script|style).*?>.*?</\\1>", " ", value or "")
    value = re.sub(r"(?i)<br\s*/?>", "\n", value)
    value = re.sub(r"(?i)</p>", "\n", value)
    return re.sub(r"[ \t]+", " ", html.unescape(re.sub(r"<[^>]+>", " ", value))).strip()


def _part_text(part: Message) -> str:
    try:
        value = part.get_content()
        if isinstance(value, bytes):
            value = value.decode(part.get_content_charset() or "utf-8", errors="replace")
        return str(value)
    except (LookupError, UnicodeError, TypeError):
        payload = part.get_payload(decode=True) or b""
        return payload.decode(part.get_content_charset() or "utf-8", errors="replace")


def _correspondence(message: Message) -> str:
    plain: list[str] = []
    rich: list[str] = []
    parts = message.walk() if message.is_multipart() else [message]
    for part in parts:
        if part.get_content_disposition() == "attachment":
            continue
        content_type = part.get_content_type()
        if content_type not in {"text/plain", "text/html"}:
            continue
        value = _part_text(part)
        (plain if content_type == "text/plain" else rich).append(value)
    text = "\n\n".join(item.strip() for item in plain if item.strip())
    if not text:
        text = _html_to_text("\n\n".join(rich))
    return re.sub(r"\n{4,}", "\n\n\n", text).strip()[:MAX_TEXT_CHARS]


def _received_at(message: Message) -> str | None:
    raw = message.get("Date")
    if not raw:
        return None
    try:
        parsed = parsedate_to_datetime(raw)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=__import__("datetime").timezone.utc)
        return parsed.isoformat()
    except (TypeError, ValueError, OverflowError):
        return None


def _sender(message: Message) -> dict[str, str]:
    addresses = getaddresses(message.get_all("From", []))
    if not addresses:
        return {"email": "", "name": ""}
    name, address = addresses[0]
    return {"email": address.strip().lower(), "name": decode_header_value(name).strip()}


def _attachment_bytes(message: Message) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    parts = message.walk() if message.is_multipart() else []
    for ordinal, part in enumerate(parts, 1):
        filename = part.get_filename()
        if part.get_content_disposition() != "attachment" and not filename:
            continue
        payload = part.get_payload(decode=True) or b""
        rows.append(
            {
                "ordinal": ordinal,
                "filename": safe_filename(filename),
                "content_type": (part.get_content_type() or "application/octet-stream").lower(),
                "size_bytes": len(payload),
                "digest": hashlib.sha256(payload).hexdigest() if payload else "",
                "_bytes": payload,
            }
        )
    return rows


def _attachment_materializable(row: Mapping[str, Any]) -> bool:
    filename = str(row.get("filename") or "").casefold()
    extension = Path(filename).suffix
    content_type = str(row.get("content_type") or "").casefold()
    return (
        extension in _MATERIALIZABLE_EXTENSIONS
        and extension not in _UNSAFE_EXTENSIONS
        and content_type not in {"application/x-msdownload", "application/x-sh", "text/javascript"}
    )


def capture_rfc822_evidence(
    raw_bytes: bytes,
    *,
    mailbox: str,
    provider_uid: str,
    received_at: str | None = None,
    transport_metadata: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    if not isinstance(raw_bytes, bytes) or not 1 <= len(raw_bytes) <= MAX_EMAIL_BYTES:
        raise ValueError("RFC822 source is empty or exceeds the configured limit")
    if not isinstance(mailbox, str) or not mailbox.strip() or len(mailbox) > 320:
        raise ValueError("mailbox is invalid")
    if not isinstance(provider_uid, str) or not 1 <= len(provider_uid.strip()) <= 512:
        raise ValueError("provider UID is invalid")
    message = email.message_from_bytes(raw_bytes, policy=default)
    source_digest = hashlib.sha256(raw_bytes).hexdigest()
    sender = _sender(message)
    attachments = _attachment_bytes(message)
    public_attachments = [{key: value for key, value in row.items() if key != "_bytes"} for row in attachments]
    message_id = decode_header_value(message.get("Message-ID"))
    thread_id = decode_header_value(message.get("References") or message.get("In-Reply-To")) or message_id or provider_uid.strip()
    transport = dict(transport_metadata or {})
    def _assert_safe_metadata(value: Any, path: str = "transport") -> None:
        if isinstance(value, Mapping):
            for key, child in value.items():
                if not isinstance(key, str) or key.casefold() in {"password", "secret", "token", "credential"}:
                    raise ValueError(f"{path} contains an unsafe key")
                _assert_safe_metadata(child, f"{path}.{key}")
        elif isinstance(value, (bytes, bytearray)):
            raise ValueError(f"{path} contains raw bytes")
    _assert_safe_metadata(transport)
    base = {
        "provider_uid": provider_uid.strip(),
        "mailbox": mailbox.strip().lower(),
        "message_id": message_id,
        "thread_id": thread_id,
        "internet_message_id": message_id,
        "subject": decode_header_value(message.get("Subject")),
        "sender": sender,
        "received_at": received_at or _received_at(message),
        "transport": transport,
        "correspondence": _correspondence(message),
        "source_digest": source_digest,
        "attachments": public_attachments,
    }
    evidence_digest = hashlib.sha256(canonical_json(base).encode("utf-8")).hexdigest()
    return {
        "receipt_id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"pdc-email-ai:{source_digest}")),
        "source_digest": source_digest,
        "evidence_digest": evidence_digest,
        "status": "RECEIVED",
        "duplicate": False,
        "transport_attempts": 0,
        **base,
        "_raw_bytes": raw_bytes,
        "_attachments": attachments,
    }


def _atomic_create(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(str(path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        if path.read_bytes() != content:
            raise EvidenceConflict(f"evidence path already contains different bytes: {path.name}")
        return
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
    except BaseException:
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        raise


class EvidenceStore:
    """Content-addressed local evidence store; never applies PDC changes."""

    def __init__(self, root: Path):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def capture(
        self,
        raw_bytes: bytes,
        *,
        mailbox: str,
        provider_uid: str,
        received_at: str | None = None,
        transport_metadata: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        evidence = capture_rfc822_evidence(
            raw_bytes,
            mailbox=mailbox,
            provider_uid=provider_uid,
            received_at=received_at,
            transport_metadata=transport_metadata,
        )
        receipt_path = self.root / "receipts" / f"{evidence['source_digest']}.json"
        if receipt_path.exists():
            previous = json.loads(receipt_path.read_text(encoding="utf-8"))
            if previous.get("evidence_digest") != evidence["evidence_digest"] or previous.get("provider_uid") != evidence["provider_uid"]:
                raise EvidenceConflict("source digest was presented with conflicting metadata")
            return {**previous, "duplicate": True}

        evidence.pop("_raw_bytes", None)
        source_path = Path("source") / f"{evidence['source_digest']}.eml"
        _atomic_create(self.root / source_path, raw_bytes)
        stored_attachments: list[dict[str, Any]] = []
        for row in evidence.pop("_attachments"):
            payload = row.pop("_bytes")
            if not payload or row["size_bytes"] > MAX_ATTACHMENT_BYTES:
                row["status"] = "REJECTED_BOUNDED"
                stored_attachments.append(row)
                continue
            if not _attachment_materializable(row):
                row["status"] = "REJECTED_UNSUPPORTED"
                stored_attachments.append(row)
                continue
            path = Path("attachments") / evidence["source_digest"] / f"{row['digest'][:16]}-{row['filename']}"
            _atomic_create(self.root / path, payload)
            row["path"] = str(path).replace("\\", "/")
            row["status"] = "RETAINED"
            stored_attachments.append(row)
        evidence["attachments"] = stored_attachments
        evidence["source_path"] = str(source_path).replace("\\", "/")
        evidence["receipt_schema_version"] = "pdc-email-ai-evidence-v1"
        receipt_bytes = (canonical_json(evidence) + "\n").encode("utf-8")
        _atomic_create(receipt_path, receipt_bytes)
        return evidence


__all__ = ["EvidenceConflict", "EvidenceStore", "bounded_retry_delay", "capture_rfc822_evidence", "safe_filename"]
