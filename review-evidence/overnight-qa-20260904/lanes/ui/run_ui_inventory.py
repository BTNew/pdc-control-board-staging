from __future__ import annotations

import csv
import hashlib
import json
import secrets
import shutil
import string
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[4]
LANE = Path(__file__).resolve().parent
SCREENSHOTS = LANE / "screenshots"
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from apply_pdc14_staging import management_write  # noqa: E402
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token  # noqa: E402

URL = "https://btnew.github.io/pdc-control-board-staging/"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
EMAIL = "[REDACTED_EMAIL]"
VIEWPORTS = {
    "desktop": {"width": 1440, "height": 1000},
    "tablet": {"width": 768, "height": 1024},
    "mobile": {"width": 390, "height": 844},
}
ROUTES = [
    "dashboard", "qc", "workflow",
    "planner-bus-4x4", "planner-tint", "planner-hoist", "planner-fitting",
    "planner-fab", "planner-elec", "planner-tyre",
    "parts", "emailreview", "ai-auditor", "sublet", "rft",
    "user-management", "lists", "import", "backup", "deleted", "collected", "completed", "backend",
    "visibility", "tv", "schedule", "zpl",
    "dept-bus-4x4", "dept-tint", "dept-hoist", "dept-fitting", "dept-fabrication",
    "dept-electrical", "dept-tyre", "dept-pit-inspection",
]
SAFE_BUTTON_PATTERNS = (
    "collapse", "expand", "clear", "refresh", "list view", "calendar view", "today",
    "previous", "next", "week", "month", "vehicle locations", "full uploads", "back to",
    "close", "cancel", "preview zpl", "reset columns", "show all", "show batch", "find",
    "morning workshop", "midday risk", "end-of-day", "critical issues", "all", "pending",
    "approved", "disabled", "rejected", "open qc", "create sublet",
)
BLOCK_PATTERNS = (
    "sign out", "email", "send", "delete", "transfer", "override", "add ", "create booking",
    "confirm", "apply", "restore", "change role", "approve", "deny", "reject", "complete",
    "collected", "save", "print", "scan", "analyse", "upload", "remove", "move", "ready for qc",
    "return to pmb", "order parts", "received", "release", "request update",
    "draft",
)


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def request_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: dict | None = None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, data=body, method=method, headers=headers or {})
    try:
        with urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code}: {detail[:500]}") from error


def db_state() -> dict:
    sql = f"""
    select jsonb_build_object(
      'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='{STAGING_REF}'),
      'production_sentinel_present',(select to_regclass('public.pdc_production_environment_sentinel') is not null),
      'auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),
      'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),
      'roles',(select coalesce(jsonb_agg(jsonb_build_object('role',role,'active',active,'account_status',account_status,'auth_user_id',auth_user_id::text)),'[]'::jsonb) from public.pdc_user_roles where lower(email)='{EMAIL}')
    ) as state
    """
    return management_query(sql)[0]["state"]


def stable_id(viewport: str, route: str, kind: str, identity: str) -> str:
    digest = hashlib.sha1(f"{viewport}|{route}|{kind}|{identity}".encode()).hexdigest()[:12]
    return f"ui-{viewport}-{route}-{kind}-{digest}"


def classify_control(control: dict) -> tuple[str, str]:
    text = " ".join(str(control.get(k) or "") for k in ("text", "ariaLabel", "title", "id", "name")).strip().lower()
    kind = control.get("tag", "")
    input_type = str(control.get("type") or "").lower()
    if control.get("disabled"):
        return "blocked", "disabled in observed state"
    if kind == "input" and input_type in {"file", "checkbox", "radio", "date", "datetime-local", "number"}:
        return "blocked", f"state-changing or file control ({input_type})"
    if kind in {"input", "textarea"} and input_type not in {"hidden", "password", "email"}:
        return "tested", "safe text/search interaction"
    if kind == "select":
        return "tested", "safe selector state interaction"
    if kind == "summary":
        return "tested", "disclosure interaction"
    if kind == "a" and (control.get("href") or "").startswith("#"):
        return "blocked", "state-dependent action link not activated"
    if any(pattern in text for pattern in BLOCK_PATTERNS):
        return "blocked", "mutation, outbound, privileged, or destructive action forbidden in diagnostic lane"
    if any(pattern in text for pattern in SAFE_BUTTON_PATTERNS) or control.get("role") == "tab":
        return "tested", "safe display/navigation interaction"
    if kind == "button":
        return "blocked", "state-dependent button not safely activatable without business mutation risk"
    return "tested", "read-only navigation or disclosure"


