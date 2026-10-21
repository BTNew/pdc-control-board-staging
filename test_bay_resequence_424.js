'use strict';
// r424 (F38): a stopped job in Unallocated can be re-planned; a job that runs into the
// same vehicle's next stage warns and offers to push it back; jobs in one bay can be
// moved ahead of / swapped with each other (preview, apply, undo).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { buildWorkshopSharedActions, workshopConfirmBayRuleWarning, workshopPushLaterQuestion } = require('./workshop-shared-actions.js');
const read = f => fs.readFileSync(path.join(__dirname, f), 'utf8');
const planner = read('workshop-planner.js');
const service = read('workshop-data-service.js');
const mig = read('supabase/migrations/20261021012144_r424_bay_resequence.sql');
const down = read('supabase/rollbacks/20261021012144_r424_bay_resequence.down.sql');

const push = { ok: false, warning: true, requires_confirmation: true, error: 'later_bookings_warning', plan_hash: 'h1',
  message: "This job would run into Key 516's next booking. Push 2 bookings back so nothing overlaps?",
  pushes: [{ key_number: '516', work_category: 'BUS_ELECTRICAL', bay_number: 8, from_start: '2026-11-02T03:54:00Z', to_start: '2026-11-06T05:07:00Z' },
    { key_number: '516', work_category: 'BUS_QA', bay_number: 7, from_start: '2026-11-04T00:06:00Z', to_start: '2026-11-10T01:19:00Z' }] };
const rule = { ok: false, warning: true, requires_confirmation: true, error: 'bay_rule_warning', rules: [{ rule: 'category_bay_mismatch', message: 'Bay 8 is Electrical.' }] };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

test('a push-back warning lists the moves and a confirmed change is resent with the plan hash', async () => {
  const calls = [];
  const asked = [];
  const result = await workshopConfirmBayRuleWarning(async (name, params) => { calls.push(params); return calls.length === 1 ? push : { ok: true }; },
    'administrator_move_workshop_booking', { p_booking_id: 'b', p_metadata: { source: 'drag' }, p_request_id: 'r1' }, q => { asked.push(q); return true; });
  assert.equal(result.ok, true);
  assert.equal(calls.length, 2);
  assert.match(asked[0], /Key 516 · electrical · Bay 8/);
  assert.match(asked[0], /Key 516 · qa · Bay 7/);
  assert.match(asked[0], /push them back/);
  assert.deepEqual(calls[1].p_metadata, { source: 'drag', push_later_confirm: { plan_hash: 'h1' } });
  assert.match(calls[1].p_request_id, UUID);
  assert.match(workshopPushLaterQuestion(push), /Cancel to leave everything as it is/);
});

test('Cancel on a push-back leaves everything as it is; a repeated warning is not asked twice', async () => {
  let n = 0;
  const cancelled = await workshopConfirmBayRuleWarning(async () => { n += 1; return push; }, 'x', { p_metadata: {} }, () => false);
  assert.equal(n, 1);
  assert.equal(cancelled.error, 'later_bookings_not_confirmed');
  n = 0;
  const again = await workshopConfirmBayRuleWarning(async () => { n += 1; return push; }, 'x', { p_metadata: {} }, () => true);
  assert.equal(n, 2, 'one resend only');
  assert.equal(again.error, 'later_bookings_warning');
});

test('a bay rule question then a push-back question keep both confirmations', async () => {
  const calls = [];
  const replies = [rule, push, { ok: true }];
  const result = await workshopConfirmBayRuleWarning(async (name, params) => { calls.push(params); return replies[calls.length - 1]; },
    'administrator_move_workshop_booking', { p_metadata: {}, p_request_id: 'r1' }, () => true);
  assert.equal(result.ok, true);
  assert.equal(calls.length, 3);
  assert.deepEqual(calls[2].p_metadata, { bay_rule_confirm: { rules: ['category_bay_mismatch'] }, push_later_confirm: { plan_hash: 'h1' } });
  assert.notEqual(calls[1].p_request_id, calls[2].p_request_id);
});

