#!/usr/bin/env python3
"""Fail-closed Supabase-management controller for staging repair successor 678."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
MIGRATION = ROOT / "supabase/staging_only/20260827112000_678_uid514_authorize_attachment_count_repair.sql"
EXPECTED_MIGRATION_SHA256 = "0fab7dbc2525173aea32a5c502b249a892684bdabf4bab483da9ad6e9edacfe1"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_678"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"

PRE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827111000','20260827112000')),
 'counts',jsonb_build_object('uid514_intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'uid514_authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'uid514_selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'stock_vehicle',(select count(*) from public.vehicles where stock_number='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))),
 'recovery_history',(select count(*) from public.pdc_uid514_recovery_history_677 where event_kind='forward_uid514_recovery')
) as evidence;
"""

POST_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827111000','20260827112000')),
 'counts',jsonb_build_object('uid514_intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'uid514_authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'uid514_selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'stock_vehicle',(select count(*) from public.vehicles where stock_number='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))),
 'history',(select jsonb_build_object('recovery_677_forward',count(*) filter(where event_kind='forward_uid514_recovery')) from public.pdc_uid514_recovery_history_677),
 'repair_history',(select count(*) from public.pdc_uid514_recovery_authorize_repair_history_678 where event_kind='forward_authorize_attachment_count_repair'),
 'authorize_repaired',position(',''13016925'',''J139125482'',7)' in pg_get_functiondef('public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure))>0,
 'security',jsonb_build_object('anon_recovery',has_function_privilege('anon','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute'),'service_recovery',has_function_privilege('service_role','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute'),'anon_claim',has_function_privilege('anon','public.claim_pdc_uid514_recovery_257(text,integer)','execute'),'service_claim',has_function_privilege('service_role','public.claim_pdc_uid514_recovery_257(text,integer)','execute'),'repair_history_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_recovery_authorize_repair_history_678'::regclass))
) as evidence;
"""


def query(sql: str, source: Path | None = None) -> dict:
    temporary = None
    try:
        if source is None:
            import tempfile
            handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", prefix="hermes-verify-", delete=False)
            handle.write(sql)
            handle.close()
            temporary = Path(handle.name)
            source = temporary
        result = subprocess.run([SUPABASE_CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", EXPECTED_REF, "--output-format", "json", "--file", str(source)], cwd=ROOT, capture_output=True, text=True, timeout=240, check=False)
        if result.returncode:
            raise RuntimeError(f"management query failed: status {result.returncode}")
        start = result.stdout.find("{")
        if start < 0:
            raise RuntimeError("management query returned no JSON")
        return json.JSONDecoder().raw_decode(result.stdout[start:])[0]
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def state(post: bool = False) -> dict:
    return query(POST_SQL if post else PRE_SQL)["rows"][0]["evidence"]


def target_ok(value: dict) -> bool:
    return value["target"] == {"database": "postgres", "current_user": "postgres", "session_user": "postgres", "staging_sentinel": 1, "production_sentinel": False}


def assert_pre(value: dict) -> None:
    if not target_ok(value) or value["ledger"] != [{"name": "677_uid514_exact_recovery_successor", "version": "20260827111000"}] or value["recovery_history"] != 1:
        raise RuntimeError("EXACT_677_PRESTATE_REQUIRED")
    if value["counts"] != {"uid514_intake": 0, "uid514_authorization": 0, "uid514_selection": 0, "stock_vehicle": 0, "active_mailboxes": 1, "pilot_enabled": 0}:
        raise RuntimeError("UID514_SAFE_PRESTATE_REQUIRED")


def assert_post(value: dict) -> None:
    if not target_ok(value) or value["ledger"] != [
        {"name": "677_uid514_exact_recovery_successor", "version": "20260827111000"},
        {"name": "678_uid514_authorize_attachment_count_repair", "version": "20260827112000"},
    ]:
        raise RuntimeError("678_LEDGER_POSTSTATE_MISMATCH")
    if value["counts"] != {"uid514_intake": 0, "uid514_authorization": 0, "uid514_selection": 0, "stock_vehicle": 0, "active_mailboxes": 1, "pilot_enabled": 0} or value["history"] != {"recovery_677_forward": 1} or value["repair_history"] != 1 or not value["authorize_repaired"]:
        raise RuntimeError("678_SAFE_POSTSTATE_MISMATCH")
    if any(value["security"][key] for key in ("anon_recovery", "service_recovery", "anon_claim", "service_claim")) or not value["security"]["repair_history_forced_rls"]:
        raise RuntimeError("678_SECURITY_POSTSTATE_MISMATCH")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preflight-678", "apply-678", "readback-678"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args(argv)
    event = {"ok": False, "mode": args.mode, "committed": False, "production_touched": False, "uid514_processed": False, "task_enabled": False}
    try:
        if not args.evidence.is_absolute() or args.evidence.exists() or args.evidence.resolve().is_relative_to(ROOT):
            raise RuntimeError("EVIDENCE_PATH_INVALID")
        raw = MIGRATION.read_bytes()
        if MIGRATION.is_symlink() or not MIGRATION.is_file() or hashlib.sha256(raw).hexdigest() != EXPECTED_MIGRATION_SHA256 or EXPECTED_REF.encode() not in raw or PRODUCTION_REF.encode() in raw:
            raise RuntimeError("MIGRATION_SOURCE_ATTESTATION_FAILED")
        event["migration_sha256"] = hashlib.sha256(raw).hexdigest()
        if args.mode == "readback-678":
            after = state(post=True)
            assert_post(after)
            event["after"] = after
            event["ok"] = True
        else:
            before = state()
            assert_pre(before)
            event["before"] = before
            if args.mode == "apply-678":
                if os.environ.get(APPROVAL_ENV) != f"apply migration 678 source {EXPECTED_MIGRATION_SHA256}":
                    raise RuntimeError("APPLY_APPROVAL_MISSING")
                query("", source=MIGRATION)
                event["committed"] = True
                after = state(post=True)
                assert_post(after)
                event["after"] = after
            else:
                event["after"] = before
            event["ok"] = True
    except Exception as exc:
        event["error"] = str(exc)[:400]
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
