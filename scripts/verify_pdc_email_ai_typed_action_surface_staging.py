#!/usr/bin/env python3
"""Read-only STAGING signature/ACL/trigger proof for the typed action surface."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
LIVE_HEAD = ("20260901080000", "pdc_email_ai_typed_action_identity_contract_20260901")
EXPECTED = {
    "reconcile_navision_operational_record": "uuid,uuid,text",
    "import_pdc_authenticated_email_operations_with_hours": "text,text,jsonb",
    "update_pdc_parts_eta": "uuid,integer,date",
    "set_pdc_vehicle_work_states": "uuid,integer,jsonb",
    "schedule_vehicle_work": "uuid,integer,text,integer,timestamp with time zone,integer,uuid,text,jsonb",
    "move_workshop_booking": "uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb",
    "cancel_workshop_booking": "uuid,integer,text,jsonb",
    "complete_workshop_work": "uuid,integer,text,timestamp with time zone,jsonb",
    "append_vehicle_timeline_event": "uuid,text,timestamp with time zone,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid",
    "move_vehicle": "uuid,integer,text,text,text,text,text",
    "rft_transfer_vehicle": "uuid,integer",
    "rft_collect_vehicle": "uuid,integer",
}


def main() -> None:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None or not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(bundle)
    url = bundle.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or "vjdtsswhroyguxyfjdkt" in url:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    import psycopg2

    conn = psycopg2.connect(url, sslmode="verify-full", sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-typed-action-surface-readonly")
    try:
        cur = conn.cursor()
        cur.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        head = tuple(cur.fetchone() or ())
        signatures = {}
        for name, args in EXPECTED.items():
            cur.execute("select to_regprocedure(%s) is not null, pg_get_functiondef(to_regprocedure(%s))", (f"public.{name}({args})", f"public.{name}({args})"))
            present, definition = cur.fetchone()
            signatures[name] = {"expected": args, "present": bool(present), "has_security_definer": "SECURITY DEFINER" in (definition or ""), "definition_bytes": len(definition or "")}
        cur.execute("select coalesce((select has_function_privilege('authenticated',oid,'execute') from pg_proc where oid=to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)')),false), coalesce((select has_function_privilege('service_role',oid,'execute') from pg_proc where oid=to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)')),false), coalesce((select has_function_privilege('public',oid,'execute') from pg_proc where oid=to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)')),false), coalesce((select has_function_privilege('anon',oid,'execute') from pg_proc where oid=to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)')),false)")
        acl = cur.fetchone()
        cur.execute("select to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') is not null, to_regprocedure('public.get_pdc_email_ai_successor_action_contract_20260901()') is not null, to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') is not null, to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') is not null, to_regprocedure('public.pdc_email_ai_successor_action_readback_20260901(uuid,text,jsonb,jsonb)') is not null")
        rpc_presence = cur.fetchone()
        tables = []
        for table in ("pdc_email_ai_successor_action_rules_20260901", "pdc_email_ai_successor_transaction_receipts", "pdc_email_ai_successor_action_receipts"):
            cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid=to_regclass(%s)", (f"public.{table}",))
            row = cur.fetchone()
            tables.append({"table": table, "rls": bool(row[0]) if row else False, "force_rls": bool(row[1]) if row else False})
        cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
        production = bool(cur.fetchone()[0])
        result = {
            "ok": head == LIVE_HEAD and all(item["present"] for item in signatures.values()) and all(item["rls"] and item["force_rls"] for item in tables) and rpc_presence == (True, True, True, True, True) and acl == (True, False, False, False) and not production,
            "environment": "staging", "project_ref": STAGING_REF, "ledger_head": head,
            "signatures": signatures,
            "typed_action_acl": {"authenticated": bool(acl[0]), "service_role": bool(acl[1]), "public": bool(acl[2]), "anon": bool(acl[3])},
            "typed_action_rpc_present": bool(rpc_presence[0]), "contract_rpc_present": bool(rpc_presence[1]), "v2_validator_present": bool(rpc_presence[2]), "v2_plan_validator_present": bool(rpc_presence[3]), "field_readback_present": bool(rpc_presence[4]),
            "tables": tables, "production_sentinel_present": production,
            "mailbox_contacted": False, "outbound_email": False, "business_mutation": False,
        }
        print(json.dumps(result, sort_keys=True))
        if not result["ok"]:
            raise RuntimeError("PDC_TYPED_ACTION_SURFACE_STAGING_PROOF_FAILED")
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False}, sort_keys=True))
        raise SystemExit(1)
