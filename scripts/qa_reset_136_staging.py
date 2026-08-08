#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from collections import Counter
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import load_local_env

URL = "https://btnew.github.io/pdc-control-board-staging/?resetRelease=20260808-02-clean-workbook-reset"
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREVIEW = ROOT / "artifacts" / "reset_136_preview.json"
EVIDENCE = ROOT / "artifacts" / "reset_136_live_qa"


def main() -> None:
    load_local_env()
    email = os.environ.get("PDC_STAGING_ADMIN_EMAIL")
    password = os.environ.get("PDC_STAGING_ADMIN_PASSWORD")
    if not email or not password:
        raise RuntimeError("staging administrator browser credentials are not configured")
    preview = json.loads(PREVIEW.read_text(encoding="utf-8"))
    excluded_stock = preview["exceptions"][0]["stock_number"]
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    output = {"ok": False, "environment": "staging", "productionRequests": 0, "credentialsExposed": False}
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1000})
        page = context.new_page()
        errors, failed, production = [], [], []
        page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("requestfailed", lambda request: failed.append(request.url))
        page.on("request", lambda request: production.append(request.url) if PRODUCTION_REF in request.url else None)
        page.goto(URL, wait_until="networkidle", timeout=60000)
        if page.locator("#app-version").inner_text().strip() != "Version 2026.08.08.02-clean-workbook-reset":
            raise AssertionError("live staging release marker mismatch")
        page.fill("#pdc-login-email", email)
        page.fill("#pdc-login-password", password)
        page.click("#pdc-password-login")
        page.locator("body[data-auth-state='approved']").wait_for(state="attached", timeout=30000)
        page.wait_for_function("window.PDC_SUPABASE && window.PDC_SUPABASE_CONFIG && window.PDC_SUPABASE_CONFIG.projectRef === 'cdsmnqxtyyoeoznmbidd'", timeout=30000)
        snapshot_result = page.evaluate("""async () => {
          const result = await window.PDC_SUPABASE.rpc('get_pdc_email_vehicle_location_snapshot');
          return { data: result.data, error: result.error ? { message: result.error.message, code: result.error.code } : null };
        }""")
        if snapshot_result["error"]:
            raise AssertionError(f"snapshot RPC failed: {snapshot_result['error']}")
        snapshot = snapshot_result["data"] or {}
        vehicles = snapshot.get("vehicles") or []
        if len(vehicles) != 325:
            raise AssertionError(f"live visible vehicle count mismatch: {len(vehicles)}")
        locations = Counter(row.get("current_location") for row in vehicles)
        expected_locations = {"IT": 72, "Other": 79, "PMB": 121, "RFT": 3, "YH": 50}
        if dict(sorted(locations.items())) != expected_locations:
            raise AssertionError(f"live location split mismatch: {dict(locations)}")
        stocks = [str(row.get("stock_number") or "").strip().upper() for row in vehicles]
        if len(stocks) != len(set(stocks)) or excluded_stock.strip().upper() in set(stocks):
            raise AssertionError("duplicate or quarantined Stock visible on board")
        lines = [line for row in vehicles for line in (row.get("operation_lines") or [])]
        if len(lines) != 2943:
            raise AssertionError(f"live operation count mismatch: {len(lines)}")
        if any(not line.get("job_card_number") or not line.get("source_row_no") or line.get("source_contract") != "pdc_staging_workbook_reset_136" for line in lines):
            raise AssertionError("operation Job Card/source identity incomplete")
        repeated = next((row for row in vehicles if len({line.get("job_card_number") for line in (row.get("operation_lines") or [])}) > 1), None)
        if not repeated:
            raise AssertionError("no repeated-Stock multi-Job-Card vehicle found")
        repeated_jcs = sorted({line["job_card_number"] for line in repeated["operation_lines"]})
        page.evaluate("stock => openVehicleModal(stock)", repeated["stock_number"])
        page.locator("#vehicle-modal:not([hidden])").wait_for(state="visible", timeout=30000)
        modal_text = page.locator("#vehicle-modal").inner_text()
        for job_card in repeated_jcs:
            if f"JC {job_card}" not in modal_text:
                raise AssertionError("repeated Job Card identity missing from vehicle modal")
        page.screenshot(path=str(EVIDENCE / "repeated-stock-job-cards.png"), full_page=True)
        page.evaluate("closeVehicleModal()")
        page.click("[data-view='workshop']")
        page.locator("#workshop-planner-root").wait_for(state="visible", timeout=30000)
        page.wait_for_timeout(1500)
        planner_bookings = page.locator("[data-workshop-booking-id],.workshop-booking-card").count()
        if planner_bookings:
            raise AssertionError(f"workshop planner rendered stale bookings: {planner_bookings}")
        if errors or failed or production:
            raise AssertionError(f"browser errors={len(errors)} failed={len(failed)} production={len(production)}")
        output.update({"ok": True, "release": "2026.08.08.02-clean-workbook-reset", "stagingProjectRef": STAGING_REF,
            "vehicles": len(vehicles), "locations": dict(sorted(locations.items())), "operations": len(lines),
            "repeatedJobCardCount": len(repeated_jcs), "plannerBookings": planner_bookings,
            "consoleErrors": 0, "failedRequests": 0, "productionRequests": 0,
            "screenshot": "repeated-stock-job-cards.png"})
        context.close()
        browser.close()
    (EVIDENCE / "live-qa.json").write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
