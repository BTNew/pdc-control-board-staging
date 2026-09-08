#!/usr/bin/env python3
"""Read authoritative STAGING durations and rejection-era evidence."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apply_t_780b25d4_staging import management_write  # noqa: E402
from inspect_pdc14_staging import STAGING_REF  # noqa: E402

STOCKS = ("12705177", "13007660", "13015144", "13021036")
stock_sql = ",".join(f"'{stock}'" for stock in STOCKS)
sql = f"""
begin read only;
select jsonb_build_object(
  'staging_sentinel_count',(
    select count(*) from public.pdc_staging_environment_sentinel
    where singleton and project_ref='{STAGING_REF}'
  ),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'migration_head',(
    select jsonb_build_array(version,name)
    from supabase_migrations.schema_migrations
    where version~'^[0-9]{{14}}$'
    order by version::bigint desc limit 1
  ),
  'vehicles',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'stock_number',v.stock_number,
      'vehicle_id',v.id,
      'version',v.version,
      'current_location',v.current_location,
      'fitting_hours',public.workshop_vehicle_stage_estimated_hours(v.id,'FITTING'),
      'fitting_minutes',public.workshop_vehicle_stage_estimated_duration_minutes(
        v.id,(select id from public.workshop_stages where code='FITTING')
      ),
      'active_booking_count',(
        select count(*) from public.workshop_bookings b
        join public.workshop_stages s on s.id=b.stage_id
        where b.vehicle_id=v.id and s.code='FITTING' and b.deleted_at is null
          and b.status::text in ('queued','planned','started','stoppage')
      )
    ) order by v.stock_number),'[]'::jsonb)
    from public.vehicles v
    where v.stock_number in ({stock_sql}) and v.deleted_at is null and v.lifecycle_state='active'
  ),
  'rejection_era_booking_history',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'created_at',h.created_at,
      'event_type',h.event_type,
      'stock_number',v.stock_number,
      'metadata',h.metadata
    ) order by h.created_at desc),'[]'::jsonb)
    from public.workshop_booking_history h
    join public.workshop_bookings b on b.id=h.booking_id
    join public.vehicles v on v.id=b.vehicle_id
    where h.created_at between '2026-09-08T22:50:00Z' and '2026-09-08T23:05:00Z'
  )
) as evidence
;
rollback;
"""
rows = management_write(sql)
evidence = rows[0]["evidence"] if rows else {}
result = {
    "project_ref": STAGING_REF,
    "evidence": evidence,
    "production_contacted": False,
    "production_writes": False,
}
out = ROOT / "review-evidence" / "t_780b25d4" / "craig-90-minute-failure-data.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(result, indent=2, default=str) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2, default=str))
