#!/usr/bin/env python3
"""External .44 runtime adapter for the authenticated staging monitor lane.

The sealed release is never edited or imported as an executable entrypoint.  This
adapter reuses only its pure IMAP/message helpers, validates the complete MIME
set, and exposes the exact four-PDF projection needed by the append-only 673
staging successor.  No mailbox or Supabase operation occurs unless a caller
explicitly invokes one of the injected side-effect callbacks.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

EXPECTED_RELEASE_VERSION = "2026.08.44"
EXPECTED_RELEASE_NAME = "pdc-monitor-staging-m502-2026.08.44"
EXPECTED_ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EXPECTED_ACTOR_EMAIL = "sales@broometoyota.com.au"
EXPECTED_GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
EXPECTED_SOURCE_SHA = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
EXPECTED_MANIFEST_SHA256 = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
EXPECTED_PLANNER_SHA256 = "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"
EXPECTED_TRUST_SHA256 = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
JOB_CARD_SHA256 = "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4"
EXPECTED_MIME_PARTS = 7
EXPECTED_BUSINESS_PDFS = 4
PRIVATE_STORAGE_PREFIX = "pdc-email-intake-private/"
_HASH = re.compile(r"^[a-f0-9]{64}$")


class RuntimeCompatibilityError(RuntimeError):
    """Raised whenever the compatibility contract cannot be proven."""


def _value(item: Any, name: str, default: Any = "") -> Any:
    if isinstance(item, Mapping):
        return item.get(name, default)
    return getattr(item, name, default)


def _copy_part(item: Any, ordinal: int) -> dict[str, Any]:
    filename = str(_value(item, "filename", _value(item, "file_name", "")) or "")
    content_type = str(_value(item, "content_type", "") or "").split(";", 1)[0].strip().lower()
    source_hash = str(_value(item, "source_hash", "") or "").strip().lower()
    status = str(_value(item, "validation_status", "verified") or "").strip().lower()
    attachment_id = str(_value(item, "attachment_id", _value(item, "id", "")) or "")
    if not filename or not attachment_id or not _HASH.fullmatch(source_hash):
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_SET_MISMATCH")
    if status != "verified":
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_SET_MISMATCH")
    if content_type not in {"application/pdf", "image/png", "image/jpeg"}:
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_MIME_SET_INVALID")
    suffix = Path(filename).suffix.lower()
    if content_type == "application/pdf" and suffix != ".pdf":
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_MIME_SET_INVALID")
    if content_type != "application/pdf" and suffix not in {".png", ".jpg", ".jpeg"}:
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_MIME_SET_INVALID")
    return {
        "attachment_id": attachment_id,
        "filename": filename,
        "content_type": content_type,
        "source_hash": source_hash,
        "validation_status": status,
        "ordinal": ordinal,
    }


def select_authenticated_business_pdfs(attachments: Sequence[Any]) -> dict[str, Any]:
    """Validate all seven parts and select the four PDF business documents.

    The returned ``all_parts`` is the complete retained evidence projection;
    ``business_pdfs`` is only the deterministic canonical-import projection.
    Selection is stable in received attachment order and the Job Card is bound
    by its exact content hash, never by a filename or caller-supplied flag.
    """
    if not isinstance(attachments, Sequence) or isinstance(attachments, (str, bytes)):
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_SET_MISMATCH")
    if len(attachments) != EXPECTED_MIME_PARTS:
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_SET_MISMATCH")
    all_parts = [_copy_part(item, ordinal) for ordinal, item in enumerate(attachments)]
    ids = [item["attachment_id"] for item in all_parts]
    if len(ids) != len(set(ids)):
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_SET_MISMATCH")
    business_pdfs = [item for item in all_parts if item["content_type"] == "application/pdf"]
    if len(business_pdfs) != EXPECTED_BUSINESS_PDFS:
        raise RuntimeCompatibilityError("PDC_673_ATTACHMENT_SET_MISMATCH")
    job_cards = [item for item in business_pdfs if item["source_hash"] == JOB_CARD_SHA256]
    if len(job_cards) != 1:
        raise RuntimeCompatibilityError("PDC_673_JOB_CARD_HASH_MISMATCH")
    if sum(item["source_hash"] == JOB_CARD_SHA256 for item in all_parts) != 1:
        raise RuntimeCompatibilityError("PDC_673_JOB_CARD_HASH_MISMATCH")
    return {
        "observed_mime_part_count": len(all_parts),
        "retained_authenticated_attachment_count": len(business_pdfs),
        "all_mime_parts_retained": True,
        "all_parts": all_parts,
        "business_pdfs": business_pdfs,
        "business_pdf_ids": [item["attachment_id"] for item in business_pdfs],
        "job_card": job_cards[0],
        "qualifying_attachment_sha256": JOB_CARD_SHA256,
    }


def build_enqueue_projection(intake: Mapping[str, Any], attachments: Sequence[Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Build the full evidence enqueue payload without dropping image parts."""
    selection = select_authenticated_business_pdfs(attachments)
    message = dict(intake)
    metadata = dict(message.get("processing_result") or {})
    metadata["mime_selection"] = {
        "observed_mime_part_count": selection["observed_mime_part_count"],
        "retained_authenticated_attachment_count": selection["retained_authenticated_attachment_count"],
        "business_pdf_ids": selection["business_pdf_ids"],
        "qualifying_attachment_sha256": JOB_CARD_SHA256,
        "all_mime_parts_retained": True,
    }
    message["processing_result"] = metadata
    payload = []
    for part in selection["all_parts"]:
        payload.append({
            "file_name": part["filename"],
            "content_type": part["content_type"],
            "size_bytes": int(_value(attachments[part["ordinal"]], "size_bytes", 0) or 0),
            "source_hash": part["source_hash"],
            "storage_path": str(_value(attachments[part["ordinal"]], "storage_path", "") or ""),
            "reported_content_type": str(_value(attachments[part["ordinal"]], "reported_content_type", part["content_type"]) or ""),
            "validation_status": "verified",
            "validation_error": "",
        })
    return message, {"all_parts": payload, "selection": selection}


