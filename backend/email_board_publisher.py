#!/usr/bin/env python
"""Publish Gmail/Supabase AI intake emails into the static PDC board.

Flow:
  backend/imap_bridge.py -> Supabase ai_email_intake -> this script -> email-board-data.js

The generated file is safe to load from the normal GitHub Pages URL. It appends
email-created vehicles into window.VEHICLE_TRACKING_DATA before app.js starts.
Secrets stay in backend/.env only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV = ROOT / "backend" / ".env"
DEFAULT_OUTPUT = ROOT / "email-board-data.js"
DEFAULT_LIMIT = 200

WORK_KEYWORDS = {
    "pdcRequiresTint": [r"\btint\b", r"window tint"],
    "pdcRequiresHoist": [r"\bhoist\b", r"lift kit", r"suspension"],
    "pdcRequiresFitting": [
        r"\bfitting\b", r"bull\s*bar", r"tow\s*bar", r"winch", r"canopy", r"seat covers?",
        r"floor mats?", r"accessor(?:y|ies)", r"fit\b",
    ],
    "pdcRequiresFabrication": [r"fabricat", r"tray\b", r"service body", r"mine bar", r"weld"],
    "pdcRequiresElectrical": [
        r"electrical", r"driving lights?", r"solis", r"brake controller", r"dual battery",
        r"\buhf\b", r"reverse alarm", r"wire\b", r"wiring",
    ],
    "pdcRequiresTyre": [r"\btyre\b", r"\btire\b", r"wheel alignment", r"alignment"],
    "pdcRequiresPitInspection": [r"pit inspection", r"\bpit\b", r"qc\b", r"quality check"],
    "pdcRequiresParts": [r"parts?", r"ordered", r"purchase order", r"\bpo\b"],
}

FIELD_PATTERNS = {
    "stock": [
        r"(?:stock(?:\s*(?:no|number))?|stock\s*#|sn)\s*[:#\-]\s*([A-Z0-9][A-Z0-9\-]{4,24})",
        r"\b((?:IS|NS|TY|PMB|PDC)\d{5,12})\b",
    ],
    "jobCard": [
        r"(?:job\s*card|jobcard|jc)\s*[:#\-]\s*(JC?\s*\d{4,12}|[A-Z]{0,3}\d{5,12})",
    ],
    "keyNumber": [
        r"(?:key(?:\s*(?:no|number|tag))?|tag)\s*[:#\-]\s*(\d{1,4})",
    ],
    "customer": [
        r"(?:customer|client|name)\s*[:#\-]\s*([^\r\n]{2,80})",
    ],
    "vehicle": [
        r"(?:vehicle|model)\s*[:#\-]\s*([^\r\n]{2,100})",
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
    navisionKewdaleEta: str
    etaAtKewdale: str
    etaAtDealer: str
    source: str
    notes: str
    sourceRow: str
    sourceEmailId: str
    sourceEmailSubject: str
    sourceEmailSender: str
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


def clean(value: str) -> str:
    value = re.sub(r"\s+", " ", value or "").strip()
    return value[:120]


def normal_stock(value: str) -> str:
    return re.sub(r"[^A-Z0-9\-]", "", (value or "").upper())[:32]


def normal_job(value: str) -> str:
    value = re.sub(r"\s+", "", (value or "").upper())
    if value and value.isdigit():
        return f"JC{value}"
    return value[:32]


def infer_work_flags(text: str) -> dict[str, bool]:
    lowered = text.lower()
    flags: dict[str, bool] = {}
    for key, patterns in WORK_KEYWORDS.items():
        flags[key] = any(re.search(pattern, lowered, flags=re.IGNORECASE) for pattern in patterns)
    # Any recognised physical/accessory work usually needs parts ordered/tracked.
    if any(flags.get(k) for k in ["pdcRequiresHoist", "pdcRequiresFitting", "pdcRequiresFabrication", "pdcRequiresElectrical", "pdcRequiresTyre"]):
        flags["pdcRequiresParts"] = True
    return flags


def parse_vehicle(record: dict[str, Any]) -> ParsedVehicle | None:
    subject = clean(str(record.get("subject") or ""))
    body = str(record.get("parsed_text") or record.get("raw_body") or "")
    text = f"{subject}\n{body}"
    stock = normal_stock(first_match(text, FIELD_PATTERNS["stock"]))
    job = normal_job(first_match(text, FIELD_PATTERNS["jobCard"]))
    key_no = clean(first_match(text, FIELD_PATTERNS["keyNumber"]))
    customer = clean(first_match(text, FIELD_PATTERNS["customer"]))
    model = clean(first_match(text, FIELD_PATTERNS["vehicle"]))
    rego = clean(first_match(text, FIELD_PATTERNS["rego"])).upper()
    eta = clean(first_match(text, FIELD_PATTERNS["eta"]))

    # Require at least one durable vehicle identifier. Ignore Google/security/setup emails.
    if not stock and not job:
        return None
    if not stock:
        stock = f"PENDING-{job}"
    if not customer:
        customer = "Email intake - review"
    if not model:
        model = "Vehicle from email intake"

    record_id = str(record.get("id") or record.get("graph_message_id") or stock)
    source_id = f"email-{stock}-{record_id[:8]}".replace(" ", "-")
    flags = infer_work_flags(text)
    notes = clean(" ".join(line.strip() for line in text.splitlines() if line.strip())[:500])
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
        navisionKewdaleEta=eta,
        etaAtKewdale=eta,
        etaAtDealer=eta,
        source="Email intake · pmbcontroller@gmail.com",
        notes=notes,
        sourceRow="Email intake",
        sourceEmailId=record_id,
        sourceEmailSubject=subject,
        sourceEmailSender=clean(str(record.get("sender_email") or "")),
        sourceEmailReceivedAt=str(record.get("received_at") or record.get("created_at") or ""),
        **flags,
    )
    return vehicle


def vehicle_key(vehicle: dict[str, Any]) -> str:
    return str(vehicle.get("stock") or vehicle.get("jobCardNumber") or vehicle.get("id") or "").strip().upper()


def merge_vehicles(existing: list[dict[str, Any]], incoming: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged = {vehicle_key(v): dict(v) for v in existing if vehicle_key(v)}
    for item in incoming:
        key = vehicle_key(item)
        if not key:
            continue
        prior = merged.get(key, {})
        merged[key] = {**prior, **item}
    return sorted(merged.values(), key=lambda v: (str(v.get("sourceEmailReceivedAt") or ""), vehicle_key(v)))


def read_existing_generated(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"window\.PDC_EMAIL_BOARD_DATA\s*=\s*(\{.*?\});", text, flags=re.S)
    if not match:
        return []
    try:
        data = json.loads(match.group(1))
        return list(data.get("vehicles") or [])
    except Exception:
        return []


def write_generated(path: Path, vehicles: list[dict[str, Any]]) -> bool:
    previous = read_existing_generated(path)
    if previous == vehicles:
        return False
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    payload = {
        "generatedAt": now,
        "source": "Supabase ai_email_intake via backend/email_board_publisher.py",
        "vehicles": vehicles,
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
    emailIntakeVehicleCount: window.PDC_EMAIL_BOARD_DATA.vehicles.length
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
    run(["git", "commit", "-m", message])
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
        "select": "id,subject,sender_email,received_at,created_at,parsed_text,raw_body,status,graph_message_id",
        "order": "created_at.desc",
        "limit": str(args.limit),
    }, key)
    parsed = [parse_vehicle(record) for record in records]
    incoming = [asdict(vehicle) for vehicle in parsed if vehicle]
    output = Path(args.output)
    existing = read_existing_generated(output)
    vehicles = merge_vehicles(existing, incoming)
    changed = write_generated(output, vehicles)
    summary = {"records_checked": len(records), "vehicles_generated": len(vehicles), "new_parseable_records": len(incoming), "changed": changed, "output": str(output)}
    if args.commit_push and changed:
        committed = git_commit_push("chore: publish email intake vehicles", [output])
        summary["committed_and_pushed"] = committed
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
