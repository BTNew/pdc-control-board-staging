"""Verify scenario 018 role, permission, idempotency and target isolation."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import urllib.parse
import uuid

from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json
from pdc_staging_management_migration import STAGING_REF, _post

ROOT = pathlib.Path(__file__).resolve().parents[1]
REF = "cdsmnqxtyyoeoznmbidd"
RUN = "HERMES-TEST-RUN-20260824"
NS = uuid.UUID("36500000-0000-5000-8000-000000000365")
OUT = ROOT / "_staging_deployment_receipts" / "20260824_overnight_roles_018.json"
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
    parsed = urllib.parse.urlsplit(base)
    if (
        STAGING_REF != REF or environment.get("PDC_STAGING_PROJECT_REF") != REF
        or parsed.scheme != "https" or parsed.hostname != f"{REF}.supabase.co"
        or parsed.username is not None or parsed.password is not None or parsed.port is not None
        or parsed.path not in ("", "/") or parsed.query or parsed.fragment
    ):
        raise RuntimeError("exact staging target guard")
    initial_environment = prove_environment()
    expected_head = {"version": "20260825110000", "name": "374_overnight_qc_fixture_registry_assignment"}
    if initial_environment["database"]["migration_head"] != expected_head:
        raise RuntimeError("migration head drift")

    def authenticate(email_key: str, password_key: str, label: str) -> dict:
        status, session = request_json(
            base + "/auth/v1/token?grant_type=password", "POST",
            {"apikey": key, "Content-Type": "application/json"},
            {"email": environment[email_key], "password": environment[password_key]},
        )
        if status != 200 or not session.get("access_token") or not (session.get("user") or {}).get("id"):
            raise RuntimeError(f"{label} staging authentication failed")
        return session

    admin = authenticate("PDC_STAGING_ADMIN2_EMAIL", "PDC_STAGING_ADMIN2_PASSWORD", "administrator")
    operator = authenticate("PDC_STAGING_CONTROLLER_A_EMAIL", "PDC_STAGING_CONTROLLER_A_PASSWORD", "operator")
    unapproved = authenticate("PDC_STAGING_UNAPPROVED_EMAIL", "PDC_STAGING_UNAPPROVED_PASSWORD", "unapproved")
    actor_ids = {admin["user"]["id"], operator["user"]["id"], unapproved["user"]["id"]}
    token_digests = {digest(x["access_token"]) for x in (admin, operator, unapproved)}
    if len(actor_ids) != 3 or len(token_digests) != 3:
        raise RuntimeError("isolated role-session identity contract")

    def authoritative_role(session: dict) -> dict:
        actor_id = str(uuid.UUID(session["user"]["id"]))
        actor_email_hash = hashlib.sha256(session["user"]["email"].strip().lower().encode()).hexdigest()
        sql = f"""SET TRANSACTION READ ONLY;
select r.role::text, coalesce(r.active,false) active, r.account_status::text,
       case when r.auth_user_id='{actor_id}'::uuid then 'auth_user_id'
            when r.email is not null then 'canonical_email' else 'auth_user_without_pdc_role' end identity_binding
from auth.users u
left join public.pdc_user_roles r on lower(r.email)=lower(u.email)
where u.id='{actor_id}'::uuid
  and encode(extensions.digest(convert_to(lower(u.email),'UTF8'),'sha256'),'hex')='{actor_email_hash}';"""
        rows = _post(f"https://api.supabase.com/v1/projects/{REF}/database/query/read-only", sql)
        if len(rows) != 1:
            raise RuntimeError("authoritative actor-role readback")
        row = rows[0]
        return {"role": row.get("role"), "active": row["active"], "account_status": row.get("account_status") or "unapproved_no_pdc_role", "identity_binding": row["identity_binding"]}

    role_rows = {
        "administrator": authoritative_role(admin),
        "operator": authoritative_role(operator),
        "authenticated-unapproved": authoritative_role(unapproved),
    }
    if {k: role_rows["administrator"][k] for k in ("role", "active", "account_status")} != {"role": "administrator", "active": True, "account_status": "approved"}:
        raise RuntimeError("Administrator role identity drift")
    if {k: role_rows["operator"][k] for k in ("role", "active", "account_status")} != {"role": "operator", "active": True, "account_status": "approved"}:
        raise RuntimeError("Operator role identity drift")
    if role_rows["authenticated-unapproved"] not in (
        {"role": None, "active": False, "account_status": "unapproved_no_pdc_role", "identity_binding": "auth_user_without_pdc_role"},
        {"role": "viewer", "active": False, "account_status": "unapproved", "identity_binding": "auth_user_id"},
    ):
        raise RuntimeError("authenticated-unapproved identity drift")

    viewer_status, viewer_response = request_json(
        base + "/auth/v1/token?grant_type=password", "POST",
        {"apikey": key, "Content-Type": "application/json"},
        {"email": environment["PDC_STAGING_VIEWER_EMAIL"], "password": environment["PDC_STAGING_VIEWER_PASSWORD"]},
    )
    if viewer_status < 400 or viewer_response.get("user") or viewer_response.get("access_token"):
        raise RuntimeError("configured Viewer credential unexpectedly authenticated")
    viewer_email_hash = hashlib.sha256(environment["PDC_STAGING_VIEWER_EMAIL"].strip().lower().encode()).hexdigest()
    viewer_role_sql = f"""SET TRANSACTION READ ONLY;
