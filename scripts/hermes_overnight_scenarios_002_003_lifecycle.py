"""Verify guarded IT/YH to PMB transitions on synthetic scenarios 002 and 003."""
from __future__ import annotations

import datetime as dt
import json
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
ENV = pathlib.Path(r"C:\Users\nwmgr\AppData\Local\hermes\profiles\website-development-lead\.env")
REF = "cdsmnqxtyyoeoznmbidd"
RUN = "HERMES-TEST-RUN-20260824"
OUT = ROOT / "_staging_deployment_receipts" / "20260824_overnight_scenarios_002_003_lifecycle.json"
NAMESPACE = uuid.UUID("36500000-0000-5000-8000-000000000365")


def env_values() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in ENV.read_text(encoding="utf-8-sig").splitlines():
        text = raw.strip()
        if text and not text.startswith("#") and "=" in text:
            key, value = text.split("=", 1)
            values[key.strip()] = value.strip().strip("'\"")
    return values


def request_json(url: str, method: str, headers: dict[str, str], body: dict) -> tuple[int, dict]:
    request = urllib.request.Request(url, data=json.dumps(body).encode(), method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8", "replace"))


def prove_environment() -> dict:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "hermes_overnight_environment_proof.py")],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        timeout=240,
    )
    proof = json.loads(result.stdout)
    database = proof.get("database") or {}
    if (
        proof.get("production_access_guard") is not True
        or database.get("project_ref") != REF
        or database.get("staging_sentinel_rows") != 1
        or database.get("production_sentinel_absent") is not True
        or database.get("monitor_status") != "stopped"
        or database.get("active_mailboxes") != 0
        or database.get("active_activation_writers") != 0
        or database.get("outbound_notification_rows") != 0
        or database.get("pending_outbound_notifications") != 0
        or database.get("synthetic_vehicle_total") != 20
    ):
        raise RuntimeError("environment proof containment mismatch")
    return proof