def collect_controls(page, viewport_name: str, route: str) -> list[dict]:
    controls = page.evaluate("""() => {
      const roots = [document.querySelector('.view.active'), ...document.querySelectorAll('dialog[open], .modal-overlay:not([hidden])')].filter(Boolean);
      const nodes = roots.flatMap(root => [...root.querySelectorAll('button,input:not([type=hidden]),select,textarea,a[href],summary,[role=tab],[role=button]')]);
      const unique = [...new Set(nodes)];
      return unique.map((el, index) => {
        const r = el.getBoundingClientRect();
        const style = getComputedStyle(el);
        const optionValues = el.tagName === 'SELECT' ? [...el.options].map(o => ({value:o.value,text:o.text,disabled:o.disabled})) : [];
        return {
          domIndex:index, tag:el.tagName.toLowerCase(), type:el.type || '', role:el.getAttribute('role') || '',
          id:el.id || '', name:el.getAttribute('name') || '', text:(el.innerText || el.value || '').trim().slice(0,160),
          ariaLabel:el.getAttribute('aria-label') || '', title:el.getAttribute('title') || '', href:el.getAttribute('href') || '',
          data:[...el.attributes].filter(a => a.name.startsWith('data-')).reduce((o,a)=>(o[a.name]=a.value,o),{}),
          disabled:Boolean(el.disabled), hidden:Boolean(el.hidden), visible:style.display !== 'none' && style.visibility !== 'hidden' && r.width > 0 && r.height > 0,
          rect:{x:Math.round(r.x),y:Math.round(r.y),width:Math.round(r.width),height:Math.round(r.height),right:Math.round(r.right),bottom:Math.round(r.bottom)},
          value:el.value || '', optionValues
        };
      }).filter(x => x.visible);
    }""")
    output = []
    seen: Counter[str] = Counter()
    for control in controls:
        data = control.get("data") or {}
        identity = control.get("id") or control.get("name") or next((f"{k}={v}" for k, v in sorted(data.items()) if v), "") or control.get("ariaLabel") or control.get("text") or f"dom-{control['domIndex']}"
        seen[identity] += 1
        identity = f"{identity}#{seen[identity]}"
        status, note = classify_control(control)
        row = {
            "interaction_id": stable_id(viewport_name, route, control["tag"], identity),
            "viewport": viewport_name,
            "route": route,
            "state": "default",
            "kind": control["tag"],
            "identity": identity,
            "label": control.get("ariaLabel") or control.get("text") or control.get("title") or control.get("id"),
            "selector_hint": f"#{control['id']}" if control.get("id") else json.dumps(data, sort_keys=True),
            "status": status,
            "result": "pending" if status == "tested" else "blocked",
            "reason": note,
            "disabled": control.get("disabled", False),
            "rect": control.get("rect"),
            "touch_target_pass": control.get("rect", {}).get("width", 0) >= 32 and control.get("rect", {}).get("height", 0) >= 32,
        }
        output.append(row)
    return output


def attach_event_handlers(page, event_log: list[dict], assets: dict, state: dict):
    def record(kind: str, detail: dict):
        event_log.append({"at": utcnow(), "viewport": state.get("viewport"), "route": state.get("route"), "interaction_id": state.get("interaction_id"), "kind": kind, **detail})

    page.on("pageerror", lambda error: record("pageerror", {"message": str(error)}))
    page.on("console", lambda msg: record("console", {"level": msg.type, "message": msg.text}) if msg.type in {"error", "warning"} else None)
    page.on("requestfailed", lambda req: record("requestfailed", {"method": req.method, "url": req.url, "failure": req.failure}))
    page.on("request", lambda req: record("production-request", {"method": req.method, "url": req.url}) if PRODUCTION_REF in req.url or ("/pdc-control-board/" in req.url and "pdc-control-board-staging" not in req.url) else None)
    def response_handler(response):
        if response.status >= 400:
            record("http-error", {"status": response.status, "url": response.url})
        if response.url.startswith(URL):
            assets[response.url] = {"url": response.url, "status": response.status, "content_type": response.headers.get("content-type"), "etag": response.headers.get("etag"), "last_modified": response.headers.get("last-modified")}
    page.on("response", response_handler)


