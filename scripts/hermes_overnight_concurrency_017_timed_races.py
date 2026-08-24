"""Run two timed competing mutations on exact synthetic scenario 017."""
from __future__ import annotations

import concurrent.futures
import datetime as dt
import hashlib
import json
import pathlib
import threading
import time
import urllib.parse
import uuid

from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json
from pdc_staging_management_migration import STAGING_REF, _post

ROOT = pathlib.Path(__file__).resolve().parents[1]
REF = "cdsmnqxtyyoeoznmbidd"
RUN = "HERMES-TEST-RUN-20260824"
NS = uuid.UUID("36500000-0000-5000-8000-000000000365")
OUT = ROOT / "_staging_deployment_receipts" / "20260824_overnight_concurrency_017_timed_races.json"
EXPECTED_HEAD = {"version": "20260825110000", "name": "374_overnight_qc_fixture_registry_assignment"}
EXPECTED_APPLY_SHA256 = "bc627c01b4a7f7c812799018894a4f9e52e512a531cea22b40cb658d2e9f3e93"
EXPECTED_EDIT_SHA256 = "c6f99e6c01196524a7ccf5c43d79cd26faab07920cf2b4901cff294bb50187ab"
UNCHANGED_TARGET_KEYS = (
    "work_items", "bookings", "booking_assignments", "booking_history", "parts_overrides",
    "parts", "sublets", "movements", "sublet_history",
)


def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), default=str).encode()).hexdigest()


