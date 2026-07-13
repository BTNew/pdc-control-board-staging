#!/usr/bin/env python
"""Local Outlook → PMB AI Intake pilot bridge.

This pilot intentionally uses the Outlook profile already configured on this
Windows PC. It does not store or ask for the mailbox password.

Requirements:
- Classic Microsoft Outlook desktop must be installed and configured.
- The account/folder must be visible in that Outlook profile.
- pywin32 must be available (already present on this PC during initial probe).

The newer web-based "Outlook for Windows" does not expose the COM automation API;
if only that app is installed this script will fail safely during --probe.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import requests
except Exception:  # pragma: no cover - surfaced in probe
    requests = None

try:
    import win32com.client
except Exception:  # pragma: no cover - surfaced in probe
    win32com = None

INTERNET_MESSAGE_ID_DASL = "http://schemas.microsoft.com/mapi/proptag/0x1035001E"
SENDER_SMTP_DASL = "http://schemas.microsoft.com/mapi/proptag/0x5D01001E"
SUPPORTED_ATTACHMENT_EXTENSIONS = {
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".csv", ".txt",
    ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".heic",
}
DEFAULT_PROCESSED_STORE = Path(os.environ.get("OUTLOOK_BRIDGE_STATE", "backend/.outlook_bridge_processed.json"))
DEFAULT_ATTACHMENT_DIR = Path(os.environ.get("OUTLOOK_BRIDGE_ATTACHMENT_DIR", "backend/.outlook_attachments"))


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


def safe_print(value: Any) -> None:
    sys.stdout.write(str(value) + "\n")
    sys.stdout.flush()


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
    path.write_text(json.dumps({"processed": sorted(processed)}, indent=2), encoding="utf-8")


def outlook_namespace():
    if win32com is None:
        raise RuntimeError("pywin32/win32com is not available in this Python environment.")
    try:
        outlook = win32com.client.Dispatch("Outlook.Application")
        return outlook.GetNamespace("MAPI")
    except Exception as exc:
        raise RuntimeError(
            "Classic Outlook COM automation is unavailable. This usually means "
            "classic Microsoft Outlook desktop is not installed/configured, or only "
            "the new web-based Outlook app is present."
        ) from exc


def list_accounts(ns) -> list[str]:
    accounts = []
    try:
        for i in range(1, ns.Accounts.Count + 1):
            acc = ns.Accounts.Item(i)
            accounts.append(str(acc.SmtpAddress or acc.DisplayName or ""))
    except Exception:
        pass
    return accounts


def folder_path(folder) -> str:
    try:
        return str(folder.FolderPath)
    except Exception:
        return str(folder.Name)


def find_store(ns, mailbox: str | None):
    mailbox_l = (mailbox or "").lower().strip()
    fallback = None
    for i in range(1, ns.Folders.Count + 1):
        folder = ns.Folders.Item(i)
        name = str(folder.Name or "")
        if fallback is None:
            fallback = folder
        if mailbox_l and mailbox_l in name.lower():
            return folder
    return fallback


def child_folder(folder, name: str):
    for i in range(1, folder.Folders.Count + 1):
        child = folder.Folders.Item(i)
        if str(child.Name).lower() == name.lower():
            return child
    raise RuntimeError(f"Folder '{name}' not found under {folder_path(folder)}")


def find_folder(ns, mailbox: str | None, folder_name: str):
    store = find_store(ns, mailbox)
    if store is None:
        raise RuntimeError("No Outlook mailbox stores were found.")
    if not folder_name or folder_name.lower() == "inbox":
        try:
            return child_folder(store, "Inbox")
        except Exception:
            # olFolderInbox = 6. This may return default account inbox.
            return ns.GetDefaultFolder(6)
    current = store
    for part in re.split(r"[\\/]", folder_name):
        if part:
            current = child_folder(current, part)
    return current


def prop(item, dasl: str) -> str:
    try:
        return str(item.PropertyAccessor.GetProperty(dasl) or "")
    except Exception:
        return ""


def sender_email(item) -> str:
    smtp = prop(item, SENDER_SMTP_DASL)
    if smtp:
        return smtp.lower()
    try:
        return str(item.SenderEmailAddress or "").lower()
    except Exception:
        return ""


def received_iso(item) -> str | None:
    try:
        value = item.ReceivedTime
        if hasattr(value, "isoformat"):
            return value.isoformat()
        return str(value)
    except Exception:
        return None


def item_body(item, max_chars: int) -> str:
    try:
        body = str(item.Body or "")
    except Exception:
        body = ""
    body = body.replace("\x00", "").strip()
    return body[:max_chars]


def save_attachments(item, message_key: str, attachment_dir: Path, save_files: bool) -> list[str]:
    names: list[str] = []
    try:
        count = item.Attachments.Count
    except Exception:
        return names
    if not save_files:
        for i in range(1, count + 1):
            try:
                names.append(str(item.Attachments.Item(i).FileName or "attachment"))
            except Exception:
                pass
        return names

    target = attachment_dir / re.sub(r"[^A-Za-z0-9_.-]+", "_", message_key)[:80]
    target.mkdir(parents=True, exist_ok=True)
    for i in range(1, count + 1):
        att = item.Attachments.Item(i)
        name = str(att.FileName or f"attachment-{i}")
        names.append(name)
        ext = Path(name).suffix.lower()
        if ext not in SUPPORTED_ATTACHMENT_EXTENSIONS:
            continue
        safe_name = re.sub(r"[^A-Za-z0-9_. -]+", "_", name).strip() or f"attachment-{i}{ext}"
        dest = target / safe_name
        try:
            att.SaveAsFile(str(dest.resolve()))
        except Exception as exc:
            safe_print(f"warning: failed to save attachment {name}: {exc}")
    return names


def to_intake(item, attachment_dir: Path, save_files: bool, max_body_chars: int) -> IntakeMessage:
    entry_id = str(getattr(item, "EntryID", "") or "")
    internet_id = prop(item, INTERNET_MESSAGE_ID_DASL)
    conversation_id = str(getattr(item, "ConversationID", "") or "")
    stable_key = internet_id or entry_id or hashlib.sha256(str(datetime.now(timezone.utc)).encode()).hexdigest()
    body = item_body(item, max_body_chars)
    attachments = save_attachments(item, stable_key, attachment_dir, save_files)
    subject = str(getattr(item, "Subject", "") or "")
    sender_name = str(getattr(item, "SenderName", "") or "")
    sender = sender_email(item)
    source_hash = hashlib.sha256(json.dumps({
        "internet_message_id": internet_id,
        "subject": subject,
        "sender": sender,
        "received_at": received_iso(item),
        "body": body,
        "attachments": attachments,
    }, sort_keys=True).encode("utf-8", "ignore")).hexdigest()
    return IntakeMessage(
        graph_message_id=f"outlook-com:{stable_key}",
        graph_thread_id=conversation_id,
        internet_message_id=internet_id,
        subject=subject,
        sender_email=sender,
        sender_name=sender_name,
        received_at=received_iso(item),
        attachment_names=attachments,
        raw_body=body,
        parsed_text=body,
        source_hash=source_hash,
        processing_result={"source": "local_outlook_bridge", "attachments_saved": save_files},
    )


def iter_messages(folder, limit: int, unread_only: bool):
    items = folder.Items
    try:
        items.Sort("[ReceivedTime]", True)
    except Exception:
        pass
    found = 0
    for i in range(1, items.Count + 1):
        item = items.Item(i)
        # MailItem class = 43
        try:
            if int(item.Class) != 43:
                continue
        except Exception:
            continue
        if unread_only:
            try:
                if not bool(item.UnRead):
                    continue
            except Exception:
                pass
        yield item
        found += 1
        if found >= limit:
            break


def supabase_headers(service_key: str) -> dict[str, str]:
    return {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=representation",
    }


def post_to_supabase(message: IntakeMessage, supabase_url: str, service_key: str) -> None:
    if requests is None:
        raise RuntimeError("requests module is not available")
    endpoint = supabase_url.rstrip("/") + "/rest/v1/ai_email_intake?on_conflict=graph_message_id"
    payload = asdict(message)
    response = requests.post(endpoint, headers=supabase_headers(service_key), data=json.dumps(payload), timeout=30)
    if response.status_code >= 300:
        raise RuntimeError(f"Supabase insert failed: HTTP {response.status_code}: {response.text[:500]}")


def probe(args) -> int:
    ns = outlook_namespace()
    safe_print("Outlook COM: available")
    safe_print("Accounts: " + json.dumps(list_accounts(ns)))
    folder = find_folder(ns, args.mailbox, args.folder)
    safe_print("Folder: " + folder_path(folder))
    sample = []
    for item in iter_messages(folder, min(args.limit, 5), args.unread_only):
        sample.append({
            "subject": str(getattr(item, "Subject", "") or "")[:120],
            "sender": sender_email(item),
            "received_at": received_iso(item),
            "attachments": int(getattr(item.Attachments, "Count", 0) or 0),
        })
    safe_print("Sample: " + json.dumps(sample, indent=2))
    return 0


def run_once(args) -> int:
    ns = outlook_namespace()
    folder = find_folder(ns, args.mailbox, args.folder)
    processed_path = Path(args.state)
    processed = load_processed(processed_path)
    supabase_url = os.environ.get("SUPABASE_URL", "")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not args.dry_run and (not supabase_url or not service_key):
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required unless --dry-run is used.")

    sent = 0
    skipped = 0
    for item in iter_messages(folder, args.limit, args.unread_only):
        message = to_intake(item, Path(args.attachment_dir), args.save_attachments, args.max_body_chars)
        if message.source_hash in processed:
            skipped += 1
            continue
        if args.dry_run:
            safe_print(json.dumps({**asdict(message), "raw_body": message.raw_body[:500]}, indent=2))
        else:
            post_to_supabase(message, supabase_url, service_key)
            processed.add(message.source_hash)
            sent += 1
            if args.mark_read:
                try:
                    item.UnRead = False
                    item.Save()
                except Exception as exc:
                    safe_print(f"warning: failed to mark read: {exc}")
    if not args.dry_run:
        save_processed(processed_path, processed)
    safe_print(f"done: sent={sent} skipped={skipped} dry_run={args.dry_run}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local Outlook to PMB AI Intake pilot bridge")
    parser.add_argument("--mailbox", default=os.environ.get("OUTLOOK_BRIDGE_MAILBOX", "nwmgreception@outlook.com"))
    parser.add_argument("--folder", default=os.environ.get("OUTLOOK_BRIDGE_FOLDER", "Inbox"))
    parser.add_argument("--limit", type=int, default=int(os.environ.get("OUTLOOK_BRIDGE_LIMIT", "10")))
    parser.add_argument("--unread-only", action="store_true", default=os.environ.get("OUTLOOK_BRIDGE_UNREAD_ONLY", "true").lower() == "true")
    parser.add_argument("--save-attachments", action="store_true", default=os.environ.get("OUTLOOK_BRIDGE_SAVE_ATTACHMENTS", "true").lower() == "true")
    parser.add_argument("--attachment-dir", default=str(DEFAULT_ATTACHMENT_DIR))
    parser.add_argument("--state", default=str(DEFAULT_PROCESSED_STORE))
    parser.add_argument("--max-body-chars", type=int, default=int(os.environ.get("OUTLOOK_BRIDGE_MAX_BODY_CHARS", "50000")))
    parser.add_argument("--mark-read", action="store_true", default=os.environ.get("OUTLOOK_BRIDGE_MARK_READ", "false").lower() == "true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--probe", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.probe:
            return probe(args)
        return run_once(args)
    except Exception as exc:
        safe_print(f"ERROR: {type(exc).__name__}: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
