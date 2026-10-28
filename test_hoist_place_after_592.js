/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r592 (F206): a drop onto a running job asks to place this job after it and push the later jobs.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { workshopConfirmBayRuleWarning, workshopPlaceAfterQuestion, workshopCascadeNotice } = require('./workshop-shared-actions.js');

const CONFLICT_TOAST = 'This change conflicts with a job already running or on stoppage. No changes were saved. Check the occupied bay or choose another available time.';

function extractFunction(src, name) {
  const start = src.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let i = src.indexOf('{', start);
  let depth = 0;
  for (; i < src.length; i += 1) {
    if (src[i] === '{') depth += 1;
    if (src[i] === '}' && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(name);
}

function placeAfterDescriber() {
  const ctx = {
    workshopAdministratorCanMove: () => false,
    workshopAdministratorErrorDetail: () => '',
    workshopVehicleConflictDetail: () => '',
  };
  vm.createContext(ctx);
  const messages = planner.slice(planner.indexOf('const WORKSHOP_PLAIN_ERROR_MESSAGES'), planner.indexOf('});', planner.indexOf('const WORKSHOP_PLAIN_ERROR_MESSAGES')) + 3);
  vm.runInContext(`${messages}\n${extractFunction(planner, 'workshopDescribeSharedActionError')}\nthis.describe = workshopDescribeSharedActionError;`, ctx);
  return ctx.describe;
}

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

test('a running-job drop cascades without a question and sends the plan hash', async () => {
  const calls = [];
  const asked = [];
  const result = await workshopConfirmBayRuleWarning(async (name, params) => {
    calls.push(params);
    return calls.length === 1 ? place : { ok: true, shifted_count: 10 };
  }, 'administrator_move_workshop_booking', { p_metadata: { source: 'planner_chip_drop' }, p_request_id: 'r1' }, question => {
    asked.push(question);
    return false;
  });
  assert.equal(result.ok, true);
  assert.equal(calls.length, 2);
  assert.equal(asked.length, 0);
  assert.deepEqual(calls[1].p_metadata.place_after_confirm, { plan_hash: 'hash-460' });
  assert.equal(calls[1].p_metadata.source, 'planner_chip_drop');
  assert.notEqual(calls[1].p_request_id, 'r1');
  assert.equal(result.cascade_notice, 'Key 365 moved back.');
  assert.match(workshopCascadeNotice(place), /Key 365 moved back/);
  assert.match(workshopPlaceAfterQuestion(place), /push the later job back/);
});

test('a running-job drop is not waiting on Cancel', async () => {
  let n = 0;
  const result = await workshopConfirmBayRuleWarning(async () => {
    n += 1;
    return n === 1 ? place : { ok: true };
  }, 'x', { p_metadata: {} }, () => false);
  assert.equal(n, 2);
  assert.equal(result.ok, true);
  assert.equal(result.cancelled, undefined);
});

test('a valid place-after drop does not show the running-job conflict toast', () => {
  const describe = placeAfterDescriber();
  const asked = workshopPlaceAfterQuestion(place);
  const shown = describe(place);
  assert.match(asked, /Place this job right after it/);
  assert.equal(asked.includes(CONFLICT_TOAST), false);
  assert.match(shown, /place this job right after it/i);
  assert.equal(shown.includes(CONFLICT_TOAST), false);
  assert.equal(describe({ ok: false, error: 'live_booking_conflict' }), CONFLICT_TOAST);
  assert.match(up, /conflicts with a job already running or on stoppage/);
  assert.match(up, /strpos\(helper, 'conflicts with a job already running'\) = 0/);
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
  assert.match(up, /timestamp with time zone,integer,text,jsonb,uuid,boolean\)' AND release='r571'/);
  assert.equal(up.includes('INSERT INTO pdc_ops.expected_function_md5'), false);
  assert.match(up, /place_after_running/);
  assert.match(down, /fa78dfb941af8fd86ca705890d4bf798/);
  assert.match(down, /DROP FUNCTION pdc_ops.place_after_live_bay_592/);
  assert.equal(karrathaPlanner.includes('place_after_not_confirmed'), false);
  assert.equal(karrathaActions.includes('workshopPlaceAfterQuestion'), false);
  assert.equal(karrathaApp.includes('r592=2026.10.28.r592'), false);
  assert.equal(app.split('r592=2026.10.28.r592').length - 1, 7);
});
