'use strict';
// r449 (F62, Bhavesh 21 Oct 18:19, approved by Craig): parts readiness stopped gating bookings and starts in r415.
// The leftover "confirm the parts" messages are gone from the Dept 138 planner and fitter screen; a retired parts code
// now says the page is out of date. Karratha 135 keeps its own copies. Check parts_gate_retired_449 guards the database.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const RETIRED=/Parts must not block workshop work|Open Workshop flow \/ parts readiness|Confirmed available for this stage|stage parts need controller confirmation|Parts are not marked ready|refresh booking rules/;

test('planner and fitter screens carry no retired parts-readiness message',()=>{
  for(const file of ['workshop-planner.js','pdc-fitters.js','workshop-data-service.js','workshop-shared-actions.js'])
    assert.doesNotMatch(fs.readFileSync(file,'utf8'),RETIRED,file);
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  assert.match(planner,/'parts_incomplete', 'parts_incomplete_blocked', 'parts_incomplete_entry', 'bus_stage_parts_required', 'stage_parts_not_ready'\]\.includes\(error\)/);
  assert.match(planner,/Parts no longer hold up a booking\. This page is out of date: refresh it and try again\./);
  const fitters=fs.readFileSync('pdc-fitters.js','utf8');
  assert.equal((fitters.match(/Parts no longer hold up a job\. Refresh the page and try again; if it happens again, tell the controller\./g)||[]).length,2);
  assert.match(fs.readFileSync('index.html','utf8'),/pdc-fitters\.js\?[^"]*parts-retired=2026\.10\.21\.r449/);
});

test('Karratha 135 copies are untouched',()=>{
  const k=fs.readFileSync('karratha/workshop-planner.js','utf8');
  assert.match(k,/Parts must not block workshop work/);
});

test('migration adds only the guard check; undo removes it',()=>{
  const up=fs.readFileSync('supabase/migrations/20261021110110_r449_parts_gate_retired.sql','utf8');
  const down=fs.readFileSync('supabase/rollbacks/20261021110110_r449_parts_gate_retired.down.sql','utf8');
  assert.match(up,/'parts_gate_retired_449','F62'/);assert.match(up,/true,248,'r449'\)/);assert.match(up,/SET LOCAL lock_timeout = '2s'/);
  assert.doesNotMatch(up,/CREATE OR REPLACE FUNCTION|expected_function_md5 SET/);
  assert.match(down,/DELETE FROM pdc_ops\.regression_checks WHERE check_name='parts_gate_retired_449' AND added_in='r449'/);
  assert.match(fs.readFileSync('tests/parts_gate_retired_449_rollback.sql','utf8'),/R449_RB_RESULT/);
});
