"""Read-only authenticated browser QA for HERMES-TEST-019 on isolated staging."""
from __future__ import annotations

import hashlib
import json
import pathlib
import time
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "_overnight_evidence" / "browser-019"
BASE = "https://btnew.github.io/pdc-control-board-staging/"
REF = "cdsmnqxtyyoeoznmbidd"
ALLOWED_HOSTS = {"btnew.github.io", f"{REF}.supabase.co"}
ROUTES = {
    "dashboard": "dashboard",
    "workflow": "workflow",
    "workshop/fitting": "planner-fitting",
    "parts": "parts",
    "sublet": "sublet",
    "qc": "qc",
    "rft": "rft",
}


def safe_host(url: str) -> bool:
    parsed = urlsplit(url)
    return parsed.scheme in {"https", "data", "blob"} and (parsed.scheme in {"data", "blob"} or parsed.hostname in ALLOWED_HOSTS)


def install_network_guard(context, evidence: dict) -> None:
    def guard(route):
        url = route.request.url
        if safe_host(url):
            route.continue_()
        else:
            evidence["blocked_external_hosts"].append(urlsplit(url).hostname or url[:80])
            route.abort("blockedbyclient")
    context.route("**/*", guard)


def attach_observers(page, evidence: dict, label: str) -> None:
    page.on("console", lambda msg: evidence["console"].append({"session": label, "type": msg.type, "text": msg.text[:500]}) if msg.type in {"error", "warning"} else None)
    page.on("pageerror", lambda exc: evidence["page_errors"].append({"session": label, "text": str(exc)[:1000]}))
    page.on("requestfailed", lambda request: evidence["failed_requests"].append({"session": label, "url": request.url, "reason": request.failure}))
    page.on("response", lambda response: evidence["http_errors"].append({"session": label, "status": response.status, "url": response.url}) if response.status >= 400 else None)


def wait_eval(page, expression: str, timeout_ms: int = 60000) -> None:
    """Poll without waitForFunction, which the staging CSP correctly blocks."""
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        if page.evaluate(expression):
            return
        page.wait_for_timeout(200)
    raise TimeoutError(f"browser condition timed out: {expression}")


def login(page, email: str, password: str) -> dict:
    page.goto(BASE + "?hermes019=authenticated#/dashboard", wait_until="domcontentloaded", timeout=60000)
    page.locator("#pdc-password-form").wait_for(state="visible", timeout=30000)
    page.locator("#pdc-login-email").fill(email)
    page.locator("#pdc-login-password").fill(password)
    page.locator("#pdc-password-form").evaluate("form => form.requestSubmit()")
    page.locator("#app-shell").wait_for(state="visible", timeout=60000)
    wait_eval(page, "!document.querySelector('#app-shell').hasAttribute('inert')")
    wait_eval(page, "typeof selectedVehicle === 'function' && !!selectedVehicle('HERMES-TEST-019')")
    page.evaluate("""() => { const u=document.querySelector('#pdc-auth-user'); if(u) u.textContent='HERMES STAGING ADMIN'; }""")
    return page.evaluate("""() => ({
      title: document.title,
      shellInert: document.querySelector('#app-shell').hasAttribute('inert'),
      shellAriaHidden: document.querySelector('#app-shell').getAttribute('aria-hidden'),
      synthetic019Loaded: typeof selectedVehicle === 'function' && !!selectedVehicle('HERMES-TEST-019'),
      totalLabel: document.querySelector('#backend-data-status, #vehicle-count, [data-vehicle-count]')?.textContent?.trim() || ''
    })""")


def active_view(page) -> str:
    return page.evaluate("""() => Array.from(document.querySelectorAll('.view')).find(x => {
      const s=getComputedStyle(x); return !x.hidden && s.display !== 'none' && s.visibility !== 'hidden';
    })?.id || ''""")


def route_tests(page, evidence: dict) -> None:
    for path, expected in ROUTES.items():
        page.goto(BASE + f"?hermes019=route-{path.replace('/', '-')}#/{path}", wait_until="domcontentloaded", timeout=60000)
        wait_eval(page, "!document.querySelector('#app-shell').hasAttribute('inert')")
        page.wait_for_timeout(700)
        first = active_view(page)
        page.reload(wait_until="domcontentloaded", timeout=60000)
        wait_eval(page, "!document.querySelector('#app-shell').hasAttribute('inert')")
        page.wait_for_timeout(500)
        reloaded = active_view(page)
        nav_active = page.locator(f'[data-view="{expected}"].active').count() > 0
        evidence["routes"].append({"path": path, "expected": expected, "first": first, "reloaded": reloaded, "hash": page.evaluate("location.hash"), "nav_active": nav_active})


