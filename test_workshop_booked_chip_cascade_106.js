'use strict';

const assert = require('assert');
const fs = require('fs');
const crypto = require('crypto');

const canonicalSqlBytes = file => {
  const source = fs.readFileSync(file, 'utf8');
  const carriageReturn = String.fromCharCode(13);
  const lineFeed = String.fromCharCode(10);
  const canonical = source.split(carriageReturn + lineFeed).join(lineFeed);
  assert.ok(!canonical.includes(carriageReturn), `${file} must not contain lone carriage returns`);
  return Buffer.from(canonical, 'utf8');
};
const migration104 = canonicalSqlBytes('supabase/staging_only/104_authenticated_operation_estimated_hours.sql');
const migration105 = canonicalSqlBytes('supabase/staging_only/105_authenticated_operation_hours_exact_replay.sql');
assert.strictEqual(crypto.createHash('sha256').update(migration104).digest('hex'), '7d71db064f66ec588a151bc3f2bb0b4e08091b4bcb6929d0e30d27a8518a15f5', 'Migration 104 source must exactly match the applied staging ledger');
assert.strictEqual(crypto.createHash('sha256').update(migration105).digest('hex'), 'c72ee9a0fccf697006849fd12d1b9b9de6aa2b3ca18407575a0f7a82d96be3f5', 'Migration 105 source must exactly match the applied staging ledger');

const sql = fs.readFileSync('supabase/staging_only/106_workshop_booked_chip_move_cascade.sql', 'utf8').toLowerCase();
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const actions = fs.readFileSync('workshop-shared-actions.js', 'utf8');
const service = fs.readFileSync('workshop-data-service.js', 'utf8');

assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'Migration 106 must remain staging guarded');
assert(sql.includes("version='105'"), 'Migration 106 must require the prior staging ledger head');
assert(sql.includes("name='authenticated_operation_hours_exact_replay'"), 'Migration 106 must pin the exact migration 105 prerequisite');
assert.match(sql, /create or replace function public\.cascade_workshop_booking_move/, 'Migration 106 must expose one atomic booked-chip move RPC');
assert.match(sql, /status\s*=\s*'planned'/, 'Only planned destination bookings may be shifted');
assert.match(sql, /status\s+in\s*\('started','stoppage'\)/, 'Live destination bookings must block instead of moving');
assert(sql.includes('order by b.scheduled_start_at desc,b.id desc'), 'Destination rows must move latest-first to avoid transient overlap');
assert(sql.includes("'cascade_move_shifted'"), 'Every shifted booking must receive authoritative history');
assert(sql.includes('workshop_upsert_primary_assignment'), 'Shifted booking assignments must follow their new times');
assert(sql.includes('move_workshop_booking'), 'The target chip must move through the protected booking mutation');
assert(sql.includes("'shifted_booking_ids'"), 'The response must identify every shifted booking');
assert.match(sql, /revoke all on function public\.cascade_workshop_booking_move[\s\S]*from public,anon,authenticated/, 'The move cascade must fail closed before its authenticated grant');
assert.match(sql, /grant execute on function public\.cascade_workshop_booking_move[\s\S]*to authenticated/, 'Authenticated planner operators must be able to call the protected move cascade');

assert(actions.includes("mutate('cascade_workshop_booking_move'"), 'Shared actions must map booked-chip cascade moves to migration 106');
assert(service.includes("'cascade_workshop_booking_move'"), 'The data service allow-list must include the new protected RPC');
const scheduleBody = planner.match(/async function scheduleWorkshopVehicle\([^]*?\r?\n}\r?\n\r?\nasync function saveWorkshopDetailForm/)?.[0] || '';
assert(scheduleBody.includes("preferRequestedTime && movingBetweenBays ? 'cascadeMoveBooking' : 'moveBooking'"), 'Exact-time chip drops between bays must use the atomic move cascade');
assert(scheduleBody.includes('cascadeMoveBooking'), 'Booked chip drops must route through the shared cascade action');

console.log('Booked Workshop chip move-cascade contracts passed');
