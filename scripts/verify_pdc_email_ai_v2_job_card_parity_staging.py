#!/usr/bin/env python3
"""Apply and verify the exact STAGING Job Card parity correction."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review-evidence/t_203851d5"
RUNTIME_PATH = ROOT / "runtime_release/v2_staging_runner.py"
CONTROLLER_PATH = ROOT / "scripts/apply_pdc_email_ai_v2_scoped_attachment_observation_authority_staging.py"
RPC = "reconcile_pdc_email_ai_v2_job_card_parity_20260902"
SOURCE_RECEIPT = "fdfa10d4-ffda-46c5-9cf3-8923b1a8cdf2"
VEHICLE_ID = "2cc5e9b8-7114-5d77-ada5-b296c9d10a9f"
SOURCE_HASH = "5e3a53566c5596ee78f6bcc91e1d75a831c1572e4e1eb6a4eddb252e687488b6"
SOURCE_UID = "1:709"
ATTACHMENT_DIGEST = "87d60dc2308eb0809d7e072226a86efe172fe708b4149a7ae7fd9159f09348f2"
STOCK = "13059806"
VIN = "JTMAA7BJ204154038"
JOB_CARD = "J139125567"
PURCHASE_ORDER_DIGEST = "a3f70786fcd9655c76adac257598d3053a01bc998ef4890afab143aa45ef0eaa"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if not spec or not spec.loader:
        raise RuntimeError(f"{name}_unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def call(runtime, connector, payload):
    status, response = runtime.json_request(
        runtime.BASE + "/rest/v1/rpc/" + RPC,
        "POST",
        connector.headers,
        {"p_source_receipt_id": payload["source_receipt_id"], "p_vehicle_id": payload["vehicle_id"], "p_source_hash": payload["source_hash"], "p_source_uid": payload["source_uid"], "p_attachment_digest": payload["attachment_digest"], "p_stock_number": payload["stock_number"], "p_vin": payload["vin"], "p_job_card_number": payload["job_card_number"]},
    )
    return {"http_status": status, "response": response}


def readback(connector):
    value = connector.readback()
    if not isinstance(value, dict) or value.get("ok") is not True:
        raise RuntimeError("authoritative_readback_failed")
    rows = ((value.get("data") or {}).get("vehicles") or [])
    return next((row for row in rows if str(row.get("stock_number")) == STOCK), None), value


def db_state(controller):
    import psycopg2
    credentials = controller.bundle()
    connection = psycopg2.connect(credentials["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-v2-job-card-parity-proof")
    connection.autocommit = True
    try:
        cursor = connection.cursor()
        cursor.execute("select v.id,v.stock_number,v.vin,v.job_card_number,v.version,v.current_location,v.visible_on_board,a.backend_record_id,a.active,a.completed_at from public.vehicles v join public.navision_board_activations a on a.canonical_vehicle_id=v.id where v.id=%s and a.active", (VEHICLE_ID,))
        identity = [list(row) for row in cursor.fetchall()]
        cursor.execute("select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=%s", (SOURCE_HASH,))
        operation_rows = cursor.fetchone()[0]
        cursor.execute("select count(*) from public.pdc_email_ai_successor_transaction_receipts where source_receipt_id=%s", (SOURCE_RECEIPT,))
        transactions = cursor.fetchone()[0]
        cursor.execute("select count(*) from public.pdc_email_ai_successor_action_receipts where source_receipt_id=%s", (SOURCE_RECEIPT,))
        actions = cursor.fetchone()[0]
        cursor.execute("select count(*) from public.workshop_bookings b where b.vehicle_id=%s and b.deleted_at is null", (VEHICLE_ID,))
        bookings = cursor.fetchone()[0]
        cursor.execute("select b.id,b.version,b.status::text,b.deleted_at from public.workshop_bookings b where b.vehicle_id=%s order by b.created_at desc", (VEHICLE_ID,))
        booking_rows = [list(row) for row in cursor.fetchall()]
        cursor.execute("select source_hash,source_uid,stock_number,vin,request_hash from public.pdc_authenticated_email_import_receipts where source_hash=%s and vehicle_id=%s", (SOURCE_HASH, VEHICLE_ID))
        receipt = list(cursor.fetchone() or ())
        cursor.execute("select count(*) from public.pdc_email_ai_v2_job_card_parity_corrections_20260902 where source_receipt_id=%s", (SOURCE_RECEIPT,))
        corrections = cursor.fetchone()[0]
        return {"identity": identity, "operation_rows": operation_rows, "successor_transactions": transactions, "successor_actions": actions, "active_bookings": bookings, "booking_rows": booking_rows, "import_receipt": receipt, "job_card_corrections": corrections}
    finally:
        connection.close()


def main():
    runtime = load(RUNTIME_PATH, "pdc_v2_job_card_runtime")
    controller = load(CONTROLLER_PATH, "pdc_v2_job_card_controller")
    connector = runtime.Connector(runtime.load_pairs(runtime.META_PATH))
    before_row, before_readback = readback(connector)
    before_state = db_state(controller)
    base = {"source_receipt_id": SOURCE_RECEIPT, "vehicle_id": VEHICLE_ID, "source_hash": SOURCE_HASH, "source_uid": SOURCE_UID, "attachment_digest": ATTACHMENT_DIGEST, "stock_number": STOCK, "vin": VIN, "job_card_number": JOB_CARD}
    applied = call(runtime, connector, base)
    replay = call(runtime, connector, base)
    negatives = {}
    for name, changes in {
        "wrong_source": {"source_hash": "0" * 64},
        "wrong_stock": {"stock_number": "13059807"},
        "wrong_vin": {"vin": "JTMAA7BJ204154039"},
        "wrong_attachment": {"attachment_digest": PURCHASE_ORDER_DIGEST},
        "protected_manual_job_card": {"job_card_number": "J139125568"},
        "no_job_card_attachment": {"attachment_digest": PURCHASE_ORDER_DIGEST, "job_card_number": "J139125567"},
    }.items():
        payload = copy.deepcopy(base)
        payload.update(changes)
        negatives[name] = call(runtime, connector, payload)
    after_row, after_readback = readback(connector)
    after_state = db_state(controller)
    health = connector.health()
    scheduler = None
    try:
        import subprocess
        result = subprocess.run(["schtasks.exe", "/Query", "/TN", "\\PDC-PMB-Email-AI-v2-Staging-Successor", "/FO", "LIST", "/V"], capture_output=True, text=True, check=True)
        values = {}
        for line in result.stdout.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                values[key.strip()] = value.strip()
        scheduler = {"status": values.get("Status"), "last_result": values.get("Last Result"), "scheduled_task_state": values.get("Scheduled Task State"), "task_name": values.get("TaskName")}
    except Exception as exc:
        scheduler = {"error": type(exc).__name__}
    expected_codes = {"wrong_source": "source_reuse_conflict", "wrong_stock": "vehicle_identity_conflict", "wrong_vin": "attachment_source_mismatch", "wrong_attachment": "attachment_source_mismatch", "protected_manual_job_card": "job_card_conflict_protected", "no_job_card_attachment": "attachment_source_mismatch"}
    proof = {
        "ok": (
            applied["http_status"] == 200 and applied["response"].get("ok") is True and applied["response"].get("code") in {"job_card_parity_corrected", "job_card_already_correct"}
            and replay["http_status"] == 200 and replay["response"].get("correction_replay") is True
            and after_row and after_row.get("job_card_number") == JOB_CARD and after_row.get("stock_number") == STOCK
            and after_state["identity"] and after_state["identity"][0][3] == JOB_CARD and after_state["operation_rows"] == before_state["operation_rows"] == 1
            and after_state["successor_transactions"] == before_state["successor_transactions"] == 1 and after_state["successor_actions"] == before_state["successor_actions"] == 1
            and after_state["active_bookings"] == before_state["active_bookings"] == 0 and after_state["job_card_corrections"] == 1
            and all(item["http_status"] == 200 and item["response"].get("code") == expected_codes[name] for name, item in negatives.items())
            and isinstance(health, dict) and health.get("production_writes") is False and health.get("outbound_email") is False
            and scheduler == {"status": "Ready", "last_result": "0", "scheduled_task_state": "Enabled", "task_name": "\\PDC-PMB-Email-AI-v2-Staging-Successor"}
        ),
        "environment": "staging", "project_ref": runtime.PROJECT_REF, "source": {"uid": SOURCE_UID, "source_hash": SOURCE_HASH, "stock_number": STOCK, "vin": VIN, "job_card_number": JOB_CARD, "attachment_digest": ATTACHMENT_DIGEST},
        "before": {"readback_vehicle": before_row, "database": before_state},
        "apply": applied, "exact_replay": replay, "negative_regressions": negatives,
        "after": {"readback_vehicle": after_row, "database": after_state},
        "rendered_readback": {"before_revision": (before_readback.get("data") or {}).get("revision"), "after_revision": (after_readback.get("data") or {}).get("revision"), "vehicle_job_card": after_row.get("job_card_number") if after_row else None, "operation_count": len(after_row.get("operation_lines") or []) if after_row else 0, "operation_numbers": [x.get("operation_no") for x in (after_row.get("operation_lines") or [])] if after_row else []},
        "scheduler": scheduler, "health": {key: health.get(key) for key in ("transactions", "partial_failures", "pending_or_blocked_actions", "production_writes", "outbound_email") if isinstance(health, dict)},
        "mailbox_contacted": False, "outbound_email": False, "production_touched": False,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "job-card-parity-live-proof.json"
    path.write_text(json.dumps(proof, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")
    if not proof["ok"]:
        raise RuntimeError("PDC_JOB_CARD_PARITY_LIVE_POSTCHECK_FAILED")
    print(json.dumps({"ok": True, "proof": str(path), "job_card_number": after_row.get("job_card_number") if after_row else None, "operation_rows": after_state["operation_rows"], "successor_transactions": after_state["successor_transactions"], "successor_actions": after_state["successor_actions"], "active_bookings": after_state["active_bookings"], "exact_replay": replay["response"].get("correction_replay"), "negative_regressions": {name: item["response"].get("code") for name, item in negatives.items()}, "scheduler": scheduler, "mailbox_contacted": False, "outbound_email": False, "production_touched": False}, sort_keys=True))


if __name__ == "__main__":
    main()
