#!/usr/bin/env python3
"""Dry-run, apply, and read back the U158318 classifier on STAGING."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260904010600_u158318_jobcard_classifier.sql"
VERSION = "20260904010600"
NAME = "u158318_jobcard_classifier"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260904010600"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_OPERATIONS = [
    (1, "BUS 4X4 CONVERSION SLWB & COMMUTER 05C2B", "bus4x4"),
    (2, "Bus 4x4 Conversion 5x BFG 265/65R17 Tyres and Rims", "tyre"),
    (3, "BUS 4X4 Tanami Snorkel", "bus4x4"),
    (4, "Hiace Rock Sliders", "fitting"),
    (5, "MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON -ACOT500", "electrical"),
    (6, "BATTERY ISOLATOR WITH RED LOCKOUT", "electrical"),
    (7, "175 AMP JUMP START UNDER BONNET", "electrical"),
    (8, "Headlamps Auto On & Hand Brake OFF Alarm -DYNAMCO", "electrical"),
    (9, "MMT COMMUTER SEAT COVERS -CANVAS", "fitting"),
    (10, "MOUNTED WHEEL CHOCKS AND HOLDER", "fitting"),
    (11, "SAFETY TRIANGLE IN PMB HOLDER", "fitting"),
    (12, "WHEEL NUT INDICATORS -COMMUTER", "tyre"),
    (13, "UHF GME XRS370C WITH AE4704B AERIAL", "electrical"),
    (14, "SUB REFLECTIVE STRIPING YELLOW", "sublet"),
    (15, "Darkest Legal Tint Commuter van", "tint"),
    (16, 'NARVA (72843) 20" EX2-R LIGHT BAR RGB DOUBLE RGB ENABLED', "electrical"),
    (17, "POST REGO CONVERSION", "bus4x4"),
    (18, "2.5KG FIRE EXTINGUISHER", "fabrication"),
]


def inspect() -> dict[str, object]:
    def sql_literal(value: str) -> str:
        return "'" + value.replace("'", "''") + "'"

    values = ",\n".join(
        f"({number},{sql_literal(description)}::text,{sql_literal(expected)}::text)"
        for number, description, expected in EXPECTED_OPERATIONS
    )
    sql = f"""
    with expected(operation_no,description,expected) as (values {values}),
    classified as (
      select operation_no,description,expected,public.pdc_email_jobcard_work_key(description) deployed
      from expected
    ), defs as (
      select pg_get_functiondef('public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)'::regprocedure) outer_def,
             pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure) inner_def
    )
    select jsonb_build_object(
      'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
      'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
      'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
      'classifications',(select jsonb_agg(jsonb_build_object('operation_no',operation_no,'description',description,'expected',expected,'deployed',deployed,'matches',expected=deployed) order by operation_no) from classified),
      'standalone_mine_bar',public.pdc_email_jobcard_work_key('MINE BAR'),
      'explicit_fab_mine_bar',public.pdc_email_jobcard_work_key('!FAB MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON'),
      'bedrock_sliders',public.pdc_email_jobcard_work_key('Bedrock Sliders'),
      'unknown',public.pdc_email_jobcard_work_key('Unmapped bespoke instruction'),
      'zero_value',public.pdc_email_safe_nonnegative_numeric_20260904('0.00'::jsonb,999.99),
      'missing_value',public.pdc_email_safe_nonnegative_numeric_20260904('null'::jsonb,999.99),
      'mapping_review_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.pdc_non_navision_mapping_reviews_20260904'::regclass),
      'mapping_review_authenticated_select',has_table_privilege('authenticated','public.pdc_non_navision_mapping_reviews_20260904','select'),
      'function_acl',jsonb_build_object(
        'outer_authenticated',has_function_privilege('authenticated','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute'),
        'outer_anon',has_function_privilege('anon','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute'),
        'outer_service_role',has_function_privilege('service_role','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute'),
        'inner_authenticated',has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')),
      'immutable_operation_trigger',exists(select 1 from pg_trigger where tgname='pdc_non_navision_operation_lines_immutable' and tgenabled='O'),
      'pit_planner_enabled',(select planner_enabled from public.workshop_stages where code='PIT_INSPECTION'),
      'outer_209_guard',position('pdc.recreation_source_hash' in outer_def)>0 and position('pdc_process_non_navision_jobcard_pre209' in outer_def)>0,
      'inner_contract',jsonb_build_object(
        'yh_creation',position(E'''active'',true,''YH'',null,''authenticated_email''' in inner_def)>0,
        'unknown_review',position('pdc_non_navision_mapping_reviews_20260904' in inner_def)>0,
        'no_booking',position(E'booking_created'',false' in inner_def)>0,
        'no_completion',position(E'completion_created'',false' in inner_def)>0)
    ) proof from defs
    """
    # The classifier is intentionally private. Use the postgres management
    # channel for exact execution without weakening its ACL for read-back.
    return management_write(sql)[0]["proof"]


def verify(proof: dict[str, object]) -> None:
    classifications = proof["classifications"]
    checks = [
        proof["project_ref"] == EXPECTED_REF,
        proof["head"] == [VERSION, NAME],
        proof["production_sentinel_present"] is False,
        isinstance(classifications, list) and len(classifications) == 18,
        isinstance(classifications, list) and all(row["matches"] is True for row in classifications),
        proof["standalone_mine_bar"] == "fabrication",
        proof["explicit_fab_mine_bar"] == "fabrication",
        proof["bedrock_sliders"] == "owner_supplied_document",
        proof["unknown"] == "owner_supplied_document",
        proof["zero_value"] == 0,
        proof["missing_value"] is None,
        proof["mapping_review_rls"] == [True, True],
        proof["mapping_review_authenticated_select"] is False,
        proof["function_acl"] == {"outer_authenticated": True, "outer_anon": False, "outer_service_role": False, "inner_authenticated": False},
        proof["immutable_operation_trigger"] is True,
        proof["pit_planner_enabled"] is False,
        proof["outer_209_guard"] is True,
        all(proof["inner_contract"].values()),
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
        "email_contacted": False,
        "email_sent": False,
    }
    if before["project_ref"] != EXPECTED_REF or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")

    if args.mode == "dry-run":
        if before["head"] != ["20260904010500", "non_navision_jobcard_current_contract"]:
            raise RuntimeError(f"dry-run requires exact predecessor, got {before['head']}")
        sql = MIGRATION.read_text(encoding="utf-8")
        if not sql.rstrip().endswith("COMMIT;"):
            raise RuntimeError("migration transaction boundary missing")
        management_write(sql.rstrip()[:-len("COMMIT;")] + "ROLLBACK;")
        after = inspect()
        if after != before:
            raise RuntimeError("dry-run changed live STAGING state")
        result["dry_run_compiled_and_rolled_back"] = True
        result["after"] = after
    elif args.mode == "apply":
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for authorized STAGING apply")
        if before["head"] == ["20260904010500", "non_navision_jobcard_current_contract"]:
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
        evidence = ROOT / "review-evidence/t_6967aa42-staging-apply-proof.json"
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
