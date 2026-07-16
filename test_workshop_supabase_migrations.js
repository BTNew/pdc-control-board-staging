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
];
for (const file of files) {
  assert.ok(fs.existsSync(path.join(migrationsDir, file)), `${file} is missing`);
}

const foundation = fs.readFileSync(path.join(migrationsDir, '006_workshop_planner_foundation.sql'), 'utf8');
const rpc = fs.readFileSync(path.join(migrationsDir, '007_workshop_planner_booking_rpc.sql'), 'utf8');
const lockDown = fs.readFileSync(path.join(migrationsDir, '008_workshop_planner_lock_down.sql'), 'utf8');

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

console.log('Workshop Supabase migration checks passed');