test('re-order and undo use their own RPCs with the exact parameters', async () => {
  const calls = [];
  const actions = buildWorkshopSharedActions({ mutate: async (name, params) => { calls.push({ name, params }); return { ok: true }; } });
  await actions.resequenceBay({ bookingId: 'a', expectedVersion: 3, targetBookingId: 'b', mode: 'ahead', requestId: 'q1' });
  await actions.resequenceBay({ bookingId: 'a', expectedVersion: 3, targetBookingId: 'b', mode: 'swap', apply: true, planHash: 'h', requestId: 'q2' });
  await actions.undoBayResequence({ receiptId: 'rc', requestId: 'q3' });
  assert.deepEqual(calls[0], { name: 'workshop_resequence_bay_424', params: { p_booking_id: 'a', p_expected_version: 3, p_target_booking_id: 'b', p_mode: 'ahead', p_apply: false, p_plan_hash: null, p_metadata: {}, p_request_id: 'q1' } });
  assert.equal(calls[1].params.p_apply, true);
  assert.equal(calls[1].params.p_plan_hash, 'h');
  assert.deepEqual(calls[2], { name: 'workshop_undo_bay_resequence_424', params: { p_receipt_id: 'rc', p_request_id: 'q3' } });
});

test('the data service knows the RPCs and the new codes, and every code has plain English', () => {
  for (const rpc of ['workshop_resequence_bay_424', 'workshop_undo_bay_resequence_424']) assert.ok(service.includes(`'${rpc}'`), rpc);
  assert.match(service, /workshop_resequence_bay_424: 'p_expected_version'/);
  for (const code of ['later_bookings_warning', 'later_bookings_not_confirmed', 'resequence_rejected', 'plan_changed', 'order_unchanged', 'not_same_bay', 'started_job_fixed', 'resequence_too_large']) {
    assert.ok(service.includes(`'${code}'`), code);
    assert.match(planner, new RegExp(`\\n  ${code}: `), code);
  }
});

function extract(name) {
  const start = planner.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  const open = planner.indexOf(') {', start) + 2;
  let depth = 0;
  for (let i = open; i < planner.length; i += 1) {
    if (planner[i] === '{') depth += 1;
    if (planner[i] === '}') { depth -= 1; if (depth === 0) return planner.slice(start, i + 1); }
  }
  throw new Error(name);
}

test('a stopped job in Unallocated is offered again with its stoppage reason; a stopped job in a bay is not', () => {
  const ctx = {};
  vm.createContext(ctx);
  vm.runInContext([extract('workshopPlanStoppedUnallocated'), extract('workshopReturnedQueuePlans')].join('\n'), ctx);
  const base = { stage: 'BUS_4X4', sharedBayId: '', bay: 0, actualStartAt: '2026-10-20T01:18:00Z', actualEndAt: '', workCategory: 'BUS_MECHANICAL' };
  const rows = [{ ...base, id: 'stopped', sharedStatus: 'stoppage' }, { ...base, id: 'in-bay', sharedStatus: 'stoppage', sharedBayId: 'b1', bay: 1 },
    { ...base, id: 'never-started', sharedStatus: 'stoppage', actualStartAt: '' }, { ...base, id: 'queued', sharedStatus: 'queued' }];
  assert.deepEqual(Array.from(ctx.workshopReturnedQueuePlans(rows, 'BUS_4X4', 'BUS_MECHANICAL'), r => r.id), ['stopped', 'queued']);
  assert.match(planner, /\['Stopped', cleanNavisionText\(entry\.stoppageReason \|\| ''\), 'time worked is kept'\]/);
  assert.match(planner, /\['started', 'stoppage', 'completed'\]\.includes\(existing\.status\) && !workshopPlanStoppedUnallocated\(existing\)/);
  assert.match(planner, /entry\.status === 'planned' \|\| workshopPlanStoppedUnallocated\(entry\)/);
});

