#!/usr/bin/env python
"""Publish Gmail/Supabase AI intake as bounded static review proposals.

Flow:
  backend/imap_bridge.py -> Supabase ai_email_intake -> this script -> email-board-data.js

Email-derived vehicle details, job lines, categories and starting labour estimates
never enter the operational board directly. Staff must confirm and approve included
rows in AI Intake Review first. Secrets stay in backend/.env only.

Mailbox content is untrusted data, never an instruction source. This program uses
only fixed parsers and fixed subprocess arguments; it never evaluates email text,
runs email-supplied commands, or changes PC/Hermes configuration.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV = ROOT / "backend" / ".env"
DEFAULT_OUTPUT = ROOT / "email-board-data.js"
DEFAULT_ATTACHMENT_DIR = ROOT / "backend" / ".imap_attachments"
DEFAULT_ARB_CATALOG = ROOT / "backend" / "arb_labor_catalog.json"
DEFAULT_LIMIT = 200
MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024

WORK_KEYWORDS = {
    "pdcRequiresTint": [r"\btint\b", r"window tint"],
    "pdcRequiresHoist": [r"\bhoist\b", r"lift kit", r"suspension", r"\bgvm\b", r"weight upgrade"],
    "pdcRequiresFitting": [
        r"\bfitting\b", r"bull\s*bar", r"tow\s*bar", r"winch", r"canopy", r"seat covers?",
        r"floor mats?", r"accessor(?:y|ies)", r"fit\b", r"pdi\b", r"pre[- ]?delivery",
    ],
    "pdcRequiresFabrication": [r"fabricat", r"tray\b", r"service body", r"mine bar", r"weld"],
    "pdcRequiresElectrical": [
        r"electrical", r"driving lights?", r"solis", r"brake controller", r"dual battery",
        r"\buhf\b", r"reverse alarm", r"wire\b", r"wiring",
    ],
    "pdcRequiresTyre": [r"\btyre\b", r"\btire\b", r"wheel alignment", r"alignment"],
    "pdcRequiresPitInspection": [r"pit inspection", r"pit and weigh", r"\bpit\b", r"quality check"],
    "pdcRequiresParts": [r"parts?", r"ordered", r"purchase order", r"\bpo\b"],
}

JOB_LINE_STAGE_RULES = [
    ("TINT", re.compile(r"\btint\b", re.I)),
    ("TYRE", re.compile(r"\b(?:tyres?|tires?|wheel alignment|alignment)\b", re.I)),
    ("ELECTRICAL", re.compile(r"\b(?:electrical|driving lights?|light bar|dual battery|battery system|uhf|antenna|reverse alarm|brake controller|wiring|wire|solis)\b", re.I)),
    ("FITTING", re.compile(r"\b(?:bull\s*bar|nudge\s*bar|tow\s*bar|winch|canopy|snorkel|side rails?|side steps?|seat covers?|floor mats?|dash mat|recovery point|roof rack|fold step|fit(?:ting)?)\b", re.I)),
    ("FABRICATION", re.compile(r"\b(?:fabricat|tray|module|service body|rops|tool ?box|jacking points?|water tank|mine bar|weld)\b", re.I)),
    ("HOIST", re.compile(r"\b(?:suspension|gvm|lift kit|weight upgrade)\b", re.I)),
    ("PIT_INSPECTION", re.compile(r"\b(?:pit inspection|pit and weigh|quality check)\b", re.I)),
    ("BUS_4X4", re.compile(r"\bbus\s*4\s*x\s*4\b", re.I)),
]

# Review-screen starting points only. They never become operational until a person
# checks the line, category and hours and explicitly approves the import.
REVIEW_HOUR_RULES = [
    (re.compile(r"\b(?:tool ?box|water tank|jacking points?)\b", re.I), 2.0, "tray accessory"),
    (re.compile(r"\bfold step\b", re.I), 1.0, "fold step"),
    (re.compile(r"\btow\s*bar\b", re.I), 4.0, "towbar"),
    (re.compile(r"\b(?:tray|module|service body).*\b(?:rops|roll over)\b", re.I), 16.0, "tray/module with ROPS"),
    (re.compile(r"\b(?:tray|module|service body)\b", re.I), 12.0, "tray/module"),
    (re.compile(r"\b(?:suspension|gvm|lift kit|weight upgrade)\b", re.I), 8.0, "suspension/GVM"),
    (re.compile(r"\b(?:dual battery|battery system)\b", re.I), 6.0, "dual-battery system"),
    (re.compile(r"\bbull\s*bar\b", re.I), 5.0, "bullbar"),
    (re.compile(r"\b(?:side rails?|side steps?)\b", re.I), 4.0, "side rails/steps"),
    (re.compile(r"\bsnorkel\b", re.I), 3.5, "snorkel"),
    (re.compile(r"\b(?:driving lights?|light bar)\b", re.I), 3.0, "driving lights"),
    (re.compile(r"\b(?:uhf|antenna)\b", re.I), 3.0, "UHF/antenna"),
    (re.compile(r"\btint\b", re.I), 3.0, "tint"),
    (re.compile(r"\bwinch\b", re.I), 2.0, "winch"),
    (re.compile(r"\b(?:tyres?|tires?)\b", re.I), 2.5, "tyres"),
    (re.compile(r"\bseat covers?\b", re.I), 1.5, "seat covers"),
    (re.compile(r"\bdash mat\b", re.I), 0.25, "dash mat"),
]


def suggested_job_line_stage(code: str, description: str) -> str:
    value = f"{code} {description}"
    for stage, pattern in JOB_LINE_STAGE_RULES:
        if pattern.search(value):
            return stage
    return "FITTING"


def suggested_review_hours(description: str) -> tuple[float | None, str]:
    for pattern, hours, label in REVIEW_HOUR_RULES:
        if pattern.search(description or ""):
            return hours, label
    return None, ""


FIELD_PATTERNS = {
    "stock": [
        r"\bref\.?[ \t]*[:#\-]?[ \t]*(\d{5,12})\b",
        r"\bstock(?:[ \t]*(?:no\.?|number)|[ \t]*#)?[ \t]*[:#\-]?[ \t]*(?:\r?\n[ \t]*)?([A-Z0-9][A-Z0-9\-]{4,24})",
        r"\b((?:IS|NS|TY|PMB|PDC)\d{5,12})\b",
    ],
    "jobCard": [
        r"(?:repair\s*order\s*no\.?|job\s*card|jobcard|jc)\s*[:#\-]?\s*(JC?\s*\d{4,12}|J\s*\d{5,12}|[A-Z]{0,3}\d{5,12})",
    ],
    "purchaseOrder": [
        r"\bP\s*[./]?\s*O\.?\s*(?:No\.?)?\s*[:#\-]?\s*([A-Z]{1,5}\d{5,12})\b",
        r"\bpurchase\s*order(?:\s*(?:no\.?|number))?\s*[:#\-]?\s*([A-Z]{1,5}\d{5,12})\b",
    ],
    "keyNumber": [
        r"(?:key(?:\s*(?:no|number|tag))?|tag(?:\s*no)?)\s*[:#\-]\s*(\d{1,4})",
    ],
    "customer": [
        r"Customer\s*[:#\-]\s*([^\r\n]{2,120})",
        r"CUSTOMER[ \t]*[:#\-]?[ \t]*(?:\r?\n[ \t]*){1,3}([^\r\n]{2,120})",
        r"(?:client|name)\s*[:#\-]\s*([^\r\n]{2,80})",
    ],
    "vehicle": [
        r"Make\s*&\s*([^\r\n]{2,120})",
        r"VEHICLE[ \t]*[:#\-]?[ \t]*(?:\r?\n[ \t]*){1,3}([^\r\n]{2,120})",
        r"\b(Nissan\s+[^\r\n]{8,100})",
        r"\b(Isuzu\s+[^\r\n]{8,100})",
        r"\b(Toyota\s+[^\r\n]{8,100})",
        r"(?:vehicle|model)\s*[:#\-]\s*([^\r\n]{2,120})",
    ],
    "rego": [
        r"(?:rego|registration)\s*[:#\-]\s*([A-Z0-9\- ]{2,12})",
    ],
    "eta": [
        r"(?:eta(?:\s*(?:to|at)?\s*kewdale)?|kewdale)\s*[:#\-]\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}-\d{2}-\d{2})",
    ],
}

@dataclass
class ParsedVehicle:
    id: str
    stock: str
    batch: str
    toyotaBatch: str
    order: str
    salesOrder: str
    client: str
    toyotaCustomer: str
    vehicle: str
    toyotaVehicle: str
    registration: str
    toyotaStatus: str
    navisionSubLocationDescription: str
    navisionLocationStatus: str
    internalStatus: str
    pdcLocation: str
    pdcStatus: str
    manualLocation: str
    pmbStage: str
    pmbKeyNumber: str
    jobCardNumber: str
    purchaseOrderNumber: str
    navisionKewdaleEta: str
    etaAtKewdale: str
    etaAtDealer: str
    source: str
    notes: str
    sourceRow: str
    sourceEmailId: str
    sourceEmailReceivedAt: str
    pdcRequiresTint: bool = False
    pdcRequiresHoist: bool = False
    pdcRequiresFitting: bool = False
    pdcRequiresFabrication: bool = False
    pdcRequiresElectrical: bool = False
    pdcRequiresTyre: bool = False
    pdcRequiresPitInspection: bool = False
    pdcRequiresParts: bool = False
    pdcCompleteTint: bool = False
    pdcCompleteHoist: bool = False
    pdcCompleteFitting: bool = False
    pdcCompleteFabrication: bool = False
    pdcCompleteElectrical: bool = False
    pdcCompleteTyre: bool = False
    pdcCompletePitInspection: bool = False
    pdcCompleteParts: bool = False
    pdcJobLines: list[dict[str, Any]] = field(default_factory=list)


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing {name}; set it in backend/.env")
    return value


def supabase_get(path: str, params: dict[str, str], key: str) -> Any:
    base = require_env("SUPABASE_URL").rstrip("/")
    url = f"{base}/rest/v1/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"apikey": key, "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Supabase fetch failed HTTP {exc.code}: {body}") from exc


def first_match(text: str, patterns: list[str]) -> str:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            return re.sub(r"\s+", " ", match.group(1)).strip(" .;,\t")
    return ""


def all_matches(text: str, patterns: list[str]) -> list[str]:
    values: list[str] = []
    for pattern in patterns:
        for match in re.finditer(pattern, text, flags=re.IGNORECASE):
            value = re.sub(r"\s+", " ", match.group(1)).strip(" .;,\t")
            if value:
                values.append(value[:120])
    return values


def bad_customer_value(value: str) -> bool:
    normalized = re.sub(r"\s+", " ", value or "").strip().lower().rstrip(":")
    return (
        not normalized
        or normalized.isdigit()
        or normalized in {"price group", "fleet customer", "fleet amount", "customer"}
    )


def clean_customer(value: str) -> str:
    value = re.sub(r"\s+", " ", value or "").strip(" .;,\t")
    comma_parts = [part.strip() for part in value.split(",") if part.strip()]
    if len(comma_parts) == 2 and comma_parts[0].casefold() == comma_parts[1].casefold():
        value = comma_parts[0]
    company = re.match(r"^(.+?\b(?:Pty Ltd|Ltd|Limited|Inc|Corporation|Corp)\b)", value, flags=re.I)
    if company:
        return company.group(1).strip()[:120]
    return value[:120]


def clean(value: str) -> str:
    value = re.sub(r"\s+", " ", value or "").strip()
    return value[:120]


def bad_vehicle_value(value: str) -> bool:
    normalized = re.sub(r"\s+", " ", value or "").strip().lower().rstrip(":")
    return not normalized or normalized in {
        "month/year", "air", "model no", "registration", "stock no", "selling dealer", "vehicle"
    }


def normalize_attachment_names(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item or "").strip() for item in value if str(item or "").strip()]
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                return [str(item or "").strip() for item in parsed if str(item or "").strip()]
        except Exception:
            return [item.strip() for item in value.split(",") if item.strip()]
    return []


def attachment_candidates(filename: str, attachment_dir: Path = DEFAULT_ATTACHMENT_DIR) -> list[Path]:
    safe = Path(filename).name
    if not safe or not attachment_dir.exists():
        return []
    return sorted(
        (path for path in attachment_dir.glob(f"*_{safe}") if path.is_file()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )


def pdftotext_command() -> str:
    candidates = [
        shutil.which("pdftotext"),
        r"C:\Program Files\Git\mingw64\bin\pdftotext.exe",
        r"C:\Program Files\Git\usr\bin\pdftotext.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    return "pdftotext"


def attachment_text_for_path(path: Path) -> str:
    try:
        if not path.is_file() or path.stat().st_size > MAX_ATTACHMENT_BYTES:
            return ""
    except OSError:
        return ""
    ext = path.suffix.lower()
    if ext == ".pdf":
        try:
            # Fixed executable and argv list only: no shell and no email-derived command.
            result = subprocess.run(
                [pdftotext_command(), "-layout", str(path), "-"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=20,

            )
            return result.stdout if result.returncode == 0 else ""
        except Exception:
            return ""
    if ext in {".txt", ".csv"}:
        return path.read_text(encoding="utf-8", errors="replace")[:20000]
    return ""


def attachment_text_chunks(record: dict[str, Any]) -> list[tuple[str, str]]:
    chunks: list[tuple[str, str]] = []
    for filename in normalize_attachment_names(record.get("attachment_names")):
        for path in attachment_candidates(filename)[:1]:
            text = attachment_text_for_path(path)
            if text.strip():
                chunks.append((filename, text))
    return chunks


def attachment_text(record: dict[str, Any]) -> str:
    chunks = [f"\n--- Attachment: {filename} ---\n{text}" for filename, text in attachment_text_chunks(record)]
    return "\n".join(chunks)[:50000]


def normal_stock(value: str) -> str:
    return re.sub(r"[^A-Z0-9\-]", "", (value or "").upper())[:32]


def normal_job(value: str) -> str:
    value = re.sub(r"\s+", "", (value or "").upper())
    if value and value.isdigit():
        return f"JC{value}"
    if value.startswith("J") and not value.startswith("JC") and value[1:].isdigit():
        return f"JC{value[1:]}"
    return value[:32]


def extract_stocks(text: str) -> list[str]:
    stocks: list[str] = []
    for pattern in FIELD_PATTERNS["stock"]:
        for match in re.finditer(pattern, text or "", flags=re.IGNORECASE):
            stock = normal_stock(match.group(1))
            if stock and stock not in stocks:
                stocks.append(stock)
    return stocks


def extract_jobs(text: str) -> list[str]:
    jobs: list[str] = []
    patterns = FIELD_PATTERNS["jobCard"] + [r"\b(JC\s*\d{5,12}|J\s*\d{5,12})\s*/\s*\d+"]
    for pattern in patterns:
        for match in re.finditer(pattern, text or "", flags=re.IGNORECASE):
            job = normal_job(match.group(1))
            if job and job not in jobs:
                jobs.append(job)
    return jobs


def infer_work_flags(text: str) -> dict[str, bool]:
    lowered = text.lower()
    flags: dict[str, bool] = {}
    for key, patterns in WORK_KEYWORDS.items():
        flags[key] = any(re.search(pattern, lowered, flags=re.IGNORECASE) for pattern in patterns)
    # Any recognised physical/accessory work usually needs parts ordered/tracked.
    if any(flags.get(k) for k in ["pdcRequiresHoist", "pdcRequiresFitting", "pdcRequiresFabrication", "pdcRequiresElectrical", "pdcRequiresTyre"]):
        flags["pdcRequiresParts"] = True
    return flags


def load_arb_catalog(path: Path = DEFAULT_ARB_CATALOG) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def job_line_id(code: str, description: str, quantity: float) -> str:
    normalized = "|".join([
        re.sub(r"[^A-Z0-9-]", "", (code or "").upper()),
        re.sub(r"\s+", " ", (description or "").strip().upper()),
        f"{quantity:g}",
    ])
    return f"jobline-{hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:16]}"


def extract_job_lines(text: str, catalog: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    """Extract bounded business job lines and attach conservative ARB estimates.

    Plain attachment text is accepted only when it is either a structured PO row,
    contains a catalogue product code, or contains a known workshop-work keyword.
    Ambiguous catalogue codes never receive an automatic hour estimate.
    """
    catalog = catalog if catalog is not None else load_arb_catalog()
    entries = catalog.get("entries") if isinstance(catalog.get("entries"), dict) else {}
    ambiguous = catalog.get("ambiguous") if isinstance(catalog.get("ambiguous"), dict) else {}
    source_code = clean(str(catalog.get("sourceCode") or "ARB catalogue"))
    labour_rate = float(catalog.get("labourRate") or 160)
    labour_rate_page = int(catalog.get("labourRateSourcePage") or 0)
    raw_lines = str(text or "").replace(chr(13), "\n").replace("\f", "\n").split("\n")
    lines = [re.sub(r"\s+", " ", line).strip() for line in raw_lines]
    excluded = re.compile(
        r"^(?:CUSTOMER|VEHICLE|MONTH/YEAR|STOCK(?: NO)?\.?|JOB CARD|JOBCARD|J\.O\.|P\.?O\.?|"
        r"PURCHASE ORDER|TOTAL|GST|PRINTED|DELIVER TO|VIN|COLOUR|TRIM|ENGINE|BUILD DATE|"
        r"DEALER PRICE|FITTING|DEALER FITTED|ARB RETAIL|DESCRIPTION|ITEM DESCRIPTION)\s*:?(?:\s|$)",
        re.I,
    )
    work_pattern = re.compile(
        r"\b(?:tint|hoist|lift kit|suspension|gvm|bull\s*bar|nudge\s*bar|tow\s*bar|winch|canopy|"
        r"seat covers?|floor mats?|dash mat|fit(?:ting)?|fabricat|tray|module|service body|mine bar|weld|electrical|"
        r"driving lights?|solis|brake controller|dual battery|uhf|reverse alarm|wire|wiring|tyres?|"
        r"wheel alignment|pit inspection|quality check|snorkel|recovery point|roof rack|side steps?)\b",
        re.I,
    )
    structured = re.compile(
        r"^([!A-Z0-9][A-Z0-9_*!-]{1,40})\s+(.+?)\s+(\d+(?:\.\d+)?)\s+\$?([\d,.]+)\s+\$?([\d,.]+)$"
    )
    results: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in lines:
        if not line or len(line) < 3 or len(line) > 240 or excluded.search(line):
            continue
        code = ""
        description = line
        quantity = 1.0
        match = structured.match(line)
        if match and not re.fullmatch(r"PO\d{6,}", match.group(1), flags=re.I):
            code = match.group(1).upper()
            description = match.group(2).strip()
            quantity = float(match.group(3))
        else:
            tokens = [token.upper() for token in re.findall(r"\b[A-Z0-9][A-Z0-9-]{2,39}\b", line, flags=re.I)]
            known_codes = [token for token in tokens if token in entries or token in ambiguous]
            if known_codes:
                code = known_codes[0]
                description = re.sub(rf"^\s*{re.escape(code)}\s*[-:]?\s*", "", line, flags=re.I).strip() or line
            elif not work_pattern.search(line):
                continue
        description = clean(description)
        if not description or description.isdigit() or excluded.search(description):
            continue
        if code in {"MISC", "TEXT"} and not work_pattern.search(description):
            continue
        identity = job_line_id(code, description, quantity)
        if identity in seen:
            continue
        seen.add(identity)

        matched_codes = []
        if code in entries:
            matched_codes.append(code)
        for token in re.findall(r"\b[A-Z0-9][A-Z0-9-]{2,39}\b", line.upper()):
            if token in entries and token not in matched_codes:
                matched_codes.append(token)
        candidate_hours = {float(entries[token].get("hours") or 0) for token in matched_codes if float(entries[token].get("hours") or 0) > 0}
        catalog_entry = entries.get(matched_codes[0]) if matched_codes else None
        estimated_hours = round(next(iter(candidate_hours)) * quantity, 4) if len(matched_codes) == 1 and len(candidate_hours) == 1 else None
        source_text = ""
        if estimated_hours is not None and catalog_entry:
            source_text = f"{source_code} · {matched_codes[0]} · page {catalog_entry.get('page') or '?'}"
            fitting_charge = float(catalog_entry.get("fittingCharge") or 0)
            source_text += f" · ${fitting_charge:g} ÷ ${labour_rate:g}/h (rate p{labour_rate_page or '?'})" if fitting_charge else " · explicit catalogue fit time"
        elif code in ambiguous:
            source_text = f"{source_code} · {code} has vehicle-dependent fitting times"
        elif len(matched_codes) > 1:
            source_text = f"{source_code} · multiple product codes require line-by-line review"
        estimate_method = str(catalog_entry.get("method") or "") if catalog_entry and estimated_hours is not None else ""
        if estimated_hours is None and not matched_codes and code not in ambiguous:
            review_hours, review_label = suggested_review_hours(description)
            if review_hours is not None:
                estimated_hours = round(review_hours * quantity, 4)
                source_text = f"AI Intake Review starting estimate · {review_label}; confirm before publishing"
                estimate_method = "review-starting-estimate"
        results.append({
            "id": identity,
            "code": code,
            "description": description,
            "quantity": quantity,
            "estimatedHours": estimated_hours,
            "estimateStatus": "provisional" if estimated_hours is not None else "review-required",
            "estimateSource": source_text,
            "estimateMethod": estimate_method,
            "catalogHoursEach": float(catalog_entry.get("hours") or 0) if catalog_entry and estimate_method != "review-starting-estimate" else None,
            "suggestedStage": suggested_job_line_stage(code, description),
            "source": "Email attachment",
        })
    return results[:120]


def merge_job_lines(previous: Any, incoming: Any) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for line in list(previous or []) + list(incoming or []):
        if not isinstance(line, dict):
            continue
        identity = str(line.get("id") or job_line_id(str(line.get("code") or ""), str(line.get("description") or ""), float(line.get("quantity") or 1)))
        merged[identity] = {**merged.get(identity, {}), **line, "id": identity}
    return list(merged.values())


def parse_vehicle_from_text(record: dict[str, Any], subject: str, body: str, attachments: str, stock_hint: str = "") -> ParsedVehicle | None:
    text = f"{subject}\n{body}\n{attachments}"
    stock = normal_stock(stock_hint or first_match(text, FIELD_PATTERNS["stock"]))
    job = normal_job(first_match(attachments, FIELD_PATTERNS["jobCard"]) or first_match(text, FIELD_PATTERNS["jobCard"]) or (extract_jobs(attachments) or extract_jobs(text) or [""])[0])
    purchase_order = clean(first_match(attachments, FIELD_PATTERNS["purchaseOrder"]) or first_match(text, FIELD_PATTERNS["purchaseOrder"])).upper()
    key_no = clean(first_match(attachments, FIELD_PATTERNS["keyNumber"]) or first_match(text, FIELD_PATTERNS["keyNumber"]))
    customer = clean(first_match(attachments, FIELD_PATTERNS["customer"]) or first_match(text, FIELD_PATTERNS["customer"]))
    model = clean(first_match(attachments, FIELD_PATTERNS["vehicle"]) or first_match(text, FIELD_PATTERNS["vehicle"]))
    if bad_vehicle_value(model):
        model = next((value for value in all_matches(attachments, FIELD_PATTERNS["vehicle"]) if not bad_vehicle_value(value)), "")
    if bad_vehicle_value(model):
        model = next((value for value in all_matches(text, FIELD_PATTERNS["vehicle"]) if not bad_vehicle_value(value)), "")
    rego = clean(first_match(attachments, FIELD_PATTERNS["rego"]) or first_match(text, FIELD_PATTERNS["rego"])).upper()
    eta = clean(first_match(attachments, FIELD_PATTERNS["eta"]) or first_match(text, FIELD_PATTERNS["eta"]))

    # Require at least one durable vehicle identifier. Ignore Google/security/setup emails.
    if not stock and not job:
        return None
    if not stock:
        stock = f"PENDING-{job}"
    subject_customer = re.sub(r"\s+[-–−]\s*\d{5,12}.*$", "", subject).strip()
    if bad_customer_value(customer):
        customer = next((value for value in all_matches(attachments, FIELD_PATTERNS["customer"]) if not bad_customer_value(value)), "")
    if bad_customer_value(customer):
        customer = next((value for value in all_matches(text, FIELD_PATTERNS["customer"]) if not bad_customer_value(value)), "")
    if bad_customer_value(customer):
        customer = subject_customer if subject_customer and subject_customer != subject else "Email intake - review"
    else:
        customer = clean_customer(customer)
    if not model:
        model = "Vehicle from email intake"

    record_id = str(record.get("id") or record.get("graph_message_id") or stock)
    source_id = f"email-{stock}-{record_id[:8]}".replace(" ", "-")
    flags = infer_work_flags(text)
    job_lines = extract_job_lines(attachments)
    vehicle = ParsedVehicle(
        id=source_id,
        stock=stock,
        batch=stock,
        toyotaBatch=stock,
        order="",
        salesOrder="",
        client=customer,
        toyotaCustomer=customer,
        vehicle=model,
        toyotaVehicle=model,
        registration=rego,
        toyotaStatus="At PMB",
        navisionSubLocationDescription="At PMB",
        navisionLocationStatus="PMB",
        internalStatus="PMB",
        pdcLocation="PMB",
        pdcStatus="PMB",
        manualLocation="PMB",
        pmbStage="",
        pmbKeyNumber=key_no,
        jobCardNumber=job,
        purchaseOrderNumber=purchase_order,
        navisionKewdaleEta=eta,
        etaAtKewdale=eta,
        etaAtDealer=eta,
        source="Email intake",
        notes="",
        sourceRow="Email intake",
        sourceEmailId=record_id,
        sourceEmailReceivedAt=str(record.get("received_at") or record.get("created_at") or ""),
        pdcJobLines=job_lines,
        **flags,
    )
    return vehicle


def parse_vehicles(record: dict[str, Any]) -> list[ParsedVehicle]:
    subject = clean(str(record.get("subject") or ""))
    body = str(record.get("parsed_text") or record.get("raw_body") or "")
    chunks = attachment_text_chunks(record)

    grouped: dict[str, list[str]] = {}
    unkeyed: list[str] = []
    for filename, chunk_text in chunks:
        attachment_block = f"\n--- Attachment: {filename} ---\n{chunk_text}"
        stocks = extract_stocks(chunk_text)
        if stocks:
            for stock in stocks:
                grouped.setdefault(stock, []).append(attachment_block)
        else:
            unkeyed.append(attachment_block)

    vehicles: list[ParsedVehicle] = []
    if grouped:
        # Attach unkeyed cover/companion attachments to every stock-specific group, but keep
        # different stock PDFs separate so one email can create multiple jobs.
        for stock, parts in grouped.items():
            vehicle = parse_vehicle_from_text(record, subject, body, "\n".join(parts + unkeyed), stock_hint=stock)
            if vehicle:
                vehicles.append(vehicle)
    else:
        vehicle = parse_vehicle_from_text(record, subject, body, "\n".join(unkeyed))
        if vehicle:
            vehicles.append(vehicle)

    # De-duplicate any repeated stock inside the same email while preserving the richest/latest parse.
    by_key: dict[str, ParsedVehicle] = {}
    for vehicle in vehicles:
        by_key[vehicle.stock or vehicle.jobCardNumber or vehicle.id] = vehicle
    return list(by_key.values())


def parse_vehicle(record: dict[str, Any]) -> ParsedVehicle | None:
    vehicles = parse_vehicles(record)
    return vehicles[0] if vehicles else None


def vehicle_key(vehicle: dict[str, Any]) -> str:
    return str(vehicle.get("stock") or vehicle.get("jobCardNumber") or vehicle.get("id") or "").strip().upper()


def sanitize_public_vehicle(vehicle: dict[str, Any]) -> dict[str, Any]:
    """Remove mailbox-private/raw fields before generating the public static payload."""
    clean_vehicle = dict(vehicle)
    clean_vehicle.pop("sourceEmailSubject", None)
    clean_vehicle.pop("sourceEmailSender", None)
    if str(clean_vehicle.get("sourceRow") or "").strip().lower() == "email intake":
        clean_vehicle.pop("notes", None)
        clean_vehicle["source"] = "Email intake"
    return clean_vehicle


def merge_vehicles(existing: list[dict[str, Any]], incoming: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged = {vehicle_key(v): sanitize_public_vehicle(v) for v in existing if isinstance(v, dict) and vehicle_key(v)}
    for item in incoming:
        key = vehicle_key(item)
        if not key:
            continue
        prior = merged.get(key, {})
        combined = {**prior, **item}
        combined["pdcJobLines"] = merge_job_lines(prior.get("pdcJobLines"), item.get("pdcJobLines"))
        merged[key] = sanitize_public_vehicle(combined)
    return sorted(merged.values(), key=lambda v: (str(v.get("sourceEmailReceivedAt") or ""), vehicle_key(v)))


def parse_parts_review_actions(record: dict[str, Any]) -> list[dict[str, Any]]:
    """Convert explicit Parts update fields into review-only proposals."""
    text = str(record.get("parsed_text") or record.get("raw_body") or "").replace(chr(13) + chr(10), "\n")
    blocks = re.split(r"(?im)(?=^\s*stock\s*:)", text)
    proposals: list[dict[str, Any]] = []
    intake_id = str(record.get("id") or record.get("graph_message_id") or "").strip()
    for block in blocks:
        stock_match = re.search(r"(?im)^\s*stock\s*:\s*([A-Z0-9-]{4,24})\s*$", block)
        parts_match = re.search(r"(?im)^\s*parts\s*:\s*(complete|completed|stoppage|stopped|note|notes)\s*$", block)
        if not stock_match or not parts_match:
            continue
        stock = stock_match.group(1).strip().upper()
        raw_action = parts_match.group(1).lower()
        action = "complete" if raw_action.startswith("complet") else "stoppage" if raw_action.startswith("stop") else "note"

        def field(name: str) -> str:
            match = re.search(rf"(?im)^\s*{name}\s*:\s*([^\n]{{1,300}})$", block)
            return clean(match.group(1)) if match else ""

        reason = field("reason")
        notes = field("notes?")
        eta = field("eta")
        if eta and not re.fullmatch(r"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}-\d{2}-\d{2}", eta):
            eta = ""
        proposals.append({
            "id": f"{intake_id}:{stock}:parts:{action}",
            "intakeId": intake_id,
            "stock": stock,
            "action": action,
            "reason": reason,
            "notes": notes,
            "eta": eta,
            "sender": "Email intake",
            "receivedAt": str(record.get("received_at") or record.get("created_at") or ""),
        })
    return proposals


def vehicle_import_review(vehicle: dict[str, Any]) -> dict[str, Any] | None:
    """Create a bounded vehicle/job-line proposal; do not mutate the live board."""
    stock = vehicle_key(vehicle)
    if not re.fullmatch(r"(?:\d{5,12}|(?:IS|NS|TY|PMB|PDC)\d{5,12})", stock.upper()):
        return None
    intake_id = str(vehicle.get("sourceEmailId") or vehicle.get("id") or stock).strip()
    allowed_vehicle_fields = (
        "id", "stock", "batch", "toyotaBatch", "order", "salesOrder", "client", "toyotaCustomer",
        "vehicle", "toyotaVehicle", "registration", "jobCardNumber", "purchaseOrderNumber",
        "navisionKewdaleEta", "etaAtKewdale", "etaAtDealer",
    )
    vehicle_data = {key: vehicle.get(key) for key in allowed_vehicle_fields if vehicle.get(key) not in (None, "")}
    vehicle_data.update({
        "source": "Reviewed email intake",
        "sourceRow": "Reviewed email intake",
        "pdcLocation": "PMB",
        "pdcStatus": "At PMB",
        "toyotaStatus": "At PMB",
        "pmbStage": "",
    })
    return {
        "id": f"{intake_id}:{stock}:vehicle-import",
        "type": "vehicle-import",
        "intakeId": intake_id,
        "stock": stock,
        "receivedAt": str(vehicle.get("sourceEmailReceivedAt") or ""),
        "vehicle": vehicle_data,
        "jobLines": [dict(line) for line in vehicle.get("pdcJobLines") or [] if isinstance(line, dict)],
    }


def read_existing_generated(path: Path) -> dict[str, Any]:
    empty = {"vehicles": [], "reviews": [], "hasReviewsField": False}
    if not path.exists():
        return empty
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"window\.PDC_EMAIL_BOARD_DATA\s*=\s*(\{.*?\});", text, flags=re.S)
    if not match:
        return empty
    try:
        data = json.loads(match.group(1))
        return {"vehicles": list(data.get("vehicles") or []), "reviews": list(data.get("reviews") or []), "hasReviewsField": "reviews" in data}
    except Exception:
        return empty


def write_generated(path: Path, vehicles: list[dict[str, Any]], reviews: list[dict[str, Any]]) -> bool:
    previous = read_existing_generated(path)
    if previous.get("hasReviewsField") and previous.get("vehicles") == vehicles and previous.get("reviews") == reviews:
        return False
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    payload = {
        "generatedAt": now,
        "source": "Supabase ai_email_intake via backend/email_board_publisher.py",
        "vehicles": vehicles,
        "reviews": reviews,
    }
    content = """// Generated by backend/email_board_publisher.py. Do not hand-edit.
