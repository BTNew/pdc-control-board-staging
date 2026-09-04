#!/usr/bin/env python3
"""Dry-run, apply and verify the archived snapshot repair on STAGING only."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260905010200_archived_snapshot_volatility_repair.sql"
PREVIOUS_HEAD = ["20260905010100", "navision_projection_cleanup_evidence_parity"]
REPAIRED_HEAD = ["20260905010200", "archived_snapshot_volatility_repair"]
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260905010200"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"


def state() -> dict[str, object]:
    row = management_query("""
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'provolatile',(select provolatile from pg_proc where oid=to_regprocedure('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)')),
  'authenticated_execute',has_function_privilege('authenticated','public.pdc_admin_archived_vehicle_snapshot(uuid,integer)','execute'),
  'anon_execute',has_function_privilege('anon','public.pdc_admin_archived_vehicle_snapshot(uuid,integer)','execute'),
  'service_role_execute',has_function_privilege('service_role','public.pdc_admin_archived_vehicle_snapshot(uuid,integer)','execute'),
  'function_definition',pg_get_functiondef('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)'::regprocedure)
) result
""")[0]["result"]
    row["function_definition"] = {
        "uses_lifecycle_wrapper": "pdc_lifecycle_history_payload_82000" in row["function_definition"],
        "uses_pre_82000_snapshot": "pdc_admin_archived_vehicle_snapshot_pre_82000" in row["function_definition"],
    }
    return row


def authenticated_probe() -> dict[str, object]:
    rows = management_write("""
begin;
set local statement_timeout='60s';
with actor as (
  select auth_user_id,email from public.pdc_user_roles
  where role='administrator' and active and account_status='approved' and auth_user_id is not null
  order by updated_at desc limit 1
), claims as (
  select set_config('request.jwt.claims',jsonb_build_object('sub',auth_user_id,'role','authenticated','email',email)::text,true) from actor
)
select jsonb_build_object(
  'actor_kind','approved_staging_administrator',
  'ok',coalesce((result->>'ok')::boolean,false),
  'code',result->>'code',
  'item_count',jsonb_array_length(coalesce(result#>'{data,items}','[]'::jsonb))
) probe
from claims cross join lateral public.pdc_admin_archived_vehicle_snapshot(null,1) result;
rollback;
""")
    return rows[0]["probe"] if rows else {"ok": False, "code": "no_approved_staging_administrator"}


def validate_target(source: str) -> None:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or PRODUCTION_REF in source:
        raise RuntimeError("refusing non-STAGING migration target")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("dry-run", "apply", "verify"))
    parser.add_argument("--output")
    args = parser.parse_args()
    source = MIGRATION.read_text(encoding="utf-8")
    validate_target(source)
    before = state()
    if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
        raise RuntimeError(f"STAGING sentinel preflight failed: {before}")

    if args.mode == "dry-run":
        if before["head"] != PREVIOUS_HEAD:
            raise RuntimeError(f"unexpected dry-run head: {before['head']}")
        management_write(source.rsplit("COMMIT;", 1)[0] + "ROLLBACK;")
    elif args.mode == "apply":
        if before["head"] == PREVIOUS_HEAD:
            if os.environ.get(APPROVAL) != "YES":
                raise RuntimeError(f"set {APPROVAL}=YES for this STAGING-only migration")
            management_write(source)
        elif before["head"] != REPAIRED_HEAD:
            raise RuntimeError(f"unexpected apply head: {before['head']}")
    elif before["head"] != REPAIRED_HEAD:
        raise RuntimeError(f"repair is not applied: {before['head']}")

    after = state()
    if args.mode == "dry-run":
        if after != before:
            raise RuntimeError("dry-run changed persistent STAGING state")
        probe = {"skipped": "repair intentionally rolled back"}
    else:
        if not (
            after["head"] == REPAIRED_HEAD
            and after["provolatile"] == "v"
            and after["authenticated_execute"] is True
            and after["anon_execute"] is False
            and after["service_role_execute"] is False
            and after["function_definition"]["uses_lifecycle_wrapper"]
            and after["function_definition"]["uses_pre_82000_snapshot"]
        ):
            raise RuntimeError(f"repair postcondition failed: {after}")
        probe = authenticated_probe()
        if not probe.get("ok"):
            raise RuntimeError(f"authenticated archived snapshot probe failed: {probe}")

    result = {
        "ok": True,
        "mode": args.mode,
        "project_ref": STAGING_REF,
        "before": before,
        "after": after,
        "authenticated_probe": probe,
        "production_contacted": False,
        "production_mutated": False,
    }
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        path = Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
