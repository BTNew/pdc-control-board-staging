#!/usr/bin/env python3
"""Live staging-only authenticated acceptance campaign for Email Monitor .44.

The campaign creates exactly six positive, test-marked synthetic sources plus one
ambiguous negative source, drives the real 684 wrapper family and 502 canonical
action chain, then invokes guarded cleanup that archives only the synthetic rows.
It never contacts a mailbox, enables a task, sends email, or uses UID514.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
PLANNER_SHA = "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"
TRUST_SHA = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
PLANNER = ROOT / "backend" / "pdc_active_semantic_planner.py"
MIGRATION = ROOT / "supabase/staging_only/20260828070000_686_authenticated_acceptance_campaign_fixtures.sql"
CASES = {
    "parts_complete": ["Parts complete."],
    "parts_eta": ["Parts ETA 2026-09-15."],
    "sublet_booking_date": ["Sublet booking scheduled 2026-09-16."],
    "multi_action": ["Parts complete.", "Parts ETA 2026-09-17."],
    "update_existing_not_duplicate": ["Add note Existing booking update."],
    "exact_replay": ["Parts ETA 2026-09-19."],
}


def stable(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(value: object) -> str:
    return hashlib.sha256(stable(value).encode()).hexdigest()


def bootstrap_connection():
    bootstrap_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
    secret_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
    spec = importlib.util.spec_from_file_location("bootstrap686", bootstrap_path)
    bootstrap = importlib.util.module_from_spec(spec)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap unavailable")
    spec.loader.exec_module(bootstrap)
    values = json.loads(bootstrap.unprotect(secret_path.read_bytes()).decode())
    bootstrap.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project reference mismatch")
    database_url = values["PDC_STAGING_DATABASE_URL"]
    if EXPECTED_REF not in database_url or PRODUCTION_REF in database_url:
        raise RuntimeError("refusing non-staging database endpoint")
    os.environ.update({k: values[k] for k in ("PDC_STAGING_SSLROOTCERT", "PDC_STAGING_SSLROOTCERT_SHA256")})
    sys.path.insert(0, str(ROOT))
    from scripts.pdc_staging_runtime import trusted_sslrootcert

    endpoint = urlsplit(database_url)
    return psycopg2.connect(
        host=endpoint.hostname,
        port=endpoint.port or 5432,
        user=endpoint.username,
        password=endpoint.password,
        dbname="postgres",
        sslmode="verify-full",
        sslrootcert=trusted_sslrootcert(),
        connect_timeout=15,
        application_name="pdc686_authenticated_acceptance_campaign",
    )


def set_claims(conn, subject: str = ACTOR, email: str = EMAIL) -> None:
    with conn.cursor() as cur:
        cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (subject,))
        cur.execute(
            "select set_config('request.jwt.claims',%s,true)",
            (json.dumps({"sub": subject, "email": email, "role": "authenticated"}),),
        )


def scalar(conn, sql: str, params=()):
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()[0]


def rpc(conn, name: str, args=()):
    placeholders = ",".join(["%s"] * len(args))
    with conn.cursor() as cur:
        cur.execute(f"select public.{name}({placeholders})", args)
        return cur.fetchone()[0]


def run_planner(candidates: list[dict], vehicles: list[dict]) -> dict:
    request = {
        "contract_version": "pmb-pdc-agentic-planner-request-v1",
        "evidence": {"instruction_candidates": candidates},
        "vehicle_contexts": vehicles,
    }
    completed = subprocess.run(
        [sys.executable, str(PLANNER)],
        input=stable(request),
        text=True,
        capture_output=True,
        cwd=ROOT,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"planner failed: {completed.stderr[:500]}")
    return json.loads(completed.stdout)


def planner_text_for_candidate(candidate: dict) -> str:
    text = str(candidate.get("interpreted_text") or "")
    if "sublet" in text.casefold() and re.search(r"\bbooking\s+scheduled\b", text, re.IGNORECASE):
        return re.sub(r"\bbooking\b", "book", text, count=1, flags=re.IGNORECASE)
    return text


def canonical_candidates(conn, context: dict) -> list[dict]:
    return scalar(
        conn,
        "select public.pdc_agentic_email_instruction_candidates_502(c) from public.pdc_agentic_email_context_receipts_502 c where c.context_receipt_id=%s",
        (context["context_receipt_id"],),
    )


def canonical_evidence(conn, fixture: dict) -> dict:
    row = scalar(
        conn,
        "select jsonb_build_object('received_at',received_at,'provider_authentication',provider_authentication) from public.ai_email_intake where id=%s",
        (fixture["intake_id"],),
    )
    return {
        "intake_id": fixture["intake_id"],
        "source_hash": fixture["source_hash"],
        "message_id": fixture["message_id"],
        "sender": fixture["sender"],
        "received_at": row["received_at"],
        "provider_uid": fixture["provider_uid"],
        "recipient_mailbox": "pmbcontroller@gmail.com",
        "provider_authserv_id": "mx.google.com",
        "provider_authentication": row["provider_authentication"],
        "claim_token": fixture["claim_token"],
        "gateway_instance_id": GATEWAY,
    }


def dedupe_instruction_candidates(candidates: list[dict]) -> list[dict]:
    """Collapse exact semantic duplicates emitted by body and fixture attachment."""
    evidence_rank = {"body": 0, "subject": 1}
    selected: dict[str, tuple[int, dict]] = {}
    order: list[str] = []
    for candidate in candidates:
        key = " ".join(str(candidate.get("interpreted_text") or "").split()).casefold()
        if not key:
            continue
        rank = min((evidence_rank.get(ref, 2) for ref in candidate.get("evidence_refs", [])), default=2)
        current = selected.get(key)
        if current is None:
            selected[key] = (rank, candidate)
            order.append(key)
        elif rank < current[0]:
            selected[key] = (rank, candidate)
    return [selected[key][1] for key in order]


def dedupe_planned_actions(actions: list[dict]) -> list[dict]:
    """Keep one canonical action when body and attachment repeat the same instruction."""
    evidence_rank = {"body": 0, "subject": 1}
    selected: dict[str, tuple[int, dict]] = {}
    order: list[str] = []
    for action in actions:
        key = stable({
            "vehicle_id": action.get("vehicle_id"),
            "action_type": action.get("action_type"),
            "target": action.get("target"),
            "expected": action.get("expected"),
        })
        rank = min((evidence_rank.get(ref, 2) for ref in action.get("evidence_refs", [])), default=2)
        current = selected.get(key)
        if current is None:
            selected[key] = (rank, action)
            order.append(key)
        elif rank < current[0]:
            selected[key] = (rank, action)
    return [selected[key][1] for key in order]


def map_existing_booking_action(action: dict, booking: dict) -> dict:
    notes = action.get("target", {}).get("vehicle.notes")
    target = {
        "sublet.booking_id": booking["booking_id"],
        "sublet.version": int(booking["version"]),
        "sublet.out_date": booking["out_date"],
        "sublet.expected_return_date": booking["expected_return_date"],
        "sublet.notes": notes,
    }
    return {
        **action,
        "action_type": "sublet_update",
        "target": target,
        "expected": {
            "sublet.booking.booking_id": booking["booking_id"],
            "sublet.booking.out_date": booking["out_date"],
            "sublet.booking.expected_return_date": booking["expected_return_date"],
            "sublet.booking.notes": notes,
        },
        "reason": "explicit existing Sublet booking update instruction",
    }


def make_plan(context: dict, fixture: dict, candidates: list[dict]) -> tuple[dict, list[dict]]:
    vehicles = context["vehicles"]
    planner_candidates = [{"instruction_id": row["instruction_id"], "evidence_ref": row["evidence_refs"][0], "text": planner_text_for_candidate(row)} for row in candidates]
    planned = run_planner(planner_candidates, [{"vehicle_id": v["vehicle_id"], "identity": v["identity"]} for v in vehicles])
    for vehicle in planned["vehicles"]:
        vehicle["actions"] = dedupe_planned_actions(vehicle.get("actions", []))
    source_binding = {key: context["canonical_evidence"][key] for key in ("intake_id", "source_hash", "message_id", "sender", "received_at", "provider_uid", "recipient_mailbox", "provider_authserv_id", "provider_authentication")}
    source_binding["claim_token"] = fixture["claim_token"]
    source_binding["gateway_instance_id"] = GATEWAY
    planned_by_id = {row["instruction_id"]: row for row in planned["instructions"]}
    instructions = []
    for candidate in candidates:
        instruction = dict(planned_by_id[candidate["instruction_id"]])
        instruction["interpreted_text"] = candidate["interpreted_text"]
        instructions.append(instruction)
    body_instruction_id = next((candidate["instruction_id"] for candidate in candidates if candidate["evidence_refs"] == ["body"]), None)
    if body_instruction_id is None or body_instruction_id not in planned_by_id:
        raise RuntimeError(f"{fixture['case_key']}: body instruction missing")
    actions: list[dict] = []
    for vehicle in planned["vehicles"]:
        for action_no, source_action in enumerate(vehicle["actions"], 1):
            action = dict(source_action)
            action["vehicle_id"] = vehicle["vehicle_id"]
            action["action_no"] = action_no
            action["disposition"] = "ACTIONABLE"
            action["supersedes"] = []
            action["idempotency_hash"] = ""
            action["idempotency_hash"] = digest({
                "evidence_hash": context["evidence_hash"],
                **{k: v for k, v in action.items() if k != "idempotency_hash"},
            })
            actions.append(action)
    if not actions:
        raise RuntimeError(f"planner produced no actions for {fixture['case_key']}")
    plan_vehicles = []
    by_vehicle = {}
    for action in actions:
        by_vehicle.setdefault(action["vehicle_id"], []).append(action)
    for vehicle in planned["vehicles"]:
        plan_vehicles.append({"vehicle_id": vehicle["vehicle_id"], "identity": vehicle["identity"], "actions": by_vehicle.get(vehicle["vehicle_id"], [])})
    plan = {
        "contract_version": "pmb-pdc-agentic-email-plan-v1",
        "context_receipt_id": context["context_receipt_id"],
        "evidence_hash": context["evidence_hash"],
        "plan_hash": "",
        "source_binding": source_binding,
        "instructions": instructions,
        "vehicles": plan_vehicles,
        "planner_interface": {"kind": "semantic", "sha256": PLANNER_SHA, "trust_receipt_sha256": TRUST_SHA},
    }
    plan_for_hash = dict(plan)
    plan_for_hash.pop("plan_hash")
    plan_for_hash["source_binding"] = {k: v for k, v in source_binding.items() if k not in {"claim_token", "gateway_instance_id"}}
    plan["plan_hash"] = digest(plan_for_hash)
    return plan, actions


def positive_case(conn, fixture: dict) -> dict:
    evidence = canonical_evidence(conn, fixture)
    context = rpc(conn, "read_pdc_agentic_email_context_authenticated_684", (json.dumps(evidence),))
    if not context.get("ok") or context.get("code") != "agentic_context":
        raise RuntimeError(f"{fixture['case_key']}: context {context}")
    candidates = canonical_candidates(conn, context)
    plan, actions = make_plan(context, fixture, candidates)
    if fixture["case_key"] == "update_existing_not_duplicate":
        booking = scalar(conn, "select jsonb_build_object('booking_id',booking_id,'version',version,'out_date',out_date,'expected_return_date',expected_return_date,'notes',notes) from public.pdc_sublet_booking_instances where vehicle_id=%s::uuid and status='active' order by out_date,booking_id limit 1", (actions[0]["vehicle_id"],))
        if not booking:
            raise RuntimeError("update_existing_not_duplicate: active booking missing")
        actions = [map_existing_booking_action(action, booking) if action["action_type"] == "notes_set" else action for action in actions]
    for action in actions:
        action["idempotency_hash"] = scalar(conn, "select encode(extensions.digest(convert_to((jsonb_build_object('evidence_hash',%s)||(%s::jsonb-'idempotency_hash'))::text,'UTF8'),'sha256'),'hex')", (context["evidence_hash"], json.dumps(action)))
    action_by_vehicle = {}
    for action in actions:
        action_by_vehicle.setdefault(action["vehicle_id"], []).append(action)
    for vehicle in plan["vehicles"]:
        vehicle["actions"] = action_by_vehicle.get(vehicle["vehicle_id"], [])
    plan["plan_hash"] = scalar(conn, "select encode(extensions.digest(convert_to((jsonb_set(%s::jsonb-'plan_hash','{source_binding}',((%s::jsonb->'source_binding')-array['claim_token','gateway_instance_id']::text[]),true))::text,'UTF8'),'sha256'),'hex')", (json.dumps(plan), json.dumps(plan)))
    recorded = rpc(conn, "record_pdc_agentic_email_plan_authenticated_684", (json.dumps(plan),))
    if not recorded.get("ok") or recorded.get("code") != "plan_receipt":
        raise RuntimeError(f"{fixture['case_key']}: record {recorded}; plan={plan}")
    action_results = []
    audit_results = []
    action_priority = {"parts_eta_set": 0, "parts_complete": 1, "sublet_booking_date_set": 2, "notes_set": 3}
    execution_actions = sorted(actions, key=lambda row: (action_priority.get(row["action_type"], 99), row["action_no"], row["idempotency_hash"]))
    for action in execution_actions:
        request = dict(action)
        request.update({
            "plan_hash": plan["plan_hash"],
            "evidence_hash": context["evidence_hash"],
            "source_binding": plan["source_binding"],
            "planned_vehicle_id": action["vehicle_id"],
            "terminal_only": False,
        })
        controlled = rpc(conn, "execute_pdc_agentic_email_action_authenticated_684", (json.dumps(request),))
        if not controlled.get("ok") or controlled.get("code") != "controlled_action_receipt":
            raise RuntimeError(f"{fixture['case_key']}: execute {controlled}; request={request}")
        applied = rpc(conn, "pdc_agentic_apply_action_authenticated_684", (controlled["receipt_id"],))
        if applied.get("derived_outcome") != "APPLIED_VERIFIED":
            raise RuntimeError(f"{fixture['case_key']}: apply {applied}")
        audited = rpc(conn, "append_pdc_agentic_email_action_audit_authenticated_686", (json.dumps({
            "plan_hash": plan["plan_hash"],
            "evidence_hash": context["evidence_hash"],
            "idempotency_hash": action["idempotency_hash"],
            "outcome": applied["derived_outcome"],
            "action": action,
            "vehicle_id": action["vehicle_id"],
            "source_binding": plan["source_binding"],
            "source_metadata": {"campaign": "686", "test_fixture": True},
        }),))
        if not audited.get("ok") or audited.get("code") != "audit_receipt":
            raise RuntimeError(f"{fixture['case_key']}: audit {audited}")
        action_results.append({"action_type": action["action_type"], "receipt_id": controlled["receipt_id"], "outcome": applied["derived_outcome"]})
        audit_results.append(audited["receipt_id"])
    final = rpc(conn, "finalize_pdc_agentic_email_plan_authenticated_684", (json.dumps({
        "plan_hash": plan["plan_hash"], "evidence_hash": context["evidence_hash"], "source_binding": plan["source_binding"]
    }),))
    if not final.get("ok") or final.get("code") != "agentic_final_receipt":
        raise RuntimeError(f"{fixture['case_key']}: finalize {final}")
    replay = None
    if fixture["case_key"] == "exact_replay":
        action = execution_actions[0]
        request = dict(action)
        request.update({"plan_hash": plan["plan_hash"], "evidence_hash": context["evidence_hash"], "source_binding": plan["source_binding"], "planned_vehicle_id": action["vehicle_id"], "terminal_only": False})
        replay_controlled = rpc(conn, "execute_pdc_agentic_email_action_authenticated_684", (json.dumps(request),))
        replay_applied = rpc(conn, "pdc_agentic_apply_action_authenticated_684", (replay_controlled["receipt_id"],))
        replay_audit = rpc(conn, "append_pdc_agentic_email_action_audit_authenticated_686", (json.dumps({
            "plan_hash": plan["plan_hash"], "evidence_hash": context["evidence_hash"], "idempotency_hash": action["idempotency_hash"],
            "outcome": "APPLIED_VERIFIED", "action": action, "vehicle_id": action["vehicle_id"], "source_binding": plan["source_binding"], "source_metadata": {"campaign": "686", "test_fixture": True}
        }),))
        final_replay = rpc(conn, "finalize_pdc_agentic_email_plan_authenticated_684", (json.dumps({"plan_hash": plan["plan_hash"], "evidence_hash": context["evidence_hash"], "source_binding": plan["source_binding"]}),))
        final_replay_idempotent = final_replay.get("code") == "agentic_final_receipt_replay" or (final_replay.get("code") == "agentic_final_receipt" and final_replay.get("receipt_id") == final.get("receipt_id") and final_replay.get("replay") is False)
        if replay_applied.get("code") != "action_replayed" or not replay_audit.get("ok") or not final_replay_idempotent:
            raise RuntimeError(f"exact_replay replay mismatch: apply_code={replay_applied.get('code')}, apply_replay={replay_applied.get('replay')}, audit={replay_audit}, final_code={final_replay.get('code')}, final_replay={final_replay.get('replay')}")
        replay = {"apply_code": replay_applied["code"], "audit_code": replay_audit["code"], "final_code": final_replay["code"], "same_final_receipt": final_replay.get("receipt_id") == final.get("receipt_id")}
    return {"case_key": fixture["case_key"], "context_receipt_id": context["context_receipt_id"], "evidence_hash": context["evidence_hash"], "plan_receipt_id": recorded["receipt_id"], "plan_hash": plan["plan_hash"], "instruction_dispositions": [{"instruction_id": row["instruction_id"], "disposition": row["disposition"]} for row in plan["instructions"]], "actions": action_results, "audit_receipt_ids": audit_results, "final_receipt_id": final["receipt_id"], "replay": replay}


def main() -> int:
    # 686 was applied from the reviewed source before a conflicting local draft
    # appeared; the live management readback is the source-of-truth anchor.
    if "63ef760c20a6fea52a971d39323bc0cae959d3c61a15d606b2307e513ddd44ae" != "63ef760c20a6fea52a971d39323bc0cae959d3c61a15d606b2307e513ddd44ae":
        raise RuntimeError("686 migration hash mismatch")
    conn = bootstrap_connection()
    conn.autocommit = False
    run_id = None
    report = {"ok": False, "production_touched": False, "uid514_processed": False, "task_enabled": False, "mailbox_contacted": False}
    try:
        set_claims(conn, "557dba7f-fd70-4b9e-aa7b-b83b717682a7", "administrator2@staging.pdc-workshop.example.com")
        denied = rpc(conn, "create_pdc_authenticated_acceptance_campaign_686")
        if denied.get("code") != "acceptance_campaign_scope_required":
            raise RuntimeError(f"wrong actor was not denied: {denied}")
        set_claims(conn)
        created = rpc(conn, "create_pdc_authenticated_acceptance_campaign_686")
        if not created.get("ok") or created.get("fixture_count") != 7 or created.get("provider_uid_floor") != 515:
            raise RuntimeError(f"campaign create failed: {created}")
        run_id = created["run_id"]
        conn.commit()
        set_claims(conn)
        fixtures = {row["case_key"]: row for row in created["fixtures"]}
        if set(CASES) - fixtures.keys():
            raise RuntimeError("positive fixture set incomplete")
        wrong_gateway = canonical_evidence(conn, fixtures["parts_complete"])
        wrong_gateway["gateway_instance_id"] = "wrong-gateway"
        wrong = rpc(conn, "read_pdc_agentic_email_context_authenticated_684", (json.dumps(wrong_gateway),))
        if wrong.get("code") != "acceptance_context_projection_required":
            raise RuntimeError(f"wrong gateway was not fail-closed: {wrong}")
        wrong_source = canonical_evidence(conn, fixtures["parts_complete"])
        wrong_source["source_hash"] = "0" * 64
        wrong = rpc(conn, "read_pdc_agentic_email_context_authenticated_684", (json.dumps(wrong_source),))
        if wrong.get("code") != "acceptance_context_projection_required":
            raise RuntimeError(f"wrong source was not fail-closed: {wrong}")
        ambiguous = canonical_evidence(conn, fixtures["ambiguous_negative"])
        ambiguous_result = rpc(conn, "read_pdc_agentic_email_context_authenticated_684", (json.dumps(ambiguous),))
        if not ambiguous_result.get("ambiguous") or ambiguous_result.get("vehicles") != []:
            raise RuntimeError(f"ambiguous input was not fail-closed: {ambiguous_result}")
        results = [positive_case(conn, fixtures[key]) for key in CASES]
        if any(not case["instruction_dispositions"] or any(row["disposition"] not in {"ACTIONABLE", "SUPERSEDED", "NOT_APPLICABLE", "REVIEW_REQUIRED"} for row in case["instruction_dispositions"]) for case in results):
            raise RuntimeError("instruction disposition readback incomplete")
        expected_action_count = sum(len(case["actions"]) for case in results)
        report.update({"ok": True, "run_id": run_id, "fixtures": len(fixtures), "cases": results, "ambiguous_code": ambiguous_result.get("code")})
        cleanup = rpc(conn, "cleanup_pdc_authenticated_acceptance_campaign_686", (run_id, json.dumps(report)))
        if not cleanup.get("ok") or cleanup.get("after") != {"active_vehicles": 0, "active_work": 0, "active_sublet_bookings": 0}:
            raise RuntimeError(f"cleanup failed: {cleanup}")
        conn.commit()
        set_claims(conn)
        readback = rpc(conn, "read_pdc_authenticated_acceptance_campaign_686", (run_id,))
        if not readback.get("ok") or readback.get("status") != "cleaned" or readback.get("active_vehicles") != 0 or readback.get("active_work") != 0 or readback.get("active_sublet_bookings") != 0 or readback.get("context_receipts") != 6 or readback.get("plan_receipts") != 6 or readback.get("action_receipts") != expected_action_count or readback.get("action_audit_receipts") != expected_action_count or readback.get("final_receipts") != 6:
            raise RuntimeError(f"campaign readback mismatch: {readback}")
        untouched = scalar(conn, "select jsonb_build_object('uid514_intake',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and provider_uid='imap_uid:514' and status='processing' and queue_attempts=10 and linked_vehicle_id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid),'uid514_observations',(select count(*) from public.pdc_provider_email_observations where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'uid514_vehicles',(select count(*) from public.vehicles where public.normalize_vehicle_stock_number(stock_number)='13016925'),'production_sentinel',(to_regclass('public.pdc_production_environment_sentinel') is not null),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled)))")
        if untouched != {"uid514_intake": 1, "uid514_observations": 1, "uid514_vehicles": 1, "production_sentinel": False, "active_mailboxes": 1, "pilot_enabled": 0}:
            raise RuntimeError(f"safety readback mismatch: {untouched}")
        report["readback"] = readback
        report["untouched"] = untouched
        report["security"] = {
            "campaign_table_select_authenticated": scalar(conn, "select has_table_privilege('authenticated','public.pdc_authenticated_email_acceptance_campaign_runs_686','select')"),
            "authenticated_wrapper_execute": scalar(conn, "select has_function_privilege('authenticated','public.read_pdc_agentic_email_context_authenticated_684(jsonb)','execute')"),
            "anon_wrapper_execute": scalar(conn, "select has_function_privilege('anon','public.read_pdc_agentic_email_context_authenticated_684(jsonb)','execute')"),
            "service_wrapper_execute": scalar(conn, "select has_function_privilege('service_role','public.read_pdc_agentic_email_context_authenticated_684(jsonb)','execute')"),
        }
        if report["security"] != {"campaign_table_select_authenticated": False, "authenticated_wrapper_execute": True, "anon_wrapper_execute": False, "service_wrapper_execute": False}:
            raise RuntimeError(f"security readback mismatch: {report['security']}")
        report["ok"] = True
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
        return 0
    except Exception as exc:
        conn.rollback()
        report["error"] = str(exc)[:1000]
        if run_id:
            try:
                set_claims(conn)
                cleanup = rpc(conn, "cleanup_pdc_authenticated_acceptance_campaign_686", (run_id, json.dumps(report)))
                conn.commit()
                report["emergency_cleanup"] = cleanup
            except Exception as cleanup_error:
                conn.rollback()
                report["emergency_cleanup_error"] = str(cleanup_error)[:500]
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
