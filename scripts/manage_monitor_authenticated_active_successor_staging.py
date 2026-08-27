#!/usr/bin/env python3
"""Fail-closed Supabase-management controller for staging successor 672."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
MIGRATION = ROOT / "supabase/staging_only/20260827067200_672_authenticated_active_email_monitor_identity_successor.sql"
EXPECTED_MIGRATION_SHA256 = "9f5efd2fbaa5f9d66783f27f660dbaa585598a773d67f2c9059eddb5362fbefc"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_672"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"


def run_query(sql: str, source: Path | None = None) -> dict:
    temp = None
    try:
        if source is None:
            handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", prefix="hermes-verify-", delete=False)
            handle.write(sql)
            handle.close()
            temp = Path(handle.name)
            source = temp
        result = subprocess.run(
            [SUPABASE_CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", EXPECTED_REF, "--output-format", "json", "--file", str(source)],
            cwd=ROOT, capture_output=True, text=True, timeout=180, check=False,
        )
        if result.returncode:
            raise RuntimeError(f"management query failed: status {result.returncode}")
        start = result.stdout.find("{")
        if start < 0:
            raise RuntimeError("management query returned no JSON")
        value, _ = json.JSONDecoder().raw_decode(result.stdout[start:])
        return value
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)


def source_bytes() -> bytes:
    if MIGRATION.is_symlink() or not MIGRATION.is_file():
        raise RuntimeError("MIGRATION_SOURCE_MISSING")
    raw = MIGRATION.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_MIGRATION_SHA256:
        raise RuntimeError("MIGRATION_SOURCE_HASH_MISMATCH")
    if EXPECTED_REF.encode() not in raw or PRODUCTION_REF.encode() in raw:
        raise RuntimeError("MIGRATION_TARGET_GUARD_MISMATCH")
    return raw


STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827067100','20260827067200')),
 'actor',(select coalesce(to_jsonb(x),'{}'::jsonb) from (select r.role::text,r.active,r.account_status,w.active writer_active,w.revoked_at from public.pdc_user_roles r join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id where r.auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' and lower(r.email)='sales@broometoyota.com.au') x),
 'binding',(select coalesce(to_jsonb(x),'{}'::jsonb) from (select actor_id,gateway_instance_id,release_name,source_sha,manifest_sha256,semantic_planner_sha256,semantic_planner_trust_receipt_sha256,semantic_planner_commissioned_at from public.pdc_monitor_runtime_bindings_255 where singleton) x),
 'security',jsonb_build_object('authenticated_verify',case when to_regprocedure('public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)') is null then false else has_function_privilege('authenticated','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute') end,'authenticated_reader',case when to_regprocedure('public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)') is null then false else has_function_privilege('authenticated','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute') end,'anon_verify',case when to_regprocedure('public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)') is null then false else has_function_privilege('anon','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute') end,'service_verify',case when to_regprocedure('public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)') is null then false else has_function_privilege('service_role','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute') end,'anon_reader',case when to_regprocedure('public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)') is null then false else has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute') end,'service_reader',case when to_regprocedure('public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)') is null then false else has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute') end,'direct_dml',(select count(*)=0 from information_schema.role_table_grants where grantee='authenticated' and table_schema='public' and table_name like 'pdc_email_monitor_authenticated_active_%' and privilege_type in('INSERT','UPDATE','DELETE','TRUNCATE')),'history_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid=to_regclass('public.pdc_email_monitor_authenticated_active_capability_history_672'))),
 'containment',jsonb_build_object('active_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'automatic_pilot',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled)))
) as evidence;
"""


def evidence_state() -> dict:
    result = run_query(STATE_SQL)
    return result["rows"][0]["evidence"]


def assert_predecessor(state: dict) -> None:
    if state["target"]["database"] != "postgres" or state["target"]["current_user"] != "postgres" or state["target"]["session_user"] != "postgres" or state["target"]["staging_sentinel"] != 1 or state["target"]["production_sentinel"]:
        raise RuntimeError("EXACT_STAGING_DATABASE_PRESTATE_REQUIRED")
    if state["head"] != "20260827067100" or state["ledger"] != [{"version": "20260827067100", "name": "671_email_monitor_active_planner_rotation_after_670"}]:
        raise RuntimeError("EXACT_671_LEDGER_PRESTATE_REQUIRED")
    if state["actor"].get("role") != "importer" or state["actor"].get("active") is not True or state["actor"].get("account_status") != "approved" or state["actor"].get("writer_active") is not True or state["actor"].get("revoked_at") is not None:
        raise RuntimeError("EXACT_ACTIVE_IMPORTER_WRITER_PRESTATE_REQUIRED")
    if state["binding"].get("actor_id") != "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b" or state["binding"].get("gateway_instance_id") != "pdc-monitor-staging-sales-uid509-v1" or state["binding"].get("release_name") != "pdc-monitor-staging-m502-2026.08.44" or state["binding"].get("semantic_planner_sha256") != "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348" or state["binding"].get("semantic_planner_trust_receipt_sha256") != "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227":
        raise RuntimeError("EXACT_671_BINDING_PRESTATE_REQUIRED")
    if state["containment"] != {"active_writers": 1, "active_mailboxes": 0, "automatic_pilot": 0}:
        raise RuntimeError("STAGING_CONTAINMENT_PRESTATE_REQUIRED")
    if any(state["security"].get(key) for key in ("anon_verify", "service_verify", "anon_reader", "service_reader")):
        raise RuntimeError("BROAD_EXECUTE_PRESTATE_COLLISION")


def assert_post(state: dict) -> None:
    if state["head"] != "20260827067200" or state["ledger"] != [
        {"version": "20260827067100", "name": "671_email_monitor_active_planner_rotation_after_670"},
        {"version": "20260827067200", "name": "672_authenticated_active_email_monitor_identity_successor"},
    ]:
        raise RuntimeError("SUCCESSOR_POSTSTATE_LEDGER_MISMATCH")
    if state["security"] != {"authenticated_verify": True, "authenticated_reader": True, "anon_verify": False, "service_verify": False, "anon_reader": False, "service_reader": False, "direct_dml": True, "history_rls": True}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_SECURITY_MISMATCH")
    if state["containment"] != {"active_writers": 1, "active_mailboxes": 0, "automatic_pilot": 0}:
        raise RuntimeError("SUCCESSOR_POSTSTATE_CONTAINMENT_MISMATCH")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preflight-672", "apply-672"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args(argv)
    event = {"ok": False, "mode": args.mode, "committed": False, "mailbox_contacted": False, "production_touched": False, "task_enabled": False}
    try:
        if not args.evidence.is_absolute() or args.evidence.exists() or args.evidence.resolve().is_relative_to(ROOT):
            raise RuntimeError("EVIDENCE_PATH_INVALID")
        raw = source_bytes()
        event["migration_sha256"] = hashlib.sha256(raw).hexdigest()
        before = evidence_state()
        assert_predecessor(before)
        event["before"] = before
        if args.mode == "apply-672":
            if os.environ.get(APPROVAL_ENV) != f"apply migration 672 source {EXPECTED_MIGRATION_SHA256}":
                raise RuntimeError("APPLY_APPROVAL_MISSING")
            run_query("", source=MIGRATION)
            event["committed"] = True
        after = evidence_state()
        assert_post(after) if args.mode == "apply-672" else None
        event["after"] = after
        event["ok"] = True
    except Exception as exc:
        event["error"] = str(exc)[:400]
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
