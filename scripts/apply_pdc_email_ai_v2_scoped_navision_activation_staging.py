#!/usr/bin/env python3
"""Apply and prove the scoped successor Navision activation in STAGING."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902263200_pdc_email_ai_v2_scoped_navision_activation_readback_repair_20260902.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PRE = ("20260902263100", "pdc_email_ai_v2_scoped_navision_activation_source_repair_20260902")
TARGET = ("20260902263200", "pdc_email_ai_v2_scoped_navision_activation_readback_repair_20260902")
ACTIVATION = "public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(jsonb)"
PREPARE = "public.pdc_email_ai_v2_prepare_scoped_attachment_observation_20260902(jsonb)"
HISTORY = "public.pdc_email_ai_v2_scoped_navision_activation_history_20260902"
REPAIR_HISTORY = "public.pdc_email_ai_v2_scoped_navision_activation_source_repair_history_20260902"
READBACK_HISTORY = "public.pdc_email_ai_v2_scoped_navision_activation_readback_repair_history_20260902"
RECEIPTS = "public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902"
ACTOR_EMAIL = "pdc-email-ai-successor-staging@broometoyota.com.au"
SOURCE_HASH = "5e3a53566c5596ee78f6bcc91e1d75a831c1572e4e1eb6a4eddb252e687488b6"
SOURCE_UID = "1:709"
STOCK = "13059806"
SENDER = "scott@karrathatoyota.com.au"
EVIDENCE_HASH = hashlib.sha256(b"hermes-scoped-navision-activation-evidence").hexdigest()
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260902263200"


def one(cur, query: str, params=()):
    cur.execute(query, params)
    row = cur.fetchone()
    return row[0] if row else None


def load_staging_database() -> dict[str, str]:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(values)
    url = values.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_NON_STAGING_TARGET")
    return values


def head(cur) -> tuple[str, str]:
    cur.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1")
    row = cur.fetchone()
    return tuple(row) if row else ()


def payload(stock: str = STOCK, source_hash: str = SOURCE_HASH, uid: str = SOURCE_UID) -> dict[str, object]:
    attachment_hash = hashlib.sha256(("hermes-scoped-activation-attachment:" + source_hash).encode()).hexdigest()
    return {
        "attachments": [{
            "attachment_index": 1,
            "content_type": "application/pdf",
            "extracted_text": "Stock " + stock,
            "filename": "hermes-verify-scoped-activation.pdf",
            "size_bytes": 1,
            "source_hash": attachment_hash,
        }],
        "authentication": {
            "dkim_aligned": False,
            "dmarc_aligned": True,
            "gmail_authentication_results": True,
            "sender_domain": "karrathatoyota.com.au",
            "spf_aligned": True,
        },
        "evidence_hash": EVIDENCE_HASH,
        "observations": {"source_text": "Stock " + stock, "operation_lines": []},
        "provider_message_id": "hermes-verify-scoped-activation-message-" + source_hash[:12],
        "provider_thread_id": "hermes-verify-scoped-activation-thread-" + source_hash[:12],
        "sender_address": SENDER,
        "source_hash": source_hash,
        "source_received_at": "2026-09-01T03:13:15+00:00",
        "source_uid": uid,
        "stock_number": stock,
        "subject": "Hermes scoped Navision activation verification",
    }


def set_actor(cur, *, role: str = "authenticated") -> None:
    claims = {"sub": str(ACTOR_ID), "role": role, "email": ACTOR_EMAIL}
    cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(ACTOR_ID),))
    cur.execute("select set_config('request.jwt.claim.role',%s,true)", (role,))
    cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps(claims),))


def call(cur, request: dict[str, object]) -> dict[str, object]:
    cur.execute("select public.pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(%s::jsonb)", (json.dumps(request),))
    value = cur.fetchone()[0]
    return value if isinstance(value, dict) else {}


def readback(cur, stock: str) -> dict[str, object]:
    cur.execute("""
      select
        (select count(*) from public.navision_backend_records r where r.is_current and r.record_status='current' and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=%s),
        (select count(*) from public.navision_backend_records r where r.is_current and r.record_status='current' and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=%s and r.canonical_vehicle_id is not null),
        (select count(*) from public.vehicles v where v.deleted_at is null and v.stock_number_normalized=%s and v.lifecycle_state='active' and v.visible_on_board),
        (select count(*) from public.navision_board_activations a where a.active and public.normalize_vehicle_stock_number(a.activated_stock_number)=%s and a.canonical_vehicle_id is not null),
        (select count(*) from public.pdc_email_ai_v2_scoped_navision_activation_receipts_20260902 r where r.source_hash=%s),
        (select count(*) from public.vehicle_work_items w join public.vehicles v on v.id=w.vehicle_id where v.stock_number_normalized=%s),
        (select count(*) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.stock_number_normalized=%s and b.deleted_at is null),
        (select count(*) from public.vehicle_parts_updates p join public.vehicles v on v.id=p.vehicle_id where v.stock_number_normalized=%s)
    """, (stock, stock, stock, stock, SOURCE_HASH, stock, stock, stock))
    row = cur.fetchone()
    return {
        "current_navision_rows": row[0],
        "backend_canonical_links": row[1],
        "active_visible_vehicles": row[2],
        "active_board_activations": row[3],
        "activation_receipts": row[4],
        "work_rows": row[5],
        "active_booking_rows": row[6],
        "parts_rows": row[7],
    }


def main() -> None:
    global ACTOR_ID
    migration_hash = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected_approval = f"apply migration 20260902263200 pdc email ai v2 scoped navision activation source {migration_hash}"
    if os.environ.get(APPROVAL_ENV) != expected_approval:
        raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_APPROVAL_MISSING_OR_HASH_MISMATCH")
    credentials = load_staging_database()
    import psycopg2

    connection = psycopg2.connect(
        credentials["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-v2-scoped-navision-activation-staging-controller",
    )
    connection.autocommit = False
    try:
        cur = connection.cursor()
        live_head = head(cur)
        if live_head not in {PRE, TARGET}:
            raise RuntimeError(f"PDC_SCOPED_NAVISION_ACTIVATION_UNEXPECTED_LIVE_HEAD:{live_head}")
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_PRODUCTION_SENTINEL_PRESENT")
        ACTOR_ID = one(cur, "select auth_user_id from public.pdc_email_ai_successor_runtime_identities where normalized_email=%s and environment='staging' and identity_purpose='pdc_email_ai_transaction_successor' and active and revoked_at is null limit 1", (ACTOR_EMAIL,))
        if not ACTOR_ID:
            raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_RUNTIME_ACTOR_MISSING")
        already_applied = live_head == TARGET
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
        live_head = head(cur)
        cur.execute("select pg_get_functiondef(%s::regprocedure)", (ACTIVATION,))
        activation_source = one(cur, "select pg_get_functiondef(%s::regprocedure)", (ACTIVATION,)) or ""
        prepare_source = one(cur, "select pg_get_functiondef(%s::regprocedure)", (PREPARE,)) or ""
        history_rows = int(one(cur, f"select count(*) from {HISTORY}") or 0)
        repair_history_rows = int(one(cur, f"select count(*) from {REPAIR_HISTORY}") or 0)
        readback_history_rows = int(one(cur, f"select count(*) from {READBACK_HISTORY}") or 0)
        acl = {role: bool(one(cur, "select has_function_privilege(%s,%s,'execute')", (role, ACTIVATION))) for role in ("public", "anon", "authenticated", "service_role", "pdc_email_monitor")}
        if live_head != TARGET or history_rows != 1 or repair_history_rows != 1 or readback_history_rows != 1 or "pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902" not in prepare_source:
            raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_LIVE_POSTCHECK_FAILED")

        # The migration is intentionally committed before the disposable
        # positive/replay probes; those probes use their own savepoint.
        connection.commit()
        before = readback(cur, STOCK)
        cur.execute("savepoint scoped_navision_activation_proof")
        set_actor(cur)
        first_activation = call(cur, payload())
        after_first = readback(cur, STOCK)
        replay_activation = call(cur, payload())
        negative_identity = call(cur, payload(stock=STOCK, source_hash=hashlib.sha256(b"hermes-negative-identity").hexdigest(), uid="1:710"))
        set_actor(cur, role="anon")
        negative_authentication = call(cur, payload(source_hash=hashlib.sha256(b"hermes-negative-auth").hexdigest(), uid="1:711"))
        cur.execute("rollback to savepoint scoped_navision_activation_proof")
        after_rollback = readback(cur, STOCK)
        cur.execute("release savepoint scoped_navision_activation_proof")
        connection.commit()

        proof = {
            "ok": (
                live_head == TARGET
                and history_rows == 1
                and repair_history_rows == 1
                and readback_history_rows == 1
                and acl == {"public": False, "anon": False, "authenticated": True, "service_role": False, "pdc_email_monitor": False}
                and first_activation.get("ok") is True
                and first_activation.get("code") == "scoped_navision_activation_prepared"
                and first_activation.get("activation_only") is True
                and replay_activation.get("ok") is True
                and replay_activation.get("code") == "scoped_navision_activation_replayed"
                and negative_identity.get("code") in {"canonical_vehicle_identity_conflict", "operational_identity_conflict"}
                and negative_authentication.get("code") == "runtime_identity_required"
                and after_first["active_visible_vehicles"] == 1
                and after_first["active_board_activations"] == 1
                and after_first["backend_canonical_links"] == 1
                and after_first["work_rows"] == 0
                and after_first["active_booking_rows"] == 0
                and after_first["parts_rows"] == 0
                and after_rollback == before
            ),
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": migration_hash,
            "migration_identity": TARGET,
            "already_applied": already_applied,
            "ledger_head": live_head,
            "history_rows": history_rows,
            "repair_history_rows": repair_history_rows,
            "readback_history_rows": readback_history_rows,
            "acl": acl,
            "first_activation": first_activation,
            "replay_activation": replay_activation,
            "negative_identity": negative_identity,
            "negative_authentication": negative_authentication,
            "authoritative_readback": {"before": before, "after_first": after_first, "after_rollback": after_rollback},
            "prepare_source_bound": "pdc_email_ai_v2_activate_scoped_navision_vehicle_20260902(p_request)" in prepare_source,
            "activation_source_markers": {
                "successor_identity": "pdc_email_ai_successor_runtime_identities" in activation_source,
                "stage_writer": "pdc_monitor_stage_activation_writers" in activation_source,
                "exact_sender_enrollment": "pdc_monitor_exact_sender_enrollments" in activation_source,
                "canonical_trigger": "trigger_reconcile_navision_operational_record" in activation_source,
                "no_operation_status_mutation": all(marker in activation_source for marker in ("work_mutated',false", "parts_mutated',false", "booking_created',false", "completion_created',false", "status_mutated',false")),
            },
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email": False,
            "action_rpc_invoked": False,
            "positive_probe_rolled_back": True,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_SCOPED_NAVISION_ACTIVATION_PROOF_FAILED:" + json.dumps(proof, sort_keys=True))
        output = ROOT / "review-evidence/v2-controlled/scoped-navision-activation-live-proof.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(proof, sort_keys=True, indent=2, default=str) + "\n", encoding="utf-8")
        print(json.dumps({"ok": True, "proof": str(output), "migration": TARGET, "migration_sha256": migration_hash, "ledger_head": live_head, "first_code": first_activation.get("code"), "replay_code": replay_activation.get("code"), "negative_identity_code": negative_identity.get("code"), "negative_authentication_code": negative_authentication.get("code"), "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    main()
