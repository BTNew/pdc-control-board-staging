#!/usr/bin/env python3
"""Dry-run or apply the bounded PDC-14 synthetic-user helper on STAGING."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903200000_pdc14_synthetic_operator_verification_helper.sql"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260903200000"


def inspect() -> dict[str, object]:
    return management_query(
        """
        select jsonb_build_object(
          'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
          'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
          'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
          'apply_exists',exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='apply_pdc14_staging_test_operator_role' and p.pronargs=0),
          'rollback_exists',exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='rollback_pdc14_staging_test_operator_role' and p.pronargs=1),
          'apply_owner_only',case when exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='apply_pdc14_staging_test_operator_role' and p.pronargs=0) then
            not has_function_privilege('authenticated','public.apply_pdc14_staging_test_operator_role()','execute')
            and not has_function_privilege('anon','public.apply_pdc14_staging_test_operator_role()','execute')
            and not has_function_privilege('service_role','public.apply_pdc14_staging_test_operator_role()','execute') else true end,
          'rollback_owner_only',case when exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='rollback_pdc14_staging_test_operator_role' and p.pronargs=1) then
            not has_function_privilege('authenticated','public.rollback_pdc14_staging_test_operator_role(text)','execute')
            and not has_function_privilege('anon','public.rollback_pdc14_staging_test_operator_role(text)','execute')
            and not has_function_privilege('service_role','public.rollback_pdc14_staging_test_operator_role(text)','execute') else true end,
          'history_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid='public.pdc14_parts_coordinator_role_history'::regclass),
          'synthetic_auth_count',(select count(*) from auth.users where lower(email)='functional.pdc.staging@example.com'),
          'synthetic_role_count',(select count(*) from public.pdc_user_roles where lower(email)='functional.pdc.staging@example.com')
        ) as inspection
        """
    )[0]["inspection"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("dry-run", "apply", "inspect"))
    args = parser.parse_args()
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")

    before = inspect()
    result: dict[str, object] = {
        "project_ref": STAGING_REF,
        "mode": args.mode,
        "before": before,
        "production_contacted": False,
        "email_sent": False,
    }
    if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")

    if args.mode in {"dry-run", "apply"}:
        sql = MIGRATION.read_text(encoding="utf-8")
        if STAGING_REF not in sql or PRODUCTION_REF in sql:
            raise RuntimeError("migration target guard failed")
        if args.mode == "dry-run":
            if before["head"] != ["20260903190000", "pdc14_role_replay_rollback_hardening"]:
                raise RuntimeError(f"dry-run requires exact predecessor, got {before['head']}")
            management_write("BEGIN;\n" + sql + "\nROLLBACK;")
            result["dry_run_compiled_and_rolled_back"] = True
        else:
            if os.environ.get(APPROVAL) != "YES":
                raise RuntimeError(f"set {APPROVAL}=YES for this authorized STAGING-only apply")
            if before["head"] == ["20260903190000", "pdc14_role_replay_rollback_hardening"]:
                management_write(sql)
                result["applied"] = True
            elif before["head"] == ["20260903200000", "pdc14_synthetic_operator_verification_helper"]:
                result["applied"] = False
                result["idempotent_existing"] = True
            else:
                raise RuntimeError(f"unexpected live head {before['head']}")

    after = inspect()
    result["after"] = after
    if args.mode == "dry-run" and after != before:
        raise RuntimeError("dry-run changed live state")
    if args.mode == "apply":
        expected = ["20260903200000", "pdc14_synthetic_operator_verification_helper"]
        checks = [
            after["head"] == expected,
            after["apply_exists"],
            after["rollback_exists"],
            after["apply_owner_only"],
            after["rollback_owner_only"],
            after["history_rls"] == [True, True],
            after["synthetic_auth_count"] == 0,
            after["synthetic_role_count"] == 0,
        ]
        if not all(checks):
            raise RuntimeError(f"postcondition failed: {after}")
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
