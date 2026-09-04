from __future__ import annotations

import json
import secrets
import string
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
ROOT = HERE.parents[2]
OUT = HERE / "deployed-remediation-browser.json"
SHOTS = EVIDENCE / "screenshots" / "remediation"
sys.path.insert(0, str(ROOT / "scripts"))
from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

URL = "https://btnew.github.io/pdc-control-board-staging/"
EMAIL = "[REDACTED_EMAIL]"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
VIEWPORTS = {"desktop": {"width": 1440, "height": 1000}, "tablet": {"width": 768, "height": 1024}, "mobile": {"width": 390, "height": 844}}
ROUTES = ("deleted", "ai-auditor", "parts", "backend", "collected")


def request_json(url: str, method: str = "GET", headers: dict | None = None, payload: dict | None = None):
    data = None if payload is None else json.dumps(payload).encode()
    with urlopen(Request(url, data=data, method=method, headers=headers or {}), timeout=60) as response:
        raw = response.read().decode()
        return json.loads(raw) if raw else None


def residue() -> dict[str, object]:
    return management_query(f"select jsonb_build_object('auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null) state")[0]["state"]


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or residue() != {"auth_count": 0, "role_count": 0, "production_sentinel_present": False}:
        raise RuntimeError("STAGING-only preflight or residue check failed")
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    service = ""
    uid = ""
    checks: list[dict[str, object]] = []
    events: list[dict[str, object]] = []
    cleanup: dict[str, object] = {}
    error = ""
    try:
        keys = request_json(f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys", headers={"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"})
        service = str(next((item for item in keys if item.get("name") == "service_role"), {}).get("api_key") or "")
        headers = {"apikey": service, "Authorization": f"Bearer {service}", "Content-Type": "application/json", "Accept": "application/json"}
        uid = str(request_json(f"https://{STAGING_REF}.supabase.co/auth/v1/admin/users", "POST", headers, {"email": EMAIL, "password": password, "email_confirm": True}).get("id") or "")
        for _ in range(10):
            if management_query(f"select count(*)::int c from public.pdc_user_roles where lower(email)='{EMAIL}'")[0]["c"]:
                break
            time.sleep(.25)
        management_write(f"update public.pdc_user_roles set display_name='Overnight Remediation Verifier',role='administrator',active=true,account_status='approved',auth_user_id='{uid}'::uuid,approved_at=coalesce(approved_at,clock_timestamp()),updated_at=clock_timestamp() where lower(email)='{EMAIL}'")
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            for name, viewport in VIEWPORTS.items():
                context = browser.new_context(viewport=viewport)
                page = context.new_page()
                page.set_default_timeout(5000)
                page.on("response", lambda response, n=name: events.append({"kind": "http-error", "viewport": n, "status": response.status, "url": response.url}) if response.status >= 400 else None)
                page.on("request", lambda request, n=name: events.append({"kind": "production-request", "viewport": n, "url": request.url}) if PRODUCTION_REF in request.url else None)
                page.on("pageerror", lambda exc, n=name: events.append({"kind": "pageerror", "viewport": n, "message": str(exc)}))
                page.goto(URL + f"?overnight_remediation={int(time.time())}-{name}", wait_until="domcontentloaded", timeout=90000)
                page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
                if page.evaluate("() => document.body.dataset.authState") == "signed-out":
                    page.locator("#pdc-login-email").fill(EMAIL)
                    page.locator("#pdc-login-password").fill(password)
                    page.locator("#pdc-password-login").click()
                    page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=90000)
                for route in ROUTES:
                    start = len(events)
                    page.evaluate("route => showView(route,{historyMode:'replace'})", route)
                    page.wait_for_timeout(1200)
                    shot = SHOTS / f"{name}-{route}.png"
                    shot.parent.mkdir(parents=True, exist_ok=True)
                    page.screenshot(path=str(shot), full_page=True, timeout=30000)
                    route_events = events[start:]
                    facts = page.evaluate("""route => ({
                      route,
                      pageTitle: document.querySelector('#page-title')?.textContent?.trim() || '',
                      bodyText: document.body.innerText,
                      auditorLabel: document.querySelector('[data-view="ai-auditor"]')?.textContent?.trim() || '',
                      auditorTitle: document.querySelector('[data-view="ai-auditor"]')?.getAttribute('title') || '',
                      navCueDisplay: getComputedStyle(document.querySelector('.nav-scroll-cue')).display,
                      tableCueDisplay: document.querySelector('.view.active .table-scroll-cue') ? getComputedStyle(document.querySelector('.view.active .table-scroll-cue')).display : 'absent',
                      tableCueText: document.querySelector('.view.active .table-scroll-cue')?.textContent?.trim() || '',
                      tableOverflow: (() => { const el=document.querySelector('.view.active .parts-table-wrap,.view.active .responsive-table'); return el ? el.scrollWidth > el.clientWidth : null; })(),
                      partsVehicleCustomerWidth: (() => { const el=document.querySelector('.parts-queue-table th:nth-child(4)'); return el ? Math.round(el.getBoundingClientRect().width) : null; })()
                    })""", route)
                    facts.pop("bodyText", None)
                    facts.update({
                        "viewport": name,
                        "screenshot": str(shot.relative_to(EVIDENCE)).replace("\\", "/"),
                        "deleted_load_error_absent": "Could not load Deleted Vehicles" not in page.locator("body").inner_text(),
                        "http_405_count": sum(1 for event in route_events if event.get("status") == 405),
                    })
                    checks.append(facts)
                context.close()
            browser.close()
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
    finally:
        cleanup_errors = []
        if uid:
            try:
                cleanup["bounded_rows"] = management_write(f"""
with a as (delete from public.audit_events where actor_id='{uid}'::uuid returning id),
 r as (delete from public.workshop_schedule_recovery_receipts where actor_user_id='{uid}'::uuid returning receipt_id),
 h as (delete from public.workshop_bay_default_technician_history where actor_id='{uid}'::uuid returning id)
select (select count(*) from a)::int audit_events,(select count(*) from r)::int recovery_receipts,(select count(*) from h)::int bay_history
""")
            except Exception as exc:
                cleanup_errors.append(f"bounded rows: {exc}")
            try:
                request_json(f"https://{STAGING_REF}.supabase.co/auth/v1/admin/users/{uid}", "DELETE", {"apikey": service, "Authorization": f"Bearer {service}", "Accept": "application/json"})
            except Exception as exc:
                cleanup_errors.append(f"auth delete: {exc}")
        try:
            management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
        except Exception as exc:
            cleanup_errors.append(f"role delete: {exc}")
        cleanup.update(residue())
        cleanup["errors"] = cleanup_errors
        password = service = uid = ""

    failures = []
    for check in checks:
        if check["route"] == "deleted" and (not check["deleted_load_error_absent"] or check["http_405_count"]): failures.append(f"deleted:{check['viewport']}")
        if check["route"] == "collected" and check["pageTitle"] != "Collected Vehicles": failures.append(f"collected-title:{check['viewport']}")
        if check["auditorLabel"] != "AI Auditor · Restricted" or check["auditorTitle"] != "Requires separately approved AI Auditor access": failures.append(f"auditor-disclosure:{check['viewport']}:{check['route']}")
        compact = check["viewport"] != "desktop"
        if compact and check["navCueDisplay"] == "none": failures.append(f"nav-cue:{check['viewport']}:{check['route']}")
        if compact and check["route"] in {"parts", "backend"}:
            if check["tableCueDisplay"] in {"none", "absent"}: failures.append(f"table-cue:{check['viewport']}:{check['route']}")
            if check["tableOverflow"] is not True: failures.append(f"table-overflow:{check['viewport']}:{check['route']}")
        if compact and check["route"] == "parts" and (check["partsVehicleCustomerWidth"] is None or check["partsVehicleCustomerWidth"] < 190): failures.append(f"parts-width:{check['viewport']}")
    if any(event["kind"] in {"production-request", "pageerror"} for event in events): failures.append("production-request-or-pageerror")
    if cleanup.get("auth_count") or cleanup.get("role_count") or cleanup.get("errors"): failures.append("cleanup")
    if len(checks) != len(VIEWPORTS) * len(ROUTES): failures.append("coverage")
    payload = {
        "ok": not error and not failures,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "deployed_url": URL,
        "project_ref": STAGING_REF,
        "checks": checks,
        "events": events,
        "failures": failures,
        "error": error or None,
        "cleanup": cleanup,
        "production_contacted": False,
        "production_mutated": False,
    }
    OUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": payload["ok"], "checks": len(checks), "events": len(events), "failures": failures, "error": error or None, "cleanup": cleanup}, indent=2))
    return 0 if payload["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
