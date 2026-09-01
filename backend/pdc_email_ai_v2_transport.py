"""Read-only mailbox transport and immutable evidence handoff for v2.

Only the transport talks IMAP. It selects folders read-only, fetches with
BODY.PEEK, never issues STORE/EXPUNGE or changes flags, and enqueues references
to content-addressed evidence after a successful capture. The returned rows are
safe planner inputs; they contain no credentials or mutation instructions.
"""
from __future__ import annotations

import email
import imaplib
import re
import ssl
from dataclasses import dataclass
from email.message import Message
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping

from .pdc_email_ai_successor_intake import EvidenceStore
from .pdc_email_ai_v2_queue import DurableQueue


@dataclass(frozen=True)
class MailboxCursor:
    folder: str
    uidvalidity: int
    high_water_uid: int = 0


class MailboxTransportError(RuntimeError):
    """A bounded read-only transport operation failed."""


def _response_uidvalidity(client: Any) -> int:
    response = client.response("UIDVALIDITY") if hasattr(client, "response") else (None, None)
    values = response[1] if isinstance(response, tuple) and len(response) > 1 else None
    raw = values[0] if isinstance(values, list) and values else values
    match = re.search(rb"\d+", raw if isinstance(raw, bytes) else str(raw or "").encode())
    if not match:
        raise MailboxTransportError("mailbox did not provide UIDVALIDITY")
    return int(match.group(0))


def _flags(fetch_data: Any) -> bytes:
    chunks: list[bytes] = []
    for item in fetch_data or []:
        if isinstance(item, tuple) and isinstance(item[0], bytes):
            chunks.append(item[0])
        elif isinstance(item, bytes):
            chunks.append(item)
    return b" ".join(chunks)


def _raw_message(fetch_data: Any) -> bytes:
    chunks = [item[1] for item in fetch_data or [] if isinstance(item, tuple) and len(item) > 1 and isinstance(item[1], bytes)]
    return b"".join(chunks)


def _internaldate(fetch_data: Any) -> str | None:
    meta = _flags(fetch_data).decode("ascii", errors="replace")
    match = re.search(r'INTERNALDATE\s+"([^"]+)"', meta, re.I)
    return match.group(1) if match else None


def _header_message_id(raw: bytes) -> str:
    try:
        return str(email.message_from_bytes(raw).get("Message-ID") or "")
    except Exception:
        return ""


class ReadOnlyImapTransport:
    """Bounded IMAP reader; evidence storage and queue are injected dependencies."""

    def __init__(
        self,
        evidence_store: EvidenceStore,
        queue: DurableQueue,
        *,
        client_factory: Callable[..., Any] | None = None,
        port: int = 993,
        max_messages: int = 50,
    ) -> None:
        if not 1 <= max_messages <= 200:
            raise ValueError("max_messages must be between 1 and 200")
        self.evidence_store = evidence_store
        self.queue = queue
        self.client_factory = client_factory or imaplib.IMAP4_SSL
        self.port = port
        self.max_messages = max_messages

    def poll(
        self,
        *,
        host: str,
        username: str,
        password: str,
        cursors: Iterable[MailboxCursor],
    ) -> list[dict[str, Any]]:
        if not host.strip() or not username.strip() or not password:
            raise ValueError("host, username and password are required")
        cursor_list = list(cursors)
        if not cursor_list:
            return []
        client = self.client_factory(host, self.port, ssl_context=ssl.create_default_context())
        results: list[dict[str, Any]] = []
        try:
            status, _ = client.login(username, password)
            if status != "OK":
                raise MailboxTransportError("mailbox login failed")
            for cursor in cursor_list:
                results.extend(self._poll_folder(client, username, cursor))
            return results
        finally:
            try:
                client.close()
            except Exception:
                pass
            try:
                client.logout()
            except Exception:
                pass

    def _poll_folder(self, client: Any, mailbox: str, cursor: MailboxCursor) -> list[dict[str, Any]]:
        if not cursor.folder.strip() or cursor.uidvalidity < 0 or cursor.high_water_uid < 0:
            raise ValueError("invalid mailbox cursor")
        status, _ = client.select(f'"{cursor.folder}"', readonly=True)
        if status != "OK":
            raise MailboxTransportError(f"read-only selection failed for {cursor.folder}")
        observed_uidvalidity = _response_uidvalidity(client)
        if cursor.uidvalidity and observed_uidvalidity != cursor.uidvalidity:
            raise MailboxTransportError("UIDVALIDITY changed; cursor requires re-establishment")
        start_uid = cursor.high_water_uid + 1
        status, data = client.uid("SEARCH", None, "UID", f"{start_uid}:*")
        if status != "OK":
            raise MailboxTransportError(f"read-only UID search failed for {cursor.folder}")
        raw_uids = (data[0] if data else b"").split()
        uids = [int(value) for value in raw_uids if value.isdigit() and int(value) >= start_uid]
        uids = uids[: self.max_messages]
        rows: list[dict[str, Any]] = []
        for uid in uids:
            scoped_uid = f"{observed_uidvalidity}:{uid}"
            before_status, before_data = client.uid("FETCH", str(uid), "(FLAGS)")
            if before_status != "OK":
                raise MailboxTransportError(f"flags read failed for {scoped_uid}")
            status, fetched = client.uid("FETCH", str(uid), "(UID INTERNALDATE FLAGS BODY.PEEK[])")
            if status != "OK":
                raise MailboxTransportError(f"read-only message fetch failed for {scoped_uid}")
            raw = _raw_message(fetched)
            if not raw:
                raise MailboxTransportError(f"empty message fetch for {scoped_uid}")
            after_status, after_data = client.uid("FETCH", str(uid), "(FLAGS)")
            if after_status != "OK":
                raise MailboxTransportError(f"post-fetch flags read failed for {scoped_uid}")
            flags_unchanged = _flags(before_data) == _flags(after_data)
            if not flags_unchanged:
                raise MailboxTransportError(f"mailbox flags changed during read-only fetch for {scoped_uid}")
            evidence = self.evidence_store.capture(
                raw,
                mailbox=mailbox,
                provider_uid=f"imap:{cursor.folder}:{scoped_uid}",
                received_at=_internaldate(fetched),
                transport_metadata={
                    "folder": cursor.folder,
                    "uidvalidity": observed_uidvalidity,
                    "uid": uid,
                    "flags_unchanged": True,
                    "read_only": True,
                },
            )
            receipt_path = str((self.evidence_store.root / "receipts" / f"{evidence['source_digest']}.json").resolve())
            queued = self.queue.enqueue(
                source_digest=evidence["source_digest"],
                receipt_path=receipt_path,
                mailbox=mailbox,
                folder=cursor.folder,
                uidvalidity=observed_uidvalidity,
                uid=uid,
            )
            self.queue.advance_checkpoint(
                folder=cursor.folder,
                uidvalidity=observed_uidvalidity,
                uid=uid,
                source_digest=evidence["source_digest"],
            )
            rows.append({
                "provider_uid": evidence["provider_uid"],
                "source_digest": evidence["source_digest"],
                "evidence_digest": evidence["evidence_digest"],
                "receipt_id": evidence["receipt_id"],
                "message_id": _header_message_id(raw),
                "folder": cursor.folder,
                "uidvalidity": observed_uidvalidity,
                "uid": uid,
                "flags_unchanged": True,
                "queued": not bool(queued.get("duplicate")),
                "queue_item_key": queued["item_key"],
            })
        return rows


