#!/usr/bin/env python3
"""Dry-run/apply/read back the t_780b25d4 STAGING-only migration."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260908103000_jobcard_hours_live_repair.sql"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
APPROVAL = "PDC_APPROVE_T780_JOB_CARD_HOURS_STAGING"


def management_write(sql: str):
    request = Request(
        f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query",
        data=json.dumps({"query": sql, "read_only": False}, separators=(",", ":")).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {supabase_access_token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "SupabaseCLI/2.75.0",
        },
    )
    try:
        with urlopen(request, timeout=180) as response:
            body = response.read().decode()
            return json.loads(body) if body else []
    except HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"STAGING migration request failed ({error.code}): {detail}") from error


def readback() -> dict:
    return management_query("""
      select jsonb_build_object(
        'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
        'migration_count',(select count(*) from supabase_migrations.schema_migrations where version='20260908103000'),
        'function_has_pilbara',position('pdc_pilbara_service_operations' in pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure))>0,
        'function_has_unknown',position('manual_operator_unknown' in pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure))>0,
        'base_authenticated_execute',has_function_privilege('authenticated','public.get_vehicle_workshop_detail(uuid)','execute'),
        'scoped_authenticated_execute',has_function_privilege('authenticated','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute'),
        'scoped_anon_execute',has_function_privilege('anon','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute'),
        'scoped_service_execute',has_function_privilege('service_role','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute'),
        'authenticated_execute',has_function_privilege('authenticated','public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','execute'),
        'anon_execute',has_function_privilege('anon','public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','execute'),
        'service_execute',has_function_privilege('service_role','public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','execute'),
        'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null
      ) evidence
    """)[0]["evidence"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.dry_run == args.apply:
        raise RuntimeError("choose exactly one of --dry-run or --apply")
    sql = MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("non-STAGING migration refused")
    before = readback()
    if args.dry_run:
        if not sql.rstrip().endswith("COMMIT;"):
            raise RuntimeError("migration transaction terminator drift")
        management_write(sql.rstrip()[:-len("COMMIT;")] + "ROLLBACK;\n")
        after = readback()
        if before != after:
            raise RuntimeError("dry-run changed persistent STAGING state")
        result = {"ok": True, "mode": "dry-run", "before": before, "after": after}
    else:
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for STAGING apply")
        management_write(sql)
        after = readback()
        if (after.get("head") != ["20260908103000", "jobcard_hours_live_repair"]
                or after.get("migration_count") != 1
                or after.get("base_authenticated_execute") is not False
                or after.get("scoped_authenticated_execute") is not True
                or after.get("scoped_anon_execute") is not False
                or after.get("scoped_service_execute") is not False):
            raise RuntimeError(f"STAGING readback failed: {after}")
        result = {"ok": True, "mode": "apply", "before": before, "after": after}
    result.update({"project_ref": STAGING_REF, "production_contacted": False, "production_writes": False})
    out = ROOT / "review-evidence" / "t_780b25d4" / f"migration-{result['mode']}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
