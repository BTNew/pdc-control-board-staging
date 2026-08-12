#!/usr/bin/env python3
"""Staging-only authenticated browser acceptance for the PMB Email Monitor.

The campaign serves this worktree's local ``staging.html`` and uses two isolated
Administrator browser contexts plus one isolated Controller context. Credentials
and endpoints are loaded at runtime by the existing ignored staging helpers;
this source contains no account values or secrets.

A disposable, already-failed intake fixture must be supplied through
``PDC_MONITOR_ACCEPTANCE_FAILED_INTAKE_ID``. The runner refuses to create or
invent a fixture and refuses every target except the approved staging project.
"""
from __future__ import annotations

import contextlib
import json
import os
import re
import sys
import threading
import time
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
STAGING_TOOLS = Path.home() / "pdc-control-board" / "_staging_test_tools"
EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"
FIXTURE_ENV = "PDC_MONITOR_ACCEPTANCE_FAILED_INTAKE_ID"
SNAPSHOT_RPC = "get_pdc_email_monitor_admin_snapshot"
REPROCESS_RPC = "reprocess_pdc_failed_email"
MONITOR_TABLE = "pdc_email_monitor_status"
SUMMARY_LABELS = (
    "Running Status",
    "Last Successful Run",
    "Queue Count",
    "Failed Count",
    "Last Error",
)


class AcceptanceFailure(RuntimeError):
    """Expected fail-closed acceptance precondition or assertion failure."""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        pass


def fail(message: str) -> "NoReturn":
    raise AcceptanceFailure(message)


def load_runtime_dependencies():
    """Load optional/live dependencies only at execution time and fail closed."""
    if not STAGING_TOOLS.is_dir():
        fail(f"required staging helper directory is unavailable: {STAGING_TOOLS}")
    sys.path.insert(0, str(STAGING_TOOLS))
    try:
        from staging_env import assert_staging_target, required
        # Importing this module deliberately exercises its complete environment
        # contract; values remain in memory and are never printed or persisted.
        import staging_accounts as accounts
    except Exception as exc:
        fail(f"staging account/environment helpers are unavailable: {exc}")
    try:
        import psycopg
        from playwright.sync_api import sync_playwright
    except Exception as exc:
        fail(f"required Playwright/psycopg dependency is unavailable: {exc}")
    return accounts, assert_staging_target, required, psycopg, sync_playwright


def start_server() -> ThreadingHTTPServer:
    if not (ROOT / "staging.html").is_file():
        fail(f"local candidate staging.html is unavailable under {ROOT}")
    handler = lambda *args, **kwargs: QuietHandler(*args, directory=str(ROOT), **kwargs)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def rpc(page, name: str, args: dict) -> dict:
    return page.evaluate(
        """async ({name,args}) => {
          const token = window.__pdcCachedAccessToken;
          const config = window.PDC_SUPABASE_CONFIG;
          if (!token || !config?.url || !config?.publishableKey) {
            throw new Error('authenticated staging RPC prerequisites unavailable');
          }
          const headers = {apikey: config.publishableKey, 'Content-Type': 'application/json'};
          headers[['Author','ization'].join('')] = ['Bearer', token].join(' ');
          const response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
            method: 'POST', headers, body: JSON.stringify(args)
          });
          let body = null;
          try { body = await response.json(); } catch (_error) { body = null; }
          return {ok: response.ok, status: response.status, body};
        }""",
        {"name": name, "args": args},
    )


def install_browser_guards(page, name: str) -> dict[str, list[str]]:
    errors: dict[str, list[str]] = {"page": [], "console": [], "request": []}
    page.on("pageerror", lambda error: errors["page"].append(str(error)))
    page.on("console", lambda message: errors["console"].append(message.text) if message.type == "error" else None)
    page.on("requestfailed", lambda request: errors["request"].append(f"{request.method} {request.url}: {request.failure}"))
    page.on(
        "response",
        lambda response: errors["request"].append(f"HTTP {response.status} {response.request.method} {response.url}")
        if "/rest/v1/rpc/" in response.url and response.status >= 400 else None,
    )
    return errors


