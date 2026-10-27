/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r571 (F185) / sort 343. A drop between jobs pushes later jobs in that bay.
// A started or stoppage booking of the same vehicle cannot move; the planner
// is asked to place this job after it. A raw vehicle exclusion is not shown.
// Preview only: the migration is not applied. #557's head is not edited.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { workshopPlaceAfterQuestion, workshopConfirmBayRuleWarning, workshopPushLaterQuestion, buildWorkshopSharedActions } = require('./workshop-shared-actions.js');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const up = read('supabase/migrations/20261027230000_r571_slot_between_jobs.sql');
const down = read('supabase/rollbacks/20261027230000_r571_slot_between_jobs.down.sql');
const planner = read('workshop-planner.js');
const app = read('app.js');
const key112 = {
  message: 'Key 112, stock 13109746, KIMBERLEY ABORIGINAL MEDICAL is on stoppage in Fitting, Unallocated, until Wed 28 Oct 07:08. That booking cannot move. Place this job right after it.',
  place_after: '2026-10-28T00:08:00.000Z',
  bay_push_count: 0,
  plan_hash: 'fit-stop',
  warning: true,
  requires_confirmation: true,
  ok: false,
  error: 'place_after_running',
};

test('r571 migration is a staging preview stacked on r567: pins stay 241 and department 135 stays frozen', () => {
  for (const src of [up, down]) {
    assert.match(src, /SET LOCAL lock_timeout = '2s'/);
    assert.match(src, /NOT BETWEEN 2 AND 45/);
    assert.match(src, /cdsmnqxtyyoeoznmbidd/);
    assert.match(src, /pdc_production_environment_sentinel/);
    assert.match(src, /staging only/);
    assert.match(src, /<>241/);
    assert.match(src, /4eb5baf999b849d174880a1e261fcbf2/);
    assert.match(src, /Production vjdtsswhroyguxyfjdkt is not a target/);
    assert.doesNotMatch(src, /project_ref='vjdtsswhroyguxyfjdkt'/);
  }
  assert.match(up, /cross_station_drop_576/);
  assert.match(up, /keeps the live argument defaults/);
  assert.match(up, /p_duration_minutes integer DEFAULT NULL::integer, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT ''\{\}''::jsonb/);
  assert.match(up, /p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid/);
  assert.match(up, /p_shift_minutes integer DEFAULT 0, p_override_reason text DEFAULT NULL::text/);
  assert.match(down, /p_duration_minutes integer DEFAULT NULL::integer/);
  assert.match(down, /p_duration_minutes integer DEFAULT 180/);
  assert.match(up, /b6e8241730be349bdd79a295afba0a8a/);
  assert.match(up, /r576 \(F190\)/);
  assert.doesNotMatch(up, /r567/);
  assert.match(up, /bay_job_pause_569/);
  assert.match(up, /sort_order=343 OR fault_id='F185'/);
  assert.match(up, /'slot_between_571','F185'/);
  assert.match(up, /, 343, 'r571'/);
  assert.match(up, /SECURITY DEFINER/);
  assert.match(up, /SET search_path TO ''pg_catalog'', ''public'', ''extensions''/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /REVOKE ALL ON FUNCTION public\.workshop_exclusion_conflict_571/);
  assert.match(down, /DROP FUNCTION public\.workshop_exclusion_conflict_571/);
  assert.match(down, /release='r576'/);
  assert.doesNotMatch(down, /r567/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks/);
  assert.match(down, /sort_order=343 AND added_in='r571'/);
  const pair = /old:=\$old\$([\s\S]*?)\$old\$;\n repl:=\$new\$([\s\S]*?)\$new\$;/g;
  const pairs = [...up.matchAll(pair)];
  assert.equal(pairs.length, 12);
  for (const match of pairs) {
    assert.ok(down.includes(`$old$${match[2]}$old$`), 'down does not remove the r571 text');
    assert.ok(down.includes(`$new$${match[1]}$new$`), 'down does not restore the previous text');
  }
});

test('the place-after question names Key 112 and only mentions a bay push when later jobs exist', () => {
  const named = workshopPlaceAfterQuestion(key112);
  assert.match(named, /Key 112/);
  assert.match(named, /13109746/);
  assert.match(named, /KIMBERLEY ABORIGINAL MEDICAL/);
  assert.match(named, /Fitting/);
  assert.match(named, /Unallocated/);
  assert.match(named, /stoppage/);
  assert.match(named, /Wed 28 Oct/);
  assert.match(named, /right after it/);
  assert.match(named, /08:08/);
  assert.doesNotMatch(named, /Later jobs in this bay/);
  assert.match(named, /Cancel to leave everything as it is/);
  const pushed = workshopPlaceAfterQuestion({ ...key112, bay_push_count: 2 });
  assert.match(pushed, /Later jobs in this bay move back too/);
  assert.match(workshopPushLaterQuestion({
    message: "This job would run into Key 516's next booking. Push 2 bookings back so nothing overlaps?",
    pushes: [{ key_number: '516', work_category: 'BUS_ELECTRICAL', bay_number: 8, from_start: '2026-11-02T03:54:00Z', to_start: '2026-11-06T05:07:00Z' }],
  }), /Key 516 · electrical · Bay 8/);
});

