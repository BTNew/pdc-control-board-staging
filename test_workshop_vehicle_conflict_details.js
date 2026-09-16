'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
const start = source.indexOf('function workshopDescribeSharedActionError(');
const end = source.indexOf('function workshopPersistPlanAction(', start);
const A = 'a1000000-0000-4000-8000-000000000001';
const B = 'b1000000-0000-4000-8000-000000000002';
const V = 'c1000000-0000-4000-8000-000000000003';
const W = 'd1000000-0000-4000-8000-000000000004';
const record = () => ({ booking_id: A, vehicle_id: V, stage: { code: 'FITTING' }, bay: { bay_number: 2 }, scheduled_start_at: '2026-09-18T01:00:00Z', scheduled_end_at: '2026-09-18T03:00:00Z' });
const wrapper = id => ({ error: 'vehicle_overlap', body: { code: '22023', message: `Workshop Planner validation rejected booking: ${JSON.stringify({ ok: false, error: 'vehicle_overlap', conflict_booking_id: id })}`, details: null, hint: null } });

function runtime(snapshot) {
  const reads = { trusted: 0, legacy: 0 };
  const context = vm.createContext({
    window: { __workshopDataService: {
      getTrustedSnapshot() { reads.trusted++; return snapshot; },
      getLastSnapshot() { reads.legacy++; throw new Error('Untrusted data must not be read'); },
    } },
    workshopAdministratorCanMove: () => false,
  });
  vm.runInContext(source.slice(start, end), context);
  return { describe: context.workshopDescribeSharedActionError, reads };
}

test('SQL trigger wrapper resolves the canonical booking UUID and separate vehicle UUID', () => {
  const { describe, reads } = runtime({ bookings: [record()], vehicles: [{ id: V, stock_number: 'TEST-13043983' }] });
  const message = describe(wrapper(A.toUpperCase()));
  assert.match(message, /stock TEST-13043983 · Fitting · Bay 2/);
  assert.match(message, /18 Sept,? 9:00 am/);
  assert.match(message, /18 Sept,? 11:00 am/);
  assert.match(message, /Perth time/);
  assert.match(message, /No conflicting bookings were saved/);
  assert.match(message, /at least 1 hour/);
  assert.equal(reads.trusted, 1);
  assert.equal(reads.legacy, 0);
  assert.ok(!message.includes(A));
});

test('structured canonical existing_booking works without a cached snapshot', () => {
  const { describe } = runtime(null);
  const dto = { ...record(), vehicle: { id: V, stock_number: 'TEST-NEW' }, stage: { code: 'TINT' } };
  const message = describe({ error: 'vehicle_overlap', conflict: { existing_booking: dto } });
  assert.match(message, /stock TEST-NEW · Tint · Bay 2/);
  assert.match(message, /9:00 am/);
});

test('canonical HTTP body details and blocker booking UUID are supported', () => {
  const { describe } = runtime({ bookings: [record()], vehicles: [{ id: V, stock_number: 'TEST-A' }] });
  assert.match(describe({ error: 'vehicle_overlap', body: { error: 'vehicle_overlap', blocker: { booking_id: A } } }), /stock TEST-A/);
  assert.match(describe({ error: 'vehicle_overlap', body: { details: JSON.stringify({ error: 'vehicle_overlap', conflict_booking_id: A }) } }), /stock TEST-A/);
});

test('a stock, key or noncanonical booking identifier never selects another booking', () => {
  const { describe } = runtime({ bookings: [record(), { ...record(), booking_id: B, vehicle_id: W }], vehicles: [{ id: V, stock_number: 'SAME' }, { id: W, stock_number: 'SAME' }] });
  const generic = describe({ error: 'vehicle_overlap' });
  for (const id of ['SAME', '', 'key-223', 'another-uuid', 'e1000000-0000-4000-8000-000000000005']) {
    assert.equal(describe(wrapper(id)), generic);
  }
  assert.equal(describe({ error: 'vehicle_overlap', conflict: { existing_booking: { vehicleKey: 'SAME', stock_number: 'SAME', stage: { code: 'TINT' } } } }), generic);
});