test('dropping a booking onto another in the same bay finds that booking; other bays and gaps do not', () => {
  const ctx = {
    workshopSharedModeActive: () => true,
    normalizePmbStage: s => String(s || '').toUpperCase(),
    workshopDateAtOffset: (dateKey, minutes) => new Date(Date.parse(`${dateKey}T00:00:00+08:00`) + minutes * 60000),
  };
  vm.createContext(ctx);
  vm.runInContext(`const WORKSHOP_RESEQUENCE_STATUSES = new Set(['planned', 'stoppage']);\n${extract('workshopResequenceTarget')}`, ctx);
  const b = (id, start, end, extra = {}) => ({ id, sharedBookingId: id, sharedStatus: 'planned', stage: 'BUS_4X4', bay: 1, startAt: start, endAt: end, hours: 10, ...extra });
  const k799 = b('799', '2026-10-22T06:00:00+08:00', '2026-10-27T10:30:00+08:00');
  const k516 = b('516', '2026-10-27T10:30:00+08:00', '2026-11-06T12:07:00+08:00', { hours: 73.6 });
  const other = b('x', '2026-10-22T06:00:00+08:00', '2026-10-23T06:00:00+08:00', { bay: 2 });
  const rows = [k799, k516, other];
  assert.equal(ctx.workshopResequenceTarget(k516, 'BUS_4X4', 1, '2026-10-22', 360, rows)?.id, '799', 'onto 799');
  assert.equal(ctx.workshopResequenceTarget(k799, 'BUS_4X4', 1, '2026-10-28', 360, rows)?.id, '516', 'onto 516');
  assert.equal(ctx.workshopResequenceTarget(k516, 'BUS_4X4', 2, '2026-10-22', 360, rows), null, 'another bay is a normal move');
  assert.equal(ctx.workshopResequenceTarget(k516, 'BUS_4X4', 1, '2026-11-20', 360, rows), null, 'an empty time is a normal move');
  assert.equal(ctx.workshopResequenceTarget({ ...k516, sharedStatus: 'started' }, 'BUS_4X4', 1, '2026-10-22', 360, rows), null, 'started jobs stay fixed');
  ctx.workshopSharedModeActive = () => false;
  assert.equal(ctx.workshopResequenceTarget(k516, 'BUS_4X4', 1, '2026-10-22', 360, rows), null);
});

test('the re-order uses dialogs (no window.confirm), a preview, the plan hash and an undo', () => {
  const drop = extract('workshopResequenceDrop');
  assert.doesNotMatch(drop + extract('workshopResequenceDialog'), /window\.confirm|confirm\(/);
  assert.match(drop, /apply: false/);
  assert.match(drop, /apply: true, planHash: preview\.plan_hash/);
  assert.match(drop, /Move ahead of/);
  assert.match(drop, /Swap with/);
  assert.match(planner, /data-workshop-undo-bay-resequence>Undo re-order/);
  assert.match(extract('workshopUndoLastBayResequence'), /undoBayResequence/);
  assert.match(planner, /const resequenceTarget = workshopResequenceTarget\(entry, stage, bay, dateKey, startMinutes, workshopLoadPlans\(\)\);/);
});

test('migration: server-side checks, receipts, undo, warn-and-confirm, clock tick untouched; rollback is exact', () => {
  assert.match(mig, /CREATE FUNCTION public\.workshop_resequence_bay_424\(/);
  assert.match(mig, /CREATE FUNCTION public\.workshop_undo_bay_resequence_424\(/);
  assert.match(mig, /require_vehicle_planner\(\)/);
  assert.match(mig, /push_later_confirm/);
  assert.match(mig, /later_bookings_warning/);
  assert.match(mig, /'bay_resequence_and_stopped_replan','F38'/);
  assert.match(mig, /84af7607bfd0ce9907c89bae8644d5b6/);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/);
  assert.match(mig, /REVOKE ALL ON SCHEMA pdc_bay_seq_private FROM PUBLIC/);
  assert.match(down, /DROP FUNCTION public\.workshop_resequence_bay_424\(/);
  assert.match(down, /DROP SCHEMA pdc_bay_seq_private CASCADE/);
  assert.match(down, /0f5bff8f/);
  assert.doesNotMatch(mig + down, /[a-z0-9._-]+@[a-z0-9-]+\.[a-z.]+/i, "no e-mail addresses in repo SQL");
});
