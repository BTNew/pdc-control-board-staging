'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createWorkshopDataService } = require('./workshop-data-service');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const snapshot = revision => ({ ok: true, status: 200, body: { revision, bookings: [{ id: 'saved-booking', version: revision }] } });
const confirmed = { ok: true, booking_id: 'saved-booking' };
const scope = { stageCode: 'FITTING', dateFrom: '2026-09-17', dateTo: '2026-09-17' };

function fixture(options = {}) {
  let token = 'session-one', role = 'operator', timerId = 0;
  let read = async () => snapshot(1), write = async () => ({ ok: true, body: confirmed });
  let probe = async () => ({ ok: true, body: [{ revision: 1 }] });
  const calls = [], delivered = [], timers = new Map();
  const client = { rpc: async (_token, name, params) => {
    calls.push(name); return name.includes('snapshot') ? read(name, params) : write(name, params);
  } };
  if (options.probes) client.readRevision = async (...args) => { calls.push('revision'); return probe(...args); };
  const service = createWorkshopDataService({ config: { workshop: { sharedData: true } }, scope, client,
    getAccessToken: () => token, getRole: () => role, onSnapshot: value => delivered.push(value.revision),
    scheduleTimeout: (fn, ms) => { const id = ++timerId; timers.set(id, { fn, ms }); return id; },
    clearScheduledTimeout: id => timers.delete(id),
  });
  return { service, calls, delivered, timers,
    setRead: fn => { read = fn; }, setWrite: fn => { write = fn; }, setProbe: fn => { probe = fn; },
    setToken: value => { token = value; }, setRole: value => { role = value; },
    reads: () => calls.filter(name => name.includes('snapshot')).length,
    fire: ms => { const entry = [...timers].find(([, value]) => value.ms === ms); assert.ok(entry, `timer ${ms}`); timers.delete(entry[0]); entry[1].fn(); },
    move: () => service.mutate('move_workshop_booking', { p_booking_id: 'saved-booking', p_expected_version: 1 }),
  };
}

for (const debounceFired of [false, true]) {
  test(`one post-save read satisfies a covered Realtime burst (${debounceFired ? 'after' : 'before'} debounce)`, async () => {
    const h = fixture(); await h.service.loadSnapshot('initial');
    const gate = deferred(); h.setRead(() => gate.promise);
    const saved = h.move(); await tick();
    for (let revision = 2; revision <= 30; revision++) h.service.onRevisionSignal(revision);
    assert.equal(h.service.getTrustedSnapshot(), null);
    if (debounceFired) h.fire(250);
    gate.resolve(snapshot(30)); assert.deepEqual(await saved, confirmed);
    assert.equal(h.reads(), 2, 'one initial + one mandatory post-commit read, with no duplicate');
    assert.deepEqual(h.delivered, [1, 30]); assert.equal(h.service.getTrustedSnapshot().revision, 30);
    assert.equal(h.timers.size, 0);
    h.service.onRevisionSignal(29); h.service.onRevisionSignal(30);
    assert.equal(h.timers.size, 0, 'late/out-of-order covered events do not download or repaint');
  });
}

test('a newer revision not covered by readback still waits for one trailing authoritative read', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const first = deferred(), last = deferred(); let calls = 0;
  h.setRead(() => ++calls === 1 ? first.promise : last.promise);
  let complete = false; const saved = h.move().then(value => { complete = true; return value; }); await tick();
  h.service.onRevisionSignal(3); h.fire(250); first.resolve(snapshot(2)); await tick();
  assert.equal(h.reads(), 3); assert.equal(complete, false); assert.equal(h.service.getTrustedSnapshot(), null);
  last.resolve(snapshot(3)); assert.deepEqual(await saved, confirmed);
  assert.equal(h.service.getTrustedSnapshot().revision, 3); assert.equal(h.timers.size, 0);
});

for (const signal of [undefined, 'invalid', 9007199254740992]) {
  test(`unknown invalidation (${String(signal)}) cannot be satisfied by an overlapping read`, async () => {
    const h = fixture(); await h.service.loadSnapshot('initial');
    const first = deferred(); let calls = 0;
    h.setRead(() => ++calls === 1 ? first.promise : Promise.resolve(snapshot(3)));
    const saved = h.move(); await tick(); h.service.onRevisionSignal(2); h.service.onRevisionSignal(signal); h.fire(250);
    first.resolve(snapshot(2)); assert.deepEqual(await saved, confirmed);
    assert.equal(h.reads(), 3); assert.equal(h.service.getTrustedSnapshot().revision, 3); assert.equal(h.timers.size, 0);
  });
}