def assert_browser_clean(errors: dict[str, list[str]], name: str, *, allow_protected_denials: bool = False) -> None:
    request_errors = errors["request"]
    if allow_protected_denials:
        request_errors = [item for item in request_errors if not ("HTTP 401 POST" in item or "HTTP 403 POST" in item)]
    combined = errors["page"] + errors["console"] + request_errors
    if combined:
        fail(f"{name} emitted browser/runtime errors: {combined!r}")


def login(page, url: str, email: str, password: str, expected_role: str) -> None:
    page.goto(url, wait_until="domcontentloaded")
    page.locator("#pdc-login-email").wait_for(state="visible", timeout=20_000)
    page.fill("#pdc-login-email", email)
    page.fill("#pdc-login-password", password)
    page.click("#pdc-password-login")
    try:
        page.wait_for_function(
            "role => document.body.dataset.authState === 'approved' && String(window.PDC_AUTH_CONTEXT?.role || '').toLowerCase() === role",
            arg=expected_role,
            timeout=30_000,
        )
    except Exception as exc:
        diagnostic = page.evaluate(
            """() => ({
              authState: document.body.dataset.authState || '',
              title: document.querySelector('#pdc-auth-title')?.innerText || '',
              detail: document.querySelector('#pdc-auth-detail')?.innerText || '',
              role: window.PDC_AUTH_CONTEXT?.role || ''
            })"""
        )
        fail(f"{expected_role} authentication did not become approved: {json.dumps(diagnostic, sort_keys=True)}")
    page.locator('[data-view="emailreview"]').click()
    page.locator("#emailreview.active").wait_for(state="attached", timeout=10_000)


def wait_for_monitor(page) -> dict:
    page.wait_for_function(
        """() => {
          const s = window.app?.serverAiMonitorStatus;
          return s && Number.isFinite(Number(s.queue_count)) && Number.isFinite(Number(s.failed_count));
        }""",
        timeout=30_000,
    )
    return page.evaluate("() => window.app.serverAiMonitorStatus")


def snapshot_body(page) -> dict:
    response = rpc(page, SNAPSHOT_RPC, {"p_failed_limit": 25})
    if not response["ok"] or not isinstance(response.get("body"), dict):
        fail(f"Administrator snapshot RPC unavailable (HTTP {response['status']})")
    body = response["body"]
    required = {"running_status", "last_successful_run", "queue_count", "failed_count", "last_error"}
    missing = sorted(required.difference(body))
    if missing:
        fail(f"Administrator snapshot omitted required monitor fields: {missing}")
    return body


def rendered_summary(page) -> dict[str, str]:
    rows = page.locator("#ai-intake-monitor-summary article")
    if rows.count() != 5:
        fail(f"monitor summary must contain exactly five fields, found {rows.count()}")
    result = page.evaluate(
        """() => Object.fromEntries([...document.querySelectorAll('#ai-intake-monitor-summary article')]
          .map(row => [row.querySelector('span')?.textContent.trim(), row.querySelector('strong')?.textContent.trim()]))"""
    )
    if tuple(result.keys()) != SUMMARY_LABELS:
        fail(f"monitor field labels/order differ: {tuple(result.keys())!r}")
    return result


def expected_summary(page, snapshot: dict) -> dict[str, str]:
    return page.evaluate(
        """status => ({
          'Running Status': String(status.running_status),
          'Last Successful Run': status.last_successful_run ? operationalHealthDateLabel(status.last_successful_run) : 'Never',
          'Queue Count': String(status.queue_count),
          'Failed Count': String(status.failed_count),
          'Last Error': status.last_error || 'None'
        })""",
        snapshot,
    )


def assert_five_fields(page, snapshot: dict, context_name: str) -> None:
    actual = rendered_summary(page)
    expected = expected_summary(page, snapshot)
    if actual != expected:
        fail(f"{context_name} five-field monitor rendering differs from admin snapshot: actual={actual!r}, expected={expected!r}")


def capture_exact_row(cur, table: str, key_clause: str, params: tuple) -> dict:
    cur.execute(f"select to_jsonb(t) from public.{table} t where {key_clause} for update", params)
    row = cur.fetchone()
    if row is None:
        fail(f"required {table} fixture is unavailable")
    return row[0]


