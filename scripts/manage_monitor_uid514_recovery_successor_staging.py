#!/usr/bin/env python3
"""Fail-closed Supabase-management controller for the exact UID514 successor 677."""
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
MIGRATION = ROOT / "supabase/staging_only/20260827111000_677_uid514_exact_recovery_successor.sql"
EXPECTED_MIGRATION_SHA256 = "ad921292bdafb3bfc25413df8c1faa803442f0c645799aac3cd42af76b0da85f"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_677"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"


def run_query(sql: str, source: Path | None = None) -> dict:
    temporary = None
    try:
        if source is None:
            handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", prefix="hermes-verify-", delete=False)
            handle.write(sql)
            handle.close()
            temporary = Path(handle.name)
            source = temporary
        result = subprocess.run(
            [SUPABASE_CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", EXPECTED_REF,
             "--output-format", "json", "--file", str(source)],
            cwd=ROOT, capture_output=True, text=True, timeout=240, check=False,
        )
        if result.returncode:
            raise RuntimeError(f"management query failed: status {result.returncode}")
        start = result.stdout.find("{")
        if start < 0:
            raise RuntimeError("management query returned no JSON")
        value, _ = json.JSONDecoder().raw_decode(result.stdout[start:])
        return value
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


PRE_STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827067000','20260827067100','20260827067200','20260827106000','20260827108000','20260827109000','20260827110000')),
 'counts',jsonb_build_object('uid514_intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'uid514_authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'uid514_selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'stock_vehicle',(select count(*) from public.vehicles where stock_number='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))),
 'history',jsonb_build_object('forward',0,'rollback',0)
) as evidence;
"""


STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827067000','20260827067100','20260827067200','20260827106000','20260827108000','20260827109000','20260827110000','20260827111000')),
 'control',(select coalesce(to_jsonb(x),'{}'::jsonb) from (select enabled,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,mailbox_id,mailbox_key,mailbox_address,provider,mailbox_folder,mailbox_uidvalidity,mailbox_uid,recovery_event_id,parent_source_hash,all_attachment_hashes,pdf_hashes,job_card_sha256,observed_mime_part_count,retained_authenticated_attachment_count,all_mime_parts_retained,task_enabled,mailbox_contacted,uid514_processed,production_writes from public.pdc_uid514_recovery_controls_677 where singleton) x),
 'history',(select jsonb_build_object('forward',count(*) filter(where event_kind='forward_uid514_recovery'),'rollback',count(*) filter(where event_kind='rollback')) from public.pdc_uid514_recovery_history_677),
 'counts',jsonb_build_object('uid514_intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'uid514_authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'uid514_selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'stock_vehicle',(select count(*) from public.vehicles where stock_number='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))),
 'security',jsonb_build_object('recovery_execute',has_function_privilege('authenticated','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute'),'rollback_execute',has_function_privilege('authenticated','public.admin_rollback_pdc_uid514_recovery_677(text)','execute'),'claim_execute',has_function_privilege('authenticated','public.claim_pdc_uid514_recovery_257(text,integer)','execute'),'anon_recovery',has_function_privilege('anon','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute'),'service_recovery',has_function_privilege('service_role','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute'),'anon_claim',has_function_privilege('anon','public.claim_pdc_uid514_recovery_257(text,integer)','execute'),'service_claim',has_function_privilege('service_role','public.claim_pdc_uid514_recovery_257(text,integer)','execute'),'history_select',has_table_privilege('authenticated','public.pdc_uid514_recovery_history_677','select'),'control_select',has_table_privilege('authenticated','public.pdc_uid514_recovery_controls_677','select'),'capability_select',has_table_privilege('authenticated','public.pdc_uid514_recovery_enqueue_capabilities_677','select'),'history_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_recovery_history_677'::regclass),'control_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_recovery_controls_677'::regclass),'capability_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_recovery_enqueue_capabilities_677'::regclass)),
 'runtime',jsonb_build_object('trigger_has_exact_branch',position('pdc_uid514_recovery_enqueue_capability_677' in pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure))>0,'claim_has_677_gate',position('pdc_uid514_recovery_claim_enabled_677' in pg_get_functiondef('public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure))>0)
) as evidence;
"""


def state(include_successor: bool = False) -> dict:
    return run_query(STATE_SQL if include_successor else PRE_STATE_SQL)["rows"][0]["evidence"]


def assert_target(value: dict) -> None:
    target = value["target"]
    if target != {"database": "postgres", "current_user": "postgres", "session_user": "postgres", "staging_sentinel": 1, "production_sentinel": False}:
        raise RuntimeError("EXACT_STAGING_DATABASE_TARGET_REQUIRED")


