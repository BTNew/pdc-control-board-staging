'use strict';
const assert = require('assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/staging_only/20260827002000_452_admin_ignore_completed_history.sql', 'utf8');
assert.match(sql, /v_head IS DISTINCT FROM '20260827001000'/);
for (const fn of [
  'create_workshop_admin_block',
  'workshop_admin_nearest_available_slot',
  'workshop_admin_repack_planned',
  'workshop_enforce_admin_block_fixed_booking_conflict',
]) assert.ok(sql.includes(fn), `missing ${fn}`);
assert.match(sql, /replace\(original,[\s\S]*queued[\s\S]*started[\s\S]*stoppage[\s\S]*completed[\s\S]*queued[\s\S]*started[\s\S]*stoppage/);
assert.match(sql, /Completed Workshop bookings remain immutable history but no longer block Admin downtime/);
assert.match(sql, /Queued, started and stoppage bookings remain fixed blockers/);
assert.match(sql, /PDC_452_POSTCONDITION_FAILED/);
console.log('Admin completed-history exclusion 452: PASS');
