'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const sql = fs.readFileSync(path.join(root, 'supabase', 'migrations', '040_atomic_same_bay_booking_cascade.sql'), 'utf8');
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');

assert.ok(
  sql.includes('perform public.workshop_lock_resources(v_bay.id, null);'),
  'Cascade must share the established namespaced bay lock with every booking mutation',
);
assert.ok(
  !sql.includes('pg_advisory_xact_lock(hashtextextended(v_bay.id::text, 0))'),
  'Cascade must not use an incompatible un-namespaced advisory lock',
);
assert.ok(
  sql.includes('v_conflict := public.workshop_find_bay_conflict('),
  'Every shifted interval must be checked against queued/planned/live bay bookings',
);
assert.ok(
  sql.indexOf('v_conflict := public.workshop_find_bay_conflict(') < sql.indexOf("v_result := public.schedule_vehicle_work("),
  'Shifted bay conflicts must be rejected before the target action commits',
);
assert.ok(
  sql.includes("if v_stage.is_physical and not public.workshop_parts_ready(p_target_id) then"),
  'Insert cascade must preserve the physical Parts-incomplete gate before shifting the queue',
);
assert.ok(
  sql.includes("return jsonb_build_object('ok', false, 'error', 'parts_incomplete');"),
  'Parts-incomplete rejection must remain structured for the authorised override flow',
);
assert.ok(
  sql.includes("exception when sqlstate 'P0001' then") && sql.includes('return v_result;'),
  'Structured target/conflict rejection must roll back the cascade subtransaction and return intact',
);
assert.ok(
  planner.includes("new Set(['moveBooking', 'scheduleVehicleWork', 'cascadeSchedule'])"),
  'Atomic cascade scheduling must retain the existing authorised Parts override retry',
);
assert.ok(
  /revoke all on function public\.cascade_workshop_schedule\([\s\S]*?from public, anon;/.test(sql),
  'Cascade execute must stay revoked from PUBLIC and anon',
);
assert.ok(
  /revoke all on function public\.workshop_add_operational_minutes\([\s\S]*?from public, anon, authenticated;/.test(sql),
  'Internal operational-time helper must remain inaccessible to API roles',
);

console.log('Workshop atomic cascade SQL contract tests passed.');