test('even a covered snapshot issued before command completion never replaces mandatory post-commit readback', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  const command = deferred(), before = deferred(), after = deferred(); let reads = 0;
  h.setWrite(() => command.promise); h.setRead(() => ++reads === 1 ? before.promise : after.promise);
  let complete = false; const saved = h.move().then(value => { complete = true; return value; });
  const background = h.service.loadSnapshot('already-running'); h.service.onRevisionSignal(2); h.fire(250);
  command.resolve({ ok: true, body: confirmed }); await tick(); before.resolve(snapshot(2)); await tick();
  assert.equal(complete, false); assert.equal(h.reads(), 3);
  after.resolve(snapshot(2)); await background; assert.deepEqual(await saved, confirmed);
  assert.equal(h.timers.size, 0);
});

test('signals before the read starts are covered by that fresh read and later new events still reload', async () => {
  const h = fixture(); await h.service.loadSnapshot('initial');
  h.service.onRevisionSignal(2); h.setRead(async () => snapshot(2)); h.fire(250); await tick();
  assert.equal(h.reads(), 2); assert.equal(h.service.getTrustedSnapshot().revision, 2);
  h.service.onRevisionSignal(3); assert.equal(h.service.getTrustedSnapshot(), null);
  h.setRead(async () => snapshot(3)); h.fire(250); await tick();
  assert.equal(h.reads(), 3); assert.equal(h.service.getTrustedSnapshot().revision, 3); assert.equal(h.timers.size, 0);
});

test('decimal string revisions preserve precision when suppressing only covered signals', async () => {
  const h = fixture(); h.setRead(async () => snapshot('9007199254740993')); await h.service.loadSnapshot('initial');
  h.service.onRevisionSignal('9007199254740992'); assert.equal(h.timers.size, 0);
  h.service.onRevisionSignal('9007199254740994'); assert.equal(h.service.getTrustedSnapshot(), null);
  h.setRead(async () => snapshot('9007199254740994')); h.fire(250); await tick(); assert.equal(h.reads(), 2);
});

test('scope/session teardown discards pending revisions without leaking them into new authority', async () => {
  for (const mode of ['scope', 'token', 'role', 'logout', 'destroy']) {
    const h = fixture(); await h.service.loadSnapshot('initial'); const gate = deferred(); h.setRead(() => gate.promise);
    const saved = h.move(); await tick(); h.service.onRevisionSignal(99); h.fire(250);
    h.setRead(async () => snapshot(2));
    if (mode === 'scope') await h.service.setScope({ ...scope, stageCode: 'TINT' });
    if (mode === 'token') { h.setToken('session-two'); await h.service.onTokenRefresh(); }
    if (mode === 'role') { h.setRole('viewer'); h.service.onAuthorityLost(); }
    if (mode === 'logout') { h.setToken(null); h.service.onAuthorityLost(); }
    if (mode === 'destroy') h.service.destroy();
    assert.equal((await saved).ok, false); gate.resolve(snapshot(99)); await tick();
    assert.notEqual(h.service.getLastRevision(), 99); h.service.destroy(); assert.equal(h.timers.size, 0);
  }
});

test('foreground and focus use one revision probe and no unchanged station download', async () => {
  const h = fixture({ probes: true }); await h.service.loadSnapshot('initial'); const gate = deferred(); h.setProbe(() => gate.promise);
  const visible = h.service.onVisibilityReturn(), focus = h.service.reconcileRevision('focus');
  assert.equal(visible, focus); assert.equal(h.calls.filter(name => name === 'revision').length, 1);
  gate.resolve({ ok: true, body: [{ revision: 1 }] }); await visible;
  assert.equal(h.reads(), 1); assert.deepEqual(h.delivered, [1]); assert.equal(h.timers.size, 0);
});

test('foreground changed revision reloads; old transports retain fresh full-read fallback', async () => {
  for (const probes of [true, false]) {
    const h = fixture({ probes }); await h.service.loadSnapshot('initial');
    h.setProbe(async () => ({ ok: true, body: [{ revision: 2 }] })); h.setRead(async () => snapshot(2));
    await h.service.onVisibilityReturn(); assert.equal(h.reads(), 2); assert.equal(h.service.getTrustedSnapshot().revision, 2);
    assert.equal(h.timers.size, 0);
  }
});