(function () {
  window.PDC_EMAIL_BOARD_DATA = PAYLOAD;
  var base = window.VEHICLE_TRACKING_DATA = window.VEHICLE_TRACKING_DATA || { report: {}, vehicles: [], toyotaMatches: {} };
  var existing = Array.isArray(base.vehicles) ? base.vehicles : [];
  var byKey = Object.create(null);
  function key(vehicle) {
    return String((vehicle && (vehicle.stock || vehicle.jobCardNumber || vehicle.id)) || '').trim().toUpperCase();
  }
  existing.forEach(function (vehicle) { var k = key(vehicle); if (k) byKey[k] = vehicle; });
  window.PDC_EMAIL_BOARD_DATA.vehicles.forEach(function (vehicle) {
    var k = key(vehicle);
    if (!k) return;
    byKey[k] = Object.assign({}, byKey[k] || {}, vehicle);
  });
  base.vehicles = Object.keys(byKey).map(function (k) { return byKey[k]; });
  base.report = Object.assign({}, base.report || {}, {
    emailIntakeGeneratedAt: window.PDC_EMAIL_BOARD_DATA.generatedAt,
    emailIntakeVehicleCount: window.PDC_EMAIL_BOARD_DATA.vehicles.length,
    emailIntakeReviewCount: (window.PDC_EMAIL_BOARD_DATA.reviews || []).length
  });
}());
""".replace("PAYLOAD", json.dumps(payload, indent=2, ensure_ascii=False))
    old = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    if old == content:
        return False
    path.write_text(content, encoding="utf-8")
    return True


def run(cmd: list[str], cwd: Path = ROOT) -> str:
    result = subprocess.run(cmd, cwd=str(cwd), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed ({' '.join(cmd)}):\n{result.stdout}")
    return result.stdout.strip()


def git_commit_push(message: str, paths: list[Path]) -> bool:
    for path in paths:
        run(["git", "add", str(path.relative_to(ROOT)).replace("\\", "/")])
    status = run(["git", "status", "--short", "--", *[str(p.relative_to(ROOT)).replace("\\", "/") for p in paths]])
    if not status:
        return False
    run(["git", "commit", "--only", "-m", message, "--", *[str(p.relative_to(ROOT)).replace("\\", "/") for p in paths]])
    run(["git", "push", "origin", "main"])
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate email-board-data.js from Supabase ai_email_intake")
    parser.add_argument("--env-file", default=str(DEFAULT_ENV))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    parser.add_argument("--commit-push", action="store_true", help="Commit and push generated website update")
    args = parser.parse_args()

    load_dotenv(Path(args.env_file))
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_ANON_KEY") or ""
    if not key:
        raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY is required in backend/.env")

    records = supabase_get("ai_email_intake", {
        "select": "id,subject,sender_email,received_at,created_at,parsed_text,raw_body,status,graph_message_id,attachment_names",
        "order": "created_at.desc",
        "limit": str(args.limit),
    }, key)
    parsed = [vehicle for record in records for vehicle in parse_vehicles(record)]
    incoming = [asdict(vehicle) for vehicle in parsed if vehicle]
    output = Path(args.output)

    # Email-derived vehicles/work lines remain review proposals until a staff
    # member explicitly approves them in AI Intake Review.
    vehicles: list[dict[str, Any]] = []
    vehicle_reviews = [proposal for vehicle in incoming if (proposal := vehicle_import_review(vehicle))]
    reviews = sorted(
        [proposal for record in records for proposal in parse_parts_review_actions(record)] + vehicle_reviews,
        key=lambda proposal: (str(proposal.get("receivedAt") or ""), str(proposal.get("id") or "")),
        reverse=True,
    )
    changed = write_generated(output, vehicles, reviews)
    summary = {
        "records_checked": len(records),
        "vehicles_generated": len(vehicles),
        "review_actions_generated": len(reviews),
        "vehicle_review_proposals_generated": len(vehicle_reviews),
        "new_parseable_records": len(incoming),
        "changed": changed,
        "output": str(output),
    }
    if args.commit_push and changed:
        committed = git_commit_push("chore: publish email intake review proposals", [output])
        summary["committed_and_pushed"] = committed
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
