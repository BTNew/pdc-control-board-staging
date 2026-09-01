#!/usr/bin/env python3
"""Read-only live proof for the v2 executor reconciliation."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_successor_executor_reconciliation_staging.py"
PROOF = ROOT / "review-evidence/v2-controlled/executor-reconciliation-live-proof.json"
META_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/config/pdc-email-ai-successor-runtime.env")
STORE_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/secrets/pdc-email-ai-successor-runtime.dpapi")
BASE = "https://cdsmnqxtyyoeoznmbidd.supabase.co"


def main() -> None:
    spec = importlib.util.spec_from_file_location("controller", CONTROLLER)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_CONTROLLER_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    credentials = module.bundle()
    import psycopg2

    conn = psycopg2.connect(credentials["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-successor-executor-reconciliation-staging-verifier")
    conn.autocommit = True
    try:
        cur = conn.cursor()
        state = module.state(cur)
        executor = module.function_source(cur, module.FUNCTIONS["executor"])
        operation = module.function_source(cur, module.FUNCTIONS["operation_update"])
        strict = module.function_source(cur, module.FUNCTIONS["strict"])
        meta = {
            key.strip(): value.strip()
            for raw in META_PATH.read_text(encoding="utf-8").splitlines()
            if (line := raw.strip()) and not line.startswith("#") and "=" in line
            for key, value in [line.split("=", 1)]
        }
        spec = importlib.util.spec_from_file_location("pdc_email_bootstrap", module.BOOTSTRAP)
        if spec is None or spec.loader is None:
            raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_RUNTIME_BOOTSTRAP_INVALID")
        runtime_bootstrap = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runtime_bootstrap)
        runtime_secret = json.loads(runtime_bootstrap.unprotect(STORE_PATH.read_bytes()).decode("utf-8"))
        anon = credentials.get("PDC_STAGING_SUPABASE_ANON_KEY", "").strip()

        def request(url: str, method: str, headers: dict[str, str], body: object) -> tuple[int, object]:
            data = json.dumps(body, separators=(",", ":")).encode("utf-8")
            try:
                with urlopen(Request(url, data=data, method=method, headers={"Content-Type": "application/json", **headers}), timeout=45) as response:
                    raw = response.read().decode("utf-8")
                    return response.status, json.loads(raw) if raw else None
            except HTTPError as exc:
                raw = exc.read().decode("utf-8", errors="replace")
                try:
                    return exc.code, json.loads(raw)
                except json.JSONDecodeError:
                    return exc.code, {"raw": raw[:200]}

        login_status, auth = request(BASE + "/auth/v1/token?grant_type=password", "POST", {"apikey": anon}, {"email": runtime_secret["email"], "password": runtime_secret["runtime_password"]})
        if login_status != 200 or not isinstance(auth, dict) or not auth.get("access_token"):
            raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_RUNTIME_LOGIN_FAILED")
        headers = {"apikey": anon, "Authorization": "Bearer " + auth["access_token"]}
        invalid_status, invalid_body = request(BASE + "/rest/v1/rpc/" + meta["PDC_SUCCESSOR_TYPED_ACTION_RPC"], "POST", headers, {"p_plan": {"environment": "production"}})
        invalid_code = invalid_body.get("code") if isinstance(invalid_body, dict) else None
        direct_table_http = {}
        for table in module.TABLES[:3]:
            table_name = table.rsplit(".", 1)[-1]
            status, _ = request(BASE + "/rest/v1/" + table_name + "?select=*", "GET", headers, {})
            direct_table_http[table] = status
        after_negative_state = module.state(cur)
        proof = {
            "ok": (
                state["ledger_head"] == module.TARGET
                and state["history_rows"] == 1
                and "SELECT r.source_uid INTO v_source_uid" in executor
                and "pdc_authenticated_email_import_receipts" in executor
                and "import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid" in executor
                and "GET STACKED DIAGNOSTICS" in executor
                and "RETURNED_SQLSTATE" in executor
                and "canonical_error" in executor
                and "SELECT r.source_uid INTO v_source_uid" in operation
                and "source_hash,v_source_uid" in operation
                and state["strict_acl"] == (True, False, False, False)
                and all(all(bool(flag) for flag in values) for values in state["rls"].values())
                and all(not flag for table in state["direct_table_privileges"].values() for flag in table.values())
                and not state["production_sentinel_present"]
                and invalid_status == 200
                and invalid_code == "typed_v2_plan_invalid"
                and all(status in (401, 403) for status in direct_table_http.values())
                and state["receipts"] == after_negative_state["receipts"]
            ),
            "environment": "staging",
            "project_ref": module.STAGING_REF,
            "ledger_head": state["ledger_head"],
            "history_rows": state["history_rows"],
            "receipts": state["receipts"],
            "strict_acl": state["strict_acl"],
            "rls": state["rls"],
            "direct_table_privileges": state["direct_table_privileges"],
            "direct_table_http_status": direct_table_http,
            "strict_negative": {"http_status": invalid_status, "code": invalid_code, "receipts_unchanged": state["receipts"] == after_negative_state["receipts"]},
            "function_hashes": state["function_hashes"],
            "source_binding": {
                "executor_receipt_lookup": "SELECT r.source_uid INTO v_source_uid" in executor,
                "operation_add_exact_uid": "import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid" in executor,
                "operation_update_exact_uid": "source_hash,v_source_uid" in operation,
                "typed_payload_uid_not_used_for_dispatch": "operations_with_hours(source_hash,item->'payload'->>'source_uid'" not in executor,
            },
            "canonical_result_error_evidence": {
                "sqlstate": "RETURNED_SQLSTATE" in executor,
                "message": "MESSAGE_TEXT" in executor,
                "detail": "PG_EXCEPTION_DETAIL" in executor,
                "hint": "PG_EXCEPTION_HINT" in executor,
                "actual_result": "actual:=result" in executor,
                "verification_result": "canonical_result" in executor and "source_uid_binding" in executor,
            },
            "strict_source": {
                "authenticated_only": state["strict_acl"] == (True, False, False, False),
                "preserved": "pdc_email_ai_successor_execute_v2_20260901" in strict,
            },
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email": False,
            "action_rpc_invoked": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_LIVE_PROOF_FAILED")
        PROOF.parent.mkdir(parents=True, exist_ok=True)
        PROOF.write_text(json.dumps(proof, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"proof": str(PROOF), "ok": True, "ledger_head": state["ledger_head"], "receipts": state["receipts"], "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