def assert_pre(value: dict) -> None:
    assert_target(value)
    required = [
        {"version": "20260827067000", "name": "670_email_monitor_active_capability_uid514_seven_part_reconciliation"},
        {"version": "20260827067100", "name": "671_email_monitor_active_planner_rotation_after_670"},
        {"version": "20260827067200", "name": "672_authenticated_active_email_monitor_identity_successor"},
        {"version": "20260827106000", "name": "673_authenticated_monitor_execution_attachment_successor"},
        {"version": "20260827108000", "name": "674_authenticated_monitor_mailbox_activation_transition"},
        {"version": "20260827109000", "name": "675_authenticated_monitor_enqueue_trigger_compatibility"},
        {"version": "20260827110000", "name": "676_authenticated_monitor_rollback_control_repair"},
    ]
    if value["ledger"] != required or value["counts"] != {"uid514_intake": 0, "uid514_authorization": 0, "uid514_selection": 0, "stock_vehicle": 0, "active_mailboxes": 1, "pilot_enabled": 0}:
        raise RuntimeError("EXACT_676_PRESTATE_REQUIRED")
    if value["history"] != {"forward": 0, "rollback": 0}:
        raise RuntimeError("677_OBJECTS_ALREADY_PRESENT")


def assert_post(value: dict) -> None:
    assert_target(value)
    if value["ledger"][-1] != {"version": "20260827111000", "name": "677_uid514_exact_recovery_successor"}:
        raise RuntimeError("677_LEDGER_POSTSTATE_MISMATCH")
    control = value["control"]
    for key, expected in {
        "enabled": True, "actor_id": "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b", "actor_email": "sales@broometoyota.com.au", "jwt_role": "authenticated", "server_application_role": "importer",
        "gateway_instance_id": "pdc-monitor-staging-sales-uid509-v1", "release_name": "pdc-monitor-staging-m502-2026.08.44", "source_sha": "e850c319989d98b45b95a28aa815d78e2c2e3a4b", "manifest_sha256": "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
        "planner_sha256": "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348", "trust_receipt_sha256": "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227", "mailbox_id": "12fe383d-5c1e-5801-96e4-f67cf3e3bb57", "mailbox_key": "pdc_pmb_email", "mailbox_address": "pmbcontroller@gmail.com", "provider": "gmail", "mailbox_folder": "Inbox", "mailbox_uidvalidity": 1, "mailbox_uid": 514, "recovery_event_id": 25751401, "parent_source_hash": "440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280", "observed_mime_part_count": 7, "retained_authenticated_attachment_count": 4, "all_mime_parts_retained": True, "task_enabled": False, "mailbox_contacted": False, "uid514_processed": False, "production_writes": False,
    }.items():
        if control.get(key) != expected:
            raise RuntimeError(f"677_CONTROL_MISMATCH_{key}")
    if value["history"] != {"forward": 1, "rollback": 0} or value["counts"] != {"uid514_intake": 0, "uid514_authorization": 0, "uid514_selection": 0, "stock_vehicle": 0, "active_mailboxes": 1, "pilot_enabled": 0}:
        raise RuntimeError("677_SAFE_POSTSTATE_MISMATCH")
    security = value["security"]
    if security["recovery_execute"] is not True or security["rollback_execute"] is not True or security["claim_execute"] is not True or any(security[key] for key in ("anon_recovery", "service_recovery", "anon_claim", "service_claim", "history_select", "control_select", "capability_select")):
        raise RuntimeError("677_SECURITY_POSTSTATE_MISMATCH")
    if not all(value["security"][key] for key in ("history_forced_rls", "control_forced_rls", "capability_forced_rls")) or not value["runtime"]["trigger_has_exact_branch"] or not value["runtime"]["claim_has_677_gate"]:
        raise RuntimeError("677_RUNTIME_POSTSTATE_MISMATCH")


def source_bytes() -> bytes:
    if MIGRATION.is_symlink() or not MIGRATION.is_file():
        raise RuntimeError("MIGRATION_SOURCE_MISSING")
    raw = MIGRATION.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_MIGRATION_SHA256:
        raise RuntimeError("MIGRATION_SOURCE_HASH_MISMATCH")
    if EXPECTED_REF.encode() not in raw or PRODUCTION_REF.encode() in raw:
        raise RuntimeError("MIGRATION_TARGET_GUARD_MISMATCH")
    return raw


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preflight-677", "apply-677", "readback-677"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args(argv)
    event = {"ok": False, "mode": args.mode, "committed": False, "production_touched": False, "uid514_processed": False, "task_enabled": False}
    try:
        if not args.evidence.is_absolute() or args.evidence.exists() or args.evidence.resolve().is_relative_to(ROOT):
            raise RuntimeError("EVIDENCE_PATH_INVALID")
        raw = source_bytes()
        event["migration_sha256"] = hashlib.sha256(raw).hexdigest()
        if args.mode == "readback-677":
            after = state(include_successor=True)
            assert_post(after)
            event["after"] = after
            event["ok"] = True
        else:
            before = state()
            assert_pre(before)
            event["before"] = before
        if args.mode == "apply-677":
            if os.environ.get(APPROVAL_ENV) != f"apply migration 677 source {EXPECTED_MIGRATION_SHA256}":
                raise RuntimeError("APPLY_APPROVAL_MISSING")
            run_query("", source=MIGRATION)
            event["committed"] = True
            after = state(include_successor=True)
            assert_post(after)
        elif args.mode == "preflight-677":
            after = before
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
