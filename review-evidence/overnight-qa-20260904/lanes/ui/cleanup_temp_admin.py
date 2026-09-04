from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
from apply_pdc14_staging import management_write
from inspect_pdc14_staging import management_query

EMAIL = "ui.inventory.20260905@pdc-staging.invalid"
cleanup = management_write(f"""
with target as (select id from auth.users where lower(email)='{EMAIL}'),
deleted_receipts as (
  delete from public.workshop_schedule_recovery_receipts
  where actor_user_id in (select id from target)
  returning receipt_id
),
deleted_audit as (
  delete from public.audit_events
  where actor_id in (select id from target)
  returning id
)
select (select count(*)::int from deleted_receipts) as deleted_recovery_receipts,
       (select count(*)::int from deleted_audit) as deleted_audit_events
""")
management_write(f"delete from auth.users where lower(email)='{EMAIL}'")
management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
state = management_query(f"select jsonb_build_object('auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),'production_sentinel_present',(select to_regclass('public.pdc_production_environment_sentinel') is not null)) as state")[0]["state"]
print(json.dumps({"bounded_cleanup": cleanup, "state": state}, indent=2))
raise SystemExit(0 if state == {"auth_count": 0, "role_count": 0, "production_sentinel_present": False} else 2)
