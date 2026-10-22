/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r415 (F31): a job started and then returned to the queue is re-planned by resuming it.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = f => fs.readFileSync(path.join(__dirname, f), 'utf8');
const mig = read('supabase/migrations/20261020232117_r415_resume_returned_jobs.sql');
const down = read('supabase/rollbacks/20261020232117_r415_resume_returned_jobs.down.sql');
const fix = read('supabase/migrations/20261020232244_r415b_resume_check_format.sql');

test('migration is staging only and refuses changed functions', () => {
  assert.match(mig, /pdc_monitor_staging_guard\(\)/);
  assert.match(mig, /project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.match(mig, /pdc_production_environment_sentinel'\) IS NOT NULL/);
  assert.match(mig, /7edd2a97fb88093a09d3275fb349797f/);
  assert.match(mig, /1c8341ad165c9e968286546387e5374f/);
  assert.match(mig, /84af7607bfd0ce9907c89bae8644d5b6/);
  assert.equal(/vjdtsswhroyguxyfjdkt/.test(mig), false);
});

test('only queued, bay-less, returned jobs with a start and no finish are resumed', () => {
  assert.match(mig, /v_booking\.status='queued' and v_booking\.bay_id is null\s+and v_booking\.actual_start_at is not null and v_booking\.actual_end_at is null and v_booking\.returned_to_queue_at is not null/);
  assert.match(mig, /if not v_resumable and \(v_booking\.deleted_at is not null or v_booking\.status not in\('queued','planned'\)/);
});

test('time worked is kept and only the remaining hours are planned', () => {
  assert.match(mig, /greatest\(1,coalesce\(v_base,b\.capacity_base_minutes,1\)-v_worked\)/);
  assert.match(mig, /'resumed_for_replan'/);
  assert.match(mig, /UNIQUE\(booking_id,actual_start_at,returned_to_queue_at\)/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.workshop_resume_returned_booking_415\(uuid,integer,text\) FROM PUBLIC, anon, authenticated/);
});

test('a refused move rolls the resume back', () => {
  assert.match(mig, /raise exception 'r415: move refused; resume rolled back' using errcode='P0415'/);
  assert.match(mig, /exception when sqlstate 'P0415' then return v_result;/);
});

test('undo asserts the released versions and restores the old ones', () => {
  assert.match(down, /acb09f07d4bc59ecb1cb75c6f87d78ba/);
  assert.match(down, /7dcc9b114f5484722febaa769253d54b/);
  assert.match(down, /<>'7edd2a97fb88093a09d3275fb349797f'/);
  assert.match(down, /DROP TABLE public\.workshop_booking_resume_ledger_415/);
  assert.match(fix, / as ok,/i);
  assert.match(fix, / as detail/i);
});
