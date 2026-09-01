#!/usr/bin/env python3
"""Apply/read back the final typed-action hardening in STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901070000_pdc_email_ai_typed_action_execution_readback_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901060000", "pdc_email_ai_typed_action_boundary_hardening_20260901")
TARGET = ("20260901070000", "pdc_email_ai_typed_action_execution_readback_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901070000"


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle():
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_TYPED_ACTION_EXECUTION_READBACK_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_TYPED_ACTION_EXECUTION_READBACK_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_TYPED_ACTION_EXECUTION_READBACK_NON_STAGING_TARGET")
    return data


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901070000 pdc email ai typed action execution readback source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_TYPED_ACTION_EXECUTION_READBACK_APPROVAL_MISSING_OR_HASH_MISMATCH")
    data = bundle()
    import psycopg2

    conn = psycopg2.connect(data["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=data["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-typed-action-execution-readback-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f"PDC_TYPED_ACTION_EXECUTION_READBACK_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_TYPED_ACTION_EXECUTION_READBACK_PRODUCTION_SENTINEL_PRESENT")
        cur.execute(MIGRATION.read_text(encoding="utf-8"))
        conn.commit()
        cur = conn.cursor()
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901070000'") or ())
        funcs = {
            "strict": bool(one(cur, "select to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') is not null")[0]),
            "plan_validator": bool(one(cur, "select to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') is not null")[0]),
            "readback": bool(one(cur, "select to_regprocedure('public.pdc_email_ai_successor_action_readback_20260901(uuid,text,jsonb,jsonb)') is not null")[0]),
            "parity": bool(one(cur, "select to_regprocedure('public.pdc_email_ai_successor_action_readback_parity_20260901(text,jsonb,jsonb,jsonb)') is not null")[0]),
        }
        acl = tuple(one(cur, "select has_function_privilege('authenticated','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('service_role','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('public','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('anon','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute')"))
        source = one(cur, "select pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure)")[0] or ""
        executor = one(cur, "select pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure)")[0] or ""
        operation = one(cur, "select pg_get_functiondef('public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric)'::regprocedure)")[0] or ""
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and all(funcs.values()) and acl == (True, False, False, False) and not production and "pdc_email_ai_successor_validate_v2_plan_20260901" in source and "pdc_email_ai_successor_action_readback_20260901" in executor and "manual_assignment_locked" in operation and "ai_auditor" in operation,
            "environment": "staging", "project_ref": STAGING_REF, "migration_sha256": digest, "ledger_head": ledger,
            "functions": funcs, "typed_action_acl": {"authenticated": acl[0], "service_role": acl[1], "public": acl[2], "anon": acl[3]},
            "production_sentinel_present": production, "action_rpc_invoked": False, "business_mutation": False, "mailbox_contacted": False, "outbound_email": False,
        }
        print(json.dumps(proof, sort_keys=True))
        if not proof["ok"]:
            raise RuntimeError("PDC_TYPED_ACTION_EXECUTION_READBACK_POST_APPLY_READBACK_FAILED")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "action_rpc_invoked": False}, sort_keys=True))
        raise SystemExit(1)
