/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r592 (F206): a drop onto a running job asks to place this job after it and push the later jobs.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { workshopConfirmBayRuleWarning, workshopPlaceAfterQuestion } = require('./workshop-shared-actions.js');

const up = fs.readFileSync('supabase/migrations/20261028081000_r592_hoist_place_after.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028081000_r592_hoist_place_after.down.sql', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const service = fs.readFileSync('workshop-data-service.js', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const karrathaPlanner = fs.readFileSync('karratha/workshop-planner.js', 'utf8');
const karrathaActions = fs.readFileSync('karratha/workshop-shared-actions.js', 'utf8');
const karrathaApp = fs.readFileSync('karratha/app.js', 'utf8');

const place = {
  ok: false,
  warning: true,
  requires_confirmation: true,
  error: 'place_after_running',
  plan_hash: 'hash-460',
  message: 'Key 328 is already running in Jason Ranoco until Wed 28 Oct 12:05. Place this job right after it? Later jobs in this bay move back.',
  pushes: [{ key_number: 365, bay_number: 2, from_start: '2026-10-28T05:33:00Z', to_start: '2026-10-29T05:35:00Z' }],
};

test('a running-job drop asks in plain English and a confirmed drop sends the plan hash', async () => {
  const calls = [];
  const asked = [];
  const result = await workshopConfirmBayRuleWarning(async (name, params) => {
    calls.push(params);
    return calls.length === 1 ? place : { ok: true };
  }, 'administrator_move_workshop_booking', { p_metadata: { source: 'planner_chip_drop' }, p_request_id: 'r1' }, question => {
    asked.push(question);
    return true;
  });
  assert.equal(result.ok, true);
  assert.equal(calls.length, 2);
  assert.match(asked[0], /Key 328 is already running in Jason Ranoco/);
  assert.match(asked[0], /Key 365 · Bay 2/);
  assert.match(asked[0], /Choose Cancel to leave everything as it is/);
  assert.deepEqual(calls[1].p_metadata.place_after_confirm, { plan_hash: 'hash-460' });
  assert.equal(calls[1].p_metadata.source, 'planner_chip_drop');
  assert.notEqual(calls[1].p_request_id, 'r1');
  assert.match(workshopPlaceAfterQuestion(place), /push the later job back/);
});

test('Cancel on a running-job drop leaves the bay as it is', async () => {
  let n = 0;
  const cancelled = await workshopConfirmBayRuleWarning(async () => { n += 1; return place; }, 'x', { p_metadata: {} }, () => false);
  assert.equal(n, 1);
  assert.equal(cancelled.error, 'place_after_not_confirmed');
  assert.equal(cancelled.cancelled, true);
});

test('the planner has plain English for both codes and the migration keeps the pins', () => {
  assert.match(planner, /place_after_running: 'A job is already running in this bay/);
  assert.match(planner, /place_after_not_confirmed: 'No change was made/);
  assert.match(service, /'place_after_running'/);
  assert.match(service, /'place_after_not_confirmed'/);
  assert.match(up, /sort 360/);
  assert.match(up, /F206/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.match(up, /<>241/);
  assert.equal(up.includes('INSERT INTO pdc_ops.expected_function_md5'), false);
  assert.match(up, /place_after_running/);
  assert.match(down, /fa78dfb941af8fd86ca705890d4bf798/);
  assert.match(down, /DROP FUNCTION pdc_ops.place_after_live_bay_592/);
  assert.equal(karrathaPlanner.includes('place_after_not_confirmed'), false);
  assert.equal(karrathaActions.includes('workshopPlaceAfterQuestion'), false);
  assert.equal(karrathaApp.includes('r592=2026.10.28.r592'), false);
  assert.equal(app.split('r592=2026.10.28.r592').length - 1, 7);
});