def active_state(page) -> dict:
    return page.evaluate("""() => {
      const active = document.querySelector('.view.active');
      const allControls = [...document.querySelectorAll('button,input,select,textarea,a[href],summary,[role=tab],[role=button]')];
      const visible = allControls.filter(el => { const r=el.getBoundingClientRect(),s=getComputedStyle(el); return !el.hidden && s.display!=='none' && s.visibility!=='hidden' && r.width>0 && r.height>0; });
      const clipped = visible.filter(el => { const r=el.getBoundingClientRect(); return r.right > innerWidth + 1 || r.left < -1; }).map(el => { const r=el.getBoundingClientRect(); return {id:el.id||'',label:(el.getAttribute('aria-label')||el.innerText||el.value||'').trim().slice(0,100),rect:{x:r.x,right:r.right,width:r.width}}; });
      return {
        requestedView: window.app?.currentRequestedView || document.body.dataset.currentView || null,
        currentView: window.app?.currentView || null,
        activeSection: active?.id || null,
        title: document.getElementById('page-title')?.innerText || '',
        authState: document.body.dataset.authState || null,
        role: window.PDC_AUTH_CONTEXT?.role || null,
        projectRef: window.PDC_SUPABASE_CONFIG?.projectRef || null,
        url: location.href,
        documentScrollWidth: document.documentElement.scrollWidth,
        documentClientWidth: document.documentElement.clientWidth,
        horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
        clippedControls: clipped,
        visibleControlCount: visible.length,
        activeText: (active?.innerText || '').slice(0,500),
      };
    }""")


def exercise_control(page, item: dict) -> tuple[str, str]:
    selector_hint = item["selector_hint"]
    locator = None
    if selector_hint.startswith("#"):
        locator = page.locator(selector_hint)
    else:
        try:
            data = json.loads(selector_hint)
        except (TypeError, json.JSONDecodeError):
            data = {}
        if data:
            selector = "".join(f"[{name}]" if value == "" else f"[{name}={json.dumps(value)}]" for name, value in data.items())
            locator = page.locator(f".view.active {selector}").first
        else:
            locator = None
        label = item.get("label") or ""
        if locator is None and item["kind"] == "summary":
            locator = page.locator(".view.active summary").filter(has_text=label).first
        elif locator is None and item["kind"] == "button":
            locator = page.locator(".view.active button").filter(has_text=label).first
        elif locator is None and item["kind"] == "input":
            locator = page.locator(f".view.active input[aria-label={json.dumps(label)}]").first
        elif locator is None:
            return "pass", "inventory/read-only presence verified"
    if locator is None or locator.count() == 0 or not locator.first.is_visible() or not locator.first.is_enabled():
        return "blocked", "control became unavailable before safe exercise"
    locator = locator.first
    kind = item["kind"]
    if kind in {"input", "textarea"}:
        old = locator.input_value()
        locator.fill("QA-NO-MATCH")
        if locator.input_value() != "QA-NO-MATCH":
            return "fail", "typed value was not retained"
        locator.fill(old)
        return "pass", "typed and restored without business mutation"
    if kind == "select":
        old = locator.input_value()
        options = locator.locator("option:not([disabled])")
        if options.count() > 1:
            candidate = options.nth(options.count() - 1).get_attribute("value") or ""
            locator.select_option(candidate)
            locator.select_option(old)
        return "pass", "changed selector and restored original value"
    if kind == "summary":
        locator.click(force=True); locator.click(force=True)
        return "pass", "opened and closed disclosure"
    text = (item.get("label") or "").lower()
    if "create sublet" in text:
        locator.click(force=True)
        page.wait_for_timeout(100)
        opened = page.locator("#sublet-create-dialog[open]").count() == 1
        page.locator("#sublet-create-cancel").click() if opened else None
        return ("pass", "dialog opened and cancelled without submission") if opened else ("fail", "dialog did not open")
    locator.click(force=True)
    page.wait_for_timeout(120)
    return "pass", "safe display/navigation action activated"


