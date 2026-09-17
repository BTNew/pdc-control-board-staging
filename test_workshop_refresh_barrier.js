'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createWorkshopDataService, createWorkshopSupabaseClient, WORKSHOP_CONNECTION_STATE: STATES } = require('./workshop-data-service.js');

const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const response = (revision = 1, status = 'planned') => ({ ok: true, status: 200, body: { revision, bookings: [{ id: 'booking-one', status }] } });
const confirmed = { ok: true, booking_id: 'booking-one', status: 'started', shifted_count: 2 };
const scope = { stageCode: 'FITTING', dateFrom: '2026-09-16', dateTo: '2026-09-16' };
function fixture() {
  let token = 'actor-one', role = 'operator', timerId = 0;
  let read = async () => response(), write = async () => ({ ok: true, status: 200, body: confirmed });
  const calls = [], snapshots = [], timers = new Map();
  const service = createWorkshopDataService({ config: { workshop: { sharedData: true } }, scope,
    getAccessToken: () => token, getRole: () => role, onSnapshot: value => snapshots.push(value),
    scheduleTimeout: (fn, ms) => { const id = ++timerId; timers.set(id, { fn, ms }); return id; },
    clearScheduledTimeout: id => timers.delete(id),
    client: { rpc: async (...args) => { calls.push(args); return args[1].includes('snapshot') ? read(...args) : write(...args); } },
  });
  return { service, calls, snapshots, timers, setRead: value => { read = value; }, setWrite: value => { write = value; },
    setToken: value => { token = value; }, setRole: value => { role = value; },
    reads: () => calls.filter(call => call[1].includes('snapshot')),
    writes: () => calls.filter(call => !call[1].includes('snapshot')),
    fire: ms => { const timer = [...timers.entries()].find(([, value]) => value.ms === ms); assert.ok(timer, `timer ${ms} exists`); timers.delete(timer[0]); timer[1].fn(); },
    mutate: () => service.mutate('start_workshop_work', { p_booking_id: 'booking-one', p_expected_version: 1 }),
  };
}

test('Start joins the active snapshot without self-requested trailing reads', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const pending = deferred(); h.setRead(() => pending.promise);
  const background = h.service.loadSnapshot('background');
  let settled = false; const action = h.mutate().then(value => { settled = true; return value; });
  await flush(); await flush();
  assert.equal(settled, false); assert.equal(h.reads().length, 2); assert.equal(h.writes().length, 0);
  h.setRead(async () => response(2, 'started')); pending.resolve(response());
  await background; assert.deepEqual(await action, confirmed);
  assert.equal(h.reads().length, 3, 'initial, active preflight and one post-write read');
  assert.equal(h.writes().length, 1); assert.equal(h.service.getTrustedSnapshot().bookings[0].status, 'started');
  assert.equal(h.timers.size, 0);
});

test('a revision burst during preflight schedules exactly one genuine trailing refresh', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const first = deferred(), latest = deferred(); let reads = 0;
  h.setRead(() => ++reads === 1 ? first.promise : reads === 2 ? latest.promise : Promise.resolve(response(3, 'started')));
  const background = h.service.loadSnapshot('background');
  for (let revision = 2; revision <= 30; revision++) h.service.onRevisionSignal(revision);
  const action = h.mutate(); await flush();
  assert.equal(h.reads().length, 2); assert.equal(h.writes().length, 0);
  first.resolve(response()); await flush();
  assert.equal(h.reads().length, 3); assert.equal(h.writes().length, 0);
  latest.resolve(response(30)); await background; assert.deepEqual(await action, confirmed);
  assert.equal(h.reads().length, 4, 'one initial, one existing, one revision trailing, one post-write');
  assert.equal(h.writes().length, 1); assert.equal(h.timers.size, 0);
});

test('confirmed write waits for a post-commit read when an older read is already active', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const command = deferred(), old = deferred(), current = deferred(); let reads = 0;
  h.setWrite(() => command.promise); h.setRead(() => ++reads === 1 ? old.promise : current.promise);
  let settled = false; const action = h.mutate().then(value => { settled = true; return value; });
  const background = h.service.loadSnapshot('before-commit');
  command.resolve({ ok: true, status: 200, body: confirmed }); await flush();
  assert.equal(settled, false); assert.equal(h.service.getTrustedSnapshot(), null);
  old.resolve(response()); await flush();
  assert.equal(settled, false); assert.equal(h.reads().length, 3);
  current.resolve(response(2, 'started')); await background;
  assert.deepEqual(await action, confirmed); assert.equal(h.service.getTrustedSnapshot().revision, 2);
  assert.equal(h.writes().length, 1); assert.equal(h.timers.size, 0);
});

test('confirmed write plus failed readback remains saved, read-only and never replayed', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  h.setRead(async () => ({ ok: false, status: 503, body: { message: 'unavailable' } }));
  const result = await h.mutate();
  assert.deepEqual(result, { ...confirmed, reconciliation: 'pending', refreshRequired: true });
  assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.service.getState(), STATES.OFFLINE_READ_ONLY);
  assert.equal(h.writes().length, 1); assert.equal(h.timers.size, 0);
});