test('failed foreground probes fail closed and cannot mark a retained station editable', async () => {
  for (const result of [{ ok: false, status: 503 }, { ok: false, status: 403 }, { ok: true, body: [] }]) {
    const h = fixture({ probes: true }); await h.service.loadSnapshot('initial'); h.setProbe(async () => result);
    await h.service.onVisibilityReturn(); assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.reads(), 1);
    assert.equal(h.timers.size, 0);
  }
});

for (const failure of ['http', 'network']) {
  test(`a delayed ${failure} foreground failure cannot revoke a later successful same-scope snapshot`, async () => {
    const h = fixture({ probes: true }); await h.service.loadSnapshot('initial'); const gate = deferred();
    h.setProbe(async () => { await gate.promise; if (failure === 'network') throw new Error('disconnected'); return { ok: false, status: 503 }; });
    const foreground = h.service.onVisibilityReturn();
    h.service.onRevisionSignal(2); h.setRead(async () => snapshot(2)); h.fire(250); await tick();
    assert.equal(h.service.getTrustedSnapshot().revision, 2);
    gate.resolve(); await foreground;
    assert.equal(h.service.getTrustedSnapshot().revision, 2); assert.equal(h.service.getState(), 'connected_editable');
    assert.equal(h.reads(), 2); assert.deepEqual(h.delivered, [1, 2]); assert.equal(h.timers.size, 0);
  });
}

test('later snapshot success never suppresses a foreground permission denial or empty RLS response', async () => {
  for (const result of [{ ok: false, status: 401 }, { ok: false, status: 403 }, { ok: true, body: [] }]) {
    const h = fixture({ probes: true }); await h.service.loadSnapshot('initial'); const gate = deferred(); h.setProbe(() => gate.promise);
    const foreground = h.service.onVisibilityReturn();
    h.service.onRevisionSignal(2); h.setRead(async () => snapshot(2)); h.fire(250); await tick();
    assert.equal(h.service.getTrustedSnapshot().revision, 2);
    gate.resolve(result); await foreground;
    assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.timers.size, 0);
    if (result.status === 401 || result.status === 403) assert.equal(h.service.getLastSnapshot(), null);
  }
});

test('a failed newer read cannot make a delayed probe failure preserve old authority', async () => {
  const h = fixture({ probes: true }); await h.service.loadSnapshot('initial'); const gate = deferred(); h.setProbe(() => gate.promise);
  const foreground = h.service.onVisibilityReturn();
  h.service.onRevisionSignal(2); h.setRead(async () => ({ ok: false, status: 503 })); h.fire(250); await tick();
  gate.resolve({ ok: false, status: 503 }); await foreground;
  assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.service.getState(), 'offline_read_only');
  assert.equal(h.timers.size, 0);
});

test('a delayed probe failure does not cross a scope or token authority change', async () => {
  for (const change of ['scope', 'token']) {
    const h = fixture({ probes: true }); await h.service.loadSnapshot('initial'); const gate = deferred(); h.setProbe(() => gate.promise);
    const foreground = h.service.onVisibilityReturn(); h.setRead(async () => snapshot(2));
    if (change === 'scope') await h.service.setScope({ ...scope, stageCode: 'TINT' });
    else { h.setToken('session-two'); await h.service.onTokenRefresh(); }
    gate.resolve({ ok: false, status: 503 }); await foreground;
    assert.equal(h.service.getTrustedSnapshot().revision, 2); assert.equal(h.service.getState(), 'connected_editable');
    assert.equal(h.timers.size, 0);
  }
});

test('Refresh downloads the new station scope once while same-scope explicit Refresh stays fresh', async () => {
  const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
  const start = source.indexOf('function operationalRefreshCommonLoaders('), end = source.indexOf('\nfunction getOperationalRefreshCoordinator(', start);
  const h = fixture(); await h.service.loadSnapshot('initial'); let date = '2026-09-18';
  const context = { app: { activeWorkshopPlannerStage: 'FITTING' }, window: { __workshopDataService: h.service },
    workshopState: () => ({ date }), normalizePmbStage: value => value.toUpperCase(), cleanNavisionText: value => String(value),
  };
  vm.runInNewContext(source.slice(start, end), context);
  const loader = context.operationalRefreshCommonLoaders('workshop').workOperationStates;
  assert.equal((await loader()).ok, true); assert.equal(h.reads(), 2, 'initial + one new-scope read');
  assert.equal((await loader()).ok, true); assert.equal(h.reads(), 3, 'same-scope explicit refresh is not cached');
  assert.equal(h.timers.size, 0);
});
