#!/usr/bin/env python3
"""Approved management-path controller for staging-only Email Monitor 684."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
MIGRATION = ROOT / "supabase/staging_only/20260828050000_684_authenticated_provider_import_agentic_compatibility.sql"
EXPECTED = "567b756d2b1742e9aa5d1d02451af0c512caa5bd5b3bb54be13bd1af4997fa29"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_684"
CLI = "npx.cmd" if os.name == "nt" else "npx"

STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260828010000','20260828020000','20260828030000','20260828040000','20260828050000')),
 'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'failed',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and status='failed' and queue_attempts=8),'observations',(select count(*) from public.pdc_provider_email_observations where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'attachments',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'extracted',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and text_extraction_status='extracted'),'vehicles',(select count(*) from public.vehicles where public.normalize_vehicle_stock_number(stock_number)='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))),
 'security',jsonb_build_object('control_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_authenticated_provider_import_agentic_compatibility_controls_684'::regclass),'history_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_authenticated_provider_import_agentic_compatibility_history_684'::regclass),'history_forward',(select count(*) from public.pdc_authenticated_provider_import_agentic_compatibility_history_684 where event_kind='forward_compatibility'),'history_rollback',(select count(*) from public.pdc_authenticated_provider_import_agentic_compatibility_history_684 where event_kind='rollback'),'provider_wrapper_authenticated',has_function_privilege('authenticated','public.attest_pdc_monitor_provider_email_observation_684(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute'),'provider_wrapper_anon',has_function_privilege('anon','public.attest_pdc_monitor_provider_email_observation_684(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute'),'provider_wrapper_service',has_function_privilege('service_role','public.attest_pdc_monitor_provider_email_observation_684(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute'),'legacy_provider_authenticated',has_function_privilege('authenticated','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','execute'),'legacy_import_authenticated',has_function_privilege('authenticated','public.import_pdc_monitor_jobcard_attachment_279(text,uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')),
 'wrapper_hashes',(select coalesce(jsonb_object_agg(p.proname,encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')),'{}'::jsonb) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('attest_pdc_monitor_provider_email_observation_684','import_pdc_monitor_jobcard_attachment_authenticated_684','read_pdc_monitor_jobcard_attachment_receipt_authenticated_684','read_pdc_agentic_email_context_authenticated_684','record_pdc_agentic_email_plan_authenticated_684','execute_pdc_agentic_email_action_authenticated_684','pdc_agentic_apply_action_authenticated_684','finalize_pdc_agentic_email_plan_authenticated_684'))
) as evidence;
"""

