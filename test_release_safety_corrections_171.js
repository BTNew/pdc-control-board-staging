const fs = require('fs');
const assert = require('assert');
const sql = fs.readFileSync('supabase/staging_only/171_release_safety_corrections.sql', 'utf8');
for (const token of [
  "version='170' and name='authoritative_workshop_admin_blocks'",
  "version::integer>170",
  "values('171','release_safety_corrections'",
  'for update;',
  'vehicle_aliases_active_raw_unique_idx',
  'vehicles_enforce_reactivation_identity_uniqueness',
  'prelock_vehicle_aliases_for_soft_delete',
  "hashtextextended('navision-backend-store',0)",
  'reconcile_navision_operational_record_pre171',
  'pdc_lock_canonical_sublet_vehicle',
  "'pdc-sublet-workshop:'",
  "'pdc-sublet-booking:'",
  'pdc_canonical_sublet_workshop_overlap_guard',
  'provider_attested_sublet_contract_required',
  'process_pdc_email_communication_pre171',
  "'historical_vehicle_retained'",
  'cancel_pdc_sublet_booking',
  'vehicles_cancel_active_sublets_on_delete',
  "'replay_conflict'",
  'v_receipt.prior_version=coalesce(p_expected_version,0)',
  'update_pdc_sublet_booking_pre171',
  'return_pdc_sublet_booking_pre171',
  "pg_advisory_xact_lock(hashtextextended('pdc-sublet-instance:'||p_vehicle_id::text,0))",
  'workshop_booking_effective_duration_minutes',
  'workshop_booking_effective_end_at',
  'workshop_technician_leave_date',
  "b.vehicle_id=v_booking.vehicle_id",
  "order by b.id for update",
  "order by (value->>'scheduled_start_at')::timestamptz desc",
  "not (b.bay_id=p_bay_id and b.status='planned'",
]) assert(sql.includes(token), `missing contract: ${token}`);
assert(/before insert or update of vehicle_id,alias_type,alias_value,active,source_system/.test(sql));
assert(/set active=false,version=a\.version\+1,updated_at=clock_timestamp\(\)/.test(sql));
assert(/where active group by alias_type,alias_value having count\(\*\)>1/.test(sql));
assert(/before update of deleted_at on public\.vehicles/.test(sql));
assert(!/on conflict\(version\) do nothing/i.test(sql));
console.log('Migration171 release safety contracts passed');