test('hung readback times out even when the client ignores cancellation and late data stays inert', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const old = deferred(); h.setRead(() => old.promise); const action = h.mutate(); await flush();
  const signal = h.reads().at(-1)[3].signal;
  h.fire(15000); const result = await action;
  assert.equal(signal.aborted, true); assert.equal(result.ok, true); assert.equal(result.refreshRequired, true);
  assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.writes().length, 1);
  h.setRead(async () => response(3, 'started')); await h.service.loadSnapshot('retry-read-only');
  old.resolve(response(99, 'planned')); await flush();
  assert.equal(h.service.getTrustedSnapshot().revision, 3); assert.equal(h.writes().length, 1); assert.equal(h.timers.size, 0);
});

test('overall wait is bounded across continuing revision-triggered reads', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const first = deferred(), trailing = deferred(); let reads = 0;
  h.setRead(() => ++reads === 1 ? first.promise : trailing.promise);
  const action = h.mutate(); await flush(); h.service.onRevisionSignal(3); h.fire(250);
  first.resolve(response(2, 'started')); await flush();
  h.fire(20000); const result = await action;
  assert.equal(result.ok, true); assert.equal(result.refreshRequired, true); assert.equal(h.writes().length, 1);
  await flush(); assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.timers.size, 0);
});

for (const change of ['logout', 'token', 'role', 'scope', 'destroy']) {
  test(`authority ${change} during confirmed-write readback releases waiters without old success`, async () => {
    const h = fixture(); await h.service.loadSnapshot('initial');
    const old = deferred(); h.setRead(() => old.promise); const action = h.mutate(); await flush();
    const signal = h.reads().at(-1)[3].signal;
    if (change === 'logout') { h.setToken(null); h.service.onAuthorityLost(); }
    if (change === 'token') { h.setRead(async () => response(4)); h.setToken('actor-two'); h.service.onTokenRefresh(); }
    if (change === 'role') { h.setRole('viewer'); h.service.onAuthorityLost(); }
    if (change === 'scope') { h.setRead(async () => response(4)); await h.service.setScope({ ...scope, stageCode: 'TINT' }); }
    if (change === 'destroy') h.service.destroy();
    const result = await action;
    assert.equal(result.ok, false); assert.equal(result.error, change === 'destroy' ? 'destroyed' : 'authority_superseded');
    assert.equal(result.booking_id, undefined); assert.equal(signal.aborted, true); assert.equal(h.writes().length, 1);
    old.resolve(response(99)); await flush();
    assert.notEqual(h.service.getLastRevision(), 99); h.service.destroy(); await flush(); assert.equal(h.timers.size, 0);
  });
}

test('authority change during preflight cannot submit a queued write as the replacement actor', async () => {
  const h = fixture(), old = deferred(); h.setRead(() => old.promise);
  const background = h.service.loadSnapshot('initial'), action = h.mutate(); await flush();
  h.setToken('actor-two'); h.service.onAuthorityLost();
  assert.equal((await action).error, 'authority_superseded'); await background;
  assert.equal(h.writes().length, 0); old.resolve(response(99)); await flush();
  assert.equal(h.service.getLastSnapshot(), null); assert.equal(h.timers.size, 0);
});

test('token or role changes without callbacks are caught after the command and readback', async () => {
  for (const phase of ['command', 'readback']) for (const kind of ['token', 'role']) {
    const h = fixture(); await h.service.loadSnapshot('initial'); const old = deferred();
    if (phase === 'command') h.setWrite(() => old.promise); else h.setRead(() => old.promise);
    const action = h.mutate(); await flush();
    if (kind === 'token') h.setToken('actor-two'); else h.setRole('viewer');
    old.resolve(phase === 'command' ? { ok: true, body: confirmed } : response(2, 'started'));
    const result = await action; assert.equal(result.ok, false); assert.equal(result.error, 'authority_superseded');
    assert.equal(h.service.getLastSnapshot(), null); assert.equal(h.timers.size, 0);
  }
});

test('RPC client forwards read cancellation without inventing automatic mutation retries', async () => {
  const calls = [], controller = new AbortController();
  const client = createWorkshopSupabaseClient({ url: 'https://example.test', publishableKey: 'public-key' }, async (...args) => {
    calls.push(args); return { ok: true, status: 200, json: async () => ({ ok: true }) };
  });
  await client.rpc('actor-token', 'get_workshop_snapshot', {}, { signal: controller.signal });
  await client.rpc('actor-token', 'start_workshop_work', { p_expected_version: 1 });
  assert.equal(calls[0][1].signal, controller.signal); assert.equal(calls[1][1].signal, undefined); assert.equal(calls.length, 2);
});

test('proxy and timeout responses preserve uncertainty without masking canonical rejections', async () => {
  for (const status of [408, 500, 502, 503, 504]) {
    const h = fixture(); await h.service.loadSnapshot('initial');
    h.setWrite(async () => ({ ok: false, status, body: { code: 'proxy_error', message: 'Response unavailable' } }));
    const result = await h.mutate(); assert.equal(result.ok, false); assert.equal(result.outcomeUnknown, true);
    assert.equal(result.code, 'proxy_error'); assert.equal(h.writes().length, 1); assert.equal(h.timers.size, 0);
  }
  const h = fixture(); await h.service.loadSnapshot('initial');
  h.setWrite(async () => ({ ok: false, status: 500, body: { message: '{"error":"fixed_booking_conflict"}' } }));
  const result = await h.mutate(); assert.equal(result.error, 'fixed_booking_conflict'); assert.equal(result.outcomeUnknown, undefined);
  assert.equal(h.writes().length, 1);
});
