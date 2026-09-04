from __future__ import annotations

import json
import os
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

URL = "https://btnew.github.io/pdc-control-board-staging/"
EXPECTED_PROJECT = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_PROJECT = "vjdtsswhroyguxyfjdkt"
VIEWPORTS = [(360, 800), (768, 900), (1440, 1000)]
OUT = Path(__file__).resolve().parent / "screenshots"


def main() -> None:
    email = os.environ.get("PDC_STAGING_ADMIN_EMAIL")
    password = os.environ.get("PDC_STAGING_ADMIN_PASSWORD")
    OUT.mkdir(parents=True, exist_ok=True)
    result = {
        "url": URL,
        "expected_project_ref": EXPECTED_PROJECT,
        "production_contacted": False,
        "production_requests": [],
        "viewports": [],
    }
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        for width, height in VIEWPORTS:
            context = browser.new_context(viewport={"width": width, "height": height})
            page = context.new_page()
            errors = {"page": [], "console": [], "requests": []}
            page.on("pageerror", lambda error, bucket=errors["page"]: bucket.append(str(error)))
            page.on("console", lambda message, bucket=errors["console"]: bucket.append(message.text) if message.type == "error" else None)
            page.on("requestfailed", lambda request, bucket=errors["requests"]: bucket.append(f"{request.method} {request.url}"))
            page.on("response", lambda response, bucket=errors["requests"]: bucket.append(f"HTTP {response.status} {response.url}") if response.status >= 400 else None)
            def inspect_request(request):
                if PRODUCTION_PROJECT in request.url or ("pdc-control-board/" in request.url and "pdc-control-board-staging" not in request.url):
                    result["production_requests"].append(request.url)
            page.on("request", inspect_request)
            page.goto(URL + "?qa_overnight=" + str(int(time.time())), wait_until="domcontentloaded", timeout=90000)
            page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
            if email and password and page.evaluate("() => document.body.dataset.authState") == "signed-out":
                page.locator("#pdc-login-email").fill(email)
                page.locator("#pdc-login-password").fill(password)
                page.locator("#pdc-password-login").click()
                page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=90000)
            page.wait_for_timeout(2000)
            screenshot = OUT / f"staging-post-cleanup-{width}x{height}.png"
            page.screenshot(path=str(screenshot), full_page=True)
            state = page.evaluate("""() => ({
                authState: document.body.dataset.authState,
                role: window.PDC_AUTH_CONTEXT?.role || null,
                projectRef: window.PDC_SUPABASE_CONFIG?.projectRef || null,
                currentView: window.app?.currentView || null,
                bodyText: document.body.innerText.slice(0, 300),
                syntheticTextPresent: document.body.innerText.includes('QA-OVERNIGHT-20260904'),
                horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
                scrollWidth: document.documentElement.scrollWidth,
                clientWidth: document.documentElement.clientWidth,
                navigationViews: [...document.querySelectorAll('[data-view]')].map(el => el.dataset.view).filter(Boolean)
            })""")
            result["viewports"].append({
                "width": width,
                "height": height,
                "screenshot": str(screenshot),
                "state": state,
                "errors": errors,
            })
            context.close()
        browser.close()
    result["production_contacted"] = bool(result["production_requests"])
    result["ok"] = all(
        item["state"]["authState"] == ("approved" if email and password else "signed-out")
        and item["state"]["projectRef"] == EXPECTED_PROJECT
        and not item["errors"]["page"]
        and not item["errors"]["console"]
        and not item["state"]["syntheticTextPresent"]
        for item in result["viewports"]
    ) and not result["production_contacted"]
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