select role::text, active, account_status::text
from public.pdc_user_roles
where encode(extensions.digest(convert_to(lower(email),'UTF8'),'sha256'),'hex')='{viewer_email_hash}';"""
    viewer_role_rows = _post(f"https://api.supabase.com/v1/projects/{REF}/database/query/read-only", viewer_role_sql)
    if viewer_role_rows != [{"role": "viewer", "active": True, "account_status": "approved"}]:
        raise RuntimeError("configured Viewer authoritative role identity drift")

    def rpc(session: dict, name: str, payload: dict) -> tuple[int, dict]:
        headers = {"apikey": key, "Authorization": "Bearer " + session["access_token"], "Content-Type": "application/json"}
        return request_json(base + "/rest/v1/rpc/" + name, "POST", headers, payload)

    def read(session: dict, vehicle_id: str | None = None, must_succeed: bool = True) -> tuple[int, dict]:
        status, state = rpc(session, "read_pdc_hermes_test_mutation_state_365", {"p_run_id": RUN, "p_vehicle_id": vehicle_id})
        if must_succeed and (status != 200 or state.get("ok") is not True or state.get("notification_count") != 0):
            raise RuntimeError(f"authoritative read failed {status} {json.dumps(state)[:800]}")
        return status, state

    _, admin_fleet = read(admin)
    _, operator_fleet = read(operator)
    if digest(admin_fleet) != digest(operator_fleet):
        raise RuntimeError("Administrator/Operator read projection mismatch")
    protected = admin_fleet["protected_state"]
    row18 = next((row for row in admin_fleet["vehicles"] if row["scenario_no"] == 18), None)
    row5 = next((row for row in admin_fleet["vehicles"] if row["scenario_no"] == 5), None)
    if not row18 or not row5 or row18["vehicle"]["stock_number"] != "HERMES-TEST-018":
        raise RuntimeError("scenario inventory")
    if not row18["vehicle"]["customer_name"].startswith("HERMES-TEST"):
        raise RuntimeError("scenario 018 static identity")
    vehicle_id = row18["vehicle"]["id"]

    unapproved_read_status, unapproved_read_response = read(unapproved, vehicle_id, must_succeed=False)
    if unapproved_read_status < 400 or "PDC_365_READ_UNAUTHORIZED_OR_RUN_INVALID" not in json.dumps(unapproved_read_response):
        raise RuntimeError("authenticated-unapproved read did not fail closed")

    def state_digest(row: dict) -> str:
        return digest({name: row.get(name) for name in STATE_KEYS})

    def current() -> dict:
        _, state = read(admin, vehicle_id)
        if state["protected_state"] != protected or len(state["vehicles"]) != 1:
            raise RuntimeError("scenario 018 containment")
        return state["vehicles"][0]

    def full_fleet() -> dict:
        _, state = read(admin)
        if state["protected_state"] != protected or state["notification_count"] != 0:
            raise RuntimeError("fleet containment")
        return state

    def sibling_digest(state: dict) -> str:
        return digest({str(row["scenario_no"]): state_digest(row) for row in state["vehicles"] if row["scenario_no"] != 18})

    checks: list[dict] = [
        {"role": "administrator", "authenticated": True, "read_allowed": True, "authoritative_role": role_rows["administrator"]},
        {"role": "operator", "authenticated": True, "read_allowed": True, "authoritative_role": role_rows["operator"]},
        {"role": "authenticated-unapproved", "authenticated": True, "read_allowed": False, "http_status": unapproved_read_status, "authoritative_role": role_rows["authenticated-unapproved"]},
        {"role": "viewer", "authenticated": False, "read_attempted": False, "http_status": viewer_status, "error": viewer_response.get("error_code") or viewer_response.get("msg"), "authoritative_role": viewer_role_rows[0]},
    ]

    # Unapproved identity has function EXECUTE exposure but no internal write authority.
    before = current(); fleet_before = full_fleet()
    denied_payload = {
        "p_run_id": RUN, "p_vehicle_id": vehicle_id,
        "p_expected_version": int(before["vehicle"]["version"]),
        "p_idempotency_key": str(uuid.uuid5(NS, f"{RUN}:018-unapproved-write")),
        "p_pmb_key_tag": "HERMES-TEST-018-UNAPPROVED-MUST-NOT-WRITE",
    }
    prove_environment()
    denied_status, denied_response = rpc(unapproved, "pdc_hermes_test_vehicle_edit_365", denied_payload)
    after = current(); fleet_after = full_fleet()
    if denied_status < 400 or "PDC_365_UNAUTHORIZED" not in json.dumps(denied_response):
        raise RuntimeError("unapproved write boundary")
    if digest(after) != digest(before) or sibling_digest(fleet_after) != sibling_digest(fleet_before):
        raise RuntimeError("unapproved write changed authoritative state")
    checks.append({"role": "authenticated-unapproved", "write_allowed": False, "http_status": denied_status, "error": "PDC_365_UNAUTHORIZED", "authoritative_no_change": True})

    shared_key = str(uuid.uuid5(NS, f"{RUN}:018-cross-role-shared-key"))
    actor_actions: list[dict] = []

    def apply_and_replay(session: dict, role: str, tag: str) -> tuple[dict, dict]:
        before_row = current(); fleet0 = full_fleet()
        existing = next((r for r in before_row["receipts"] if r.get("actor_id") == session["user"]["id"] and r.get("idempotency_key") == shared_key), None)
        stored = (existing or {}).get("response") or {}
        expected_version = int(stored.get("vehicle_version_before", before_row["vehicle"]["version"]))
        if existing and (existing.get("request_payload") or {}).get("pmb_key_tag") != tag:
            raise RuntimeError(f"{role} interrupted receipt payload drift")
        payload = {
            "p_run_id": RUN, "p_vehicle_id": vehicle_id,
            "p_expected_version": expected_version,
            "p_idempotency_key": shared_key, "p_pmb_key_tag": tag,
        }
        prove_environment()
        status, response = rpc(session, "pdc_hermes_test_vehicle_edit_365", payload)
        after_row = current(); fleet1 = full_fleet()
        if status != 200 or response.get("ok") is not True or response.get("replay") is not bool(existing):
            raise RuntimeError(f"{role} Apply/recovery {status} {json.dumps(response)[:1000]}")
        if not existing and (int(after_row["vehicle"]["version"]) != int(before_row["vehicle"]["version"]) + 1 or after_row["vehicle"].get("pmb_key_tag") != tag):
            raise RuntimeError(f"{role} authoritative Apply state")
        if existing and digest(after_row) != digest(before_row):
            raise RuntimeError(f"{role} interrupted replay changed state")
        if sibling_digest(fleet1) != sibling_digest(fleet0) or fleet1["protected_state"] != protected:
            raise RuntimeError(f"{role} Apply containment")
        matches = [r for r in after_row["receipts"] if r.get("actor_id") == session["user"]["id"] and r.get("idempotency_key") == shared_key]
        if len(matches) != 1 or matches[0]["receipt_id"] != response.get("receipt_id") or matches[0]["request_sha256"] != response.get("request_sha256"):
            raise RuntimeError(f"{role} receipt binding")
        prove_environment()
        replay_status, replay = rpc(session, "pdc_hermes_test_vehicle_edit_365", payload)
        replay_row = current()
        if replay_status != 200 or replay.get("replay") is not True or replay.get("replay_containment_verified") is not True or digest(replay_row) != digest(after_row):
            raise RuntimeError(f"{role} exact replay")
        changed = dict(payload); changed["p_pmb_key_tag"] = tag + "-CHANGED"
        prove_environment()
        changed_status, changed_response = rpc(session, "pdc_hermes_test_vehicle_edit_365", changed)
        if changed_status < 400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(changed_response) or digest(current()) != digest(after_row):
            raise RuntimeError(f"{role} same-key changed-payload no-change")
        actor_actions.append({
            "role": role, "actor_id": session["user"]["id"], "idempotency_key": shared_key,
            "receipt_id": response["receipt_id"], "request_sha256": response["request_sha256"],
            "version_before": stored.get("vehicle_version_before", before_row["vehicle"]["version"]),
            "version_after": stored.get("vehicle_version_after", after_row["vehicle"]["version"]),
            "tag": tag, "exact_replay": True, "changed_payload_rejected": True,
            "recovered_from_prior_receipt": bool(existing),
        })
        return after_row, payload

    admin_after, _ = apply_and_replay(admin, "administrator", "HERMES-TEST-018-ADMIN")
    operator_after, _ = apply_and_replay(operator, "operator", "HERMES-TEST-018-OPERATOR")
    if operator_after["vehicle"].get("pmb_key_tag") != "HERMES-TEST-018-OPERATOR":
        raise RuntimeError("cross-role final version delta")
    shared_receipts = [r for r in operator_after["receipts"] if r.get("idempotency_key") == shared_key]
    if len(shared_receipts) != 2 or {r["actor_id"] for r in shared_receipts} != {admin["user"]["id"], operator["user"]["id"]} or len({r["receipt_id"] for r in shared_receipts}) != 2:
        raise RuntimeError("actor-scoped shared-key receipt isolation")
    applied_baseline_version = min(int((r.get("response") or {}).get("vehicle_version_before")) for r in shared_receipts)
    if int(operator_after["vehicle"]["version"]) != applied_baseline_version + 2:
        raise RuntimeError("cross-role final version delta")

    # Actual protected-row rejection, selected read-only from the exact staging project.
    protected_query = """SET TRANSACTION READ ONLY;
