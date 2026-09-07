#!/usr/bin/env python3
"""Dry-run/apply and verify complete-VIN gating on STAGING only."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260907090000_navision_complete_vin_gate.sql"
PREVIOUS_HEAD = ["20260905010200", "archived_snapshot_volatility_repair"]
TARGET_HEAD = ["20260907090000", "navision_complete_vin_gate"]
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260907090000"


def head_state() -> dict[str, object]:
    return management_query("""
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'helper_exists',to_regprocedure('public.pdc_navision_complete_vin_20260907(jsonb)') is not null
) result
""")[0]["result"]


def verification() -> dict[str, object]:
    return management_write("""
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'complete',public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CD1','frame','00000001')),
  'partial_is_null',public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR','vdsNumber','BA3CD1','frame','00000001')) is null,
  'invalid_is_null',public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3$D1','frame','00000001')) is null,
  'i_is_null',public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CDI','frame','00000001')) is null,
  'o_is_null',public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CDO','frame','00000001')) is null,
  'q_is_null',public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CDQ','frame','00000001')) is null,
  'legacy_short_is_null',public.pdc_navision_complete_vin_20260907(jsonb_build_object('vin','REBHV112345678')) is null,
  'normalized_partial',public.navision_backend_normalize_row(jsonb_build_object('wmi','MR','vdsNumber','BA3CD1','frame','00000001','vin','MRBA3CD100000001')),
  'partial_preflight',public.navision_import_candidate_preflight_770(jsonb_build_array(
    jsonb_build_object('id','VIN-GATE-PARTIAL-1','stock','13090001','wmi','MR','vdsNumber','BA3CD1','frame','00000001','vin','MRBA3CD100000001'),
    jsonb_build_object('id','VIN-GATE-PARTIAL-2','stock','13090002','wmi','MR','vdsNumber','BA3CD1','frame','00000001','vin','MRBA3CD100000001')
  ),'microsoft_navision','37047'),
  'duplicate_preflight',public.navision_import_candidate_preflight_770(jsonb_build_array(
    jsonb_build_object('id','VIN-GATE-COMPLETE-1','stock','13090003','wmi','MR0','vdsNumber','BA3CD1','frame','00000001','vin','MR0BA3CD100000001'),
    jsonb_build_object('id','VIN-GATE-COMPLETE-2','stock','13090004','wmi','MR0','vdsNumber','BA3CD1','frame','00000001','vin','MR0BA3CD100000001')
  ),'microsoft_navision','37047'),
  'helper_authenticated_private',not has_function_privilege('authenticated','public.pdc_navision_complete_vin_20260907(jsonb)','execute'),
  'preflight_authenticated_private',not has_function_privilege('authenticated','public.navision_import_candidate_preflight_770(jsonb,text,text)','execute'),
  'preview_authenticated_execute',has_function_privilege('authenticated','public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)','execute'),
  'apply_authenticated_execute',has_function_privilege('authenticated','public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)','execute'),
  'records_rls',(select relrowsecurity from pg_class where oid='public.navision_backend_records'::regclass),
  'items_rls',(select relrowsecurity from pg_class where oid='public.navision_import_items'::regclass),
  'batches_rls',(select relrowsecurity from pg_class where oid='public.navision_import_batches'::regclass)
) result
""")[0]["result"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("dry-run", "apply"))
    args = parser.parse_args()
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("refusing non-STAGING target")
    before = head_state()
    if before["head"] not in (PREVIOUS_HEAD, TARGET_HEAD):
        raise RuntimeError(f"unexpected STAGING head: {before['head']}")
    sql = MIGRATION.read_text(encoding="utf-8")
    if args.mode == "dry-run":
        if before["head"] != PREVIOUS_HEAD:
            raise RuntimeError("dry-run requires predecessor head")
        management_write(sql.rsplit("COMMIT;", 1)[0] + "ROLLBACK;")
        after = head_state()
        if after != before:
            raise RuntimeError(f"dry-run changed state: before={before}, after={after}")
        result = {"ok": True, "mode": args.mode, "before": before, "after": after}
    else:
        if before["head"] == PREVIOUS_HEAD:
            if os.environ.get(APPROVAL) != "YES":
                raise RuntimeError(f"set {APPROVAL}=YES")
            management_write(sql)
        after = head_state()
        proof = verification()
        normalized = proof.get("normalized_partial") or {}
        partial = proof.get("partial_preflight") or {}
        duplicate = proof.get("duplicate_preflight") or {}
        checks = [
            after.get("head") == TARGET_HEAD,
            proof.get("head") == TARGET_HEAD,
            proof.get("staging_sentinel_count") == 1,
            not proof.get("production_sentinel_present"),
            proof.get("complete") == "MR0BA3CD100000001",
            all(proof.get(key) is True for key in ("partial_is_null", "invalid_is_null", "i_is_null", "o_is_null", "q_is_null", "legacy_short_is_null")),
            normalized.get("vin") is None,
            normalized.get("wmi") == "MR" and normalized.get("vdsNumber") == "BA3CD1" and normalized.get("frame") == "00000001",
            partial.get("blocking") is False and partial.get("issue_count") == 0,
            duplicate.get("blocking") is True and duplicate.get("issue_count") == 2,
            all(proof.get(key) is True for key in (
                "helper_authenticated_private", "preflight_authenticated_private",
                "preview_authenticated_execute", "apply_authenticated_execute",
                "records_rls", "items_rls", "batches_rls",
            )),
        ]
        if not all(checks):
            raise RuntimeError(f"STAGING postcondition failed: {proof}")
        result = {"ok": True, "mode": args.mode, "before": before, "after": after, "proof": proof}
    print(json.dumps({"environment": "staging", "project_ref": STAGING_REF, "production_contacted": False, **result}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
