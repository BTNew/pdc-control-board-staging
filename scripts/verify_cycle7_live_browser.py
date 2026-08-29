from __future__ import annotations

import json
import os
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = "https://btnew.github.io/pdc-control-board-staging/"
EXPECTED_PROJECT = "cdsmnqxtyyoeoznmbidd"
VIEWS = [
    "dashboard", "workflow", "planner-bus-4x4", "planner-tint", "planner-hoist",
    "planner-fitting", "planner-fab", "planner-elec", "planner-tyre", "parts",
    "sublet", "rft",
]

def main() -> None:
    email = os.environ.get("PDC_STAGING_ADMIN_EMAIL")
    password = os.environ.get("PDC_STAGING_ADMIN_PASSWORD")
    if not email or not password:
        raise RuntimeError("approved staging administrator credentials are unavailable")
    results = {"url": URL, "project_ref": EXPECTED_PROJECT, "views": {}, "errors": {"page": [], "console": [], "requests": []}, "production_requests": []}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1000})
        page = context.new_page()
        page.on("pageerror", lambda error: results["errors"]["page"].append(str(error)))
        page.on("console", lambda message: results["errors"]["console"].append(message.text) if message.type == "error" else None)
        page.on("requestfailed", lambda request: results["errors"]["requests"].append(f"{request.method} {request.url}"))
        page.on("response", lambda response: results["errors"]["requests"].append(f"HTTP {response.status} {response.url}") if response.status >= 400 else None)
        page.on("request", lambda request: results["production_requests"].append(request.url) if "vjdtsswhroyguxyfjdkt" in request.url or "pdc-control-board/" in request.url and "pdc-control-board-staging" not in request.url else None)
        page.goto(URL + "?cycle7=" + str(int(time.time())), wait_until="domcontentloaded", timeout=90000)
        page.wait_for_function("() => document.body.dataset.authState === 'signed-out' || document.body.dataset.authState === 'approved'", timeout=90000)
        page.locator("#pdc-login-email").fill(email)
        page.locator("#pdc-login-password").fill(password)
        page.locator("#pdc-password-login").click()
        page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=90000)
        results["auth"] = page.evaluate("() => ({state: document.body.dataset.authState, role: window.PDC_AUTH_CONTEXT?.role || null, project: window.PDC_SUPABASE_CONFIG?.projectRef || null})")
        for view in VIEWS:
            button = page.locator(f"[data-view='{view}']")
            if button.count() != 1:
                results["views"][view] = {"present": False}
                continue
            button.click()
            page.wait_for_timeout(1200)
            results["views"][view] = page.evaluate("view => ({present: true, currentView: window.app?.currentView || null, authState: document.body.dataset.authState, inert: document.getElementById('app-shell')?.hasAttribute('inert'), bodyTextMarkers: {accessDenied: document.body.innerText.includes('Access not approved'), loading: document.body.innerText.includes('Loading')}})", view)
        result = page.evaluate("""async () => {
          const token = window.__pdcCachedAccessToken;
          const config = window.PDC_SUPABASE_CONFIG;
          const row = window.app?.emailVehicleLocationRows?.find(item => item?.id || item?.permanent_vehicle_id);
          const vehicleId = row?.id || row?.permanent_vehicle_id || null;
          const out = {vehicle_id_present: Boolean(vehicleId), planner: null, intake_status: null};
          const headers = {apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'};
          if (vehicleId) {
            const response = await fetch(`${config.url}/rest/v1/rpc/get_vehicle_workshop_detail_scoped`, {method:'POST', headers, body: JSON.stringify({p_vehicle_id: vehicleId, p_dealer_code: config.dealerCode || '14450'})});
            out.planner = {status: response.status, ok: response.ok, body_keys: Object.keys(await response.json().catch(() => ({}))).sort()};
          }
          const denied = await fetch(`${config.url}/rest/v1/rpc/get_vehicle_workshop_detail_scoped`, {method:'POST', headers, body: JSON.stringify({p_vehicle_id: '00000000-0000-4000-8000-000000000000', p_dealer_code: '37047'})});
          out.planner_negative = {status: denied.status, body: await denied.json().catch(() => null)};
          return out;
        }""")
        results["rpc_probes"] = result
        results["errors"]["requests"] = results["errors"]["requests"][:50]
        context.close(); browser.close()
    results["ok"] = bool(results.get("auth", {}).get("state") == "approved" and results.get("auth", {}).get("project") == EXPECTED_PROJECT and not results["production_requests"] and not results["errors"]["page"] and not results["errors"]["console"])
    print(json.dumps(results, sort_keys=True))

if __name__ == "__main__":
    main()
