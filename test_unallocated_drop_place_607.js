/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r607 (F221): a drop from Unallocated is placed after a running job or before the planned job it lands in,
// and a resize of a running job sets its real length. Key 448 onto Jason Ranoco's Hoist bay.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const up = fs.readFileSync('supabase/migrations/20261028150000_r607_unallocated_drop_place.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028150000_r607_unallocated_drop_place.down.sql', 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');

test('r607 guards: staging only, test window, pin count, exact pre-fix bodies', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /expected_function_md5\)<>241/);
  assert.match(up, /'50c3c198c6ccd360390442043e18ce72'/);
  assert.match(up, /'7dcc9b114f5484722febaa769253d54b'/);
  assert.match(up, /'fdb2b641534c4bafaacd5ee35b59b6ba'/);
  assert.match(up, /'fd05b9eef69498002ac06dd68e01cdff'/);
  assert.doesNotMatch(up, /karratha135_pdc\.administrator_schedule/);
});

test('the Unallocated drop places itself after a running job and before a planned job', () => {
  assert.match(up, /pdc_ops\.place_after_live_bay_592\(null,v_bay,p_scheduled_start_at,v607_end/);
  assert.match(up, /v607_placement:='after_running'/);
  assert.match(up, /v607_placement:='before_planned'/);
  assert.match(up, /b\.scheduled_start_at<p_scheduled_start_at\s+and b\.scheduled_start_at>=date_trunc\('minute',statement_timestamp\(\)\)/);
  assert.match(up, /'requested_start_at',v607_requested,'placed_start_at',p_scheduled_start_at,'placement',v607_placement/);
  // Only cascade drops move; Best slot (cascade false) is unchanged.
  const patch = up.slice(up.indexOf('new_lock text'), up.indexOf('old_res text'));
  assert.ok(patch.indexOf(' if p_cascade then') < patch.indexOf('place_after_live_bay_592'));
  // The r417 bay-rule warning stays.
  assert.match(up, /pdc_bay_rules_private\.warning\(v_rules\)/);
});

test('a resize of a running job sets its real length only for that resize', () => {
  assert.match(up, /NEW\.status IN\('started','stoppage'\) AND OLD\.status=NEW\.status/);
  assert.match(up, /jsonb_build_object\('booking',NEW\.id,'version',OLD\.version,'duration',NEW\.default_duration_minutes\)/);
  assert.match(up, /->>'actor'\) IS NOT DISTINCT FROM auth\.uid\(\)::text/);
  assert.match(up, /NEW\.capacity_base_minutes:=NEW\.default_duration_minutes::numeric\*NEW\.capacity_efficiency_percent\/100/);
  // The r415 resume path is kept.
  assert.match(up, /pdc\.workshop_resume_415/);
});

test('Key 460 repair touches one exact row and is recorded', () => {
  assert.match(up, /0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd/);
  assert.match(up, /default_duration_minutes=225/);
  assert.match(up, /'capacity_repaired'/);
  assert.match(up, /IF n<>1 THEN RAISE EXCEPTION 'r607: Key 460 repair/);
});

test('pins stay 241, both re-pinned as r607, regression check sort 376', () => {
  assert.match(up, /release='r607'/);
  assert.match(up, /IF n<>2 THEN RAISE EXCEPTION 'r607: re-pin/);
  assert.match(up, /'unallocated_drop_place_607', 'F221'/);
  assert.match(up, /true, 376, 'r607'\);/);
});

test('undo restores both exact bodies, pins and notes, and removes the check', () => {
  assert.match(down, /'50c3c198c6ccd360390442043e18ce72'/);
  assert.match(down, /'7dcc9b114f5484722febaa769253d54b'/);
  assert.match(down, /release='r417', note='F32: bay rule mismatch warns; confirmed overrides are logged'/);
  assert.match(down, /release='r415', note='F31: started-then-returned jobs resume for re-planning'/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='unallocated_drop_place_607'/);
});

test('fault log has the F221 row', () => {
  assert.match(log, /\| F221 \|/);
  assert.match(log, /unallocated_drop_place_607/);
});
