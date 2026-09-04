#!/usr/bin/env python3
"""Apply/read back the PDC-14 location runtime alignment on STAGING only."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from apply_pdc14_staging import management_write, security_advisor_summary
from inspect_pdc14_staging import STAGING_REF, management_query

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260904011100_pdc14_location_replay_runtime_schema_alignment.sql"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260904011100"
EXPECTED_PREDECESSOR = ["20260904011000", "pdc14_location_replay_idempotency"]
EXPECTED_HEAD = ["20260904011100", "pdc14_location_replay_runtime_schema_alignment"]


def inspect() -> dict[str, object]:
    return management_query(
        """
        select jsonb_build_object(
          'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
          'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
          'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
          'old_signature_exists',to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text)') is not null,
          'new_signature_exists',to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text,text)') is not null,
          'fixed_search_path',(select p.proconfig @> array['search_path=pg_catalog, public'] or p.proconfig @> array['search_path=pg_catalog,public'] from pg_proc p where p.oid=to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text,text)')),
          'authenticated_execute',case when to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text,text)') is null then false else has_function_privilege('authenticated','public.set_pdc_vehicle_location_1500(uuid,integer,text,text)','execute') end,
          'anon_denied',case when to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text,text)') is null then false else not has_function_privilege('anon','public.set_pdc_vehicle_location_1500(uuid,integer,text,text)','execute') end,
          'receipt_rls',(select jsonb_build_array(relrowsecurity,relforcerowsecurity) from pg_class where oid=to_regclass('public.pdc_vehicle_location_receipts_20260904')),
          'receipt_public_denied',case when to_regclass('public.pdc_vehicle_location_receipts_20260904') is null then false else not has_table_privilege('authenticated','public.pdc_vehicle_location_receipts_20260904','select') and not has_table_privilege('service_role','public.pdc_vehicle_location_receipts_20260904','select') end,
          'receipt_table_exists',to_regclass('public.pdc_vehicle_location_receipts_20260904') is not null
        ) as inspection
        """
    )[0]["inspection"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inspect", "dry-run", "apply"))
    args = parser.parse_args()
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd" or STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("refusing non-STAGING target")
    sql = MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("migration containment marker failed")
    before = inspect()
    result: dict[str, object] = {"ok": True, "project_ref": STAGING_REF, "mode": args.mode, "before": before, "production_contacted": False, "email_sent": False}
    if before["staging_sentinel_count"] != 1 or before["production_sentinel_present"]:
        raise RuntimeError("STAGING sentinel preflight failed")
    if args.mode == "dry-run":
        if before["head"] != EXPECTED_PREDECESSOR:
            raise RuntimeError(f"dry-run requires exact predecessor, got {before['head']}")
        management_write(sql.rsplit("COMMIT;", 1)[0] + "ROLLBACK;\n")
        result["compiled_and_rolled_back"] = True
    elif args.mode == "apply":
        if os.environ.get(APPROVAL) != "YES":
            raise RuntimeError(f"set {APPROVAL}=YES for this authorized STAGING-only apply")
        if before["head"] == EXPECTED_PREDECESSOR:
            management_write(sql); result["applied"] = True
        elif before["head"] == EXPECTED_HEAD:
            result["applied"] = False; result["idempotent_existing"] = True
        else:
            raise RuntimeError(f"unexpected live head {before['head']}")
    after = inspect(); result["after"] = after
    if args.mode == "dry-run" and after != before:
        raise RuntimeError("dry-run changed live state")
    if args.mode == "apply":
        checks = [after["head"] == EXPECTED_HEAD, not after["old_signature_exists"], after["new_signature_exists"], after["fixed_search_path"], after["authenticated_execute"], after["anon_denied"], after["receipt_rls"] == [True, True], after["receipt_public_denied"]]
        if not all(checks): raise RuntimeError(f"postcondition failed: {after}")
        result["security_advisors"] = security_advisor_summary()
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
