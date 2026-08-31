"""Optional read-only IMAP transport fallback for the successor.

Disabled unless --enable is supplied. It retains evidence only and never marks
messages seen, calls Supabase, interprets PDC content, or sends mail.
"""
from __future__ import annotations

import argparse
import email
import imaplib
import json
import os
import ssl
from pathlib import Path
from typing import Any

from .pdc_email_ai_successor_intake import EvidenceStore


def _required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing secure connector setting: {name}")
    return value


def poll_once(store: EvidenceStore, *, host: str, username: str, password: str, folder: str = "INBOX", limit: int = 10) -> list[dict[str, Any]]:
    if not 1 <= limit <= 50:
        raise ValueError("limit must be between 1 and 50")
    client = imaplib.IMAP4_SSL(host, 993, ssl_context=ssl.create_default_context())
    try:
        client.login(username, password)
        status, _data = client.select(f'"{folder}"', readonly=True)
        if status != "OK":
            raise RuntimeError("read-only mailbox selection failed")
        status, data = client.uid("SEARCH", None, "ALL")
        if status != "OK":
            raise RuntimeError("read-only mailbox search failed")
        uids = (data[0] or b"").decode("ascii", errors="strict").split()[-limit:]
        results: list[dict[str, Any]] = []
        for uid in uids:
            status, fetched = client.uid("FETCH", uid, "(RFC822)")
            if status != "OK":
                raise RuntimeError(f"read-only message fetch failed for UID {uid}")
            raw = b"".join(item[1] for item in fetched if isinstance(item, tuple))
            if not raw:
                raise RuntimeError(f"read-only message fetch returned no bytes for UID {uid}")
            message = email.message_from_bytes(raw)
            results.append(store.capture(raw, mailbox=username, provider_uid=f"imap_uid:{uid}", received_at=None))
            results[-1] = {"receipt_id": results[-1]["receipt_id"], "source_digest": results[-1]["source_digest"], "message_id": str(message.get("Message-ID") or "")}
        return results
    finally:
        try:
            client.close()
        finally:
            client.logout()


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only PDC successor evidence poller")
    parser.add_argument("--enable", action="store_true", help="explicitly permit one read-only mailbox poll")
    parser.add_argument("--evidence-root", type=Path, default=Path("backend/.pdc_email_ai_successor_evidence"))
    parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args()
    if not args.enable:
        print(json.dumps({"ok": True, "enabled": False, "contacted_mailbox": False}, sort_keys=True))
        return 0
    host = os.environ.get("PDC_AI_IMAP_HOST", "outlook.office365.com")
    results = poll_once(
        EvidenceStore(args.evidence_root),
        host=host,
        username=_required("PDC_AI_IMAP_USERNAME"),
        password=_required("PDC_AI_IMAP_PASSWORD"),
        limit=args.limit,
    )
    print(json.dumps({"ok": True, "enabled": True, "contacted_mailbox": True, "receipts": results}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
