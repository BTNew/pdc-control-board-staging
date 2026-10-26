'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const up = fs.readFileSync('supabase/migrations/20261026120000_r537_planner_duration_after_insert.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261026120000_r537_planner_duration_after_insert.down.sql', 'utf8');

test('r537 stores the post-insert length and still rejects a different length', () => {
  assert.match(up, /workshop_booking_capacity_duration_minutes\(NULL,p_vehicle_id,v_stage_id,v_bay_id\)/);
  assert.match(up, /workshop_booking_capacity_duration_minutes\(v_booking_id,p_vehicle_id,v_stage_id,v_bay_id\)/);
  const live = up.indexOf('workshop_booking_capacity_duration_minutes(v_booking_id,p_vehicle_id,v_stage_id,v_bay_id)');
  const insertAt = up.indexOf('insert into public.workshop_bookings');
  const updateAt = up.indexOf('set default_duration_minutes = v_live');
  const assignAt = up.indexOf('workshop_upsert_primary_assignment');
  assert.ok(insertAt > 0 && live > insertAt && updateAt > live && assignAt > updateAt);
  assert.match(up, /operation_estimate_duration_mismatch/);
  assert.match(up, /9efb08f2415c28ac57a14b401cf9f605/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.workshop_validate_booking/);
  assert.doesNotMatch(up, /karratha135_pdc/);
  assert.match(down, /f5375755bbb9c217198c4075e5c125ab/);
  assert.match(down, /864e9bdc638bd0003dab0302e9ab2de3/);
  assert.match(down, /planner_duration_after_insert_537/);
});