test('confirming place-after resends that start, and cancel saves nothing', async () => {
  const calls = [];
  const saved = await workshopConfirmBayRuleWarning(async (_name, params) => {
    calls.push(params);
    return calls.length === 1 ? key112 : { ok: true };
  }, 'administrator_move_workshop_booking', {
    p_scheduled_start_at: '2026-10-27T04:00:00.000Z',
    p_metadata: { source: 'planner_chip_drop' },
    p_request_id: 'r1',
  }, () => true);
  assert.equal(saved.ok, true);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].p_scheduled_start_at, '2026-10-28T00:08:00.000Z');
  assert.deepEqual(calls[1].p_metadata.place_after_running, { plan_hash: 'fit-stop' });
  assert.equal(calls[1].p_metadata.source, 'planner_chip_drop');
  assert.notEqual(calls[1].p_request_id, 'r1');
  let n = 0;
  const cancelled = await workshopConfirmBayRuleWarning(async () => { n += 1; return key112; }, 'x', { p_metadata: {} }, () => false);
  assert.equal(n, 1);
  assert.equal(cancelled.cancelled, true);
  assert.equal(cancelled.error, 'place_after_not_confirmed');
});

test('a new booking drop can ask the same question without inventing a request id', async () => {
  const calls = [];
  const actions = buildWorkshopSharedActions({ mutate: async (name, params) => {
    calls.push({ name, params });
    return calls.length === 1 ? key112 : { ok: true, booking: { booking_id: 'new' } };
  } }, { confirmBayRule: () => true });
  const saved = await actions.scheduleVehicleWork({
    vehicleId: '526a2e95-7b74-4ee2-aaa0-c4122fd895cb',
    vehicleExpectedVersion: 1,
    stageCode: 'TINT',
    bayNumber: 1,
    scheduledStartAt: '2026-10-27T04:00:00.000Z',
    durationMinutes: 60,
  });
  assert.equal(saved.ok, true);
  assert.equal(calls[0].name, 'schedule_vehicle_work');
  assert.equal(calls[1].params.p_scheduled_start_at, '2026-10-28T00:08:00.000Z');
  assert.equal(Object.hasOwn(calls[1].params, 'p_request_id'), false);
  const moveCalls = [];
  const moving = buildWorkshopSharedActions({ mutate: async (name, params) => { moveCalls.push({ name, params }); return { ok: true }; } });
  await moving.moveBooking({ bookingId: 'b', expectedVersion: 2, stageCode: 'TINT', bayNumber: 1, scheduledStartAt: '2026-10-27T04:00:00Z', durationMinutes: 60 });
  await moving.cascadeMoveBooking({ bookingId: 'b', expectedVersion: 2, stageCode: 'TINT', bayNumber: 1, scheduledStartAt: '2026-10-27T04:00:00Z', durationMinutes: 60 });
  await moving.cascadeSchedule({ operation: 'insert', targetId: 'v', targetExpectedVersion: 1, stageCode: 'TINT', bayNumber: 1, scheduledStartAt: '2026-10-27T04:00:00Z', durationMinutes: 60 });
  assert.deepEqual(moveCalls.map(call => call.name), ['move_workshop_booking', 'cascade_workshop_booking_move', 'cascade_workshop_schedule']);
});

test('place-after and the other-station confirm can both be accepted before anything is saved', async () => {
  const push = {
    ok: false, warning: true, requires_confirmation: true, error: 'later_bookings_warning', plan_hash: 'h1',
    message: 'This drop would book this vehicle in two places at once.',
    pushes: [{ key_number: '112', stock_number: '13109746', customer_name: 'KIMBERLEY ABORIGINAL MEDICAL', stage_name: 'Tint', bay_display_name: 'Tint Bay 01', from_start: '2026-10-27T04:45:00Z', to_start: '2026-10-28T00:08:00Z' }],
  };
  const calls = [];
  const replies = [key112, push, { ok: true }];
  const result = await workshopConfirmBayRuleWarning(async (_name, params) => {
    calls.push(params);
    return replies[calls.length - 1];
  }, 'administrator_move_workshop_booking', { p_metadata: {}, p_request_id: 'r1', p_scheduled_start_at: '2026-10-27T04:00:00.000Z' }, () => true);
  assert.equal(result.ok, true);
  assert.equal(calls.length, 3);
  assert.equal(calls[1].p_scheduled_start_at, '2026-10-28T00:08:00.000Z');
  assert.equal(calls[2].p_scheduled_start_at, '2026-10-28T00:08:00.000Z');
  assert.equal(calls[2].p_metadata.place_after_running.plan_hash, 'fit-stop');
  assert.equal(calls[2].p_metadata.push_later_confirm.plan_hash, 'h1');
});

test('a timed drop cascades in every bay, the dialog is blue, and a raw exclusion is plain English', () => {
  assert.match(planner, /const cascade = preferRequestedTime === true/);
  assert.equal(planner.includes('preferRequestedTime && movingBetweenBays'), false);
  const dialog = planner.slice(planner.indexOf('function workshopPlaceAfterDialog('), planner.indexOf('function workshopResequencePreviewHtml('));
  assert.match(dialog, /Place this job after that booking\?/);
  assert.match(dialog, /Place after/);
  assert.match(dialog, /#1d4ed8/);
  assert.match(dialog, /workshop-push-go/);
  assert.doesNotMatch(dialog, /#f97316|#ea580c|#c2410c|orange/i);
  assert.match(planner, /This vehicle is already booked at that time\. No update was saved\./);
  assert.match(planner, /place_after_not_confirmed: 'No change was made\. The job stays where it is\.'/);
  assert.equal(app.split('r571=2026.10.27.r571').length - 1, 4);
  assert.equal(app.split('r567=2026.10.27.r567').length - 1, 4);
  for (const file of ['karratha/workshop-planner.js', 'karratha/workshop-shared-actions.js', 'karratha/app.js']) {
    const text = read(file);
    assert.equal(text.includes('r571'), false, file);
    assert.equal(text.includes('preferRequestedTime === true'), false, file);
  }
  assert.match(read('karratha/workshop-planner.js'), /preferRequestedTime && movingBetweenBays/);
});