PRE_STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260828010000','20260828020000','20260828030000','20260828040000','20260828050000')),
 'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'failed',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and status='failed' and queue_attempts=8),'observations',(select count(*) from public.pdc_provider_email_observations where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'attachments',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'extracted',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and text_extraction_status='extracted'),'vehicles',(select count(*) from public.vehicles where public.normalize_vehicle_stock_number(stock_number)='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled)))
) as evidence;
"""


def query(sql: str, source: Path | None = None) -> dict:
    temp = None
    if source is None:
        f = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", prefix="hermes-verify-", delete=False)
        f.write(sql); f.close(); temp = Path(f.name); source = temp
    try:
        result = subprocess.run([CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", REF, "--output-format", "json", "--file", str(source)], cwd=ROOT, capture_output=True, text=True, timeout=240, check=False)
        if result.returncode:
            detail = " ".join((result.stdout + " " + result.stderr).split())
            raise RuntimeError(f"management query failed: {detail[:2000]}")
        start = result.stdout.find("{")
        if start < 0: raise RuntimeError("management query returned no JSON")
        return json.JSONDecoder().raw_decode(result.stdout[start:])[0]
    finally:
        if temp is not None: temp.unlink(missing_ok=True)


def target_ok(e: dict) -> bool:
    return e["target"] == {"database":"postgres","current_user":"postgres","session_user":"postgres","staging_sentinel":1,"production_sentinel":False}


def assert_pre(e: dict) -> None:
    if not target_ok(e) or e["head"] != "20260828040000": raise RuntimeError("EXACT_STAGING_716_PRESTATE_REQUIRED")
    if e["ledger"] != [{"version":"20260828010000","name":"683_uid514_capability_mint_replay_repair"},{"version":"20260828020000","name":"714_fail_closed_navision_family_catalog_hardening"},{"version":"20260828030000","name":"715_remove_leaked_navision_714_test_probes"},{"version":"20260828040000","name":"716_close_all_raw_navision_acl_grantees"}]: raise RuntimeError("EXACT_683_716_LEDGER_REQUIRED")
    c=e["counts"]
    if c != {"intake":1,"failed":1,"observations":0,"authorization":1,"selection":1,"attachments":7,"extracted":4,"vehicles":0,"active_mailboxes":1,"pilot_enabled":0}: raise RuntimeError("RETAINED_UID514_PRESTATE_MISMATCH")


def assert_post(e: dict) -> None:
    if not target_ok(e) or e["head"] != "20260828050000" or e["ledger"][-1] != {"version":"20260828050000","name":"684_authenticated_provider_import_agentic_compatibility"}: raise RuntimeError("684_LEDGER_POSTSTATE_MISMATCH")
    c=e["counts"]
    if c != {"intake":1,"failed":1,"observations":0,"authorization":1,"selection":1,"attachments":7,"extracted":4,"vehicles":0,"active_mailboxes":1,"pilot_enabled":0}: raise RuntimeError("684_UID514_SAFETY_POSTSTATE_MISMATCH")
    s=e["security"]
    if s["history_forward"] != 1 or s["history_rollback"] != 0 or not s["control_forced_rls"] or not s["history_forced_rls"] or s["provider_wrapper_authenticated"] is not True or s["provider_wrapper_anon"] or s["provider_wrapper_service"] or s["legacy_provider_authenticated"] or s["legacy_import_authenticated"]: raise RuntimeError("684_SECURITY_POSTSTATE_MISMATCH")
    if len(e["wrapper_hashes"]) != 8: raise RuntimeError("684_WRAPPER_FAMILY_MISMATCH")


def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("mode",choices=("preflight-684","apply-684","readback-684")); parser.add_argument("--evidence",required=True,type=Path); args=parser.parse_args()
    out={"ok":False,"mode":args.mode,"committed":False,"production_touched":False,"task_enabled":False,"uid514_processed":False}
    try:
        if not args.evidence.is_absolute() or args.evidence.exists() or args.evidence.resolve().is_relative_to(ROOT): raise RuntimeError("EVIDENCE_PATH_INVALID")
        raw=MIGRATION.read_bytes()
        if MIGRATION.is_symlink() or hashlib.sha256(raw).hexdigest()!=EXPECTED or REF.encode() not in raw or PROD.encode() in raw: raise RuntimeError("SOURCE_ATTESTATION_FAILED")
        out["migration_sha256"]=EXPECTED
        state=query(STATE_SQL if args.mode=="readback-684" else PRE_STATE_SQL)["rows"][0]["evidence"]
        if args.mode=="readback-684": assert_post(state); out["after"]=state; out["ok"]=True
        else:
            assert_pre(state); out["before"]=state
            if args.mode=="apply-684":
                if os.environ.get(APPROVAL) != f"apply migration 684 source {EXPECTED}": raise RuntimeError("APPLY_APPROVAL_MISSING")
                query("", source=MIGRATION)
                after=query(STATE_SQL)["rows"][0]["evidence"]; assert_post(after); out.update(after=after,committed=True,ok=True)
            else: out.update(after=state,ok=True)
    except Exception as exc: out["error"]=str(exc)[:400]
    args.evidence.parent.mkdir(parents=True,exist_ok=True); args.evidence.write_text(json.dumps(out,sort_keys=True,separators=(",",":"))+"\n",encoding="utf-8")
    print(json.dumps(out,sort_keys=True,separators=(",",":"))); return 0 if out["ok"] else 1

if __name__ == "__main__": raise SystemExit(main())