def build_planner_input(receipt: Mapping[str, Any], attachments: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Build a complete, detached planner envelope from retained evidence.

    Every correspondence clause and attachment is represented. The planner must
    assign a typed disposition later; this function never drops unknown text or
    invents an action from it.
    """
    receipt_id = str(receipt.get("receipt_id") or "")
    source_digest = str(receipt.get("source_digest") or "")
    evidence_digest = str(receipt.get("evidence_digest") or "")
    if not receipt_id or len(source_digest) != 64 or len(evidence_digest) != 64:
        raise ValueError("receipt is missing immutable identity")
    attachment_rows: list[dict[str, Any]] = []
    for index, item in enumerate(attachments, 1):
        row = dict(item)
        digest = str(row.get("digest") or row.get("source_digest") or "")
        if len(digest) != 64:
            raise ValueError(f"attachment {index} is missing a SHA-256 digest")
        attachment_rows.append({
            "attachment_index": index,
            "digest": digest,
            "filename": str(row.get("filename") or "attachment"),
            "content_type": str(row.get("content_type") or "application/octet-stream"),
            "extraction_status": str(row.get("extraction_status") or "UNEXTRACTED"),
            "extracted_text": str(row.get("extracted_text") or ""),
            "evidence_ref": f"attachment:{digest}",
        })
    return {
        "schema_version": "pdc-email-ai-planner-input-v1",
        "source": {
            "receipt_id": receipt_id,
            "source_digest": source_digest,
            "evidence_digest": evidence_digest,
            "provider_uid": str(receipt.get("provider_uid") or ""),
            "mailbox": str(receipt.get("mailbox") or ""),
            "thread_id": str(receipt.get("thread_id") or ""),
            "message_id": str(receipt.get("message_id") or ""),
            "received_at": receipt.get("received_at"),
        },
        "correspondence": str(receipt.get("correspondence") or ""),
        "attachments": attachment_rows,
        "instruction_accounting": {
            "status": "REQUIRES_TYPED_DISPOSITION",
            "dispositions": ["PLANNED", "APPLIED", "NO_OP", "ALREADY_SATISFIED", "REVIEW", "UNSUPPORTED", "CONFLICT"],
            "unclassified_text_must_be_preserved": True,
        },
        "planner_versions": {
            "input_schema": "pdc-email-ai-planner-input-v1",
            "taxonomy": "pdc-operation-taxonomy-proposed/v1",
            "ruleset": "pdc-business-rules-v2",
        },
    }


__all__ = ["MailboxCursor", "MailboxTransportError", "ReadOnlyImapTransport", "build_planner_input"]