select id::text, stock_number from public.vehicles
where stock_number not like 'HERMES-TEST%' and not exists (
 select 1 from public.pdc_overnight_synthetic_fleet_registry_363 r where r.vehicle_id=vehicles.id
) order by id limit 1;"""
    protected_rows = _post(f"https://api.supabase.com/v1/projects/{REF}/database/query/read-only", protected_query)
    if len(protected_rows) != 1 or str(protected_rows[0].get("stock_number", "")).startswith("HERMES-TEST"):
        raise RuntimeError("protected-row inventory")
    protected_vehicle_id = protected_rows[0]["id"]
    for role, session in (("administrator", admin), ("operator", operator)):
        before_row = current(); fleet0 = full_fleet()
        payload = {
            "p_run_id": RUN, "p_vehicle_id": protected_vehicle_id,
            "p_expected_version": 1,
            "p_idempotency_key": str(uuid.uuid5(NS, f"{RUN}:018-{role}-protected")),
            "p_pmb_key_tag": "HERMES-TEST-018-PROTECTED-MUST-NOT-WRITE",
        }
        prove_environment()
        status, response = rpc(session, "pdc_hermes_test_vehicle_edit_365", payload)
        fleet1 = full_fleet()
        if status < 400 or "PDC_365_REGISTRY_SCOPE_OR_VERSION_MISMATCH" not in json.dumps(response):
            raise RuntimeError(f"{role} protected-row rejection")
        if digest(current()) != digest(before_row) or sibling_digest(fleet1) != sibling_digest(fleet0) or fleet1["protected_state"] != protected:
            raise RuntimeError(f"{role} protected-row probe changed state")
        checks.append({"role": role, "protected_row_write_allowed": False, "http_status": status, "authoritative_no_change": True})

    # Present a real scenario-005 booking as though it belonged to scenario 018.
    booking = (row5.get("bookings") or [None])[0]
    if not booking or not booking.get("id") or booking.get("vehicle_id") != row5["vehicle"]["id"]:
        raise RuntimeError("cross-vehicle booking inventory")
    before18 = current(); fleet0 = full_fleet()
    cross_payload = {
        "p_run_id": RUN, "p_vehicle_id": vehicle_id,
        "p_expected_vehicle_version": int(before18["vehicle"]["version"]),
        "p_booking_id": booking["id"], "p_expected_booking_version": int(booking["version"]),
        "p_idempotency_key": str(uuid.uuid5(NS, f"{RUN}:018-cross-vehicle-booking")),
        "p_action": "resume", "p_payload": {},
    }
    prove_environment()
    cross_status, cross_response = rpc(admin, "pdc_hermes_test_booking_365", cross_payload)
    fleet1 = full_fleet()
    if cross_status < 400 or "PDC_365_SUBJECT_OUTSIDE_REGISTRY_VEHICLE" not in json.dumps(cross_response):
        raise RuntimeError(f"cross-vehicle subject boundary {cross_status} {json.dumps(cross_response)[:1000]}")
    if digest(current()) != digest(before18) or sibling_digest(fleet1) != sibling_digest(fleet0) or fleet1["protected_state"] != protected:
        raise RuntimeError("cross-vehicle subject probe changed state")
    checks.append({"role": "administrator", "cross_vehicle_subject_allowed": False, "http_status": cross_status, "authoritative_no_change": True})

    final_fleet = full_fleet(); final_row = current(); final_environment = prove_environment()
    receipts = final_row["receipts"]
    receipt_ids = [r["receipt_id"] for r in receipts]
    semantic_keys = [(r["actor_id"], r["idempotency_key"]) for r in receipts]
    if len(receipt_ids) != len(set(receipt_ids)) or len(semantic_keys) != len(set(semantic_keys)):
        raise RuntimeError("receipt uniqueness")
    if final_row["vehicle"].get("pmb_key_tag") != "HERMES-TEST-018-OPERATOR" or final_fleet["notification_count"] != 0:
        raise RuntimeError("final scenario 018 state")

    harness_bytes = pathlib.Path(__file__).read_bytes()
    harness_sha256 = hashlib.sha256(harness_bytes).hexdigest()
    git_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    committed_harness = subprocess.check_output(["git", "show", "HEAD:scripts/hermes_overnight_roles_018.py"], cwd=ROOT)
    if hashlib.sha256(committed_harness).hexdigest() != harness_sha256:
        raise RuntimeError("executed harness is not bound to repository HEAD")
    live_contract_sql = """SET TRANSACTION READ ONLY;
