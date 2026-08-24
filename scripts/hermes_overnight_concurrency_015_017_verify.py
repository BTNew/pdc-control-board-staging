"""Independently bind and verify the committed 015-017 concurrency acceptance."""
from __future__ import annotations

import concurrent.futures
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
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
ACCEPTANCE_COMMIT = "eceade4"
EXECUTED_HARNESS_SHA256 = "6b2b5d9120b967d28012e7f8f82d90c9030bbb39c0b18c7fd08444193bfb4572"
SOURCE_EVIDENCE_SHA256 = "366a6a75f52d270a946b0e0b86c557005b58a9fefb51cdc3adbc809818c2cd67"
EXPECTED_HEAD = {"version": "20260825110000", "name": "374_overnight_qc_fixture_registry_assignment"}
EXPECTED_APPLY_SHA256 = "bc627c01b4a7f7c812799018894a4f9e52e512a531cea22b40cb658d2e9f3e93"
EXPECTED_EDIT_SHA256 = "c6f99e6c01196524a7ccf5c43d79cd26faab07920cf2b4901cff294bb50187ab"
SOURCE_EVIDENCE = ROOT / "_staging_deployment_receipts" / "20260824_overnight_concurrency_015_017.json"
OUT = ROOT / "_staging_deployment_receipts" / "20260824_overnight_concurrency_015_017_verification.json"
ACTIVE_SOURCE = ROOT / "supabase" / "staging_only" / "20260825050000_368_overnight_registry_row_assignment.sql"
STATE_KEYS = (
    "vehicle", "work_items", "bookings", "booking_assignments", "booking_history",
    "parts_overrides", "parts", "sublets", "movements", "audit_events", "sublet_history",
)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest(value: object) -> str:
    return sha256_bytes(json.dumps(value, sort_keys=True, separators=(",", ":"), default=str).encode())


