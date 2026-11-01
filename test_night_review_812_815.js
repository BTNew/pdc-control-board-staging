'use strict';
// r812-r815 (F450-F453): night review guards and speed fixes.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = f => fs.readFileSync('supabase/migrations/' + f, 'utf8');
test('r812-r815 migrations and fault log', () => {
  assert.match(read('20261101210000_r812_od_is_not_delivered.sql'), /OD is not delivered/);
  const p = read('20261101211000_r813_prewarm_on_demand.sql');
  assert.match(p, /board_demand_813/);
  assert.match(p, /AT TIME ZONE 'Australia\/Perth'\) < 7/, 'Saturday prewarm kept (check 784)');
  const g = read('20261101212000_r814_night_review_guards.sql');
  assert.match(g, /retired_literals_814/);
  assert.match(g, /'finished_cars_stay_finished_814'/);
  assert.match(read('20261101213000_r815_board_rebuild_faster.sql'), /WHERE o\.vehicle_id=p_vehicle_id/);
  const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  for (const id of ['F450', 'F451', 'F452', 'F453']) assert.match(log, new RegExp('^\\| ' + id + ' \\|', 'm'));
});
