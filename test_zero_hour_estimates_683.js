'use strict';
// r683 (F293): no open Fitting/Electrical/Fab/Tyres line stays at 0 hours; Sublet and job card notes stay 0.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261029030000_r683_zero_hour_estimates.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
test('estimates: same job median, else station default; never Sublet; never a person\'s own hours; import windows skipped', () => {
  assert.match(sql, /IN \('FITTING', 'ELECTRICAL', 'FABRICATION', 'TYRE'\)/);
  assert.doesNotMatch(sql, /'SUBLET'/);
  assert.match(sql, /coalesce\(h\.med, CASE x->>'stage_code' WHEN 'FABRICATION' THEN 1\.0 ELSE 0\.5 END\)/);
  assert.match(sql, /correction_origin IN \('manual_operator', 'manual_operator_unknown'\)/);
  assert.match(sql, /status IN \('queued', 'running'\)/);
  assert.doesNotMatch(sql, /cron\.schedule/, 'one run only, no background job');
});
test('the board labels these hours Estimate', () => {
  assert.match(app, /adjustment\.correction_origin === 'zero_hour_estimate_683'\s*\? 'zero_hour_estimate'/);
  assert.match(app, /return \{ label: 'Estimate', value: Number\(estimate\) \}/);
});
