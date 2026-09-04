#!/usr/bin/env python3
"""Dry-run, apply and inspect the audited non-Navision VIN projection on STAGING."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260904010800_non_navision_jobcard_vin_projection.sql"
REGRESSION = ROOT / "tests/test_non_navision_vin_projection_20260904_live.sql"
VERSION = "20260904010800"
NAME = "non_navision_jobcard_vin_projection"
PREDECESSOR = ["20260904010700", "deferred_pit_qc_finalization"]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260904010800"
PROJECTION_APPROVAL = "PDC_APPROVE_U158318_VIN_PROJECTION_20260904"
TARGET = "e49685ca-c9b7-448d-9b45-1aba97d6d3b4"
SOURCE_RECEIPT = "5d4f30f7-561c-4998-a68d-7dfd5e188fe1"
SOURCE_HASH = "7e7d24755e4856f0d7fe22086b6b84842874c0474fe60a2f9e754fe088fcbc95"
VIN = "JTFHB8CP806024409"
EXPECTED_TARGET_VERSION = 2
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
IDEMPOTENCY = "6e32736d-e774-5d66-b2c7-35261c6f02ec"


def inspect() -> dict[str, object]:
    installed = management_query(
        "select to_regprocedure('public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)') is not null installed"
    )[0]["installed"]
    base = management_query(
        f"""
        select jsonb_build_object(
          'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
          'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version::bigint desc limit 1),
          'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
          'vehicle',(select jsonb_build_object('id',id,'version',version,'stock_number',stock_number,'vin',vin,'job_card_number',job_card_number,
             'registration',registration,'customer_name',customer_name,'current_location',current_location,'lifecycle_state',lifecycle_state,
             'visible_on_board',visible_on_board,'source_payload',source_payload) from public.vehicles where id='{TARGET}'::uuid),
          'source_receipt_count',(select count(*) from public.pdc_non_navision_jobcard_receipts where receipt_id='{SOURCE_RECEIPT}'::uuid and vehicle_id='{TARGET}'::uuid and source_hash='{SOURCE_HASH}'),
          'installed',{str(installed).lower()}
        ) proof
        """
    )[0]["proof"]
    if not installed:
        return base
    extra = management_query(
        f"""
        select jsonb_build_object(
          'receipt_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.pdc_non_navision_vin_projection_receipts_20260904'::regclass),
          'receipt_count',(select count(*) from public.pdc_non_navision_vin_projection_receipts_20260904 where vehicle_id='{TARGET}'::uuid),
          'receipt',(select jsonb_build_object('receipt_id',receipt_id,'vehicle_id',vehicle_id,'source_receipt_id',source_receipt_id,'source_hash',source_hash,
             'expected_vehicle_version',expected_vehicle_version,'vehicle_version_before',vehicle_version_before,'vehicle_version_after',vehicle_version_after,
             'vin_before',vin_before,'vin_after',vin_after,'source_provenance',source_provenance,'effective_provenance',effective_provenance,
             'idempotency_key',idempotency_key,'request_sha256',request_sha256,'response',response) from public.pdc_non_navision_vin_projection_receipts_20260904 where vehicle_id='{TARGET}'::uuid order by created_at desc limit 1),
          'acl',jsonb_build_object(
             'authenticated_execute',has_function_privilege('authenticated','public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)','execute'),
             'anon_execute',has_function_privilege('anon','public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)','execute'),
             'service_execute',has_function_privilege('service_role','public.project_pdc_non_navision_jobcard_vin_20260904(uuid,integer,uuid,text,text,uuid)','execute'),
             'authenticated_table_select',has_table_privilege('authenticated','public.pdc_non_navision_vin_projection_receipts_20260904','select'),
             'inner_authenticated',has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')),
          'contracts',jsonb_build_object(
             'processor_vin_attribute',position('authenticated_source_vin' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0,
             'processor_collision',position('non_navision_vin_collision' in pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure))>0,
             'reader_vin',position(E'''source_vin''' in pg_get_functiondef('public.read_pdc_non_navision_jobcard_receipt(uuid)'::regprocedure))>0),
          'immutable_trigger',exists(select 1 from pg_trigger where tgname='pdc_non_navision_vin_projection_receipts_immutable_20260904' and tgenabled='O')
        ) proof
        """
    )[0]["proof"]
    return {**base, **extra}


def claims_sql() -> str:
    claims = json.dumps({"sub": ACTOR_ID, "email": ACTOR_EMAIL, "role": "authenticated"}, separators=(",", ":"))
    escaped_claims = claims.replace("'", "''")
    return f"select set_config('request.jwt.claims','{escaped_claims}',true);"


def verify(proof: dict[str, object], *, projected: bool) -> None:
    expected_head = [VERSION, NAME]
    checks = [
        proof["project_ref"] == EXPECTED_REF,
        proof["head"] == expected_head,
        not proof["production_sentinel_present"],
        proof["installed"] is True,
        proof["source_receipt_count"] == 1,
        proof["receipt_rls"] == [True, True],
        proof["acl"] == {
            "authenticated_execute": True,
            "anon_execute": False,
            "service_execute": False,
            "authenticated_table_select": False,
            "inner_authenticated": False,
        },
        all(proof["contracts"].values()),
        proof["immutable_trigger"] is True,
    ]
    if projected:
        receipt = proof["receipt"] or {}
        vehicle = proof["vehicle"] or {}
        checks.extend([
            vehicle.get("id") == TARGET,
            vehicle.get("version") == EXPECTED_TARGET_VERSION + 1,
            vehicle.get("stock_number") == "U158318",
            vehicle.get("vin") == VIN,
            vehicle.get("job_card_number") == "J138000812",
            vehicle.get("registration") == "1HJX697",
            vehicle.get("customer_name") == "CATALYST METALS PTY LTD",
            vehicle.get("current_location") == "YH",
            vehicle.get("lifecycle_state") == "active",
            vehicle.get("visible_on_board") is True,
            proof["receipt_count"] == 1,
            receipt.get("vin_after") == VIN,
            receipt.get("source_receipt_id") == SOURCE_RECEIPT,
            receipt.get("source_hash") == SOURCE_HASH,
            receipt.get("expected_vehicle_version") == EXPECTED_TARGET_VERSION,
            receipt.get("vehicle_version_before") == EXPECTED_TARGET_VERSION,
            receipt.get("vehicle_version_after") == EXPECTED_TARGET_VERSION + 1,
            (receipt.get("source_provenance") or {}).get("source_receipt_id") == SOURCE_RECEIPT,
            ((receipt.get("effective_provenance") or {}).get("vin") or {}).get("value") == VIN,
            ((receipt.get("effective_provenance") or {}).get("vin") or {}).get("source_receipt_id") == SOURCE_RECEIPT,
            receipt.get("idempotency_key") == IDEMPOTENCY,
        ])
    else:
        vehicle = proof["vehicle"] or {}
        checks.extend([
            vehicle.get("id") == TARGET,
            vehicle.get("version") == EXPECTED_TARGET_VERSION,
            vehicle.get("stock_number") == "U158318",
            vehicle.get("vin") is None,
            vehicle.get("job_card_number") == "J138000812",
            vehicle.get("registration") == "1HJX697",
            vehicle.get("customer_name") == "CATALYST METALS PTY LTD",
            vehicle.get("current_location") == "YH",
            vehicle.get("lifecycle_state") == "active",
            vehicle.get("visible_on_board") is True,
            proof["receipt_count"] == 0,
        ])
    if not all(checks):
        raise RuntimeError(f"PDC_{VERSION}_READBACK_FAILED:{json.dumps(proof, default=str)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("dry-run", "regression", "apply", "inspect", "project-u158318"))
    args = parser.parse_args()
    if STAGING_REF != EXPECTED_REF:
        raise RuntimeError(f"refusing unexpected project ref {STAGING_REF}")
    before = inspect()
    if before["project_ref"] != EXPECTED_REF or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")
    result: dict[str, object] = {
        "ok": True, "mode": args.mode, "project_ref": STAGING_REF, "before": before,
        "production_contacted": False, "production_mutated": False, "email_sent": False,
        "gmail_mutated": False, "lifecycle_mutated": False, "work_mutated": False,
        "booking_mutated": False, "completion_mutated": False,
    }
    sql = MIGRATION.read_text(encoding="utf-8")
    if EXPECTED_REF not in sql or "vjdtsswhroyguxyfjdkt" in sql or not sql.rstrip().endswith("COMMIT;"):
        raise RuntimeError("migration containment or transaction boundary invalid")
    if args.mode == "dry-run":
        if before["head"] != PREDECESSOR:
            raise RuntimeError(f"dry-run requires exact predecessor, got {before['head']}")
        management_write(sql.rstrip()[:-len("COMMIT;")] + "ROLLBACK;")
        after = inspect()
        if after != before:
            raise RuntimeError("dry-run changed STAGING state")
        result["dry_run_compiled_and_rolled_back"] = True
        result["after"] = after
    elif args.mode == "regression":
        if before["head"] != PREDECESSOR:
            raise RuntimeError(f"regression requires exact predecessor, got {before['head']}")
        migration_body = sql.rstrip()[:-len("COMMIT;")]
        regression_sql = REGRESSION.read_text(encoding="utf-8")
        management_write(migration_body + regression_sql + "\nROLLBACK;")
        after = inspect()
        if after != before:
            raise RuntimeError("regression transaction changed STAGING state")
        result["sql_regressions_passed_and_rolled_back"] = True
        result["after"] = after
    elif args.mode == "apply":
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for authorized STAGING apply")
        if before["head"] == PREDECESSOR:
            management_write(sql)
            result["applied"] = True
        elif before["head"] == [VERSION, NAME]:
            result["applied"] = False
            result["idempotent_existing"] = True
        else:
            raise RuntimeError(f"unexpected live head {before['head']}")
        after = inspect()
        verify(after, projected=after["vehicle"]["vin"] == VIN)
        result["after"] = after
        result["security_advisors"] = security_advisor_summary()
    elif args.mode == "project-u158318":
        if os.environ.get(PROJECTION_APPROVAL) != "YES":
            raise RuntimeError(f"set {PROJECTION_APPROVAL}=YES for authorized U158318 projection")
        if before["vehicle"]["vin"] is None:
            verify(before, projected=False)
            rows = management_write(
                "BEGIN;" + claims_sql() +
                f"select public.project_pdc_non_navision_jobcard_vin_20260904('{TARGET}'::uuid,{EXPECTED_TARGET_VERSION},'{SOURCE_RECEIPT}'::uuid,'{SOURCE_HASH}','{VIN}','{IDEMPOTENCY}'::uuid) result;COMMIT;"
            )
            result["action"] = rows[-1]["result"] if rows else None
        elif before["vehicle"]["vin"] != VIN:
            raise RuntimeError(f"target already has a different VIN: {before['vehicle']['vin']}")
        else:
            verify(before, projected=True)
            result["already_projected"] = True
        after = inspect()
        verify(after, projected=True)
        result["after"] = after
    else:
        verify(before, projected=before["vehicle"]["vin"] == VIN)
        result["after"] = before
    evidence = ROOT / f"review-evidence/t_a19108a5/{args.mode}.json"
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
    result["evidence_path"] = str(evidence)
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