def accessibility_snapshot(page) -> dict:
    return page.evaluate("""() => {
      const visible = el => { const s=getComputedStyle(el), r=el.getBoundingClientRect(); return !el.hidden && s.display!=='none' && s.visibility!=='hidden' && r.width>0 && r.height>0; };
      const name = el => (el.getAttribute('aria-label') || el.getAttribute('title') || el.innerText || el.value || el.getAttribute('alt') || '').trim();
      const interactive = Array.from(document.querySelectorAll('button,a[href],input:not([type=hidden]),select,textarea,[role=button],[tabindex]')).filter(visible);
      const unnamed = interactive.filter(el => !name(el)).map(el => ({tag:el.tagName,id:el.id,cls:el.className})).slice(0,50);
      const ids = Array.from(document.querySelectorAll('[id]')).map(x=>x.id);
      const duplicates = [...new Set(ids.filter((x,i)=>ids.indexOf(x)!==i))];
      const unlabeled = Array.from(document.querySelectorAll('input:not([type=hidden]),select,textarea')).filter(visible).filter(el => {
        if(el.getAttribute('aria-label') || el.getAttribute('aria-labelledby')) return false;
        return !el.id || !document.querySelector(`label[for="${CSS.escape(el.id)}"]`) && !el.closest('label');
      }).map(el=>({tag:el.tagName,id:el.id,type:el.type||''})).slice(0,50);
      const smallTargets = interactive.map(el=>{const r=el.getBoundingClientRect(); return {name:name(el).slice(0,60),w:Math.round(r.width),h:Math.round(r.height),tag:el.tagName};}).filter(x=>x.w<44 || x.h<44).slice(0,100);
      return {
        lang: document.documentElement.lang,
        title: document.title,
        h1: Array.from(document.querySelectorAll('h1')).filter(visible).map(x=>x.textContent.trim()),
        interactiveCount: interactive.length,
        unnamed,
        duplicateIds: duplicates,
        unlabeled,
        smallTargets,
        viewport:{w:innerWidth,h:innerHeight,scrollWidth:document.documentElement.scrollWidth,scrollHeight:document.documentElement.scrollHeight},
        horizontalOverflow: document.documentElement.scrollWidth > innerWidth + 2
      };
    }""")


def keyboard_order(page, count: int = 30) -> list[dict]:
    page.locator("body").click(position={"x": 2, "y": 2})
    page.evaluate("document.activeElement && document.activeElement.blur()")
    result = []
    for _ in range(count):
        page.keyboard.press("Tab")
        item = page.evaluate("""() => { const e=document.activeElement; const r=e?.getBoundingClientRect(); return {tag:e?.tagName||'',id:e?.id||'',name:(e?.getAttribute('aria-label')||e?.innerText||e?.value||'').trim().slice(0,80),outline:getComputedStyle(e).outlineStyle,rect:r?{x:Math.round(r.x),y:Math.round(r.y),w:Math.round(r.width),h:Math.round(r.height)}:null}; }""")
        result.append(item)
    return result


def modal_test(page) -> dict:
    page.goto(BASE + "?hermes019=modal#/dashboard", wait_until="domcontentloaded", timeout=60000)
    wait_eval(page, "!document.querySelector('#app-shell').hasAttribute('inert')")
    wait_eval(page, "typeof selectedVehicle === 'function' && !!selectedVehicle('HERMES-TEST-019')")
    search = page.locator("#incoming-search")
    search.fill("HERMES-TEST-019")
    page.wait_for_timeout(500)
    trigger = page.locator('[data-open-stock="HERMES-TEST-019"]:visible').first
    trigger.wait_for(state="visible", timeout=10000)
    trigger.focus()
    trigger_id = trigger.get_attribute("id") or trigger.get_attribute("class") or "HERMES-TEST-019 card"
    trigger.click()
    page.locator("#vehicle-modal").wait_for(state="visible", timeout=10000)
    initial = page.evaluate("document.activeElement?.id || ''")
    focus_sequence=[]
    escaped=False
    for _ in range(80):
        page.keyboard.press("Tab")
        state=page.evaluate("""() => ({id:document.activeElement?.id||'', inside:!!document.activeElement?.closest('#vehicle-modal'), tag:document.activeElement?.tagName||''})""")
        focus_sequence.append(state)
        if not state["inside"]:
            escaped=True
            break
    page.keyboard.press("Escape")
    wait_eval(page, "document.querySelector('#vehicle-modal').hidden === true", 10000)
    after_escape = page.evaluate("""() => ({id:document.activeElement?.id||'', stock:document.activeElement?.getAttribute('data-open-stock')||'', cls:document.activeElement?.className||''})""")
    return {"trigger": trigger_id, "initialFocus": initial, "focusEscapedDialog": escaped, "stepsUntilEscape": len(focus_sequence), "escapeClosed": page.locator('#vehicle-modal').is_hidden(), "focusAfterClose": after_escape, "sample": focus_sequence[:12]}


