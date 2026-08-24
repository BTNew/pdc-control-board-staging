"""Read-only final authenticated regression journey for HERMES-TEST-020."""
from __future__ import annotations
import hashlib, json, pathlib, time
from playwright.sync_api import sync_playwright
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json
from hermes_overnight_browser_019 import BASE, REF, install_network_guard, attach_observers, login, wait_eval, active_view

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "_overnight_evidence" / "final-020"
RUN = "HERMES-TEST-RUN-20260824"
ROUTES = ["dashboard", "workflow", "workshop/fitting", "parts", "sublet", "qc", "rft", "completed"]


def digest(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    env = env_values()
    base = env["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    key = env["PDC_STAGING_ANON_KEY"]
    if env.get("PDC_STAGING_PROJECT_REF") != REF or REF not in base:
        raise RuntimeError("exact staging binding failed")
    proof_before = prove_environment()
    status, auth = request_json(base + "/auth/v1/token?grant_type=password", "POST", {"apikey": key, "Content-Type": "application/json"}, {"email": env["PDC_STAGING_ADMIN2_EMAIL"], "password": env["PDC_STAGING_ADMIN2_PASSWORD"]})
    if status != 200:
        raise RuntimeError("staging authentication failed")
    headers = {"apikey": key, "Authorization": "Bearer " + auth["access_token"], "Content-Type": "application/json"}
    def read():
        s, value = request_json(base + "/rest/v1/rpc/read_pdc_hermes_test_mutation_state_365", "POST", headers, {"p_run_id": RUN, "p_vehicle_id": None})
        if s != 200 or value.get("ok") is not True or value.get("notification_count") != 0:
            raise RuntimeError("authoritative final read failed")
        return value
    before = read()
    rows = {int(row["scenario_no"]): row for row in before["vehicles"]}
    if set(rows) != set(range(1, 21)):
        raise RuntimeError("synthetic registry inventory drift")
    if rows[2]["vehicle"]["current_location"] != "PMB" or rows[3]["vehicle"]["current_location"] != "PMB":
        raise RuntimeError("lifecycle readback drift")
    booking_minutes = sorted(int(b["default_duration_minutes"]) for no in (5, 6, 7) for b in rows[no]["bookings"])
    if booking_minutes != [47, 59, 61, 73]:
        raise RuntimeError("exact-minute Workshop readback drift")
    if not all((r["parts"][-1]["parts_received"] and not r["parts"][-1]["parts_stoppage"]) for r in (rows[8], rows[9])):
        raise RuntimeError("Parts final-state drift")
    if rows[10]["sublets"][0]["status"] != "returned" or len(rows[11]["sublets"]) != 2 or len({x["provider_id"] for x in rows[11]["sublets"]}) != 2:
        raise RuntimeError("Sublet final-state/provider isolation drift")
    separation = {no: rows[no]["vehicle"]["current_location"] for no in (12, 13, 14)}
    if separation != {12: "QC", 13: "RFT", 14: "Completed"}:
        raise RuntimeError("QC/RFT/Completed separation drift")
    row20 = rows[20]
    if (row20["vehicle"]["stock_number"] != "HERMES-TEST-020" or row20["vehicle"]["current_location"] != "IT" or int(row20["vehicle"]["version"]) != 1
        or {x["work_key"].lower() for x in row20["work_items"]} != {"fitting", "electrical", "parts", "sublet"}
        or any(x["completed"] for x in row20["work_items"]) or any(row20[k] for k in ("parts", "sublets", "bookings", "receipts", "movements", "audit_events"))):
        raise RuntimeError("020 must remain a pristine read-only journey; physical completion evidence is absent")

    evidence = {"schema": "pdc-overnight-final-020-v1", "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "project_ref": REF,
                "proof_before": proof_before, "authoritative_before_digest": digest(before), "booking_minutes": booking_minutes, "separation": separation,
                "scenario_020": {"stock": row20["vehicle"]["stock_number"], "location": "IT", "version": 1, "required_work": sorted(x["work_key"] for x in row20["work_items"]), "physical_completion_claimed": False},
                "routes": [], "console": [], "page_errors": [], "failed_requests": [], "http_errors": [], "blocked_external_hosts": []}
    chrome = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True, executable_path=chrome, args=["--disable-extensions"])
        for session_no in (1, 2):
            context = browser.new_context(viewport={"width": 1280, "height": 900})
            install_network_guard(context, evidence)
            page = context.new_page(); attach_observers(page, evidence, f"final-{session_no}")
            login(page, env["PDC_STAGING_ADMIN2_EMAIL"], env["PDC_STAGING_ADMIN2_PASSWORD"])
            for path in ROUTES:
                page.goto(BASE + f"?hermes020=s{session_no}-{path.replace('/', '-')}#/{path}", wait_until="domcontentloaded", timeout=60000)
                wait_eval(page, "!document.querySelector('#app-shell').hasAttribute('inert')")
                wait_eval(page, "typeof selectedVehicle === 'function' && !!selectedVehicle('HERMES-TEST-020')")
                page.wait_for_timeout(400)
                first = active_view(page)
                page.reload(wait_until="domcontentloaded", timeout=60000)
                wait_eval(page, "!document.querySelector('#app-shell').hasAttribute('inert')")
                wait_eval(page, "typeof selectedVehicle === 'function' && !!selectedVehicle('HERMES-TEST-020')")
                evidence["routes"].append({"session": session_no, "path": path, "first": first, "reloaded": active_view(page), "hash": page.evaluate("location.hash"), "stockLoaded": True})
            context.close()
        browser.close()
    after = read()
    proof_after = prove_environment()
    if digest(after) != digest(before) or proof_after["database"] != proof_before["database"]:
        raise RuntimeError("read-only final journey changed authoritative staging state")
    if evidence["console"] or evidence["page_errors"] or evidence["failed_requests"] or evidence["http_errors"] or evidence["blocked_external_hosts"]:
        raise RuntimeError("browser final journey emitted errors or attempted an unapproved host")
    evidence.update({"proof_after": proof_after, "authoritative_after_digest": digest(after), "authoritative_no_change": True,
                     "completed_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    (OUT / "evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"routes": len(evidence["routes"]), "sessions": 2, "booking_minutes": booking_minutes, "separation": separation,
                      "scenario_020_pristine": True, "authoritative_no_change": True, "notifications": proof_after["database"]["outbound_notification_rows"],
                      "browser_errors": 0}, indent=2))

if __name__ == "__main__":
    main()