test('duplicate stocks do not confuse canonical booking and vehicle matching', () => {
  const { describe } = runtime({ bookings: [record(), { ...record(), booking_id: B, vehicle_id: W, stage: { code: 'TINT' }, bay: { bay_number: 9 } }], vehicles: [{ id: W, stock_number: 'SAME' }, { id: V, stock_number: 'SAME' }] });
  const message = describe(wrapper(A));
  assert.match(message, /Fitting · Bay 2/);
  assert.doesNotMatch(message, /Tint|Bay 9/);
});

test('missing trusted data and duplicate booking UUIDs retain the generic warning', () => {
  for (const snapshot of [null, { bookings: [] }, { bookings: [record(), record()] }]) {
    const { describe, reads } = runtime(snapshot);
    assert.equal(describe(wrapper(A)), describe({ error: 'vehicle_overlap' }));
    assert.equal(reads.legacy, 0);
  }
});

test('conflicting canonical UUID claims are not combined into a misleading summary', () => {
  const { describe } = runtime({ bookings: [record()], vehicles: [{ id: V, stock_number: 'TEST-A' }] });
  const generic = describe({ error: 'vehicle_overlap' });
  assert.equal(describe({ error: 'vehicle_overlap', conflict_booking_id: B, conflict: { existing_booking: record() } }), generic);
  assert.equal(describe({ error: 'vehicle_overlap', conflict: { existing_booking: { ...record(), vehicle_id: W } } }), generic);
  assert.equal(describe({ error: 'vehicle_overlap', conflict: { existing_booking: { ...record(), vehicle: { id: W, stock_number: 'WRONG' } } } }), generic);
});

test('malformed, unrelated, oversized and false JSON errors fall back without leaking raw text', () => {
  const { describe } = runtime({ bookings: [record()], vehicles: [{ id: V, stock_number: 'TEST-A' }] });
  const generic = describe({ error: 'vehicle_overlap' });
  for (const message of [
    '{"error":"vehicle_overlap",',
    `Unrelated diagnostic ${JSON.stringify({ error: 'vehicle_overlap', conflict_booking_id: A })}`,
    JSON.stringify({ error: 'bay_overlap', conflict_booking_id: A }),
    JSON.stringify({ error: 'vehicle_overlap', conflict_booking_id: A, diagnostic: 'x'.repeat(8192) }),
    JSON.stringify([{ error: 'vehicle_overlap', conflict_booking_id: A }]),
  ]) assert.equal(describe({ error: 'vehicle_overlap', body: { message } }), generic);
});

test('details are plain bounded text, malformed timestamps add no invented schedule', () => {
  const { describe } = runtime(null);
  const dto = { ...record(), vehicle: { id: V, stock_number: '<img src=x>\nTEST\u202e' }, scheduled_start_at: 'not-a-date', scheduled_end_at: 'also-invalid' };
  const message = describe({ error: 'vehicle_overlap', conflict: { existing_booking: dto } });
  assert.match(message, /stock <img src=x> TEST · Fitting · Bay 2/);
  assert.doesNotMatch(message, /Invalid Date|scheduled|not-a-date|\n|\u202e/);
  // The formatter returns text; its alert callers and feedback rendering own
  // presentation. The existing feedback renderer escapes that text for HTML.
  assert.equal(typeof message, 'string');
});

test('uncertain outcomes keep their separate warning and do not claim rejection', () => {
  const { describe, reads } = runtime({ bookings: [record()] });
  const message = describe({ ...wrapper(A), outcomeUnknown: true });
  assert.match(message, /could not be confirmed/);
  assert.doesNotMatch(message, /No conflicting bookings were saved/);
  assert.equal(reads.trusted, 0);
});