def run() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    env = env_values()
    if env.get("PDC_STAGING_PROJECT_REF") != REF or REF not in env.get("PDC_STAGING_SUPABASE_URL", ""):
        raise RuntimeError("exact staging credential binding failed")
    proof = prove_environment()
    if proof["database"]["synthetic_vehicle_total"] != 20 or proof["database"]["vehicle_total"] != 173:
        raise RuntimeError("staging sentinel/fleet drift")
    evidence = {
        "schema": "pdc-overnight-browser-019-v1",
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "target": BASE,
        "project_ref": REF,
        "credential_identity": "sha256:" + hashlib.sha256(env["PDC_STAGING_ADMIN2_EMAIL"].strip().lower().encode()).hexdigest(),
        "environment": proof,
        "routes": [], "sessions": [], "console": [], "page_errors": [], "failed_requests": [], "http_errors": [], "blocked_external_hosts": [],
    }
    chrome = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True, executable_path=chrome, args=["--disable-extensions"])
        context1 = browser.new_context(viewport={"width": 1440, "height": 1000}, color_scheme="light")
        install_network_guard(context1, evidence)
        page1 = context1.new_page(); attach_observers(page1, evidence, "desktop-a")
        evidence["sessions"].append({"label":"desktop-a", "login":login(page1, env["PDC_STAGING_ADMIN2_EMAIL"], env["PDC_STAGING_ADMIN2_PASSWORD"])})
        route_tests(page1, evidence)
        page1.goto(BASE + "?hermes019=desktop-a11y#/dashboard", wait_until="domcontentloaded", timeout=60000)
        wait_eval(page1, "!document.querySelector('#app-shell').hasAttribute('inert')"); page1.wait_for_timeout(1000)
        page1.evaluate("""() => { const u=document.querySelector('#pdc-auth-user'); if(u) u.textContent='HERMES STAGING ADMIN'; }""")
        evidence["desktop_accessibility"] = accessibility_snapshot(page1)
        evidence["keyboard_order"] = keyboard_order(page1)
        page1.locator("#incoming-search").fill("HERMES-TEST-019")
        page1.wait_for_timeout(500)
        page1.screenshot(path=str(OUT / "desktop-dashboard.png"), full_page=False)
        evidence["modal"] = modal_test(page1)

        context2 = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1, is_mobile=True, has_touch=True)
        install_network_guard(context2, evidence)
        page2 = context2.new_page(); attach_observers(page2, evidence, "mobile-b")
        login2 = login(page2, env["PDC_STAGING_ADMIN2_EMAIL"], env["PDC_STAGING_ADMIN2_PASSWORD"])
        page2.goto(BASE + "?hermes019=mobile#/workflow", wait_until="domcontentloaded", timeout=60000)
        wait_eval(page2, "!document.querySelector('#app-shell').hasAttribute('inert')"); page2.wait_for_timeout(1200)
        page2.evaluate("""() => { const u=document.querySelector('#pdc-auth-user'); if(u) u.textContent='HERMES STAGING ADMIN'; }""")
        evidence["sessions"].append({"label":"mobile-b", "login":login2, "activeView":active_view(page2), "synthetic019":page2.evaluate("typeof selectedVehicle === 'function' && !!selectedVehicle('HERMES-TEST-019')")})
        evidence["mobile_accessibility"] = accessibility_snapshot(page2)
        page2.locator("#workflow-search").fill("HERMES-TEST-019")
        page2.wait_for_timeout(500)
        page2.screenshot(path=str(OUT / "mobile-workflow.png"), full_page=False)
        context2.close(); context1.close(); browser.close()
    evidence["completed_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    evidence["blocked_external_hosts"] = sorted(set(evidence["blocked_external_hosts"]))
    (OUT / "evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "routes": evidence["routes"], "sessions": evidence["sessions"], "modal": evidence["modal"],
        "desktop": evidence["desktop_accessibility"], "mobile": evidence["mobile_accessibility"],
        "console_errors": len([x for x in evidence["console"] if x["type"] == "error"]), "page_errors": len(evidence["page_errors"]),
        "failed_requests": len(evidence["failed_requests"]), "http_errors": len(evidence["http_errors"]), "blocked_external_hosts": evidence["blocked_external_hosts"]
    }, indent=2))


if __name__ == "__main__":
    run()
