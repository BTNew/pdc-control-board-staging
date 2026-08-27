#!/usr/bin/env python3
"""Staging-only management controller for the already-reviewed .44 successors."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
SUPABASE_CLI = "npx.cmd" if os.name == "nt" else "npx"
MIGRATIONS = (
    ("20260827058000", "505_forward_project_504_reconciliation_into_m503_singleton", ROOT / "supabase/staging_only/20260827058000_505_forward_project_504_reconciliation_into_m503_singleton.sql", "b6b3ef6b7d6812f49cb0832a47a0a6e86e90fecfb1ac49aaedb96957504356a0"),
    ("20260827059000", "505_repair_contained_email_runtime_rollback_path", ROOT / "supabase/staging_only/20260827059000_505_repair_contained_email_runtime_rollback_path.sql", "8293bb44b3c5ea32abb87e4771746935707e5a5e8cb284d56469e481e1707322"),
    ("20260827060000", "600_repair_contained_email_runtime_reconcile_replay_after_projection", ROOT / "supabase/staging_only/20260827060000_600_repair_contained_email_runtime_reconcile_replay_after_projection.sql", "fdc6ac857db7587516508de885d7389c754fb3271c9a88eaa80619585fe7a903"),
    ("20260827061000", "610_repair_contained_email_runtime_reconcile_replay_head", ROOT / "supabase/staging_only/20260827061000_610_repair_contained_email_runtime_reconcile_replay_head.sql", "8bc2f47dc426a339ccdefc9194308eba9d707aeee31a282d30288b88ef3e6d4a"),
    ("20260827063000", "630_repair_contained_email_runtime_reconcile_forward_head_floor", ROOT / "supabase/staging_only/20260827063000_630_repair_contained_email_runtime_reconcile_forward_head_floor.sql", "2759d05dc4d713b40cc127c8a5f7b9838bfa1d27e3bd6bdf3c8fe1ca2b583e3a"),
    ("20260827064000", "506_allow_contained_sales_uid514_receipt_read", ROOT / "supabase/staging_only/20260827064000_506_allow_contained_sales_uid514_receipt_read.sql", "a22c4574dce74564b45e6c8d8d569b53c180baef334a7c71b24d46c48483a59b"),
)
PAIR = {
    "actor_id": "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
    "gateway_instance_id": "pdc-monitor-staging-sales-uid509-v1",
    "release_name": "pdc-monitor-staging-m502-2026.08.44",
    "source_sha": "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
    "source_tree_sha": "8981540501bc629e189c39c9ea8a9adf3165d397",
    "manifest_sha256": "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
    "archive_sha256": "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90",
}

READ_STATE_SQL = """
select jsonb_build_object(
 'target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),
 'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827053000','20260827054000','20260827055000','20260827056000','20260827057000','20260827058000','20260827059000','20260827060000','20260827061000','20260827063000','20260827064000')),
 'binding',(select coalesce(to_jsonb(x),'{}'::jsonb) from (select actor_id,gateway_instance_id,release_name,source_sha,manifest_sha256,semantic_planner_sha256,semantic_planner_trust_receipt_sha256,semantic_planner_commissioned_at from public.pdc_monitor_runtime_bindings_255 where singleton) x),
 'reconciliation',(select coalesce(to_jsonb(x),'{}'::jsonb) from (select reconciliation_id,event_kind,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,manifest_sha256,archive_sha256,migration_head,mode,operational,activation_ready,writer_active,planner_commissioned,production_writes from public.pdc_monitor_contained_binding_reconciliations_504 order by created_at desc,reconciliation_id desc limit 1) x),
 'history',(select count(*) from public.pdc_monitor_runtime_binding_compatibility_history_505),
 'security',jsonb_build_object('reconcile_authenticated',has_function_privilege('authenticated','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE'),'reconcile_anon',has_function_privilege('anon','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE'),'reconcile_service',has_function_privilege('service_role','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE'),'verify_authenticated',has_function_privilege('authenticated','public.verify_pdc_monitor_contained_binding_504(text,text,text,text,text,text)','EXECUTE'),'get_authenticated',has_function_privilege('authenticated','public.get_pdc_monitor_contained_binding_504()','EXECUTE'),'history_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid=to_regclass('public.pdc_monitor_runtime_binding_compatibility_history_505')),'reconcile_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid=to_regclass('public.pdc_monitor_contained_binding_reconciliations_504'))),
 'containment',jsonb_build_object('active_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'automatic_pilot',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled)))
) as evidence;
"""


def run_query(sql: str, source: Path | None = None) -> dict:
    temp = None
    try:
        if source is None:
            handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", prefix="hermes-verify-", delete=False)
            handle.write(sql)
            handle.close()
            temp = Path(handle.name)
            source = temp
        command = [SUPABASE_CLI, "--yes", "supabase", "db", "query", "--linked", "--project-ref", EXPECTED_REF, "--output-format", "json", "--file", str(source)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180, check=False)
        if result.returncode:
            raise RuntimeError(f"management query failed: HTTP/CLI status {result.returncode}: {result.stderr[-400:] or result.stdout[-400:]}")
        start = result.stdout.find("{")
        if start < 0:
            raise RuntimeError("management query returned no JSON")
        value, _end = json.JSONDecoder().raw_decode(result.stdout[start:])
        return value
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)


def validate_sources() -> dict[str, str]:
    hashes = {}
    for version, _name, path, expected in MIGRATIONS:
        if not path.is_file() or path.is_symlink():
            raise RuntimeError(f"missing or unsafe migration source: {path.name}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != expected:
            raise RuntimeError(f"{version} source hash mismatch")
        if EXPECTED_REF not in path.read_text(encoding="utf-8") or PRODUCTION_REF in path.read_text(encoding="utf-8"):
            raise RuntimeError(f"{version} staging target guard mismatch")
        hashes[version] = digest
    return hashes


def rows(state: dict) -> list[dict]:
    return state["rows"][0]["evidence"]["ledger"]


def apply_source(path: Path) -> None:
    run_query("", source=path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("rehearse", "apply", "verify"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    event = {"ok": False, "mode": args.mode, "committed": False, "production_touched": False, "mailbox_contacted": False}
    try:
        if not args.evidence.is_absolute() or args.evidence.exists() or args.evidence.resolve().is_relative_to(ROOT):
            raise RuntimeError("EVIDENCE_PATH_INVALID")
        event["source_hashes"] = validate_sources()
        before = run_query(READ_STATE_SQL)
        event["before"] = before["rows"][0]["evidence"]
        ledger = {item["version"]: item["name"] for item in rows(before)}
        expected = {version: name for version, name, _path, _sha in MIGRATIONS}
        present = {version: ledger.get(version) == name for version, name in expected.items()}
        if any(ledger.get(version) not in (None, name) for version, name in expected.items()):
            raise RuntimeError("SUCCESSOR_LEDGER_NAME_MISMATCH")
        seen_gap = False
        for version, _name, _path, _sha in MIGRATIONS:
            if not present[version]:
                seen_gap = True
            elif seen_gap:
                raise RuntimeError("PARTIAL_SUCCESSOR_CHAIN")
        first_missing = next((version for version, _name, _path, _sha in MIGRATIONS if not present[version]), None)
        if args.mode == "rehearse":
            if first_missing:
                required_head = {"20260827058000": "20260827057000", "20260827059000": "20260827058000", "20260827060000": "20260827059000", "20260827061000": "20260827060000", "20260827063000": "20260827061000", "20260827064000": "20260827063000"}[first_missing]
                if max(ledger, default="") != required_head:
                    raise RuntimeError(f"EXACT_{required_head}_PRESTATE_REQUIRED")
                event["would_apply"] = [version for version, _name, _path, _sha in MIGRATIONS if not present[version]]
            else:
                event["already_applied"] = True
        elif args.mode == "apply":
            if not first_missing:
                event["already_applied"] = True
            else:
                required_head = {"20260827058000": "20260827057000", "20260827059000": "20260827058000", "20260827060000": "20260827059000", "20260827061000": "20260827060000", "20260827063000": "20260827061000", "20260827064000": "20260827063000"}[first_missing]
                if max(ledger, default="") != required_head:
                    raise RuntimeError(f"EXACT_{required_head}_PRESTATE_REQUIRED")
                for version, _name, path, _sha in MIGRATIONS:
                    if not present[version]:
                        apply_source(path)
                event["committed"] = True
        after = run_query(READ_STATE_SQL)
        event["after"] = after["rows"][0]["evidence"]
        final_ledger = {item["version"]: item["name"] for item in event["after"]["ledger"]}
        if any(final_ledger.get(version) != name for version, name in expected.items()):
            raise RuntimeError("SUCCESSOR_POSTSTATE_LEDGER_MISMATCH")
        event["ok"] = True
    except Exception as exc:
        event["error"] = str(exc)[:400]
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
