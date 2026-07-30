#!/usr/bin/env python3
"""Authenticated staging browser proof for one non-executable Auditor denial."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import psycopg
from playwright.sync_api import sync_playwright

URL = "https://btnew.github.io/pdc-control-board-staging/?auditorRelease=20260730-03-recorded-decision-render#ai-auditor"
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "review-evidence/ai-auditor-human-review"
REASON = "Staging browser QA only — recommendation not operationally executed."


def signatures(cur):
    cur.execute("select tablename from pg_tables where schemaname='public' and tablename not like 'pdc_auditor_%' order by tablename")
    result = {}
    for (table,) in cur.fetchall():
        safe = '"' + table.replace('"', '""') + '"'
        cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{safe} t")
        result[table] = cur.fetchone()
    return result


def main():
    for key in ("PDC_STAGING_DATABASE_URL", "PDC_STAGING_ADMIN_EMAIL", "PDC_STAGING_ADMIN_PASSWORD"):
        if not os.environ.get(key):
            raise RuntimeError(f"{key} missing")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    with psycopg.connect(os.environ["PDC_STAGING_DATABASE_URL"], autocommit=True) as conn:
        cur = conn.cursor()
        before = signatures(cur)
        cur.execute("select count(*) from public.pdc_auditor_decisions")
        decisions_before = cur.fetchone()[0]
        cur.execute("""select decision_id,finding_id,evidence_fingerprint,finding_last_seen_run_id,decision,reason,decided_by_role,operational_change,execution_reference
          from public.pdc_auditor_decisions where reason=%s order by decided_at desc limit 1""", (REASON,))
        existing = cur.fetchone()

        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1366, "height": 900})
            page = context.new_page()
            errors, failed, production = [], [], []
            page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("requestfailed", lambda request: failed.append(request.url))
            page.on("request", lambda request: production.append(request.url) if "vjdtsswhroyguxyfjdkt" in request.url else None)
            page.goto(URL, wait_until="networkidle", timeout=60000)
            page.fill("#pdc-login-email", os.environ["PDC_STAGING_ADMIN_EMAIL"])
            page.fill("#pdc-login-password", os.environ["PDC_STAGING_ADMIN_PASSWORD"])
            page.click("#pdc-password-login")
            page.locator("body[data-auth-state='approved']").wait_for(state="attached", timeout=30000)
            page.click('[data-view="ai-auditor"]')
            page.locator('#ai-auditor-state[data-state="ready"]').wait_for(state="visible", timeout=60000)
            created = existing is None
            if created:
                page.evaluate("report => selectPdcAuditorReport(report)", "critical")
                page.locator('#ai-auditor-report').filter(has_text="Critical report").wait_for(timeout=10000)
                # Client-side denial validation must reject a too-short reason without a network decision.
                first = page.locator('[data-ai-auditor-decision="denied"]').first
                first.wait_for(state="visible", timeout=30000)
                page.once("dialog", lambda dialog: dialog.accept("x"))
                first.click()
                page.locator('.ai-auditor-decision-message').filter(has_text="between 3 and 500").wait_for(state="visible", timeout=10000)
                cur.execute("select count(*) from public.pdc_auditor_decisions")
                if cur.fetchone()[0] != decisions_before:
                    raise AssertionError("short denial reason reached persistence")

                first = page.locator('[data-ai-auditor-decision="denied"]').first
                page.once("dialog", lambda dialog: dialog.accept(REASON))
                first.click()
                page.locator('#ai-auditor-state[data-state="ready"]').wait_for(state="visible", timeout=60000)
                cur.execute("""select decision_id,finding_id,evidence_fingerprint,finding_last_seen_run_id,decision,reason,decided_by_role,operational_change,execution_reference
                  from public.pdc_auditor_decisions where reason=%s order by decided_at desc limit 1""", (REASON,))
                row = cur.fetchone()
            else:
                row = existing

            if not row:
                raise AssertionError("browser decision was not persisted")
            decision_id, finding_id, fingerprint, run_id, decision, reason, role, operational_change, execution_reference = row
            if (decision, reason, role, operational_change, execution_reference) != ("denied", REASON, "administrator", False, None):
                raise AssertionError("decision audit receipt mismatch")
            cur.execute("select count(*) from public.pdc_auditor_decisions")
            expected_count = decisions_before + (1 if created else 0)
            if cur.fetchone()[0] != expected_count:
                raise AssertionError("browser QA created an unexpected number of decisions")

            visible_report = None
            labels = {"morning": "Morning report", "midday": "Midday report", "eod": "EOD report", "critical": "Critical report"}
            for report, label in labels.items():
                page.evaluate("value => selectPdcAuditorReport(value)", report)
                page.locator('#ai-auditor-report').filter(has_text=label).wait_for(timeout=10000)
                if page.locator('.ai-auditor-review-status.is-denied').filter(has_text=REASON).count():
                    visible_report = report
                    break
            if not visible_report:
                raise AssertionError("persisted decision did not render in any report")
            page.screenshot(path=str(EVIDENCE / "administrator-denied-1366x900.png"), full_page=True)

            # Exact authenticated replay must be idempotent; stale evidence must fail closed.
            replay = page.evaluate("""async args => {
              const session = (await window.PDC_SUPABASE.auth.getSession()).data.session;
              const response = await fetch(window.PDC_SUPABASE_CONFIG.url + '/rest/v1/rpc/record_pdc_auditor_decision', {
                method: 'POST', headers: { apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + session.access_token, 'Content-Type': 'application/json' }, body: JSON.stringify(args)
              });
              return { status: response.status, body: await response.json() };
            }""", {"p_finding_id": str(finding_id), "p_evidence_fingerprint": fingerprint, "p_last_seen_run_id": str(run_id), "p_decision": "denied", "p_reason": REASON})
            if replay["status"] != 200 or replay["body"].get("idempotent") is not True or replay["body"].get("decision_id") != str(decision_id):
                raise AssertionError("exact browser replay was not idempotent")
            stale = page.evaluate("""async args => {
              const session = (await window.PDC_SUPABASE.auth.getSession()).data.session;
              const response = await fetch(window.PDC_SUPABASE_CONFIG.url + '/rest/v1/rpc/record_pdc_auditor_decision', {
                method: 'POST', headers: { apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + session.access_token, 'Content-Type': 'application/json' }, body: JSON.stringify(args)
              });
              return { status: response.status, body: await response.text() };
            }""", {"p_finding_id": str(finding_id), "p_evidence_fingerprint": "0" * 64, "p_last_seen_run_id": str(run_id), "p_decision": "denied", "p_reason": REASON})
            if stale["status"] == 200 or "pdc_auditor_stale_finding" not in stale["body"]:
                raise AssertionError("stale browser submission did not fail closed")
            if errors or failed or production:
                raise AssertionError(f"browser errors={len(errors)} failed={len(failed)} production={len(production)}")
            context.close()
            browser.close()

        after = signatures(cur)
        changed = sorted(table for table in before if before[table] != after.get(table))
        if changed:
            raise AssertionError("non-Auditor operational rows changed: " + ",".join(changed))
        report = {
            "status": "passed", "environment": "staging", "decision": "denied",
            "decisionId": str(decision_id), "findingId": str(finding_id), "exactReplayIdempotent": True,
            "staleEvidenceRejected": True, "shortReasonRejectedClientSide": True,
            "reviewerRole": role, "operationalChange": False, "executionReference": None,
            "nonAuditorSignaturesUnchanged": True, "productionRequests": 0,
            "consoleErrors": 0, "failedRequests": 0, "screenshot": "administrator-denied-1366x900.png",
        }
        (EVIDENCE / "decision-live-staging-qa.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", "utf-8")
        print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
