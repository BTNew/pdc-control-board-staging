"""Fail-closed attachment content validation and canonical MIME assignment.

Mailbox MIME values and filenames are untrusted hints.  A file is uploadable only
when its extension, bounded content structure and reported MIME form one exact
supported contract.  This module never executes or extracts an attachment.
"""
from __future__ import annotations

import csv
import io
import re
import struct
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
MAX_ZIP_ENTRIES = 4096
MAX_ZIP_UNCOMPRESSED = 50 * 1024 * 1024

CANONICAL_MIME_BY_EXTENSION = {
    ".pdf": "application/pdf",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".csv": "text/csv",
    ".txt": "text/plain",
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".tif": "image/tiff", ".tiff": "image/tiff",
    ".bmp": "image/bmp",
}
SUPPORTED_EXTENSIONS = frozenset(CANONICAL_MIME_BY_EXTENSION)
GENERIC_MIME = frozenset({"", "application/octet-stream", "binary/octet-stream"})
MIME_ALIASES = {
    "image/jpeg": frozenset({"image/jpeg", "image/jpg", "image/pjpeg"}),
    "image/tiff": frozenset({"image/tiff", "image/x-tiff"}),
    "text/csv": frozenset({"text/csv", "application/csv", "text/comma-separated-values"}),
    "text/plain": frozenset({"text/plain"}),
}


@dataclass(frozen=True)
class ContentValidation:
    ok: bool
    canonical_mime: str
    detected_extension: str
    status: str
    reason: str


def _fail(reason: str, detected: str = "", status: str = "failed") -> ContentValidation:
    return ContentValidation(False, "", detected, status, reason[:1000])


def _validate_pdf(data: bytes) -> bool:
    if not re.match(br"%PDF-1\.[0-7][\r\n]", data[:10]) or b"%%EOF" not in data[-2048:]:
        return False
    try:
        import pypdfium2 as pdfium  # type: ignore
        document = pdfium.PdfDocument(data)
        count = len(document)
        document.close()
        return count > 0
    except Exception:
        return False


def _safe_zip(data: bytes) -> tuple[zipfile.ZipFile, set[str]]:
    archive = zipfile.ZipFile(io.BytesIO(data))
    infos = archive.infolist()
    names = [item.filename for item in infos]
    if not infos or len(infos) > MAX_ZIP_ENTRIES or len(names) != len(set(names)):
        archive.close(); raise ValueError("unsafe OOXML inventory")
    total = 0
    for item in infos:
        path = PurePosixPath(item.filename)
        if item.flag_bits & 1 or item.is_dir() or item.filename.startswith("/") or "\\" in item.filename or ".." in path.parts:
            archive.close(); raise ValueError("unsafe OOXML member")
        total += item.file_size
        if item.file_size < 0 or item.compress_size < 0 or total > MAX_ZIP_UNCOMPRESSED:
            archive.close(); raise ValueError("oversized OOXML content")
    return archive, set(names)


def _validate_ooxml(data: bytes) -> str:
    try:
        archive, names = _safe_zip(data)
        try:
            types = archive.read("[Content_Types].xml")
            if len(types) > 2_000_000:
                return ""
            if ("word/document.xml" in names and
                    b"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml" in types):
                return ".docx"
            if ("xl/workbook.xml" in names and
                    b"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml" in types):
                return ".xlsx"
            return ""
        finally:
            archive.close()
    except (KeyError, OSError, ValueError, zipfile.BadZipFile, RuntimeError):
        return ""


def _cfb_directory_names(data: bytes) -> set[str]:
    magic = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"
    if len(data) < 512 or data[:8] != magic or data[28:30] != b"\xfe\xff":
        return set()
    sector_shift = struct.unpack_from("<H", data, 30)[0]
    if sector_shift not in (9, 12):
        return set()
    sector_size = 1 << sector_shift
    first_dir = struct.unpack_from("<I", data, 48)[0]
    fat_count = struct.unpack_from("<I", data, 44)[0]
    difat = list(struct.unpack_from("<109I", data, 76))
    fat_sectors = [value for value in difat if value < 0xFFFFFFFA][:fat_count]
    if not fat_sectors or first_dir >= 0xFFFFFFFA:
        return set()
    fat: list[int] = []
    for sector in fat_sectors:
        start = 512 + sector * sector_size
        if start + sector_size > len(data):
            return set()
        fat.extend(struct.unpack_from(f"<{sector_size // 4}I", data, start))
    names: set[str] = set(); seen: set[int] = set(); sector = first_dir; saw_root = False
    while sector < 0xFFFFFFFA and sector not in seen and len(seen) <= 4096:
        seen.add(sector); start = 512 + sector * sector_size
        if start + sector_size > len(data):
            return set()
        block = data[start:start + sector_size]
        for offset in range(0, sector_size, 128):
            entry = block[offset:offset + 128]
            name_len = struct.unpack_from("<H", entry, 64)[0]; entry_type = entry[66]
            if 2 <= name_len <= 64 and name_len % 2 == 0:
                try:
                    name = entry[:name_len - 2].decode("utf-16le", "strict")
                except UnicodeDecodeError:
                    continue
                if name == "Root Entry" and entry_type == 5:
                    saw_root = True
                if name and entry_type in {1, 2, 5}:
                    names.add(name)
        if sector >= len(fat):
            return set()
        sector = fat[sector]
    return names if sector == 0xFFFFFFFE and saw_root else set()


