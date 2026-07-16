'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const root = __dirname;
const migrationsDir = path.join(root, 'supabase', 'migrations');

const files = [
  '006_workshop_planner_foundation.sql',
  '007_workshop_planner_booking_rpc.sql',
  '008_workshop_planner_lock_down.sql',
  '009_workshop_planner_frontend_contract.sql',
];
for (const file of files) {
  assert.ok(fs.existsSync(path.join(migrationsDir, file)), `${file} is missing`);
}

const foundation = fs.readFileSync(path.join(migrationsDir, '006_workshop_planner_foundation.sql'), 'utf8');
const rpc = fs.readFileSync(path.join(migrationsDir, '007_workshop_planner_booking_rpc.sql'), 'utf8');
const lockDown = fs.readFileSync(path.join(migrationsDir, '008_workshop_planner_lock_down.sql'), 'utf8');
const frontendContract = fs.readFileSync(path.join(migrationsDir, '009_workshop_planner_frontend_contract.sql'), 'utf8');

for (const table of [
  'workshop_stages',
  'workshop_bays',
  'workshop_technicians',
  'workshop_bookings',
  'workshop_booking_assignments',
  'workshop_booking_history',
  'workshop_settings',
]) {
  assert.ok(foundation.includes(`create table public.${table}`), `${table} table definition is missing`);
}

assert.ok(foundation.includes("'BUS_4X4', 'Bus 4x4', 1"), 'Bus 4x4 stage seed is missing');
assert.ok(foundation.includes("'SUBLET', 'Sublet', 9"), 'Sublet stage seed/order is missing');
assert.ok(foundation.includes("'default_booking_duration_minutes', to_jsonb(180)"), 'Default workshop duration setting is missing');
assert.ok(foundation.includes("'scheduling_increment_minutes', to_jsonb(15)"), 'Scheduling increment setting is missing');
assert.ok(foundation.includes('alter publication supabase_realtime add table public.workshop_bookings;'), 'Bookings realtime publication is missing');
assert.ok(foundation.includes('alter publication supabase_realtime add table public.workshop_booking_history;'), 'History realtime publication is missing');

for (const fn of [
  'workshop_create_booking',
  'workshop_move_booking',
  'workshop_resize_booking',
  'workshop_reassign_booking',
  'workshop_start_booking',
  'workshop_record_stoppage',
  'workshop_resume_booking',
  'workshop_complete_booking',
  'workshop_return_booking_to_queue',
  'workshop_delete_booking',
  'workshop_restore_booking',
]) {
  assert.ok(rpc.includes(`function public.${fn}`), `${fn} RPC is missing`);
}

assert.ok(rpc.includes('pg_advisory_xact_lock'), 'RPC layer must serialize overlapping writes with advisory locks');
assert.ok(rpc.includes("'bay_overlap'"), 'Bay overlap conflict response is missing');
assert.ok(rpc.includes("'technician_overlap'"), 'Technician overlap conflict response is missing');
assert.ok(rpc.includes('workshop_booking_history'), 'History writes are missing from RPC layer');
assert.ok(rpc.includes('public.audit_pdc_event'), 'RPC layer must write shared audit events');

assert.ok(lockDown.includes('revoke insert, update, delete on table'), 'Direct table write revocation is missing');
assert.ok(lockDown.includes('grant execute on function public.workshop_create_booking'), 'Authenticated execute grant for create RPC is missing');
assert.ok(lockDown.includes('grant execute on function public.workshop_complete_booking'), 'Authenticated execute grant for complete RPC is missing');


assert.ok(frontendContract.includes('function public.workshop_normalize_work_start'), 'Business-hours start normalization function is missing');
assert.ok(frontendContract.includes('function public.workshop_add_work_minutes'), 'Business-hours duration function is missing');
assert.ok(frontendContract.includes('function public.workshop_work_minutes_between'), 'Business-hours elapsed-time function is missing');
assert.ok(frontendContract.includes('Only a started or stopped workshop booking can be completed'), 'Completion RPC must reject invalid lifecycle transitions');
assert.ok(frontendContract.includes('Only a stopped workshop booking can be resumed'), 'Resume RPC must reject invalid lifecycle transitions');
assert.ok(frontendContract.includes("'Australia/Perth'"), 'Workshop database calendar must use the Perth business timezone');
assert.ok(frontendContract.includes("'frontend_contract_version', to_jsonb(1)"), 'Frontend contract version marker is missing');
assert.ok(frontendContract.includes('function public.workshop_update_booking'), 'Atomic combined booking update RPC is missing');
assert.ok(frontendContract.includes('function public.workshop_start_booking'), 'Start RPC override with live conflict protection is missing');
assert.ok(frontendContract.includes('workshop_bookings_one_open_vehicle_stage_idx'), 'One-open-booking-per-vehicle-stage protection is missing');
assert.ok(frontendContract.includes('Workshop migration stopped: duplicate technician/provider names'), 'Migration must fail safely before creating a case-insensitive technician index over duplicate data');
assert.ok(frontendContract.includes('multiple open bookings exist for the same vehicle/stage'), 'Migration must stop for manual reconciliation instead of silently discarding duplicate open bookings');
assert.ok(frontendContract.includes("b.status in ('planned', 'started', 'stoppage')"), 'Queued bookings must not occupy bay conflict time');
assert.ok(frontendContract.includes('p_expected_version'), 'Frontend mutation contract must enforce optimistic version checks');
assert.ok(frontendContract.includes('workshop_lock_resources'), 'Frontend mutation contract must lock bay and technician resources');
assert.ok(frontendContract.includes('revoke execute on function public.workshop_move_booking'), 'Legacy non-atomic move RPC must be disabled for browser users');
assert.ok(frontendContract.includes('grant execute on function public.workshop_update_booking'), 'Authenticated users need the atomic update RPC');

console.log('Workshop Supabase migration checks passed');
