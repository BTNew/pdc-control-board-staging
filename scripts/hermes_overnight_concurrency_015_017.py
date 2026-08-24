"""Exercise idempotency, stale versions, and two live same-record races on 015-017."""
from __future__ import annotations

import concurrent.futures
import datetime as dt
import hashlib
import json
import pathlib
import threading
import uuid

from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json

ROOT = pathlib.Path(__file__).resolve().parents[1]
REF = "cdsmnqxtyyoeoznmbidd"
RUN = "HERMES-TEST-RUN-20260824"
NS = uuid.UUID("36500000-0000-5000-8000-000000000365")
OUT = ROOT / "_staging_deployment_receipts" / "20260824_overnight_concurrency_015_017.json"
STATE_KEYS = (
    "vehicle", "work_items", "bookings", "booking_assignments", "booking_history",
    "parts_overrides", "parts", "sublets", "movements", "audit_events", "sublet_history",
)


def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), default=str).encode()).hexdigest()


def main() -> None:
    environment = env_values()
    base = environment["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    key = environment["PDC_STAGING_ANON_KEY"]
    if environment.get("PDC_STAGING_PROJECT_REF") != REF or REF not in base:
        raise RuntimeError("target guard")
    initial_environment = prove_environment()

    def auth() -> dict:
        status, session = request_json(
            base + "/auth/v1/token?grant_type=password", "POST",
            {"apikey": key, "Content-Type": "application/json"},
            {"email": environment["PDC_STAGING_ADMIN2_EMAIL"], "password": environment["PDC_STAGING_ADMIN2_PASSWORD"]},
        )
        if status != 200:
            raise RuntimeError("isolated staging Administrator session authentication failed")
        return session

    # Three separately authenticated sessions share the approved actor but not tokens/HTTP state.
    sessions = [auth() for _ in range(3)]
    actor_ids = {session["user"]["id"] for session in sessions}
    token_digests = {digest(session["access_token"]) for session in sessions}
    if len(actor_ids) != 1 or len(token_digests) != 3:
        raise RuntimeError("isolated-session identity/token contract failed")
    actor_id = next(iter(actor_ids))

    def headers(session: dict) -> dict[str, str]:
        return {"apikey": key, "Authorization": "Bearer " + session["access_token"], "Content-Type": "application/json"}

    def rpc(session: dict, name: str, payload: dict) -> tuple[int, dict]:
        return request_json(base + "/rest/v1/rpc/" + name, "POST", headers(session), payload)

    def read(vehicle_id: str | None = None) -> dict:
        status, state = rpc(sessions[0], "read_pdc_hermes_test_mutation_state_365", {"p_run_id": RUN, "p_vehicle_id": vehicle_id})
        if status != 200 or state.get("ok") is not True or state.get("notification_count") != 0:
            raise RuntimeError(f"authoritative readback failed {status} {json.dumps(state)[:800]}")
        return state

    fleet = read()
    protected = fleet["protected_state"]
    rows = {row["scenario_no"]: row for row in fleet["vehicles"] if row["scenario_no"] in (15, 16, 17)}
    if set(rows) != {15, 16, 17}:
        raise RuntimeError("scenario inventory")
    for no, row in rows.items():
        vehicle = row["vehicle"]
        if vehicle["stock_number"] != f"HERMES-TEST-{no:03d}" or vehicle["customer_name"].startswith("HERMES-TEST") is not True:
            raise RuntimeError(f"scenario {no} identity")

    def state_digest(row: dict) -> str:
        return digest({name: row.get(name) for name in STATE_KEYS})

    def fleet_digest_excluding(state: dict, excluded_no: int) -> str:
        return digest({str(row["scenario_no"]): state_digest(row) for row in state["vehicles"] if row["scenario_no"] != excluded_no})

    def current(no: int) -> dict:
        vehicle_id = rows[no]["vehicle"]["id"]
        state = read(vehicle_id)
        if state["protected_state"] != protected or len(state["vehicles"]) != 1:
            raise RuntimeError(f"scenario {no} containment")
        return state["vehicles"][0]

    def edit_payload(no: int, expected_version: int, label: str, tag: str) -> dict:
        return {
            "p_run_id": RUN,
            "p_vehicle_id": rows[no]["vehicle"]["id"],
            "p_expected_version": expected_version,
            "p_idempotency_key": str(uuid.uuid5(NS, f"{RUN}:{label}")),
            "p_pmb_key_tag": tag,
        }

    def invoke(session: dict, payload: dict) -> tuple[int, dict]:
        return rpc(session, "pdc_hermes_test_vehicle_edit_365", payload)

    def concurrent_calls(calls: list[tuple[dict, dict]]) -> list[tuple[int, dict]]:
        barrier = threading.Barrier(len(calls))

        def worker(call: tuple[dict, dict]) -> tuple[int, dict]:
            # Every mutating request independently re-proves the exact staging sentinel and containment.
            prove_environment()
            barrier.wait(timeout=240)
            return invoke(*call)

        with concurrent.futures.ThreadPoolExecutor(max_workers=len(calls)) as pool:
            futures = [pool.submit(worker, call) for call in calls]
            return [future.result(timeout=300) for future in futures]

    evidence_actions: list[dict] = []

    # 015: two isolated sessions submit the exact same actor/idempotency/payload concurrently.
    before15 = current(15)
    fleet_before15 = read()
    payload15 = edit_payload(15, int(before15["vehicle"]["version"]), "015-duplicate-submit", "HERMES-TEST-015-DUPLICATE")
    responses15 = concurrent_calls([(sessions[0], payload15), (sessions[1], payload15)])
    after15 = current(15)
    if any(status != 200 or response.get("ok") is not True for status, response in responses15):
        raise RuntimeError(f"015 duplicate results {json.dumps(responses15)[:1200]}")
    if sorted(response.get("replay") for _, response in responses15) != [False, True]:
        raise RuntimeError("015 duplicate was not exactly one Apply plus one replay")
    receipts15 = [receipt for receipt in after15["receipts"] if receipt["idempotency_key"] == payload15["p_idempotency_key"]]
    if len(receipts15) != 1 or int(after15["vehicle"]["version"]) != int(before15["vehicle"]["version"]) + 1 or after15["vehicle"]["pmb_key_tag"] != payload15["p_pmb_key_tag"]:
        raise RuntimeError("015 duplicate authoritative postcondition")
    if fleet_digest_excluding(read(), 15) != fleet_digest_excluding(fleet_before15, 15):
        raise RuntimeError("015 changed a sibling")
    prove_environment()
    changed15 = dict(payload15)
    changed15["p_pmb_key_tag"] = "HERMES-TEST-015-CHANGED-PAYLOAD"
    changed_status, changed_response = invoke(sessions[2], changed15)
    if changed_status < 400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(changed_response):
        raise RuntimeError("015 same-key changed payload did not fail closed")
    if state_digest(current(15)) != state_digest(after15):
        raise RuntimeError("015 changed-payload probe changed state")
    evidence_actions.append({
        "scenario_no": 15, "kind": "duplicate_submit", "idempotency_key": payload15["p_idempotency_key"],
        "receipt_id": receipts15[0]["receipt_id"], "responses": responses15,
        "version_before": before15["vehicle"]["version"], "version_after": after15["vehicle"]["version"],
        "exactly_one_apply_one_replay": True, "same_key_changed_payload_rejected": True,
    })

    # 016: a stale expected version commits only an immutable rejection receipt.
    before16 = current(16)
    fleet_before16 = read()
    stale16 = edit_payload(16, int(before16["vehicle"]["version"]) + 7, "016-stale-version", "HERMES-TEST-016-STALE-MUST-NOT-WRITE")
    prove_environment()
    stale_status, stale_response = invoke(sessions[0], stale16)
    after16 = current(16)
    if stale_status != 200 or stale_response.get("ok") is not False or "vehicle_version_conflict" not in json.dumps(stale_response):
        raise RuntimeError(f"016 stale result {stale_status} {json.dumps(stale_response)[:800]}")
    stale_receipts = [receipt for receipt in after16["receipts"] if receipt["idempotency_key"] == stale16["p_idempotency_key"]]
    if len(stale_receipts) != 1 or digest(after16["vehicle"]) != digest(before16["vehicle"]):
        raise RuntimeError("016 stale authoritative no-change/receipt postcondition")
    if fleet_digest_excluding(read(), 16) != fleet_digest_excluding(fleet_before16, 16):
        raise RuntimeError("016 changed a sibling")
    evidence_actions.append({
        "scenario_no": 16, "kind": "stale_expected_version", "idempotency_key": stale16["p_idempotency_key"],
        "receipt_id": stale_receipts[0]["receipt_id"], "response": stale_response,
        "vehicle_unchanged": True, "rejection_receipt_count": 1,
    })

    # 017: two separate, same-record races. Each must serialize to one winner and one version-conflict loser.
    for race_no in (1, 2):
        before17 = current(17)
        fleet_before17 = read()
        expected = int(before17["vehicle"]["version"])
        payload_a = edit_payload(17, expected, f"017-race-{race_no}-a", f"HERMES-TEST-017-RACE-{race_no}-A")
        payload_b = edit_payload(17, expected, f"017-race-{race_no}-b", f"HERMES-TEST-017-RACE-{race_no}-B")
        results = concurrent_calls([(sessions[1], payload_a), (sessions[2], payload_b)])
        after17 = current(17)
        if any(status != 200 for status, _ in results):
            raise RuntimeError(f"017 race {race_no} HTTP results {json.dumps(results)[:1200]}")
        winners = [(payload, response) for payload, (_, response) in zip((payload_a, payload_b), results) if response.get("ok") is True]
        losers = [(payload, response) for payload, (_, response) in zip((payload_a, payload_b), results) if response.get("ok") is False]
        if len(winners) != 1 or len(losers) != 1 or "vehicle_version_conflict" not in json.dumps(losers[0][1]):
            raise RuntimeError(f"017 race {race_no} winner/loser contract {json.dumps(results)[:1200]}")
        race_idems = {payload_a["p_idempotency_key"], payload_b["p_idempotency_key"]}
        race_receipts = [receipt for receipt in after17["receipts"] if receipt["idempotency_key"] in race_idems]
        if len(race_receipts) != 2 or len({receipt["receipt_id"] for receipt in race_receipts}) != 2:
            raise RuntimeError(f"017 race {race_no} duplicate/missing receipts")
        if int(after17["vehicle"]["version"]) != expected + 1 or after17["vehicle"]["pmb_key_tag"] != winners[0][0]["p_pmb_key_tag"]:
            raise RuntimeError(f"017 race {race_no} lost update/winner readback")
        if fleet_digest_excluding(read(), 17) != fleet_digest_excluding(fleet_before17, 17):
            raise RuntimeError(f"017 race {race_no} changed a sibling")
        for payload, response in winners + losers:
            matching = [receipt for receipt in race_receipts if receipt["idempotency_key"] == payload["p_idempotency_key"]]
            if len(matching) != 1 or matching[0]["receipt_id"] != response.get("receipt_id") or matching[0]["request_sha256"] != response.get("request_sha256"):
                raise RuntimeError(f"017 race {race_no} receipt binding")
            if response.get("protected_state") != protected or response.get("notification_delta") != 0:
                raise RuntimeError(f"017 race {race_no} response containment")
        evidence_actions.append({
            "scenario_no": 17, "kind": "same_record_race", "race_no": race_no,
            "expected_version": expected, "version_after": after17["vehicle"]["version"],
            "winner": {"idempotency_key": winners[0][0]["p_idempotency_key"], "tag": winners[0][0]["p_pmb_key_tag"], "receipt_id": winners[0][1]["receipt_id"]},
            "loser": {"idempotency_key": losers[0][0]["p_idempotency_key"], "error": (losers[0][1].get("result") or {}).get("error"), "receipt_id": losers[0][1]["receipt_id"]},
            "receipt_count": 2, "no_lost_update": True, "sibling_unchanged": True,
        })

    final_fleet = read()
    final_environment = prove_environment()
    final_rows = {row["scenario_no"]: row for row in final_fleet["vehicles"] if row["scenario_no"] in (15, 16, 17)}
    if final_fleet["protected_state"] != protected or final_fleet["notification_count"] != 0:
        raise RuntimeError("final containment")
    # Explicit inventory catches accidental duplicate rows.
    receipt_inventory = {
        str(no): [
            {key: receipt.get(key) for key in ("receipt_id", "actor_id", "idempotency_key", "action", "request_sha256", "response")}
            for receipt in final_rows[no]["receipts"]
        ] for no in (15, 16, 17)
    }
    all_receipt_ids = [receipt["receipt_id"] for receipts in receipt_inventory.values() for receipt in receipts]
    if len(all_receipt_ids) != len(set(all_receipt_ids)):
        raise RuntimeError("duplicate receipt rows")

    evidence = {
        "schema": "pdc-overnight-concurrency-015-017-v1", "project_ref": REF, "run_id": RUN,
        "actor_id": actor_id, "isolated_authenticated_sessions": 3, "distinct_token_digests": 3,
        "initial_environment": initial_environment, "final_environment": final_environment,
        "protected_state": protected, "actions": evidence_actions, "receipt_inventory": receipt_inventory,
        "final_state": {str(no): {"stock": final_rows[no]["vehicle"]["stock_number"], "version": final_rows[no]["vehicle"]["version"], "pmb_key_tag": final_rows[no]["vehicle"].get("pmb_key_tag"), "receipt_count": len(final_rows[no]["receipts"])} for no in (15, 16, 17)},
        "simultaneous_same_record_races": 2, "duplicate_submit_races": 1,
        "lost_updates": 0, "duplicate_receipt_rows": 0, "notifications": 0,
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    OUT.write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "status": "CONCURRENCY_015_017_VERIFIED", "duplicate_submit": True,
        "same_key_changed_payload_rejected": True, "stale_version_rejected": True,
        "simultaneous_same_record_races": 2, "lost_updates": 0, "duplicate_receipt_rows": 0,
        "notifications": 0, "final_versions": {str(no): final_rows[no]["vehicle"]["version"] for no in (15, 16, 17)},
        "evidence": str(OUT.resolve()),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
