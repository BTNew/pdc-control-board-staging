'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const migrationPath = path.join(root, 'supabase', 'staging_only', '20260826130000_397_canonical_workshop_booking_snapshot_authority.sql');
assert.ok(fs.existsSync(migrationPath), '397 snapshot-authority migration exists');
const sql = fs.readFileSync(migrationPath, 'utf8');
const lower = sql.toLowerCase();
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const admin = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260826090000_392_workshop_admin_block_atomic_cascade.sql'), 'utf8');
const compaction = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260826100000_394_admin_compaction_and_duration_bounds.sql'), 'utf8');
const protectedRead = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260825120000_375_acceptance_closure_intake.sql'), 'utf8');

for (const marker of [
  "v_head is distinct from '20260826123000'",
  "version='20260826123000'",
  'workshop_bookings',
  'jsonb_array_elements',
  'booking_id',
  'scheduled_start_at',
  'scheduled_end_at',
  'default_duration_minutes',
  "'actual_start_at'",
  "'actual_end_at'",
  "'stoppage_reason'",
  "'stoppage_started_at'",
  "'stoppage_accumulated_minutes'",
  "'version'",
  'get_workshop_snapshot_pre_397',
  'get_station_workshop_snapshot_pre_397',
  "'20260826130000'",
  "'397_canonical_workshop_booking_snapshot_authority'",
  'notify pgrst',
]) {
  assert.ok(lower.includes(marker.toLowerCase()), `397 migration contains ${marker}`);
}
assert.doesNotMatch(sql, /update\s+public\.workshop_bookings/i, 'projection repair never rewrites canonical bookings');
assert.doesNotMatch(sql, /queue_vehicle_notification/i, 'projection repair never queues notifications');
assert.match(sql, /revoke all on function public\.workshop_overlay_canonical_booking_fields_397/i);
assert.match(sql, /grant execute on function public\.get_station_workshop_snapshot\(text,date,date\)\s+to authenticated,service_role/i);
assert.match(sql, /grant execute on function public\.get_workshop_snapshot\(date,date\) to service_role/i);

// Synthetic HERMES-TEST acceptance: a stale estimate cannot shorten canonical
// geometry, while non-scheduling evidence remains visible separately.
const source = planner;
const start = source.indexOf('function workshopMapSnapshotBookingToLegacyRow');
const end = source.indexOf('function workshopAnnotateLegacyAmbiguity', start);
assert.ok(start >= 0 && end > start, 'snapshot mapper exists');
const context = {
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  workshopExactDurationHours: value => Math.round(Number(value) * 60) / 60,
  workshopDefaultBookingHours: () => 1,
};
vm.createContext(context);
vm.runInContext(`${source.slice(start, end)} this.map = workshopMapSnapshotBookingToLegacyRow;`, context);
const projected = context.map({
  booking_id: '15553952-63c3-4b4b-9f27-a81e6d64bcc4',
  vehicle_id: 'vehicle-stock-13000549',
  stage: { code: 'HOIST' },
  bay: { id: 'bay-03', bay_number: 3 },
  status: 'started',
  scheduled_start_at: '2026-08-25T03:37:00.000Z',
  scheduled_end_at: '2026-08-25T06:52:00.000Z',
  default_duration_minutes: 195,
  estimated_operation_hours: 1.5,
  actual_start_at: '2026-08-25T03:37:00.000Z',
  actual_end_at: null,
  stoppage_reason: null,
  stoppage_started_at: null,
  stoppage_accumulated_minutes: 0,
  version: 5,
  vehicle: { stock_number: '13000549' },
});
assert.strictEqual(projected.hours, 3.25, 'Stock 13000549 chip spans the canonical 195 minutes');
assert.strictEqual(projected.endAt, '2026-08-25T06:52:00.000Z');
assert.strictEqual(projected.status, 'started');
assert.strictEqual(projected.sharedVersion, 5);
assert.strictEqual(projected.operationEstimateHours, 1.5, 'stale estimate remains evidence, not geometry');

// The acceptance run is read-only for the protected vehicle and must preserve
// the existing atomic Admin mutation contract across the adjacent migrations.
for (const marker of [
  'HERMES-TEST-ACCEPTANCE-20260825',
  'fixed_booking_conflict',
  'nearest_available_slot',
  'status=\'planned\'',
  'receipt_id',
  'replay',
  'undo',
  'notification_delta',
  'no_partial_save',
]) {
  const corpus = `${admin}\n${compaction}\n${protectedRead}\n${planner}`.toLowerCase();
  assert.ok(corpus.includes(marker.toLowerCase()), `acceptance contract contains ${marker}`);
}
assert.match(admin, /p_bay_id/);
assert.match(admin, /workshop_admin_lock_physical_bays/);
assert.match(compaction, /compact_released/);

console.log('Workshop canonical booking snapshot authority 397 contract passed.');
