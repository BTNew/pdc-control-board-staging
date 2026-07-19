"""Generate sanitized authenticated-viewer C6 evidence using only tracked code."""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import stage2b_c6_operational_rehearsal as c6


def request(method: str, path: str, *, token: str | None = None, body=None):
    base = os.environ.get("PDC_STAGING_SUPABASE_URL", "").rstrip("/")
    if urllib.parse.urlparse(base).hostname != f"{c6.STAGING_REF}.supabase.co":
        raise c6.C6PilotRefusal("viewer verifier is not bound to exact staging")
    anon = os.environ.get("PDC_STAGING_ANON_KEY", "")
    headers = {"apikey": anon, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = None
        return exc.code, parsed


def run(output: Path) -> dict:
    evidence = ROOT / "review-evidence" / "stage2b-c6"
    apply_result = json.loads((evidence / "apply-result.json").read_text(encoding="utf-8"))
    operational = json.loads((evidence / "operational-scenarios.json").read_text(encoding="utf-8"))
    vehicle_id = apply_result["actions"][0]["vehicle_id"]
    booking_id = operational["workshop"]["booking_id"]
    email = os.environ["PDC_STAGING_VIEWER_EMAIL"]
    password = os.environ["PDC_STAGING_VIEWER_PASSWORD"]
    status, auth = request("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})
    if status != 200 or not isinstance(auth, dict) or not auth.get("access_token"):
        raise c6.C6PilotRefusal("viewer sign-in failed")
    token = auth["access_token"]
    session_user_id = auth.get("user", {}).get("id")
    user_status, user = request("GET", "/auth/v1/user", token=token)
    authenticated_user_id = user.get("id") if isinstance(user, dict) else None
    role_status, role_value = request("POST", "/rest/v1/rpc/current_pdc_user_role", token=token, body={})
    account_status_code, account_status_value = request("POST", "/rest/v1/rpc/current_pdc_account_status", token=token, body={})
    vehicle_fields = "id,version,current_location,lifecycle_state,workshop_status,active_workshop_booking_id"
    booking_fields = "id,vehicle_id,version,status"
    vehicle_status, vehicles = request("GET", f"/rest/v1/vehicles?id=eq.{vehicle_id}&select={vehicle_fields}", token=token)
    booking_status, bookings = request("GET", f"/rest/v1/workshop_bookings?id=eq.{booking_id}&select={booking_fields}", token=token)
    if vehicle_status != 200 or len(vehicles or []) != 1 or booking_status != 200 or len(bookings or []) != 1:
        raise c6.C6PilotRefusal("viewer bounded read failed")
    vehicle, booking = vehicles[0], bookings[0]
    contract = c6.viewer_contract_evidence(vehicle, booking)
    vehicle_write_status, vehicle_write_body = request("POST", "/rest/v1/rpc/move_vehicle", token=token, body={
        "p_vehicle_id": vehicle_id,
        "p_expected_version": vehicle["version"],
        "p_to_location": "C6-VIEWER-MUST-NOT-WRITE",
        "p_reason": "C6 viewer denial verification",
    })
    booking_write_status, booking_write_body = request("POST", "/rest/v1/rpc/start_workshop_work", token=token, body={
        "p_booking_id": booking_id,
        "p_expected_version": booking["version"],
    })
    expected_vehicle_fields = ["active_workshop_booking_id", "current_location", "id", "lifecycle_state", "version", "workshop_status"]
    expected_booking_fields = ["id", "status", "vehicle_id", "version"]
    report = {
        "schema": "pdc.stage2b.c6-viewer-contract-live-verification/v1",
        "exact_staging_project_ref": c6.STAGING_REF,
        "approved_vehicle_id": vehicle_id,
        "approved_booking_id": booking_id,
        "authentication": {
            "sign_in_status": status,
            "get_user_status": user_status,
            "session_user_matches_get_user": bool(session_user_id and session_user_id == authenticated_user_id),
            "role_read_status": role_status,
            "account_status_read_status": account_status_code,
            "role": role_value,
            "account_status": account_status_value,
            "raw_identity_retained": False,
        },
        "vehicle_fields_returned": contract["vehicle_fields_returned"],
        "workshop_fields_returned": contract["workshop_fields_returned"],
        "vehicle_fields_allowed": expected_vehicle_fields,
        "workshop_fields_allowed": expected_booking_fields,
        "prohibited_fields_absent": contract["prohibited_fields_absent"],
        "broad_direct_vehicle_projection_used": contract["broad_direct_vehicle_projection_used"],
        "technician_or_sensitive_data_retained": contract["technician_or_sensitive_data_retained"],
        "viewer_vehicle_read_status": vehicle_status,
        "viewer_workshop_read_status": booking_status,
        "viewer_vehicle_write_status": vehicle_write_status,
        "viewer_workshop_write_status": booking_write_status,
        "viewer_vehicle_write_sqlstate": vehicle_write_body.get("code") if isinstance(vehicle_write_body, dict) else None,
        "viewer_workshop_write_sqlstate": booking_write_body.get("code") if isinstance(booking_write_body, dict) else None,
        "viewer_vehicle_write_refused": vehicle_write_status == 403,
        "viewer_workshop_write_refused": booking_write_status == 403,
        "write_response_bodies_retained": False,
    }
    report["passed"] = (
        report["authentication"]["sign_in_status"] == 200
        and report["authentication"]["get_user_status"] == 200
        and report["authentication"]["session_user_matches_get_user"]
        and report["authentication"]["role_read_status"] == 200
        and report["authentication"]["account_status_read_status"] == 200
        and report["authentication"]["role"] == "viewer"
        and report["authentication"]["account_status"] == "approved"
        and report["vehicle_fields_returned"] == expected_vehicle_fields
        and report["workshop_fields_returned"] == expected_booking_fields
        and report["prohibited_fields_absent"]
        and vehicle_write_status == 403 and booking_write_status == 403
        and report["viewer_vehicle_write_sqlstate"] == "42501"
        and report["viewer_workshop_write_sqlstate"] == "42501"
    )
    if not report["passed"]:
        raise c6.C6PilotRefusal("authenticated viewer contract or write denial failed")
    output.write_text(c6.canonical_json(report) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "review-evidence/stage2b-c6/viewer-contract-live-verification.json")
    args = parser.parse_args()
    report = run(args.output)
    print(c6.canonical_json({"passed": report["passed"], "vehicle_read": report["viewer_vehicle_read_status"],
                             "booking_read": report["viewer_workshop_read_status"],
                             "vehicle_write": report["viewer_vehicle_write_status"],
                             "booking_write": report["viewer_workshop_write_status"]}))


if __name__ == "__main__":
    main()