def load_sealed_imap_module(release_root: Path):
    """Load pure helpers from the exact sealed .44 IMAP module only."""
    release_root = release_root.resolve(strict=True)
    path = (release_root / "backend" / "imap_bridge.py").resolve(strict=True)
    if release_root not in path.parents or path.is_symlink() or not path.is_file():
        raise RuntimeCompatibilityError("PDC_673_SEALED_IMAP_PATH_INVALID")
    spec = importlib.util.spec_from_file_location("pdc_sealed_044_imap_bridge", path)
    if spec is None or spec.loader is None:
        raise RuntimeCompatibilityError("PDC_673_SEALED_IMAP_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_intake_from_fetched_message(
    release_root: Path,
    uid: str,
    raw_bytes: bytes,
    message: Any,
    attachment_dir: Path,
    save_attachments: bool = True,
    max_body_chars: int = 50000,
) -> tuple[Any, dict[str, Any]]:
    """Use sealed parsing, then apply the external 7/4 contract."""
    sealed = load_sealed_imap_module(release_root)
    intake = sealed.make_intake(uid, raw_bytes, message, attachment_dir, save_attachments, max_body_chars)
    selection = select_authenticated_business_pdfs(intake.attachments)
    intake.processing_result = dict(intake.processing_result)
    intake.processing_result["mime_selection"] = {
        "observed_mime_part_count": selection["observed_mime_part_count"],
        "retained_authenticated_attachment_count": selection["retained_authenticated_attachment_count"],
        "business_pdf_ids": selection["business_pdf_ids"],
        "qualifying_attachment_sha256": JOB_CARD_SHA256,
        "all_mime_parts_retained": True,
    }
    return intake, selection


def process_fetched_message(
    release_root: Path,
    uid: str,
    raw_bytes: bytes,
    message: Any,
    attachment_dir: Path,
    enqueue: Callable[[Any, dict[str, Any]], Any],
    save_attachments: bool = True,
) -> Any:
    """Inject the caller's protected enqueue operation after validation only."""
    intake, selection = build_intake_from_fetched_message(
        release_root, uid, raw_bytes, message, attachment_dir, save_attachments
    )
    return enqueue(intake, {"all_parts": intake.attachments, "selection": selection})


def fixture_result(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    selection = select_authenticated_business_pdfs(data["attachments"])
    return {"ok": True, "adapter": "pdc_authenticated_monitor_runtime_adapter_673", **{
        key: selection[key] for key in (
            "observed_mime_part_count", "retained_authenticated_attachment_count",
            "all_mime_parts_retained", "business_pdf_ids", "qualifying_attachment_sha256",
        )
    }}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a synthetic .44 7/4 attachment set")
    parser.add_argument("--fixture", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(fixture_result(args.fixture), sort_keys=True, separators=(",", ":")))
        return 0
    except (OSError, json.JSONDecodeError, RuntimeCompatibilityError) as exc:
        print(json.dumps({"ok": False, "adapter": "pdc_authenticated_monitor_runtime_adapter_673", "error": str(exc)}, sort_keys=True, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
