#!/usr/bin/env python3
"""Apply the cleanup-evidence parity successor to STAGING only."""
from __future__ import annotations
import argparse, json, os
from pathlib import Path
from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF, management_query
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/"supabase/staging_only/20260905010100_navision_projection_cleanup_evidence_parity.sql"
PRE=["20260905010000","navision_linked_location_projection"]
HEAD=["20260905010100","navision_projection_cleanup_evidence_parity"]

def state():
    return management_query("""select jsonb_build_object(
      'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
      'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
      'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
      'parity_object_constraint',(select count(*) from pg_constraint where conrelid='public.pdc_navision_projection_cleanup_history_20260905'::regclass and conname='pdc_navision_projection_cleanup_history_20260905_parity_object_check'),
      'old_parity_constraint',(select count(*) from pg_constraint where conrelid='public.pdc_navision_projection_cleanup_history_20260905'::regclass and conname='pdc_navision_projection_cleanup_history_20260905_parity_check')) result""")[0]["result"]

def main():
    p=argparse.ArgumentParser(); p.add_argument("mode",choices=("dry-run","apply")); a=p.parse_args()
    if STAGING_REF!="cdsmnqxtyyoeoznmbidd": raise RuntimeError("refusing non-STAGING target")
    before=state(); sql=MIGRATION.read_text(encoding="utf-8")
    if before["head"]==PRE:
        if a.mode=="apply" and os.environ.get("PDC_APPROVE_STAGING_MIGRATION_20260905010100")!="YES": raise RuntimeError("approval missing")
        management_write(sql.rsplit("COMMIT;",1)[0]+("ROLLBACK;" if a.mode=="dry-run" else "COMMIT;"))
    elif not (a.mode=="apply" and before["head"]==HEAD): raise RuntimeError(f"unexpected head {before['head']}")
    after=state()
    if a.mode=="dry-run" and after!=before: raise RuntimeError("dry-run changed state")
    if a.mode=="apply" and not (after["head"]==HEAD and after["parity_object_constraint"]==1 and after["old_parity_constraint"]==0): raise RuntimeError(f"postcondition failed {after}")
    print(json.dumps({"ok":True,"project_ref":STAGING_REF,"mode":a.mode,"before":before,"after":after,"production_contacted":False},indent=2))
    return 0
if __name__=="__main__": raise SystemExit(main())