select jsonb_build_object(
 'edit_365_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_hermes_test_vehicle_edit_365(text,uuid,integer,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
 'read_365_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.read_pdc_hermes_test_mutation_state_365(text,uuid)'::regprocedure),'UTF8'),'sha256'),'hex'),
 'booking_365_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_hermes_test_booking_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
) evidence;"""
    live_contract = _post(f"https://api.supabase.com/v1/projects/{REF}/database/query/read-only", live_contract_sql)[0]["evidence"]
    if live_contract.get("edit_365_sha256") != "c6f99e6c01196524a7ccf5c43d79cd26faab07920cf2b4901cff294bb50187ab":
        raise RuntimeError("live edit contract drift")

    evidence = {
        "schema": "pdc-overnight-roles-018-v1", "project_ref": REF, "run_id": RUN,
        "scenario_no": 18, "stock": "HERMES-TEST-018", "vehicle_id": vehicle_id,
        "git_head": git_head, "harness_sha256": harness_sha256, "live_contract": live_contract,
        "initial_environment": initial_environment, "final_environment": final_environment,
        "distinct_authenticated_actor_ids": 3, "distinct_token_digests": 3,
        "role_checks": checks, "actor_scoped_actions": actor_actions,
        "shared_idempotency_key": shared_key, "shared_key_receipt_count": len(shared_receipts),
        "unique_shared_key_actors": len({r["actor_id"] for r in shared_receipts}),
        "protected_vehicle_id_sha256": digest(protected_vehicle_id), "protected_state": protected,
        "cross_vehicle_booking_id_sha256": digest(booking["id"]),
        "final_version": final_row["vehicle"]["version"], "final_tag": final_row["vehicle"].get("pmb_key_tag"),
        "receipt_count": len(receipts), "unique_receipt_ids": len(set(receipt_ids)),
        "unique_actor_idempotency_pairs": len(set(semantic_keys)),
        "sibling_state_unchanged": True, "protected_state_unchanged": True, "notifications": 0,
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "status": "ROLES_018_VERIFIED", "authenticated_roles": 3,
        "viewer_fail_closed": True, "admin_operator_reads": True, "unapproved_read_write_rejected": True,
        "actor_scoped_shared_key_receipts": 2, "exact_replays": 2, "changed_payload_rejections": 2,
        "protected_write_rejections": 2, "cross_vehicle_rejections": 1,
        "final_version": evidence["final_version"], "notifications": 0, "evidence": str(OUT.resolve()),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