def main() -> None:
    environment = env_values()
    base = environment["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    key = environment["PDC_STAGING_ANON_KEY"]
    if environment.get("PDC_STAGING_PROJECT_REF") != REF or REF not in base:
        raise RuntimeError("target guard failed")

    initial_proof = prove_environment()
    status, session = request_json(
        base + "/auth/v1/token?grant_type=password",
        "POST",
        {"apikey": key, "Content-Type": "application/json"},
        {"email": environment["PDC_STAGING_ADMIN2_EMAIL"], "password": environment["PDC_STAGING_ADMIN2_PASSWORD"]},
    )
    if status != 200:
        raise RuntimeError("staging Administrator2 authentication failed")
    token = session["access_token"]
    actor_id = session["user"]["id"]
    headers = {"apikey": key, "Authorization": "Bearer " + token, "Content-Type": "application/json"}

    def rpc(name: str, payload: dict) -> tuple[int, dict]:
        return request_json(base + "/rest/v1/rpc/" + name, "POST", headers, payload)

    def read(vehicle_id: str | None = None) -> dict:
        read_status, state = rpc("read_pdc_hermes_test_mutation_state_365", {"p_run_id": RUN, "p_vehicle_id": vehicle_id})
        if read_status != 200 or state.get("ok") is not True or state.get("notification_count") != 0:
            raise RuntimeError(f"authenticated wrapper readback failed status={read_status} body={json.dumps(state)[:800]}")
        return state

    fleet = read()
    initial_protected = fleet.get("protected_state")
    evidence_rows: list[dict] = []
    expected_locations = {2: "IT", 3: "YH"}

    for scenario_no, expected_location in expected_locations.items():
        row = next((item for item in fleet.get("vehicles") or [] if item.get("scenario_no") == scenario_no), None)
        stock = f"HERMES-TEST-{scenario_no:03d}"
        if not row or row.get("vehicle", {}).get("stock_number") != stock:
            raise RuntimeError(f"scenario {scenario_no:03d} identity mismatch")
        vehicle = row["vehicle"]
        vehicle_id = vehicle["id"]
        before = read(vehicle_id)
        before_row = before["vehicles"][0]
        before_vehicle = before_row["vehicle"]
        if before_vehicle.get("current_location") != expected_location:
            raise RuntimeError(f"{stock} expected initial location {expected_location}, got {before_vehicle.get('current_location')}")
        version_before = int(before_vehicle["version"])
        movement_count_before = len(before_row.get("movements") or [])
        audit_count_before = len(before_row.get("audit_events") or [])
        apply_key = str(uuid.uuid5(NAMESPACE, RUN + f":scenario-{scenario_no:03d}:to-pmb"))
        payload = {
            "p_run_id": RUN,
            "p_vehicle_id": vehicle_id,
            "p_expected_version": version_before,
            "p_idempotency_key": apply_key,
            "p_action": "to_pmb",
        }

        pre_apply_proof = prove_environment()
        apply_status, applied = rpc("pdc_hermes_test_lifecycle_365", payload)
        if apply_status != 200 or applied.get("ok") is not True or applied.get("replay") is not False:
            raise RuntimeError(f"{stock} lifecycle Apply failed status={apply_status} body={json.dumps(applied)[:1200]}")
        if applied.get("notification_delta") != 0:
            raise RuntimeError(f"{stock} unexpected notification delta")
        after_apply = read(vehicle_id)
        after_row = after_apply["vehicles"][0]
        after_vehicle = after_row["vehicle"]
        source_payload = after_vehicle.get("source_payload") or {}
        if (
            after_vehicle.get("current_location") != "PMB"
            or int(after_vehicle["version"]) != version_before + 1
            or source_payload.get("manual_location_authority") != "PMB"
            or len(after_row.get("movements") or []) != movement_count_before + 1
            or len(after_row.get("audit_events") or []) < audit_count_before + 1
            or len(after_row.get("receipts") or []) < 1
        ):
            raise RuntimeError(f"{stock} authoritative post-Apply state mismatch")

        replay_status, replayed = rpc("pdc_hermes_test_lifecycle_365", payload)
        if (
            replay_status != 200
            or replayed.get("ok") is not True
            or replayed.get("replay") is not True
            or replayed.get("replay_containment_verified") is not True
        ):
            raise RuntimeError(f"{stock} exact replay failed")
        after_replay = read(vehicle_id)
        replay_row = after_replay["vehicles"][0]
        if (
            replay_row["vehicle"]["version"] != after_vehicle["version"]
            or len(replay_row.get("movements") or []) != len(after_row.get("movements") or [])
            or len(replay_row.get("receipts") or []) != len(after_row.get("receipts") or [])
        ):
            raise RuntimeError(f"{stock} replay changed authoritative state")

        changed = dict(payload)
        changed["p_action"] = "ready_qc"
        changed_status, changed_result = rpc("pdc_hermes_test_lifecycle_365", changed)
        if changed_status < 400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(changed_result):
            raise RuntimeError(f"{stock} changed-payload replay was not rejected")
        after_changed = read(vehicle_id)
        changed_row = after_changed["vehicles"][0]
        if (
            changed_row["vehicle"]["version"] != after_vehicle["version"]
            or len(changed_row.get("movements") or []) != len(after_row.get("movements") or [])
            or len(changed_row.get("receipts") or []) != len(after_row.get("receipts") or [])
        ):
            raise RuntimeError(f"{stock} changed-payload rejection changed state")

        stale_key = str(uuid.uuid5(NAMESPACE, RUN + f":scenario-{scenario_no:03d}:stale-to-pmb"))
        stale_payload = dict(payload)
        stale_payload["p_idempotency_key"] = stale_key
        pre_stale_proof = prove_environment()
        stale_status, stale_result = rpc("pdc_hermes_test_lifecycle_365", stale_payload)
        if (
            stale_status != 200
            or stale_result.get("ok") is not False
            or stale_result.get("result", {}).get("error") != "vehicle_version_conflict"
            or stale_result.get("vehicle_version_after") != after_vehicle["version"]
            or stale_result.get("notification_delta") != 0
        ):
            raise RuntimeError(f"{stock} stale-version probe mismatch status={stale_status} body={json.dumps(stale_result)[:1200]}")
        final = read(vehicle_id)
        final_row = final["vehicles"][0]
        if (
            final_row["vehicle"]["version"] != after_vehicle["version"]
            or final_row["vehicle"]["current_location"] != "PMB"
            or len(final_row.get("movements") or []) != len(after_row.get("movements") or [])
            or len(final_row.get("receipts") or []) != len(after_row.get("receipts") or []) + 1
            or final.get("protected_state") != initial_protected
        ):
            raise RuntimeError(f"{stock} final authoritative state mismatch")

        evidence_rows.append(
            {
                "scenario_no": scenario_no,
                "stock": stock,
                "initial_location": expected_location,
                "final_location": final_row["vehicle"]["current_location"],
                "manual_location_authority": final_row["vehicle"]["source_payload"].get("manual_location_authority"),
                "vehicle_id": vehicle_id,
                "vehicle_version_before": version_before,
                "vehicle_version_after": final_row["vehicle"]["version"],
                "movement_count_before": movement_count_before,
                "movement_count_after": len(final_row.get("movements") or []),
                "apply_idempotency_key": apply_key,
                "apply_receipt_id": applied.get("receipt_id"),
                "stale_receipt_id": stale_result.get("receipt_id"),
                "exact_replay_verified": True,
                "changed_payload_rejected": True,
                "stale_version_rejected_without_target_change": True,
                "protected_state": applied.get("protected_state"),
                "sibling_state": applied.get("sibling_state"),
                "revisions": applied.get("revisions"),
                "pre_apply_migration_head": pre_apply_proof["database"]["migration_head"],
                "pre_stale_migration_head": pre_stale_proof["database"]["migration_head"],
            }
        )
        fleet = read()

    final_proof = prove_environment()
    final_state = read()
    if final_state.get("protected_state") != initial_protected:
        raise RuntimeError("protected-state digest changed across lifecycle scenarios")
    evidence = {
        "schema": "pdc-overnight-scenarios-002-003-lifecycle-v1",
        "project_ref": REF,
        "run_id": RUN,
        "actor_id": actor_id,
        "initial_environment": initial_proof,
        "final_environment": final_proof,
        "protected_state": final_state.get("protected_state"),
        "notification_count": final_state.get("notification_count"),
        "scenarios": evidence_rows,
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(
        json.dumps(
            {
                "status": "SCENARIOS_002_003_LIFECYCLE_VERIFIED",
                "project_ref": REF,
                "stocks": [row["stock"] for row in evidence_rows],
                "locations": [row["initial_location"] + "->" + row["final_location"] for row in evidence_rows],
                "apply_receipts": [row["apply_receipt_id"] for row in evidence_rows],
                "stale_receipts": [row["stale_receipt_id"] for row in evidence_rows],
                "notifications": final_state.get("notification_count"),
                "evidence": str(OUT.resolve()),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
