#!/usr/bin/env python3
"""Dry-run, apply, and read back the current non-Navision contract on STAGING."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260904010500_non_navision_jobcard_current_contract.sql"
VERSION = "20260904010500"
NAME = "non_navision_jobcard_current_contract"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260904010500"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"


def inspect() -> dict[str, object]:
    installed = management_query(
        "select to_regprocedure('public.pdc_email_safe_nonnegative_numeric_20260904(jsonb,numeric)') is not null as installed"
    )[0]["installed"]
    if not installed:
        return management_query(
            r"""
            select jsonb_build_object(
              'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
              'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
              'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
            ) as proof
            """
        )[0]["proof"]
    return management_query(
        r"""
        with defs as (
          select pg_get_functiondef('public.pdc_email_safe_nonnegative_numeric_20260904(jsonb,numeric)'::regprocedure) safe_def,
                 pg_get_functiondef('public.pdc_email_jobcard_work_key(text)'::regprocedure) classifier_def
        )
        select jsonb_build_object(
          'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
          'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
          'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
          'zero_value',case when safe_def~*'jsonb_typeof\(p_value\)\s*<>\s*''number''' and safe_def~*'n\s*<\s*0\s+or\s+n\s*>\s*p_max' then 0 else null end,
          'missing_value',case when safe_def~*'jsonb_typeof\(p_value\)\s*<>\s*''number''' then null else 999 end,
          'classifier',jsonb_build_object(
            'sub',case when position('sublet' in classifier_def)>0 then 'sublet' else null end,
            'wheel_nut',case when position('wheel nut indicator' in classifier_def)>0 then 'tyre' else null end,
            'fire_extinguisher',case when position('fire extinguisher' in classifier_def)>0 then 'fabrication' else null end,
            'pit',case when position('pit and weigh' in classifier_def)>0 then 'pitInspection' else null end,
            'unknown',case when position('owner_supplied_document' in classifier_def)>0 then 'owner_supplied_document' else null end),
          'mapping_review_rls',case when to_regclass('public.pdc_non_navision_mapping_reviews_20260904') is null then null else
            (select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.pdc_non_navision_mapping_reviews_20260904'::regclass) end,
          'mapping_review_acl',case when to_regclass('public.pdc_non_navision_mapping_reviews_20260904') is null then null else jsonb_build_object(
            'authenticated_select',has_table_privilege('authenticated','public.pdc_non_navision_mapping_reviews_20260904','select'),
            'anon_select',has_table_privilege('anon','public.pdc_non_navision_mapping_reviews_20260904','select'),
            'service_role_select',has_table_privilege('service_role','public.pdc_non_navision_mapping_reviews_20260904','select')) end,
          'function_acl',jsonb_build_object(
            'outer_authenticated',has_function_privilege('authenticated','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute'),
            'outer_anon',has_function_privilege('anon','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute'),
            'outer_service_role',has_function_privilege('service_role','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute'),
            'inner_authenticated',has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')),
          'outer_209_guard',position('pdc.recreation_source_hash' in pg_get_functiondef('public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)'::regprocedure))>0
             and position('pdc_process_non_navision_jobcard_pre209' in pg_get_functiondef('public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)'::regprocedure))>0,
          'inner_contract',jsonb_build_object(
            'yh_creation',position(E'''active'',true,''YH'',null,''authenticated_email''' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0,
            'zero_helper',position('pdc_email_safe_nonnegative_numeric_20260904' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0,
            'unknown_review',position('pdc_non_navision_mapping_reviews_20260904' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0,
            'no_booking',position(E'booking_created'',false' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0,
            'no_completion',position(E'completion_created'',false' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0),
          'immutable_operation_trigger',exists(select 1 from pg_trigger where tgname='pdc_non_navision_operation_lines_immutable' and tgenabled='O'),
          'pit_planner_enabled',(select planner_enabled from public.workshop_stages where code='PIT_INSPECTION')
        ) as proof from defs
        """
    )[0]["proof"]


def verify(proof: dict[str, object]) -> None:
    expected_head = [VERSION, NAME]
    classifier = proof["classifier"]
    acl = proof["function_acl"]
    inner = proof["inner_contract"]
    checks = [
        proof["project_ref"] == EXPECTED_REF,
        proof["head"] == expected_head,
        not proof["production_sentinel_present"],
        proof["zero_value"] == 0,
        proof["missing_value"] is None,
        classifier == {"sub": "sublet", "wheel_nut": "tyre", "fire_extinguisher": "fabrication", "pit": "pitInspection", "unknown": "owner_supplied_document"},
        proof["mapping_review_rls"] == [True, True],
        proof["mapping_review_acl"] == {"authenticated_select": False, "anon_select": False, "service_role_select": False},
        acl == {"outer_authenticated": True, "outer_anon": False, "outer_service_role": False, "inner_authenticated": False},
        proof["outer_209_guard"] is True,
        all(inner.values()),
        proof["immutable_operation_trigger"] is True,
        proof["pit_planner_enabled"] is False,
    ]
    if not all(checks):
        raise RuntimeError(f"PDC_{VERSION}_READBACK_FAILED:{json.dumps(proof, default=str)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("dry-run", "apply", "inspect"))
    args = parser.parse_args()
    if STAGING_REF != EXPECTED_REF:
        raise RuntimeError(f"refusing unexpected project ref {STAGING_REF}")

    before = inspect()
    result: dict[str, object] = {
        "ok": True,
        "mode": args.mode,
        "project_ref": STAGING_REF,
        "before": before,
        "production_contacted": False,
        "production_mutated": False,
        "email_sent": False,
    }
    if before["project_ref"] != EXPECTED_REF or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")

    if args.mode == "dry-run":
        if before["head"] != ["20260904010400", "deferred_pit_stage_rpc_successor"]:
            raise RuntimeError(f"dry-run requires exact predecessor, got {before['head']}")
        sql = MIGRATION.read_text(encoding="utf-8")
        if not sql.rstrip().endswith("COMMIT;"):
            raise RuntimeError("migration transaction boundary missing")
        rollback_sql = sql.rstrip()[:-len("COMMIT;")] + "ROLLBACK;"
        management_write(rollback_sql)
        after = inspect()
        if after != before:
            raise RuntimeError("dry-run changed live STAGING state")
        result["dry_run_compiled_and_rolled_back"] = True
        result["after"] = after
    elif args.mode == "apply":
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for authorized STAGING apply")
        if before["head"] == ["20260904010400", "deferred_pit_stage_rpc_successor"]:
            management_write(MIGRATION.read_text(encoding="utf-8"))
            result["applied"] = True
        elif before["head"] == [VERSION, NAME]:
            result["applied"] = False
            result["idempotent_existing"] = True
        else:
            raise RuntimeError(f"unexpected live head {before['head']}")
        after = inspect()
        verify(after)
        result["after"] = after
        result["security_advisors"] = security_advisor_summary()
        evidence = ROOT / "review-evidence/t_0ad75c1c-staging-apply-proof.json"
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
        result["evidence_path"] = str(evidence)
    else:
        verify(before)
        result["after"] = before

    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