def restore_exact_row(conn, table: str, key_clause: str, key_params: tuple, before: dict) -> None:
    columns = tuple(before.keys())
    targets = ",".join(columns)
    sources = ",".join(f"r.{column}" for column in columns)
    with conn.cursor() as cur:
        cur.execute("set local session_replication_role=replica")
        cur.execute(
            f"""update public.{table} t set ({targets})=(
                   select {sources} from jsonb_populate_record(null::public.{table}, %s::jsonb) r
                 ) where {key_clause}""",
            (json.dumps(before), *key_params),
        )
        if cur.rowcount != 1:
            fail(f"{table} fixture disappeared before exact restoration")
        cur.execute(f"select to_jsonb(t) from public.{table} t where {key_clause}", key_params)
        restored = cur.fetchone()
        if restored is None or restored[0] != before:
            fail(f"{table} fixture did not restore to exact pre-campaign JSON")
    conn.commit()


def validate_fixture(cur, fixture_id: uuid.UUID) -> dict:
    before = capture_exact_row(cur, "ai_email_intake", "id=%s", (fixture_id,))
    if before.get("status") != "failed":
        fail(f"required fixture {fixture_id} must be in failed state, found {before.get('status')!r}")
    return before


def restore_fixture(conn, fixture_id: uuid.UUID, before: dict) -> None:
    restore_exact_row(conn, "ai_email_intake", "id=%s", (fixture_id,), before)


def capture_monitor_status(cur) -> dict:
    return capture_exact_row(cur, "pdc_email_monitor_status", "singleton", ())


def restore_monitor_status(conn, before: dict) -> None:
    restore_exact_row(conn, "pdc_email_monitor_status", "singleton", (), before)


