#!/usr/bin/env python3
"""Authenticated live staging QA for the AI Auditor review surface."""
from __future__ import annotations

import json
import os
from pathlib import Path

from playwright.sync_api import sync_playwright

URL = "https://btnew.github.io/pdc-control-board-staging/?auditorRelease=20260730-03-recorded-decision-render#ai-auditor"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "review-evidence/ai-auditor-human-review"
ROLES = [
    ("administrator", "PDC_STAGING_ADMIN_EMAIL", "PDC_STAGING_ADMIN_PASSWORD", True),
    ("operator", "PDC_STAGING_CONTROLLER_A_EMAIL", "PDC_STAGING_CONTROLLER_A_PASSWORD", True),
    ("viewer", "PDC_STAGING_VIEWER_EMAIL", "PDC_STAGING_VIEWER_PASSWORD", False),
]


def main():
    if any(not os.environ.get(key) for _role, email, password, _write in ROLES for key in (email, password)):
        raise RuntimeError("staging browser QA environment incomplete")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    output = {"status": "passed", "environment": "staging", "roles": {}, "productionRequests": 0, "credentialsExposed": False}
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        for role, email_env, password_env, can_decide in ROLES:
            context = browser.new_context(viewport={"width": 1366, "height": 900})
            page = context.new_page()
            errors, failed, production = [], [], []
            page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("requestfailed", lambda request: failed.append(request.url))
            page.on("request", lambda request: production.append(request.url) if PRODUCTION_REF in request.url else None)
            page.goto(URL, wait_until="networkidle", timeout=60000)
            page.fill("#pdc-login-email", os.environ[email_env])
            page.fill("#pdc-login-password", os.environ[password_env])
            page.click("#pdc-password-login")
            try:
                page.locator("body[data-auth-state='approved']").wait_for(state="attached", timeout=30000)
            except Exception as exc:
                login_error = page.locator('#pdc-login-error').inner_text().strip() if page.locator('#pdc-login-error').count() else ''
                raise AssertionError(f"{role} sign-in did not become approved; state={page.locator('body').get_attribute('data-auth-state')}; error_present={bool(login_error)}") from exc
            page.locator('[data-view="ai-auditor"]').wait_for(state="visible", timeout=30000)
            page.click('[data-view="ai-auditor"]')
            page.locator('#ai-auditor-state[data-state="ready"]').wait_for(state="visible", timeout=60000)
            if page.locator('.ai-auditor-read-only-banner strong').inner_text().strip() != "BETA – HUMAN REVIEW / NO AUTOMATIC CHANGES":
                raise AssertionError(f"{role} banner mismatch")
            if page.locator('[data-view="ai-auditor"]').inner_text().strip() != "AI Auditor":
                raise AssertionError(f"{role} menu label mismatch")
            finding_count = 0
            approve_count = 0
            deny_count = 0
            for report in ("morning", "midday", "eod", "critical"):
                page.click(f'[data-ai-auditor-report="{report}"]')
                finding_count = max(finding_count, page.locator('.ai-auditor-finding').count())
                approve_count += page.locator('[data-ai-auditor-decision="approved"]').count()
                deny_count += page.locator('[data-ai-auditor-decision="denied"]').count()
            if finding_count < 1:
                raise AssertionError(f"{role} rendered no current findings")
            if can_decide and (approve_count < 1 or deny_count < 1):
                raise AssertionError(f"{role} did not receive review controls")
            if not can_decide and (approve_count or deny_count):
                raise AssertionError("viewer received decision controls")
            if page.locator('text=Approval is not execution').count() != 1:
                raise AssertionError(f"{role} non-execution boundary missing")
            if errors or failed or production:
                raise AssertionError(f"{role} browser errors={len(errors)} failed={len(failed)} production={len(production)}")
            screenshot = EVIDENCE / f"{role}-1366x900.png"
            page.screenshot(path=str(screenshot), full_page=True)
            output["roles"][role] = {
                "snapshotReady": True,
                "findingsRendered": finding_count,
                "approveControls": approve_count,
                "denyControls": deny_count,
                "canDecide": can_decide,
                "consoleErrors": 0,
                "failedRequests": 0,
                "productionRequests": 0,
                "screenshot": screenshot.name,
            }
            context.close()
        browser.close()
    (EVIDENCE / "live-staging-qa.json").write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", "utf-8")
    print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