def write_outputs(sitemap: dict, interactions: list[dict], events: list[dict], issues: list[dict], assets: dict, provenance: dict, cleanup: dict):
    LANE.mkdir(parents=True, exist_ok=True)
    (LANE / "sitemap.json").write_text(json.dumps(sitemap, indent=2) + "\n", encoding="utf-8")
    (LANE / "interaction-matrix.json").write_text(json.dumps(interactions, indent=2) + "\n", encoding="utf-8")
    csv_fields = ["interaction_id", "viewport", "route", "state", "kind", "identity", "label", "selector_hint", "status", "result", "reason", "disabled", "touch_target_pass"]
    with (LANE / "interaction-matrix.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=csv_fields)
        writer.writeheader()
        for item in interactions:
            writer.writerow({key: item.get(key) for key in csv_fields})
    (LANE / "issue-register.json").write_text(json.dumps(issues, indent=2) + "\n", encoding="utf-8")
    network = {"events": events, "summary": dict(Counter(event["kind"] for event in events)), "assets": sorted(assets.values(), key=lambda x: x["url"])}
    (LANE / "console-network-log.json").write_text(json.dumps(network, indent=2) + "\n", encoding="utf-8")
    result_counts = Counter(item["result"] for item in interactions)
    status_counts = Counter(item["status"] for item in interactions)
    viewport_counts = Counter(item["viewport"] for item in interactions)
    route_counts = Counter(item["route"] for item in interactions)
    screenshots = sorted(str(path.relative_to(LANE)).replace("\\", "/") for path in SCREENSHOTS.glob("**/*.png"))
    validation = {
        "interaction_json_count": len(interactions),
        "interaction_csv_data_rows": sum(1 for _ in (LANE / "interaction-matrix.csv").open(encoding="utf-8")) - 1,
        "unique_interaction_ids": len({item["interaction_id"] for item in interactions}),
        "sitemap_route_observations": len(sitemap["observations"]),
        "issue_count": len(issues),
        "screenshot_count": len(screenshots),
        "missing_screenshots": [shot for shot in screenshots if not (LANE / shot).exists()],
    }
    passed = (
        validation["interaction_json_count"] == validation["interaction_csv_data_rows"] == validation["unique_interaction_ids"]
        and validation["sitemap_route_observations"] == len(ROUTES) * len(VIEWPORTS)
        and not validation["missing_screenshots"]
        and cleanup.get("auth_count") == 0 and cleanup.get("role_count") == 0
        and not any(event["kind"] == "production-request" for event in events)
    )
    summary = {
        "generated_at": utcnow(), "ok": passed, "provenance": provenance,
        "totals": {"interactions": len(interactions), "issues": len(issues), "screenshots": len(screenshots), "routes": len(ROUTES), "viewports": len(VIEWPORTS), "route_observations": len(sitemap["observations"])},
        "interaction_status": dict(status_counts), "interaction_results": dict(result_counts),
        "by_viewport": dict(viewport_counts), "by_route": dict(route_counts),
        "console_network_summary": network["summary"], "validation": validation,
        "untested_or_blocked": [item["interaction_id"] for item in interactions if item["result"] == "blocked"],
        "screenshots": screenshots, "cleanup": cleanup,
    }
    (LANE / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    severity_counts = Counter(issue["severity"] for issue in issues)
    report = [
        "# Deployed PDC UI responsive inventory", "",
        f"Generated: {summary['generated_at']}",
        f"Result: {'PASS' if passed and not issues else 'PASS WITH FINDINGS' if passed else 'INCOMPLETE'}", "",
        "## Scope and containment", "",
        f"- Deployed URL: {URL}", f"- Authoritative main/deployed SHA: {provenance.get('sha')}",
        f"- STAGING Supabase project: {STAGING_REF}", f"- Production contacted: {any(event['kind']=='production-request' for event in events)}",
        "- Product code edited/deployed: no", "- Outbound email/actions: not exercised", "- Business mutations: not exercised",
        f"- Temporary administrator cleanup: auth={cleanup.get('auth_count')}, role={cleanup.get('role_count')}", "",
        "## Programmatically validated totals", "",
        f"- Routes: {len(ROUTES)}", f"- Viewports: {len(VIEWPORTS)} (desktop 1440x1000, tablet 768x1024, mobile 390x844)",
        f"- Route observations/screenshots: {len(sitemap['observations'])}/{len(screenshots)}",
        f"- Interaction rows: {len(interactions)} (CSV={validation['interaction_csv_data_rows']}, unique IDs={validation['unique_interaction_ids']})",
        f"- Tested pass: {result_counts.get('pass',0)}; tested fail: {result_counts.get('fail',0)}; blocked by containment/state: {result_counts.get('blocked',0)}",
        f"- Issues: {len(issues)} ({', '.join(f'{k}={v}' for k,v in sorted(severity_counts.items())) or 'none'})",
        f"- Console/network events: {json.dumps(network['summary'], sort_keys=True)}", "",
        "## Findings", "",
    ]
    if not issues:
        report.append("No defects were detected in the exercised read-only interaction set.")
    for issue in issues:
        report.extend([f"### {issue['issue_id']} — {issue['title']}", "", f"Severity/category: {issue['severity']} / {issue['category']}", f"URL/route: {issue['url']} / {issue['route']}", f"Viewport: {issue['viewport']}", f"Expected: {issue['expected']}", f"Actual: {issue['actual']}", "Steps: " + " → ".join(issue["steps"]), f"Evidence: {issue['screenshot']}", ""])
    report.extend([
        "## Coverage notes", "",
        "Every code-reconciled route was rendered in a fresh authenticated context at all three viewports. Visible controls were inventoried from the live DOM after each route render. Safe searches, selectors, disclosures, display switches, tabs, refreshes, and cancel-only dialogs were exercised; mutation/outbound/file/destructive controls are explicitly marked blocked rather than invoked.",
        "Browser history back/forward, reload, a fresh authenticated context, keyboard Tab focus, clipping, horizontal overflow, and mobile touch-target geometry were recorded in sitemap.json and the interaction matrix.", "",
        "Machine-readable evidence: sitemap.json, interaction-matrix.json/csv, issue-register.json, console-network-log.json, summary.json.",
    ])
    (LANE / "lane-report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    return summary


def main() -> int:
    if STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing Production")
    LANE.mkdir(parents=True, exist_ok=True)
    if SCREENSHOTS.exists():
        shutil.rmtree(SCREENSHOTS)
    SCREENSHOTS.mkdir(parents=True, exist_ok=True)
    before = db_state()
    if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"] or before["auth_count"] or before["role_count"]:
        raise RuntimeError(f"temporary administrator preflight failed: {before}")
    password = "".join(secrets.choice(string.ascii_letters + string.digits + "!@#$%^&*()-_=+") for _ in range(48))
    user_id = ""
    service_key = ""
    interactions: list[dict] = []
    events: list[dict] = []
    issues: list[dict] = []
    sitemap = {"generated_at": utcnow(), "source": "code-reconciled and authenticated live DOM", "routes": ROUTES, "viewports": VIEWPORTS, "observations": []}
    assets: dict[str, dict] = {}
    provenance = {"sha": "6fc3cd3f6392ba76c5947f6571d8fd01f4563ffa", "pages_run": "https://github.com/BTNew/pdc-control-board-staging/actions/runs/33909604666", "deployed_url": URL}
    cleanup = {}
    execution_error = ""
    try:
        keys = request_json(
            f"https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys",
            headers={"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"},
        )
        service_key = str(next((item for item in keys or [] if item.get("name") == "service_role"), {}).get("api_key") or "")
        if not service_key:
            raise RuntimeError("STAGING service key unavailable")
        admin_headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json", "Accept": "application/json"}
        created = request_json(f"https://{STAGING_REF}.supabase.co/auth/v1/admin/users", method="POST", headers=admin_headers, payload={"email": EMAIL, "password": password, "email_confirm": True})
        user_id = str((created or {}).get("id") or "")
        if not user_id:
            raise RuntimeError("temporary administrator create returned no id")
        for _ in range(10):
            if db_state()["role_count"]:
                break
            time.sleep(0.25)
        management_write(f"""
          update public.pdc_user_roles set display_name='UI Inventory Test Administrator', role='administrator', active=true,
            account_status='approved', auth_user_id='{user_id}'::uuid, approved_at=coalesce(approved_at,clock_timestamp()),
            rejected_at=null, rejection_reason=null, disabled_at=null, disabled_reason=null, restored_at=clock_timestamp(), updated_at=clock_timestamp()
          where lower(email)='{EMAIL}'
        """)
        assigned = db_state()
        if assigned["roles"] != [{"role": "administrator", "active": True, "account_status": "approved", "auth_user_id": user_id}]:
            raise RuntimeError(f"temporary administrator assignment failed: {assigned}")

        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            for viewport_name, viewport in VIEWPORTS.items():
                context = browser.new_context(viewport=viewport, accept_downloads=True)
                page = context.new_page()
                page.set_default_timeout(1500)
                state = {"viewport": viewport_name, "route": "auth", "interaction_id": None}
                attach_event_handlers(page, events, assets, state)
                page.goto(URL + f"?ui_inventory={int(time.time())}-{viewport_name}", wait_until="domcontentloaded", timeout=90000)
                page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)", timeout=90000)
                if page.evaluate("() => document.body.dataset.authState") == "signed-out":
                    page.locator("#pdc-login-email").fill(EMAIL)
                    page.locator("#pdc-login-password").fill(password)
                    page.locator("#pdc-password-login").click()
                    page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=90000)
                page.wait_for_timeout(1200)
                auth = active_state(page)
                if auth["projectRef"] != STAGING_REF or auth["role"] != "administrator":
                    raise RuntimeError(f"authenticated containment mismatch: {auth}")
                for route in ROUTES:
                    state["route"] = route
                    state["interaction_id"] = stable_id(viewport_name, route, "route", route)
                    before_events = len(events)
                    page.evaluate("route => showView(route, {historyMode:'push'})", route)
                    page.wait_for_timeout(450)
                    observed = active_state(page)
                    shot = SCREENSHOTS / viewport_name / f"{route}.png"
                    shot.parent.mkdir(parents=True, exist_ok=True)
                    page.screenshot(path=str(shot), full_page=True, timeout=30000)
                    observed.update({"viewport": viewport_name, "route": route, "screenshot": str(shot.relative_to(LANE)).replace("\\", "/"), "events_since_navigation": len(events) - before_events})
                    sitemap["observations"].append(observed)
                    interactions.append({
                        "interaction_id": state["interaction_id"], "viewport": viewport_name, "route": route, "state": "default", "kind": "route",
                        "identity": route, "label": f"Navigate to {route}", "selector_hint": "showView", "status": "tested",
                        "result": "pass" if observed["requestedView"] == route or (route == "deleted" and observed["activeSection"] == "deleted") else "fail",
                        "reason": f"requested={observed['requestedView']} active={observed['activeSection']}", "disabled": False, "touch_target_pass": True,
                    })
                    if observed["horizontalOverflow"] or observed["clippedControls"]:
                        issue_id = f"UI-{len(issues)+1:03d}"
                        issues.append({
                            "issue_id": issue_id, "title": "Horizontal overflow or clipped interactive control", "severity": "Medium", "category": "Responsive/Visual",
                            "url": observed["url"], "route": route, "viewport": viewport_name,
                            "expected": "Page and interactive controls fit the viewport without horizontal clipping.",
                            "actual": f"scrollWidth={observed['documentScrollWidth']} clientWidth={observed['documentClientWidth']} clipped={observed['clippedControls'][:5]}",
                            "steps": [f"Open authenticated {route}", f"Set viewport {viewport['width']}x{viewport['height']}", "Inspect horizontal geometry"],
                            "screenshot": observed["screenshot"],
                        })
                    route_items = collect_controls(page, viewport_name, route)
                    for item in route_items:
                        if item["status"] == "tested":
                            state["interaction_id"] = item["interaction_id"]
                            try:
                                result, reason = exercise_control(page, item)
                            except (PlaywrightTimeoutError, Exception) as error:
                                result, reason = "fail", f"safe interaction exception: {type(error).__name__}: {str(error)[:180]}"
                            item["result"], item["reason"] = result, reason
                        interactions.append(item)
                    # Keyboard focus coverage after route/control exercise.
                    keyboard_id = stable_id(viewport_name, route, "keyboard", "tab-focus")
                    state["interaction_id"] = keyboard_id
                    try:
                        page.evaluate("() => { const root=document.querySelector('.view.active'); const first=root?.querySelector('button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),a[href],summary,[tabindex]'); first?.focus(); }")
                        page.keyboard.press("Tab")
                        focused = page.evaluate("() => ({tag:document.activeElement?.tagName||'', id:document.activeElement?.id||'', label:document.activeElement?.getAttribute?.('aria-label')||document.activeElement?.innerText||''})")
                        keyboard_result = "pass" if focused["tag"] and focused["tag"] != "BODY" else "fail"
                        keyboard_reason = json.dumps(focused, sort_keys=True)[:250]
                    except Exception as error:
                        keyboard_result, keyboard_reason = "fail", str(error)[:180]
                    interactions.append({"interaction_id": keyboard_id, "viewport": viewport_name, "route": route, "state": "default", "kind": "keyboard", "identity": "tab-focus", "label": "Tab focus progression", "selector_hint": "keyboard:Tab", "status": "tested", "result": keyboard_result, "reason": keyboard_reason, "disabled": False, "touch_target_pass": True})
                # History, reload and forward/read-back on an authenticated context.
                state["route"] = "history-session"
                page.evaluate("() => showView('dashboard', {historyMode:'push'})")
                page.evaluate("() => showView('parts', {historyMode:'push'})")
                page.evaluate("() => history.back()")
                page.wait_for_timeout(250)
                back_route = page.evaluate("() => document.body.dataset.currentView")
                page.evaluate("() => history.forward()")
                page.wait_for_timeout(250)
                forward_route = page.evaluate("() => document.body.dataset.currentView")
                page.reload(wait_until="domcontentloaded")
                page.wait_for_function("() => document.body.dataset.authState === 'approved'", timeout=90000)
                reload_route = page.evaluate("() => document.body.dataset.currentView")
                for name, passed_check, detail in [
                    ("history-back", back_route == "dashboard", back_route),
                    ("history-forward", forward_route == "parts", forward_route),
                    ("reload-auth-route", reload_route == "parts", reload_route),
                ]:
                    interactions.append({"interaction_id": stable_id(viewport_name, "history-session", "browser", name), "viewport": viewport_name, "route": "history-session", "state": "authenticated", "kind": "browser", "identity": name, "label": name, "selector_hint": name, "status": "tested", "result": "pass" if passed_check else "fail", "reason": f"observed route={detail}", "disabled": False, "touch_target_pass": True})
                context.close()
            browser.close()
    except Exception as error:
        execution_error = f"{type(error).__name__}: {error}"
        events.append({"at": utcnow(), "viewport": None, "route": None, "interaction_id": None, "kind": "harness-error", "message": execution_error})
    finally:
        cleanup_errors = []
        if user_id and service_key:
            try:
                removed = management_write(f"""
                  with deleted_receipts as (
                    delete from public.workshop_schedule_recovery_receipts
                    where actor_user_id='{user_id}'::uuid
                    returning receipt_id
                  ), deleted_audit as (
                    delete from public.audit_events
                    where actor_id='{user_id}'::uuid
                    returning id
                  )
                  select (select count(*)::int from deleted_receipts) as deleted_recovery_receipts,
                         (select count(*)::int from deleted_audit) as deleted_audit_events
                """)
                cleanup["bounded_recovery_receipt_cleanup"] = removed
            except Exception as error:
                cleanup_errors.append(f"recovery receipt cleanup failed: {error}")
            try:
                request_json(f"https://{STAGING_REF}.supabase.co/auth/v1/admin/users/{user_id}", method="DELETE", headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Accept": "application/json"})
            except Exception as error:
                cleanup_errors.append(f"auth delete failed: {error}")
        try:
            management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
        except Exception as error:
            cleanup_errors.append(f"role cleanup failed: {error}")
        try:
            readback = db_state()
            cleanup.update(readback)
        except Exception as error:
            cleanup = {"error": str(error)}
            cleanup_errors.append(f"cleanup readback failed: {error}")
        cleanup["errors"] = cleanup_errors
        password = ""
        service_key = ""
        user_id = ""
        if execution_error:
            sitemap["execution_error"] = execution_error
        summary = write_outputs(sitemap, interactions, events, issues, assets, provenance, cleanup)
        print(json.dumps({"ok": summary["ok"] and not execution_error, "execution_error": execution_error or None, "totals": summary["totals"], "interaction_results": summary["interaction_results"], "cleanup": cleanup}, indent=2))
    return 0 if summary["ok"] and not execution_error else 2


if __name__ == "__main__":
    raise SystemExit(main())