def main() -> None:
    if STAGING_REF != REF:
        raise RuntimeError("management target guard")
    environment = env_values()
    base = environment["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if (
        environment.get("PDC_STAGING_PROJECT_REF") != REF or parsed.scheme != "https"
        or parsed.hostname != f"{REF}.supabase.co" or parsed.username is not None or parsed.password is not None
        or parsed.port is not None or parsed.path not in ("", "/") or parsed.query or parsed.fragment
    ):
        raise RuntimeError("exact staging REST target guard")
    key = environment["PDC_STAGING_ANON_KEY"]
    initial_environment = prove_environment()
    if initial_environment["database"]["migration_head"] != EXPECTED_HEAD:
        raise RuntimeError("exact migration head drift")
    sql = """SET TRANSACTION READ ONLY;
select jsonb_build_object(
 'project_ref','cdsmnqxtyyoeoznmbidd',
 'migration_head',(select jsonb_build_object('version',version,'name',name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version desc limit 1),
 'apply_365_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'),
 'edit_365_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_hermes_test_vehicle_edit_365(text,uuid,integer,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex')
) evidence;"""
    live_contract = _post(f"https://api.supabase.com/v1/projects/{REF}/database/query/read-only", sql)[0]["evidence"]
    if live_contract != {
        "project_ref": REF, "migration_head": EXPECTED_HEAD,
        "apply_365_sha256": EXPECTED_APPLY_SHA256, "edit_365_sha256": EXPECTED_EDIT_SHA256,
    }:
        raise RuntimeError("exact live mutation contract drift")

    def auth() -> dict:
        status, session = request_json(
            base + "/auth/v1/token?grant_type=password", "POST", {"apikey": key, "Content-Type": "application/json"},
            {"email": environment["PDC_STAGING_ADMIN2_EMAIL"], "password": environment["PDC_STAGING_ADMIN2_PASSWORD"]},
        )
        if status != 200:
            raise RuntimeError("isolated staging authentication")
        return session

    sessions = [auth(), auth()]
    if sessions[0]["user"]["id"] != sessions[1]["user"]["id"] or sessions[0]["access_token"] == sessions[1]["access_token"]:
        raise RuntimeError("isolated sessions")
    actor_id = sessions[0]["user"]["id"]

    def rpc(session: dict, name: str, payload: dict) -> tuple[int, dict]:
        headers = {"apikey": key, "Authorization": "Bearer " + session["access_token"], "Content-Type": "application/json"}
        return request_json(base + "/rest/v1/rpc/" + name, "POST", headers, payload)

    def read(vehicle_id: str | None = None) -> dict:
        status, state = rpc(sessions[0], "read_pdc_hermes_test_mutation_state_365", {"p_run_id": RUN, "p_vehicle_id": vehicle_id})
        if status != 200 or state.get("ok") is not True or state.get("notification_count") != 0:
            raise RuntimeError("authoritative readback")
        return state

    fleet = read()
    protected = fleet["protected_state"]
    scenario = next((row for row in fleet["vehicles"] if row["scenario_no"] == 17), None)
    if not scenario or scenario["vehicle"]["stock_number"] != "HERMES-TEST-017":
        raise RuntimeError("scenario identity")
    vehicle_id = scenario["vehicle"]["id"]

    def fleet_sibling_digest(state: dict) -> str:
        return digest({str(row["scenario_no"]): row for row in state["vehicles"] if row["scenario_no"] != 17})

    races: list[dict] = []
    for race_no in (1, 2):
        before_fleet = read()
        before = read(vehicle_id)["vehicles"][0]
        expected_version = int(before["vehicle"]["version"])
        payloads = [
            {
                "p_run_id": RUN, "p_vehicle_id": vehicle_id, "p_expected_version": expected_version,
                "p_idempotency_key": str(uuid.uuid5(NS, f"{RUN}:017-timed-race-{race_no}-{side}")),
                "p_pmb_key_tag": f"HERMES-TEST-017-TIMED-RACE-{race_no}-{side.upper()}",
            }
            for side in ("a", "b")
        ]
        barrier = threading.Barrier(2)

        def worker(index: int) -> dict:
            proof = prove_environment()
            if proof["database"]["migration_head"] != EXPECTED_HEAD:
                raise RuntimeError("pre-mutation head drift")
            barrier.wait(timeout=240)
            start_ns = time.perf_counter_ns()
            status, response = rpc(sessions[index], "pdc_hermes_test_vehicle_edit_365", payloads[index])
            end_ns = time.perf_counter_ns()
            return {"side": index, "status": status, "response": response, "start_ns": start_ns, "end_ns": end_ns}

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(worker, index) for index in range(2)]
            results = [future.result(timeout=300) for future in futures]
        after = read(vehicle_id)["vehicles"][0]
        after_fleet = read()
        overlap_ns = min(result["end_ns"] for result in results) - max(result["start_ns"] for result in results)
        winners = [(payloads[result["side"]], result) for result in results if result["response"].get("ok") is True]
        losers = [(payloads[result["side"]], result) for result in results if result["response"].get("ok") is False]
        if any(result["status"] != 200 for result in results) or overlap_ns <= 0 or len(winners) != 1 or len(losers) != 1:
            raise RuntimeError(f"timed race {race_no} dispatch/winner count")
        if (losers[0][1]["response"].get("result") or {}).get("error") != "vehicle_version_conflict":
            raise RuntimeError(f"timed race {race_no} loser truth")
        if int(after["vehicle"]["version"]) != expected_version + 1 or after["vehicle"]["pmb_key_tag"] != winners[0][0]["p_pmb_key_tag"]:
            raise RuntimeError(f"timed race {race_no} authoritative winner/lost update")
        if len(after["receipts"]) != len(before["receipts"]) + 2 or len(after["audit_events"]) != len(before["audit_events"]) + 1:
            raise RuntimeError(f"timed race {race_no} exact receipt/audit deltas")
        if digest({key: before[key] for key in UNCHANGED_TARGET_KEYS}) != digest({key: after[key] for key in UNCHANGED_TARGET_KEYS}):
            raise RuntimeError(f"timed race {race_no} unrelated target relation changed")
        if after_fleet["protected_state"] != protected or fleet_sibling_digest(after_fleet) != fleet_sibling_digest(before_fleet):
            raise RuntimeError(f"timed race {race_no} protected/sibling drift")
        race_idems = {payload["p_idempotency_key"] for payload in payloads}
        race_receipts = [receipt for receipt in after["receipts"] if receipt["idempotency_key"] in race_idems]
        if len(race_receipts) != 2 or len({receipt["receipt_id"] for receipt in race_receipts}) != 2 or len({(receipt["actor_id"], receipt["idempotency_key"]) for receipt in race_receipts}) != 2:
            raise RuntimeError(f"timed race {race_no} receipt uniqueness")
        by_idem = {receipt["idempotency_key"]: receipt for receipt in race_receipts}
        for payload, result in winners + losers:
            receipt = by_idem.get(payload["p_idempotency_key"])
            response = result["response"]
            if not receipt or receipt["actor_id"] != actor_id or receipt["receipt_id"] != response.get("receipt_id") or receipt["request_sha256"] != response.get("request_sha256"):
                raise RuntimeError(f"timed race {race_no} receipt binding")
            if response.get("protected_state") != protected or response.get("notification_delta") != 0:
                raise RuntimeError(f"timed race {race_no} response containment")
        winner_revisions = winners[0][1]["response"]["revisions"]
        loser_revisions = losers[0][1]["response"]["revisions"]
        if winner_revisions["pdc_email"]["delta"] != 1 or loser_revisions["pdc_email"]["delta"] != 0:
            raise RuntimeError(f"timed race {race_no} revision winner/loser delta")
        if any(block["delta"] != 0 for revisions in (winner_revisions, loser_revisions) for name, block in revisions.items() if name != "pdc_email"):
            raise RuntimeError(f"timed race {race_no} unrelated revision delta")
        races.append({
            "race_no": race_no, "expected_version": expected_version, "version_after": after["vehicle"]["version"],
            "client_request_windows_overlap_ns": overlap_ns,
            "requests": [{"side": result["side"], "start_ns": result["start_ns"], "end_ns": result["end_ns"], "http_status": result["status"], "response": result["response"]} for result in results],
            "winner": {"idempotency_key": winners[0][0]["p_idempotency_key"], "tag": winners[0][0]["p_pmb_key_tag"], "receipt_id": winners[0][1]["response"]["receipt_id"]},
            "loser": {"idempotency_key": losers[0][0]["p_idempotency_key"], "error": "vehicle_version_conflict", "receipt_id": losers[0][1]["response"]["receipt_id"]},
            "receipt_delta": 2, "audit_delta": 1, "pdc_revision_delta": 1,
            "protected_unchanged": True, "siblings_unchanged": True, "unrelated_target_relations_unchanged": True,
        })

    final_fleet = read()
    final = read(vehicle_id)["vehicles"][0]
    final_environment = prove_environment()
    all_keys = [(receipt["actor_id"], receipt["idempotency_key"]) for receipt in final["receipts"]]
    if len(all_keys) != len(set(all_keys)) or final_fleet["protected_state"] != protected or final_fleet["notification_count"] != 0:
        raise RuntimeError("final duplicate/containment")
    evidence = {
        "schema": "pdc-overnight-concurrency-017-timed-races-v1", "project_ref": REF, "run_id": RUN,
        "actor_id": actor_id, "isolated_authenticated_sessions": 2, "live_contract": live_contract,
        "initial_environment": initial_environment, "final_environment": final_environment,
        "protected_state": protected, "races": races, "timed_competing_mutation_races": 2,
        "lost_updates": 0, "duplicate_semantic_receipts": 0, "notifications": 0,
        "final_vehicle": final["vehicle"], "final_receipt_count": len(final["receipts"]),
        "harness_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    OUT.write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "status": "SCENARIO_017_TIMED_MUTATION_RACES_VERIFIED", "races": 2,
        "overlapping_mutation_windows": 2, "version_after": final["vehicle"]["version"],
        "lost_updates": 0, "duplicate_semantic_receipts": 0, "notifications": 0,
        "evidence": str(OUT.resolve()),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
