#!/usr/bin/env python3
"""Publish one exact deterministic AI Auditor finding set to staging.

The script uses an enrolled authenticated worker, reconstructs the complete bounded
snapshot, evaluates the committed pure Stage A engine, submits only typed evidence,
and emits no credentials or private business data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import psycopg

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "pdc-supabase-config.staging.js"
ENGINE = ROOT / "pdc-ai-auditor-stage-a.js"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"


def config():
    text = CONFIG.read_text("utf-8")
    url = re.search(r"url:\s*'([^']+)'", text)
    key = re.search(r"publishableKey:\s*'([^']+)'", text)
    if not url or not key or PROJECT_REF not in url.group(1):
        raise RuntimeError("staging publishable configuration invalid")
    return url.group(1).rstrip("/"), key.group(1)


def post(url, key, path, body, token=None):
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    request = Request(url + path, data=json.dumps(body, separators=(",", ":")).encode(), headers=headers, method="POST")
    try:
        with urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode())
    except HTTPError as exc:
        message = exc.read().decode(errors="replace")[:800]
        raise RuntimeError(f"staging request failed ({exc.code}): {message}") from exc


def exact_snapshot(url, key, token):
    pages, after = [], None
    for number in range(1, 6):
        page = post(url, key, "/rest/v1/rpc/get_pdc_auditor_snapshot", {"p_after_vehicle_id": after, "p_page_size": 100}, token)
        items = page.get("items")
        if not page.get("ok") or not isinstance(items, list) or not items:
            raise RuntimeError("snapshot page is unavailable or empty")
        pages.append(page)
        if not page.get("has_more"):
            break
        after = items[-1].get("vehicle_id")
        if not after:
            raise RuntimeError("snapshot cursor missing")
    if pages[-1].get("has_more"):
        raise RuntimeError("snapshot exceeds five-page contract")
    revision_keys = ("dealer_code", "environment", "response_revision", "operational_revision", "rule_set_hash")
    for page in pages[1:]:
        if any(page.get(key) != pages[0].get(key) for key in revision_keys):
            raise RuntimeError("snapshot revision changed during paging")
    manifest = []
    cursor = None
    rows = []
    for number, page in enumerate(pages, 1):
        items = page["items"]
        manifest.append({
            "after_vehicle_id": cursor,
            "first_vehicle_id": items[0]["vehicle_id"],
            "has_more": bool(page["has_more"]),
            "item_count": len(items),
            "last_vehicle_id": items[-1]["vehicle_id"],
            "operational_revision": page["operational_revision"],
            "page_number": number,
            "page_size": 100,
            "response_revision": page["response_revision"],
        })
        rows.extend(items)
        cursor = items[-1]["vehicle_id"]
    merged = dict(pages[0])
    merged.update({"items": rows, "item_count": len(rows), "has_more": False, "next_after_vehicle_id": None})
    return merged, manifest


def analyze(snapshot):
    js = "const fs=require('fs'),a=require('./pdc-ai-auditor-stage-a.js');const s=JSON.parse(fs.readFileSync(0,'utf8'));process.stdout.write(JSON.stringify(a.analyze(s)));"
    proc = subprocess.run(["node", "-e", js], cwd=ROOT, input=json.dumps(snapshot), text=True, capture_output=True, timeout=120)
    if proc.returncode:
        raise RuntimeError("deterministic Auditor engine failed: " + proc.stderr[-800:])
    return json.loads(proc.stdout)


def slug(value, limit=64):
    value = re.sub(r"[^a-z0-9]+", "_", str(value or "").lower()).strip("_")
    if not value or not value[0].isalpha():
        value = "finding_" + value
    return value[:limit].rstrip("_")


def stable_uuid(*parts):
    raw = bytearray(hashlib.sha256("|".join(map(str, parts)).encode()).digest()[:16])
    raw[6] = (raw[6] & 0x0F) | 0x40
    raw[8] = (raw[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(raw)))


def entity_catalog(snapshot):
    catalog = {}
    for row in snapshot["items"]:
        catalog[row["vehicle_id"]] = "vehicle"
        for item in row.get("work_items", []):
            if item.get("work_item_id"):
                catalog[item["work_item_id"]] = "work_item"
        for item in row.get("bookings", []):
            if item.get("booking_id"):
                catalog[item["booking_id"]] = "booking"
        for item in row.get("operation_lines", []):
            for key in ("operation_line_id", "line_id", "id"):
                if item.get(key):
                    catalog[item[key]] = "operation_line"
                    break
        for item in row.get("line_adjustments", []):
            for key in ("line_adjustment_id", "adjustment_id", "id"):
                if item.get(key):
                    catalog[item[key]] = "line_adjustment"
                    break
    return catalog


def category(rule):
    if "station" in rule or "bay" in rule:
        return "station_compatibility"
    if "department" in rule:
        return "department_mismatch"
    if "booking_work" in rule or "relationship" in rule:
        return "booking_work_relationship"
    if any(term in rule for term in ("booking", "overlap", "duration", "hours", "forgotten", "schedule")):
        return "schedule_risk"
    return "data_quality"


def typed_findings(snapshot, analysis):
    catalog = entity_catalog(snapshot)
    detected_at = snapshot["generated_at"]
    output, seen = [], set()
    for finding in analysis.get("findings", []):
        rule = slug(finding.get("ruleId") or finding.get("rule_id"), 64)
        candidates = [finding.get("vehicleId"), *(finding.get("scope") or [])]
        entity_id = next((str(value) for value in candidates if str(value or "") in catalog), None)
        if not entity_id:
            continue
        entity_type = catalog[entity_id]
        identity = (rule, entity_type, entity_id)
        if identity in seen:
            continue
        seen.add(identity)
        severity = str(finding.get("severity") or "medium").lower()
        if severity not in ("info", "low", "medium", "high", "critical"):
            severity = "medium"
        score = {"info": 0, "low": 3, "medium": 8, "high": 15, "critical": 25}[severity]
        output.append({
            "category": category(rule),
            "confidence": 0.9,
            "detected_at": detected_at,
            "entity_id": entity_id,
            "entity_type": entity_type,
            "evidence": [{
                "boolean_value": True,
                "entity_id": entity_id,
                "entity_type": entity_type,
                "field_code": "condition_present",
                "numeric_value": None,
                "signal_code": rule[:80],
                "timestamp_value": None,
            }],
            "finding_id": stable_uuid(snapshot["dealer_code"], rule, entity_type, entity_id),
            "risk_score": score,
            "rule_key": rule,
            "scoring_version": "stage_a_rules_v1",
            "severity": severity,
            "summary_code": rule[:80],
        })
        if len(output) == 100:
            break
    return output


def payload_hash(dsn, base_run, findings):
    with psycopg.connect(dsn, autocommit=True) as conn:
        cur = conn.cursor()
        cur.execute("""select encode(extensions.digest(convert_to(
          (%s::jsonb-array['payload_hash','request_hash']::text[])::text||'|'||%s::jsonb::text,
          'UTF8'),'sha256'),'hex')""", (json.dumps(base_run), json.dumps(findings)))
        return cur.fetchone()[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="submit the evaluated finding set; otherwise dry-run")
    args = parser.parse_args()
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    email = os.environ.get("PDC_STAGING_ADMIN_EMAIL", "").strip().lower()
    password = os.environ.get("PDC_STAGING_ADMIN_PASSWORD", "")
    if not dsn or not email or not password:
        raise RuntimeError("staging publisher environment incomplete")
    url, key = config()
    auth = post(url, key, "/auth/v1/token?grant_type=password", {"email": email, "password": password})
    token = auth.get("access_token")
    if not token:
        raise RuntimeError("staging worker authentication failed")
    snapshot, manifest = exact_snapshot(url, key, token)
    analysis = analyze(snapshot)
    findings = typed_findings(snapshot, analysis)
    if not findings:
        raise RuntimeError("deterministic Auditor produced no publishable scoped findings")
    run_id = str(uuid.uuid4())
    base = {
        "dealer_code": snapshot["dealer_code"],
        "environment": "staging",
        "model_key": "deterministic-stage-a-rules",
        "operational_revision": snapshot["operational_revision"],
        "rule_set_hash": snapshot["rule_set_hash"],
        "run_id": run_id,
        "snapshot_complete": True,
        "snapshot_generated_at": snapshot["generated_at"],
        "snapshot_page_manifest": manifest,
        "snapshot_response_revision": snapshot["response_revision"],
        "snapshot_vehicle_count": len(snapshot["items"]),
    }
    digest = payload_hash(dsn, base, findings)
    run = {**base, "payload_hash": digest, "request_hash": digest}
    receipt = None
    if args.publish:
        receipt = post(url, key, "/rest/v1/rpc/submit_pdc_auditor_findings", {"p_run": run, "p_findings": findings}, token)
        if not receipt.get("ok") or receipt.get("run_id") != run_id:
            raise RuntimeError("finding submission receipt invalid")
    print(json.dumps({
        "status": "published" if args.publish else "dry_run",
        "environment": "staging",
        "dealer_code": snapshot["dealer_code"],
        "snapshot_vehicle_count": len(snapshot["items"]),
        "snapshot_page_count": len(manifest),
        "engine_finding_count": len(analysis.get("findings", [])),
        "published_finding_count": len(findings) if args.publish else 0,
        "publishable_finding_count": len(findings),
        "run_id": run_id if args.publish else None,
        "receipt_code": receipt.get("code") if receipt else None,
        "credentials_exposed": False,
        "operational_change": False,
        "production_changed": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