def main() -> None:
    if STAGING_REF != REF:
        raise RuntimeError("management target guard")
    environment = env_values()
    base = environment["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if (
        environment.get("PDC_STAGING_PROJECT_REF") != REF
        or parsed.scheme != "https" or parsed.hostname != f"{REF}.supabase.co"
        or parsed.username is not None or parsed.password is not None or parsed.port is not None
        or parsed.path not in ("", "/") or parsed.query or parsed.fragment
    ):
        raise RuntimeError("exact staging REST target guard")
    key = environment["PDC_STAGING_ANON_KEY"]
    initial_environment = prove_environment()
    if initial_environment["database"]["migration_head"] != EXPECTED_HEAD:
        raise RuntimeError("migration head drift")

    committed_harness = subprocess.check_output(
        ["git", "show", f"{ACCEPTANCE_COMMIT}:scripts/hermes_overnight_concurrency_015_017.py"], cwd=ROOT
    )
    if sha256_bytes(committed_harness) != EXECUTED_HARNESS_SHA256:
        raise RuntimeError("executed harness/commit binding mismatch")
    committed_evidence = subprocess.check_output(
        ["git", "show", f"{ACCEPTANCE_COMMIT}:_staging_deployment_receipts/20260824_overnight_concurrency_015_017.json"], cwd=ROOT
    )
    if sha256_bytes(committed_evidence) != SOURCE_EVIDENCE_SHA256:
        raise RuntimeError("committed source-evidence binding mismatch")
    source_evidence = json.loads(committed_evidence)
    if source_evidence.get("schema") != "pdc-overnight-concurrency-015-017-v1" or source_evidence.get("project_ref") != REF:
        raise RuntimeError("source evidence identity")

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
        raise RuntimeError("exact live contract mismatch")

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
        raise RuntimeError("isolated session contract")
    actor_id = sessions[0]["user"]["id"]

    def rpc(session: dict, name: str, payload: dict) -> tuple[int, dict]:
        headers = {"apikey": key, "Authorization": "Bearer " + session["access_token"], "Content-Type": "application/json"}
        return request_json(base + "/rest/v1/rpc/" + name, "POST", headers, payload)

    def read(vehicle_id: str | None = None) -> dict:
        status, state = rpc(sessions[0], "read_pdc_hermes_test_mutation_state_365", {"p_run_id": RUN, "p_vehicle_id": vehicle_id})
        if status != 200 or state.get("ok") is not True or state.get("notification_count") != 0:
            raise RuntimeError("authoritative state read")
        return state

    fleet = read()
    protected = fleet["protected_state"]
    sibling_baseline = digest({str(row["scenario_no"]): row for row in fleet["vehicles"] if row["scenario_no"] not in (15, 16, 17)})
    rows = {row["scenario_no"]: row for row in fleet["vehicles"] if row["scenario_no"] in (15, 16, 17)}
    if set(rows) != {15, 16, 17}:
        raise RuntimeError("scenario inventory")
    for no, row in rows.items():
        if row["vehicle"]["stock_number"] != f"HERMES-TEST-{no:03d}":
            raise RuntimeError("scenario identity")

    receipts = [receipt for no in (15, 16, 17) for receipt in rows[no]["receipts"]]
    receipt_ids = [receipt["receipt_id"] for receipt in receipts]
    semantic_keys = [(receipt["actor_id"], receipt["idempotency_key"]) for receipt in receipts]
    if len(receipts) < 6 or len(receipt_ids) != len(set(receipt_ids)) or len(semantic_keys) != len(set(semantic_keys)):
        raise RuntimeError("receipt uniqueness/inventory")
    if any(receipt["actor_id"] != actor_id or receipt["action"] != "vehicle_edit" for receipt in receipts):
        raise RuntimeError("receipt actor/action binding")

    actions = source_evidence["actions"]
    duplicate = next(action for action in actions if action["kind"] == "duplicate_submit")
    stale = next(action for action in actions if action["kind"] == "stale_expected_version")
    races = sorted((action for action in actions if action["kind"] == "same_record_race"), key=lambda action: action["race_no"])
    if len(races) != 2:
        raise RuntimeError("exact race inventory")
    receipt_by_idem = {receipt["idempotency_key"]: receipt for receipt in receipts}
    if duplicate["idempotency_key"] not in receipt_by_idem or stale["idempotency_key"] not in receipt_by_idem:
        raise RuntimeError("015/016 receipt binding")
    if receipt_by_idem[duplicate["idempotency_key"]]["response"].get("ok") is not True:
        raise RuntimeError("015 stored Apply result")
    if (receipt_by_idem[stale["idempotency_key"]]["response"].get("result") or {}).get("error") != "vehicle_version_conflict":
        raise RuntimeError("016 stored stale result")

    # Independently repeat the same-key changed-payload rejection and bind full target no-change.
    before15 = read(rows[15]["vehicle"]["id"])["vehicles"][0]
    changed15 = {
        "p_run_id": RUN, "p_vehicle_id": rows[15]["vehicle"]["id"], "p_expected_version": 1,
        "p_idempotency_key": duplicate["idempotency_key"], "p_pmb_key_tag": "HERMES-TEST-015-CHANGED-PAYLOAD",
    }
    prove_environment()
    changed_status, changed_response = rpc(sessions[0], "pdc_hermes_test_vehicle_edit_365", changed15)
    after15 = read(rows[15]["vehicle"]["id"])["vehicles"][0]
    if changed_status < 400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(changed_response) or digest(after15) != digest(before15):
        raise RuntimeError("015 independently repeated changed-payload no-change")

    # Replaying the stale rejection must change none of the target's authoritative relations or receipts.
    def state_digest(row: dict) -> str:
        return digest({name: row.get(name) for name in STATE_KEYS} | {"receipts": row.get("receipts")})

    before16 = rows[16]
    stale_payload = {
        "p_run_id": RUN, "p_vehicle_id": before16["vehicle"]["id"],
        "p_expected_version": int(before16["vehicle"]["version"]) + 7,
        "p_idempotency_key": stale["idempotency_key"], "p_pmb_key_tag": "HERMES-TEST-016-STALE-MUST-NOT-WRITE",
    }
    prove_environment()
    stale_status, stale_replay = rpc(sessions[0], "pdc_hermes_test_vehicle_edit_365", stale_payload)
    after16 = read(before16["vehicle"]["id"])["vehicles"][0]
    if stale_status != 200 or stale_replay.get("replay") is not True or state_digest(after16) != state_digest(before16):
        raise RuntimeError("016 full-target replay stability")

    # Re-dispatch each immutable race pair concurrently. The barrier and overlapping client request
    # intervals prove concurrent isolated-session dispatch; stored receipts preserve the original winner/loser truth.
    timing_evidence: list[dict] = []
    for race in races:
        race_no = race["race_no"]
        expected = race["expected_version"]
        payloads = []
        for side in ("a", "b"):
            payloads.append({
                "p_run_id": RUN, "p_vehicle_id": rows[17]["vehicle"]["id"], "p_expected_version": expected,
                "p_idempotency_key": str(uuid.uuid5(NS, f"{RUN}:017-race-{race_no}-{side}")),
                "p_pmb_key_tag": f"HERMES-TEST-017-RACE-{race_no}-{side.upper()}",
            })
        barrier = threading.Barrier(2)

        def replay_worker(index: int) -> dict:
            prove_environment()
            barrier.wait(timeout=240)
            start_ns = time.perf_counter_ns()
            status, response = rpc(sessions[index], "pdc_hermes_test_vehicle_edit_365", payloads[index])
            end_ns = time.perf_counter_ns()
            return {"side": index, "start_ns": start_ns, "end_ns": end_ns, "status": status, "response": response}

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            replay_results = [future.result(timeout=300) for future in [pool.submit(replay_worker, 0), pool.submit(replay_worker, 1)]]
        if any(result["status"] != 200 or result["response"].get("replay") is not True for result in replay_results):
            raise RuntimeError(f"race {race_no} concurrent immutable replay")
        overlap_ns = min(result["end_ns"] for result in replay_results) - max(result["start_ns"] for result in replay_results)
        if overlap_ns <= 0:
            raise RuntimeError(f"race {race_no} client dispatch windows did not overlap")
        timing_evidence.append({
            "race_no": race_no, "client_request_windows_overlap_ns": overlap_ns,
            "requests": [{"side": result["side"], "start_ns": result["start_ns"], "end_ns": result["end_ns"], "receipt_id": result["response"]["receipt_id"]} for result in replay_results],
        })

    for race in races:
        winner_receipt = receipt_by_idem.get(race["winner"]["idempotency_key"])
        loser_receipt = receipt_by_idem.get(race["loser"]["idempotency_key"])
        if not winner_receipt or not loser_receipt:
            raise RuntimeError("017 receipt inventory")
        if winner_receipt["response"].get("ok") is not True or (loser_receipt["response"].get("result") or {}).get("error") != "vehicle_version_conflict":
            raise RuntimeError("017 stored winner/loser truth")
        if winner_receipt["receipt_id"] != race["winner"]["receipt_id"] or loser_receipt["receipt_id"] != race["loser"]["receipt_id"]:
            raise RuntimeError("017 evidence/receipt binding")
    final_original_winner = receipt_by_idem[races[-1]["winner"]["idempotency_key"]]["response"]
    final_original_vehicle = (final_original_winner.get("result") or {}).get("vehicle") or {}
    if final_original_winner.get("vehicle_version_after") != 3 or final_original_vehicle.get("pmb_key_tag") != races[-1]["winner"]["tag"]:
        raise RuntimeError("017 immutable original winner/no-lost-update state")

    final_fleet = read()
    final_environment = prove_environment()
    sibling_final = digest({str(row["scenario_no"]): row for row in final_fleet["vehicles"] if row["scenario_no"] not in (15, 16, 17)})
    if final_fleet["protected_state"] != protected or final_fleet["notification_count"] != 0 or sibling_final != sibling_baseline:
        raise RuntimeError("final containment")
    verifier_sha = sha256_bytes(pathlib.Path(__file__).read_bytes())
    evidence = {
        "schema": "pdc-overnight-concurrency-015-017-verification-v1", "project_ref": REF, "run_id": RUN,
        "acceptance_commit": subprocess.check_output(["git", "rev-parse", ACCEPTANCE_COMMIT], cwd=ROOT, text=True).strip(),
        "executed_harness_sha256": EXECUTED_HARNESS_SHA256,
        "source_evidence_sha256": SOURCE_EVIDENCE_SHA256,
        "verifier_sha256": verifier_sha, "active_source_sha256": sha256_bytes(ACTIVE_SOURCE.read_bytes()),
        "live_contract": live_contract, "initial_environment": initial_environment, "final_environment": final_environment,
        "isolated_authenticated_sessions": 2, "actor_id": actor_id, "receipt_count": len(receipts),
        "unique_receipt_ids": len(set(receipt_ids)), "unique_actor_idempotency_pairs": len(set(semantic_keys)),
        "duplicate_submit_apply_replay_bound": True, "same_key_changed_payload_rejected": True,
        "stale_rejection_full_target_replay_stable": True, "same_record_races": 2,
        "race_timing": timing_evidence, "stored_winner_loser_receipts_bound": True,
        "authoritative_winner_state_bound": True, "lost_updates": 0, "duplicate_semantic_receipts": 0,
        "protected_state": protected, "synthetic_siblings_unchanged": True, "notifications": 0,
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    OUT.write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "status": "CONCURRENCY_015_017_INDEPENDENTLY_VERIFIED", "acceptance_commit": evidence["acceptance_commit"],
        "same_record_races": 2, "overlapping_dispatch_windows": len(timing_evidence),
        "receipt_count": len(receipts), "duplicate_semantic_receipts": 0, "lost_updates": 0,
        "notifications": 0, "evidence": str(OUT.resolve()),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