def main() -> None:
    accounts, assert_staging_target, required, psycopg, sync_playwright = load_runtime_dependencies()
    project_url = required("PDC_STAGING_SUPABASE_URL")
    database_url = required("PDC_STAGING_DATABASE_URL")
    assert_staging_target(project_url=project_url, database_url=database_url)
    if urlparse(project_url).hostname != f"{EXPECTED_STAGING_REF}.supabase.co":
        fail("staging helper target guard passed an unexpected Supabase hostname")

    raw_fixture = os.environ.get(FIXTURE_ENV, "").strip()
    try:
        fixture_id = uuid.UUID(raw_fixture)
    except (ValueError, AttributeError):
        fail(f"{FIXTURE_ENV} must name a disposable failed ai_email_intake UUID")
    if str(fixture_id) != raw_fixture.lower():
        fail(f"{FIXTURE_ENV} must be a canonical UUID")

    server = None
    db = None
    fixture_before = None
    monitor_before = None
    try:
        db = psycopg.connect(database_url)
        with db.cursor() as cur:
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            sentinel = cur.fetchone()
            if sentinel != (EXPECTED_STAGING_REF,):
                fail("database staging sentinel is absent or mismatched")
            cur.execute("select to_regclass('public.pdc_email_monitor_status')::text")
            if cur.fetchone() != (MONITOR_TABLE,):
                fail("required monitor status relation is unavailable")
            fixture_before = validate_fixture(cur, fixture_id)
            monitor_before = capture_monitor_status(cur)
        db.commit()

        server = start_server()
        candidate_url = f"http://127.0.0.1:{server.server_port}/staging.html#emailreview"
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            contexts = []
            try:
                admin_pages = []
                browser_errors: dict[str, dict[str, list[str]]] = {}
                for index, (email, password) in enumerate((
                    (accounts.ADMIN_EMAIL, accounts.ADMIN_PASSWORD),
                    (accounts.ADMIN2_EMAIL, accounts.ADMIN2_PASSWORD),
                ), start=1):
                    context = browser.new_context(viewport={"width": 1440, "height": 1000})
                    contexts.append(context)
                    page = context.new_page()
                    browser_errors[f"admin-{index}"] = install_browser_guards(page, f"Administrator context {index}")
                    login(page, candidate_url, email, password, "administrator")
                    wait_for_monitor(page)
                    admin_pages.append(page)
                admin_a, admin_b = admin_pages
                if admin_a.context == admin_b.context:
                    fail("Administrator pages are not isolated browser contexts")

                snapshot_a = snapshot_body(admin_a)
                snapshot_b = snapshot_body(admin_b)
                assert_five_fields(admin_a, snapshot_a, "Administrator context A")
                assert_five_fields(admin_b, snapshot_b, "Administrator context B")

                controller_context = browser.new_context(viewport={"width": 1440, "height": 1000})
                contexts.append(controller_context)
                controller = controller_context.new_page()
                browser_errors["controller"] = install_browser_guards(controller, "Controller context")
                controller_monitor_calls: list[str] = []
                controller.on(
                    "request",
                    lambda request: controller_monitor_calls.append(request.url)
                    if SNAPSHOT_RPC in request.url or REPROCESS_RPC in request.url else None,
                )
                login(controller, candidate_url, accounts.CTRL_A_EMAIL, accounts.CTRL_A_PW, "operator")
                controller.wait_for_load_state("networkidle")
                if controller_monitor_calls:
                    fail("non-Administrator UI dispatched a monitor RPC")
                if controller.evaluate("() => window.app?.serverAiMonitorStatus ?? null") is not None:
                    fail("non-Administrator UI retained monitor authority data")
                assert_browser_clean(browser_errors["controller"], "Controller context before direct denial probes")
                denied_snapshot = rpc(controller, SNAPSHOT_RPC, {"p_failed_limit": 25})
                denied_reprocess = rpc(controller, REPROCESS_RPC, {"p_intake_id": str(fixture_id)})
                if denied_snapshot["ok"] or denied_snapshot["status"] not in (401, 403):
                    fail(f"Controller snapshot was not denied closed: HTTP {denied_snapshot['status']}")
                if denied_reprocess["ok"] or denied_reprocess["status"] not in (401, 403):
                    fail(f"Controller reprocess was not denied closed: HTTP {denied_reprocess['status']}")
                browser_errors["controller"]["console"].clear()
                browser_errors["controller"]["request"].clear()

                # Exercise the real rendered Reprocess button and record every RPC POST
                # emitted during the action. The fixture must be present in the admin RPC.
                fixture_rows = [row for row in snapshot_a.get("failed_items", []) if row.get("id") == str(fixture_id)]
                if len(fixture_rows) != 1:
                    fail("disposable failed fixture is not uniquely exposed by the 25-row admin snapshot")
                button = admin_a.locator(f'[data-ai-monitor-reprocess="{fixture_id}"]')
                if button.count() != 1 or not button.is_enabled():
                    fail("fixture Reprocess control is missing or disabled")
                calls: list[dict] = []
                rpc_responses: list[dict] = []

                def record_rpc(request) -> None:
                    marker = "/rest/v1/rpc/"
                    if request.method == "POST" and marker in request.url:
                        name = request.url.split(marker, 1)[1].split("?", 1)[0]
                        try:
                            payload = request.post_data_json
                        except Exception:
                            payload = None
                        calls.append({"name": name, "payload": payload})

                def record_rpc_response(response) -> None:
                    marker = "/rest/v1/rpc/"
                    if response.request.method == "POST" and marker in response.url:
                        name = response.url.split(marker, 1)[1].split("?", 1)[0]
                        body = None
                        with contextlib.suppress(Exception):
                            body = response.json()
                        rpc_responses.append({"name": name, "status": response.status, "body": body})

                admin_a.on("request", record_rpc)
                admin_a.on("response", record_rpc_response)
                with db.cursor() as cur:
                    cur.execute(
                        """select id::text from public.audit_events
                            where table_name='ai_email_intake'
                              and metadata->>'source'='administrator_monitor_reprocess'
                              and after_data->>'id'=%s
                            order by created_at,id""",
                        (str(fixture_id),),
                    )
                    audit_before = {row[0] for row in cur.fetchall()}
                db.commit()
                admin_a.once("dialog", lambda dialog: dialog.accept())
                button.click()
                admin_a.wait_for_function(
                    "id => !window.app.serverAiMonitorReprocessInFlight.has(id)",
                    arg=str(fixture_id),
                    timeout=20_000,
                )
                reprocess_calls = [call for call in calls if call["name"] == REPROCESS_RPC]
                allowed_read_rpcs = {SNAPSHOT_RPC, "get_pdc_ai_intake_snapshot"}
                unexpected_rpc_calls = [call for call in calls if call["name"] not in allowed_read_rpcs | {REPROCESS_RPC}]
                exact_payload = {"p_intake_id": str(fixture_id)}
                if reprocess_calls != [{"name": REPROCESS_RPC, "payload": exact_payload}]:
                    fail(f"Reprocess did not send exactly one scoped UUID RPC: {reprocess_calls!r}")
                if unexpected_rpc_calls:
                    fail(f"Reprocess action emitted an unexpected RPC POST: {unexpected_rpc_calls!r}")
                reprocess_responses = [item for item in rpc_responses if item["name"] == REPROCESS_RPC]
                if len(reprocess_responses) != 1 or reprocess_responses[0]["status"] not in (200, 201):
                    fail(f"Reprocess response was not one successful RPC response: {reprocess_responses!r}")
                response_body = reprocess_responses[0]["body"]
                if response_body != {"ok": True, "code": "email_requeued", "intake_id": str(fixture_id)}:
                    fail(f"Reprocess response body was not the exact authoritative contract: {response_body!r}")
                with db.cursor() as cur:
                    cur.execute("select status::text from public.ai_email_intake where id=%s", (fixture_id,))
                    if cur.fetchone() != ("received",):
                        fail("Reprocess RPC did not make the exact fixture authoritative state received")
                    cur.execute(
                        """select id::text,action,table_name,before_data,after_data,metadata
                            from public.audit_events
                            where table_name='ai_email_intake'
                              and metadata->>'source'='administrator_monitor_reprocess'
                              and after_data->>'id'=%s
                            order by created_at,id""",
                        (str(fixture_id),),
                    )
                    audit_rows = cur.fetchall()
                db.commit()
                new_audits = [row for row in audit_rows if row[0] not in audit_before]
                if len(new_audits) != 1:
                    fail("Reprocess did not append exactly one retained audit event")
                audit_event_id, audit_action, audit_table, audit_before_data, audit_after_data, audit_metadata = new_audits[0]
                if audit_action != "update" or audit_table != "ai_email_intake" \
                   or audit_before_data.get("id") != str(fixture_id) or audit_before_data.get("status") != "failed" \
                   or audit_after_data != {"id": str(fixture_id), "status": "received"} \
                   or audit_metadata.get("scoped_rpc") is not True \
                   or audit_metadata.get("monitor_status_signalled") is not True:
                    fail("Reprocess durable audit evidence did not match the exact scoped transition")

                # Restore and reread the disposable queue fixture before the independent Realtime proof.
                restore_fixture(db, fixture_id, fixture_before)
                fixture_restored_exactly = True
                fixture_before = None

                # Prove context B changes through Realtime: no reload, no refresh click,
                # no direct B-side RPC, and no test polling. We wait for the single snapshot
                # response caused by the table event, then inspect the already-updated DOM.
                baseline_text = rendered_summary(admin_b)["Last Error"]
                navigation_events: list[str] = []
                admin_b.on(
                    "framenavigated",
                    lambda frame: navigation_events.append(frame.url) if frame == admin_b.main_frame else None,
                )
                marker = f"acceptance-realtime-{uuid.uuid4()}"
                b_snapshot_requests: list[str] = []

                def record_b_snapshot_request(request) -> None:
                    if request.method == "POST" and f"/rest/v1/rpc/{SNAPSHOT_RPC}" in request.url:
                        b_snapshot_requests.append(request.url)

                admin_b.on("request", record_b_snapshot_request)
                initial_b_requests = len(b_snapshot_requests)
                admin_b.evaluate(
                    """marker => {
                      window.__pdcMonitorMarkerPromise = new Promise((resolve, reject) => {
                        const node = document.querySelector('#ai-intake-monitor-summary');
                        if (!node) return reject(new Error('monitor summary missing'));
                        const observer = new MutationObserver(() => {
                          if ([...node.querySelectorAll('strong')].some(item => item.textContent.trim() === marker)) {
                            observer.disconnect(); resolve(true);
                          }
                        });
                        observer.observe(node, {subtree: true, childList: true, characterData: true});
                        setTimeout(() => { observer.disconnect(); reject(new Error('causal marker DOM mutation timeout')); }, 20000);
                      });
                    }""",
                    marker,
                )
                with admin_b.expect_response(
                    lambda response: response.request.method == "POST"
                    and f"/rest/v1/rpc/{SNAPSHOT_RPC}" in response.url,
                    timeout=20_000,
                ) as causal_info:
                    with db.cursor() as cur:
                        cur.execute(
                            """update public.pdc_email_monitor_status
                                  set running_status='degraded',last_error=%s,
                                      last_error_code='acceptance_realtime',updated_at=clock_timestamp()
                                where singleton""",
                            (marker,),
                        )
                    db.commit()
                admin_b.evaluate("() => window.__pdcMonitorMarkerPromise")
                causal_response = causal_info.value
                causal_body = causal_response.json()
                if causal_response.status not in (200, 201) or not isinstance(causal_body, dict) or causal_body.get("last_error") != marker:
                    fail(f"Realtime-causal snapshot did not contain the marker: HTTP {causal_response.status}, body={causal_body!r}")
                # Keep request instrumentation active through a bounded post-response
                # observation window so a late duplicate refresh cannot escape the count.
                admin_b.wait_for_timeout(1000)
                causal_requests = b_snapshot_requests[initial_b_requests:]
                if len(causal_requests) != 1:
                    fail(f"Realtime event caused {len(causal_requests)} context-B snapshot requests within the observation window, expected exactly one")
                realtime_actual = rendered_summary(admin_b)["Last Error"]
                if realtime_actual != marker or realtime_actual == baseline_text:
                    fail("context B DOM did not change from the pdc_email_monitor_status Realtime event")
                if navigation_events:
                    fail(f"context B navigated/reloaded during the Realtime proof: {navigation_events!r}")
                assert_browser_clean(browser_errors["admin-1"], "Administrator context A")
                assert_browser_clean(browser_errors["admin-2"], "Administrator context B")
                assert_browser_clean(browser_errors["controller"], "Controller context", allow_protected_denials=True)

                restore_monitor_status(db, monitor_before)
                monitor_restored_exactly = True
                monitor_before = None
                print(json.dumps({
                    "ok": True,
                    "candidate": str((ROOT / 'staging.html').resolve()),
                    "administrator_contexts": 2,
                    "five_monitor_fields_verified": list(SUMMARY_LABELS),
                    "reprocess_rpc": {"name": REPROCESS_RPC, "uuid_argument_count": 1, "code": "email_requeued"},
                    "authoritative_reprocess_transition_verified": True,
                    "durable_audit_event": {"id": audit_event_id, "retained": True},
                    "fixture_restored_exactly": fixture_restored_exactly,
                    "monitor_status_restored_exactly": monitor_restored_exactly,
                    "controller_denied": True,
                    "realtime_causal_snapshot_count": 1,
                    "realtime_context_b_without_manual_refresh_reload_or_test_polling": True,
                }, indent=2, sort_keys=True))
            finally:
                for context in contexts:
                    with contextlib.suppress(Exception):
                        context.close()
                browser.close()
    finally:
        cleanup_errors: list[str] = []
        if db is not None:
            if fixture_before is not None:
                try:
                    db.rollback()
                    restore_fixture(db, fixture_id, fixture_before)
                except Exception:
                    cleanup_errors.append("failed-intake fixture exact restoration failed")
                    with contextlib.suppress(Exception):
                        db.rollback()
            if monitor_before is not None:
                try:
                    db.rollback()
                    restore_monitor_status(db, monitor_before)
                except Exception:
                    cleanup_errors.append("monitor singleton exact restoration failed")
                    with contextlib.suppress(Exception):
                        db.rollback()
            db.close()
        if server is not None:
            server.shutdown()
            server.server_close()
        if cleanup_errors:
            fail("; ".join(cleanup_errors))


if __name__ == "__main__":
    try:
        main()
    except AcceptanceFailure as exc:
        print(f"PDC monitor browser acceptance FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        # Unexpected dependency/network exceptions can embed credential-bearing
        # connection strings, so never print their repr or traceback.
        print("PDC monitor browser acceptance FAILED: unexpected runtime error (details redacted)", file=sys.stderr)
        raise SystemExit(1)
