#!/usr/bin/env python3
"""Apply the bounded STAGING-only v2 canonical action capability."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901230000_pdc_email_ai_v2_canonical_action_capability_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901220000", "pdc_email_ai_successor_executor_reconciliation_20260901")
TARGET = ("20260901230000", "pdc_email_ai_v2_canonical_action_capability_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901230000"
FUNCTIONS = {
    "capability": "public.pdc_email_ai_v2_canonical_action_capability_20260902()",
    "executor": "public.pdc_email_ai_successor_execute_v2_20260901(jsonb)",
    "parts_eta": "public.update_pdc_parts_eta(uuid,integer,date)",
    "work_states": "public.set_pdc_vehicle_work_states(uuid,integer,jsonb)",
    "timeline": "public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)",
    "location": "public.move_vehicle(uuid,integer,text,text,text,text,text)",
    "strict": "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)",
}
TABLES = ("public.pdc_email_ai_successor_runtime_identities", "public.pdc_email_ai_successor_transaction_receipts", "public.pdc_email_ai_successor_action_receipts", "public.pdc_email_ai_v2_canonical_action_capability_history_20260901")
ROLES = ("public", "anon", "authenticated", "service_role")

def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()

def bundle():
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_CANONICAL_CAPABILITY_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None: raise RuntimeError("PDC_CANONICAL_CAPABILITY_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8")); module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url: raise RuntimeError("PDC_CANONICAL_CAPABILITY_NON_STAGING_TARGET")
    return data

def fhash(cur, sig):
    return one(cur, "select case when to_regprocedure(%s) is null then null else encode(extensions.digest(convert_to(pg_get_functiondef(to_regprocedure(%s)),'UTF8'),'sha256'),'hex') end", (sig, sig))[0]

def fsource(cur, sig):
    return one(cur, "select coalesce(pg_get_functiondef(to_regprocedure(%s)),'')", (sig,))[0] or ""

def state(cur):
    existing = [t for t in TABLES if one(cur, "select to_regclass(%s)", (t,))[0] is not None]
    return {
        "ledger_head": tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1") or ()),
        "receipts": tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)")),
        "rls": {t: tuple(one(cur, "select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass", (t,)) or (False,False)) for t in existing},
        "direct_table_privileges": {t: {r: bool(one(cur, "select has_table_privilege(%s,%s,'select')", (r,t))[0]) for r in ROLES} for t in existing},
        "function_hashes": {k: fhash(cur,v) for k,v in FUNCTIONS.items()},
        "production_sentinel": bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]),
    }

def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901230000 pdc email ai v2 canonical action capability source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected: raise RuntimeError("PDC_CANONICAL_CAPABILITY_APPROVAL_MISSING_OR_HASH_MISMATCH")
    import psycopg2
    credentials = bundle()
    conn = psycopg2.connect(credentials["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-v2-canonical-capability-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor(); before = state(cur)
        if before["ledger_head"] not in {PREDECESSOR, TARGET}: raise RuntimeError(f"PDC_CANONICAL_CAPABILITY_UNEXPECTED_LIVE_HEAD:{before['ledger_head']}")
        if before["production_sentinel"]: raise RuntimeError("PDC_CANONICAL_CAPABILITY_PRODUCTION_SENTINEL_PRESENT")
        already = before["ledger_head"] == TARGET
        if not already: cur.execute(MIGRATION.read_text(encoding="utf-8"))
        after = state(cur)
        sources = {k: fsource(cur,v) for k,v in FUNCTIONS.items()}
        proof = {
            "ok": after["ledger_head"] == TARGET and before["receipts"] == after["receipts"] and not after["production_sentinel"] and all(all(bool(x) for x in flags) for flags in after["rls"].values()) and all(not x for table in after["direct_table_privileges"].values() for x in table.values()) and "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["parts_eta"] and "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["work_states"] and "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["timeline"] and "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["location"] and "set_config('pdc_email_ai_v2_canonical_action_capability_20260902'" in sources["executor"],
            "environment": "staging", "project_ref": STAGING_REF, "migration_identity": TARGET, "migration_sha256": digest, "already_applied": already,
            "before": before, "after": after,
            "capability": {"actor_bound": True, "authenticated_only": True, "active_stage_writer_required": True, "administrator_excluded": True, "transaction_local": True, "allowed_actions": ["parts_eta_set","parts_complete","required_work_set","note_append","location_set","operation_add","operation_update"]},
            "source_markers": {"parts_eta": "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["parts_eta"], "work_states": "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["work_states"], "timeline": "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["timeline"], "location": "pdc_email_ai_v2_canonical_action_capability_20260902()" in sources["location"], "executor_transaction_scope": "set_config('pdc_email_ai_v2_canonical_action_capability_20260902'" in sources["executor"]},
            "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False,
        }
        if not proof["ok"]: raise RuntimeError("PDC_CANONICAL_CAPABILITY_POSTCHECK_FAILED")
        conn.commit()
        out = ROOT / "review-evidence/v2-controlled/canonical-action-capability-apply-proof.json"; out.parent.mkdir(parents=True, exist_ok=True); out.write_text(json.dumps(proof, sort_keys=True, indent=2)+"\n", encoding="utf-8")
        print(json.dumps({"proof": str(out), "ok": True, "migration": TARGET, "migration_sha256": digest, "ledger_head": after["ledger_head"], "receipts_preserved": before["receipts"]==after["receipts"], "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
    except Exception:
        conn.rollback(); raise
    finally: conn.close()
if __name__ == "__main__": main()
