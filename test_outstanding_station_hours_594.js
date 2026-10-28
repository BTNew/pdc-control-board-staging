const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const up = fs.readFileSync('supabase/migrations/20261028083000_r594_outstanding_station_hours.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028083000_r594_outstanding_station_hours.down.sql', 'utf8');
const karrathaPlanner = fs.readFileSync('karratha/workshop-planner.js', 'utf8');

test('an unallocated drag books the unticked station lines, not the retained total', () => {
  assert.match(planner, /operationEstimateHours/);
  assert.match(planner, /hours still to do/);
  assert.match(planner, /storedBay < 1/);
  assert.equal(karrathaPlanner.includes('hours still to do'), false);
  assert.match(up, /pdc_panel_line_completion_565/);
  assert.match(up, /sort 364/);
  assert.match(up, /F208/);
  assert.match(up, /70f484ed3b141ecfa2d523dc4ebd805c/);
  assert.match(up, /888513949fadd73e24323dbba8c8bc12/);
  assert.equal(up.includes('INSERT INTO pdc_ops.expected_function_md5'), false);
  const check = up.slice(up.indexOf('$chk$'));
  assert.equal(/expected_function_md5\s*\)\s*=\s*241/.test(check), false);
  assert.match(down, /pdc_panel_line_completion_565/);
  assert.match(down, /outstanding_station_hours_594/);
});