def _validate_text(data: bytes, csv_expected: bool) -> bool:
    try:
        if data.startswith((b"\xff\xfe", b"\xfe\xff")):
            text = data.decode("utf-16")
        elif data.startswith(b"\xef\xbb\xbf"):
            text = data.decode("utf-8-sig")
        else:
            text = data.decode("utf-8", "strict")
    except UnicodeDecodeError:
        return False
    if not text or any(ord(char) < 32 and char not in "\t\r\n" for char in text):
        return False
    if not csv_expected:
        return True
    try:
        rows = list(csv.reader(io.StringIO(text), strict=True))
    except (csv.Error, UnicodeError):
        return False
    return bool(rows) and any(any(cell.strip() for cell in row) for row in rows)


def _validate_image(data: bytes) -> str:
    try:
        from PIL import Image  # type: ignore
        with Image.open(io.BytesIO(data)) as image:
            image.verify()
            fmt = str(image.format or "").upper()
        return {"JPEG": ".jpg", "PNG": ".png", "TIFF": ".tif", "BMP": ".bmp"}.get(fmt, "")
    except Exception:
        return ""


def detect_extension(data: bytes) -> str:
    if _validate_pdf(data):
        return ".pdf"
    ooxml = _validate_ooxml(data)
    if ooxml:
        return ooxml
    if "Workbook" in _cfb_directory_names(data) or "Book" in _cfb_directory_names(data):
        return ".xls"
    image = _validate_image(data)
    if image:
        return image
    return ""


def validate_attachment(filename: str, reported_mime: str, data: bytes) -> ContentValidation:
    ext = Path(filename).suffix.lower()
    reported = (reported_mime or "").split(";", 1)[0].strip().lower()
    if not data:
        return _fail("attachment_content_invalid: empty attachment")
    if len(data) > MAX_ATTACHMENT_BYTES:
        return _fail(f"attachment_content_invalid: attachment exceeds {MAX_ATTACHMENT_BYTES} bytes")
    if ext not in SUPPORTED_EXTENSIONS:
        label = ext or "<none>"
        if ext == ".heic":
            return _fail("unsupported_attachment_type: HEIC is unsupported and must never be marked extracted; original RFC822 evidence retained", status="unsupported")
        detected = detect_extension(data)
        if detected:
            return _fail(f"attachment_extension_content_mismatch: unsupported extension {label} contains verified {detected} content; original RFC822 evidence retained", detected, "unsupported")
        return _fail(f"attachment_content_unknown: extension {label} and binary content are not recognized; original RFC822 evidence retained", status="unsupported")
    detected = detect_extension(data)
    if ext in {".txt", ".csv"}:
        if _validate_text(data, ext == ".csv"):
            detected = ext
    if not detected:
        return _fail(f"attachment_content_invalid: {ext} content is malformed or its actual format is unknown")
    equivalent = ({".jpg", ".jpeg"}, {".tif", ".tiff"})
    # One attested provider quirk is narrowly tolerated: the original filename
    # image.png contains a verified JPEG and the provider reports image/jpeg.
    # Keep the filename untouched for the storage path, but canonicalize the
    # content MIME from the verified format. Every other extension/content
    # mismatch remains fail-closed.
    preserved_jpeg_name = ext == ".png" and detected == ".jpg" and reported == "image/jpeg"
    if detected != ext and not preserved_jpeg_name and not any(ext in group and detected in group for group in equivalent):
        return _fail(f"attachment_extension_content_mismatch: extension {ext} does not match verified {detected} content", detected)
    canonical = "image/jpeg" if preserved_jpeg_name else CANONICAL_MIME_BY_EXTENSION[ext]
    accepted = MIME_ALIASES.get(canonical, frozenset({canonical}))
    if reported not in GENERIC_MIME and reported not in accepted:
        return _fail(f"attachment_mime_content_mismatch: reported {reported or '<empty>'} does not match verified {canonical} content", detected)
    return ContentValidation(True, canonical, detected, "verified", "")
