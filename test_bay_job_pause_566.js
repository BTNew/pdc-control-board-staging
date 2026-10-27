'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const upPath = 'supabase/migrations/20261027200000_r566_bay_job_pause.sql';
const downPath = 'supabase/rollbacks/20261027200000_r566_bay_job_pause.down.sql';

function between(text, tag) {
  const parts = text.split(tag);
  assert.equal(parts.length, 3, tag);
  return parts[1];
}

test('r569 pause SQL guards the booking move and leaves pins alone', () => {
  const up = fs.readFileSync(upPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  const body = between(up, '$pause566$');
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
  assert.equal(body.includes('pg_catalog.coalesce'), false);
  assert.equal(body.includes('UPDATE public.vehicles'), false);
  assert.equal(body.includes('DELETE FROM public.vehicles'), false);
  assert.equal(body.includes('complete_workshop_work'), false);
  assert.equal(body.includes('cancel_workshop_booking'), false);
  assert.match(body, /stop_workshop_work/);
  assert.match(body, /workshop_move_booking/);
  assert.match(body, /start_workshop_work/);
  assert.match(body, /bay_id = NULL/);
  assert.match(up, /SET search_path TO pg_catalog, public/);
  assert.match(up, /check_name='bay_job_pause_569'/);
  assert.match(up, /'F183'/);
  assert.match(up, /340, 'r569'/);
  assert.match(up, /83a2c8d5ff85b5a295343e5f3ef66ded/);
  assert.match(up, /f15067e423da1ce70957e5190c922d50/);
  assert.match(up, /<>241/);
  assert.match(up, /search_path', 'pg_catalog'/);
  assert.match(down, /36be5d0f4bc13546911a95adbbf41456/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks/);
  assert.equal(down.includes('UPDATE public.vehicles'), false);
  assert.equal(down.includes('DELETE FROM public.vehicles'), false);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F183 \|/);
});

test('pause choices stay on the same station and a different vehicle', () => {
  const planner = fs.readFileSync('workshop-planner.js', 'utf8');
  const start = planner.indexOf('function workshopPauseForOtherChoices');
  const end = planner.indexOf('function workshopPlanLifecycleActionsHtml');
  const src = planner.slice(start, end);
  global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
  const workshopPauseForOtherChoices = new Function(`${src}; return workshopPauseForOtherChoices;`)();
  const live = { id: 'live', status: 'started', stage: 'FITTING', sharedVehicleId: 'veh-a', sharedBookingId: 'book-a' };
  const rows = [
    live,
    { id: 'same', status: 'planned', stage: 'FITTING', sharedVehicleId: 'veh-a', sharedBookingId: 'book-same' },
    { id: 'other-stage', status: 'planned', stage: 'HOIST', sharedVehicleId: 'veh-b', sharedBookingId: 'book-b' },
    { id: 'started-other', status: 'started', stage: 'FITTING', sharedVehicleId: 'veh-c', sharedBookingId: 'book-c' },
    { id: 'ok', status: 'planned', stage: 'FITTING', sharedVehicleId: 'veh-d', sharedBookingId: 'book-d' },
    { id: 'queued', status: 'queued', stage: 'fitting', sharedVehicleId: 'veh-e', sharedBookingId: 'book-e' },
    { id: 'no-id', status: 'planned', stage: 'FITTING', sharedVehicleId: 'veh-f', sharedBookingId: '' },
  ];
  assert.deepEqual(workshopPauseForOtherChoices(live, rows).map(row => row.id), ['ok', 'queued']);
  assert.deepEqual(workshopPauseForOtherChoices({ ...live, status: 'planned' }, rows), []);
  assert.match(planner, /data-workshop-pause-for-other=/);
  assert.match(planner, /data-workshop-stop-plan=/);
  assert.match(planner, /data-workshop-resume-plan=/);
  assert.match(planner, /data-workshop-start-plan=/);
  const startFn = planner.slice(planner.indexOf('async function startWorkshopPlan'), planner.indexOf('async function pauseBayForOtherJob'));
  assert.match(startFn, /workshopDispatchSharedAction\('startWork'/);
  assert.match(startFn, /already has a started job\. Stop or complete that job before starting another in this bay\./);
  assert.equal(startFn.includes('pauseBayForOther'), false);
  assert.match(planner, /Pause this job\. Its remaining time moves behind the job you pick\. Neither job card is closed\./);
});

test('shared action and cache bust name the pause RPC, and Karratha stays frozen', () => {
  const shared = fs.readFileSync('workshop-shared-actions.js', 'utf8');
  assert.match(shared, /pauseBayForOther\(\{ bookingId, expectedVersion, liveBookingId, liveExpectedVersion \}\)/);
  assert.match(shared, /mutate\('pause_bay_job_for_other_566'/);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.equal((app.match(/r569=2026\.10\.27\.r569/g) || []).length, 4);
  assert.equal(fs.readFileSync('karratha/workshop-planner.js', 'utf8').includes('data-workshop-pause-for-other'), false);
  assert.equal(fs.readFileSync('karratha/workshop-shared-actions.js', 'utf8').includes('pause_bay_job_for_other_566'), false);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('r569=2026.10.27.r569'), false);
});
