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

test('slow socket does not delay the initial request, but cannot authorize display or edits', async () => {
  const h = fixture({ probes: true });
  await h.service.startConnecting();
  assert.equal(h.reads(), 1);
  assert.equal(h.service.getLastSnapshot(), null);
  assert.equal(h.service.getTrustedSnapshot(), null);
  assert.equal(h.service.getState(), 'connecting');
  assert.equal((await h.move()).ok, false);
  assert.equal(h.calls.includes('move_workshop_booking'), false);
  await h.service.onReconnect();
  assert.equal(h.reads(), 1, 'matching revision reuses the initial read');
  assert.equal(h.service.getTrustedSnapshot().revision, 1);
  assert.equal(h.service.getState(), 'connected_editable');
  assert.equal(h.timers.size, 0);
});

test('subscription joins an in-flight snapshot and checks its revision concurrently', async () => {
  const h = fixture({ probes: true }), rows = deferred(), revision = deferred();
  h.setRead(() => rows.promise); h.setProbe(() => revision.promise);
  const first = h.service.startConnecting();
  const ready = h.service.onReconnect(); await tick();
  assert.equal(h.reads(), 1); assert.ok(h.calls.includes('revision'));
  revision.resolve({ ok: true, body: [{ revision: 3 }] });
  rows.resolve(snapshot(3)); await first; await ready;
  assert.equal(h.reads(), 1); assert.equal(h.service.getTrustedSnapshot().revision, 3);
});

test('commit missed before subscription forces one post-subscription read', async () => {
  const h = fixture({ probes: true }); await h.service.startConnecting();
  h.setProbe(async () => ({ ok: true, body: [{ revision: 2 }] }));
  h.setRead(async () => snapshot(2)); await h.service.onReconnect();
  assert.equal(h.reads(), 2); assert.equal(h.service.getTrustedSnapshot().revision, 2);
});

for (const result of [{ ok: false, status: 403 }, { ok: true, body: [] }, { ok: true, body: [{ revision: 'bad' }] }]) {
  test('denied or invalid initial revision cannot expose retained authority: ' + JSON.stringify(result), async () => {
    const h = fixture({ probes: true }); await h.service.startConnecting();
    h.setProbe(async () => result); await h.service.onReconnect();
    assert.equal(h.service.getTrustedSnapshot(), null); assert.equal(h.service.getLastSnapshot(), null);
    assert.equal(h.reads(), 1); assert.equal((await h.move()).ok, false);
  });
}

for (const mode of ['destroy', 'logout', 'role', 'scope', 'channel']) {
  test('late initial handshake cannot restore a replaced ' + mode, async () => {
    const h = fixture({ probes: true }), revision = deferred(); await h.service.startConnecting();
    h.setProbe(() => revision.promise); const ready = h.service.onReconnect(); await tick();
    if (mode === 'destroy') h.service.destroy();
    if (mode === 'logout') h.setToken(null);
    if (mode === 'role') h.setRole('viewer');
    if (mode === 'scope') {
      h.setRead(async () => snapshot(2)); h.setProbe(async () => ({ ok: true, body: [{ revision: 2 }] }));
      await h.service.setScope({ ...scope, stageCode: 'TINT' });
    }
    if (mode === 'channel') h.service.onAuthorityLost();
    revision.resolve({ ok: true, body: [{ revision: 1 }] }); await ready;
    if (mode === 'scope') assert.equal(h.service.getTrustedSnapshot().revision, 2);
    else { assert.equal(h.service.getTrustedSnapshot(), null); assert.notEqual(h.service.getState(), 'connected_editable'); }
    h.service.destroy();
  });
}

test('stalled initial revision has a bounded fresh-read fallback', async () => {
  const h = fixture({ probes: true }); await h.service.startConnecting();
  h.setProbe(() => new Promise(() => {})); const ready = h.service.onReconnect(); await tick();
  h.fire(5000); await ready;
  assert.equal(h.reads(), 2); assert.equal(h.service.getTrustedSnapshot().revision, 1);
  assert.equal(h.timers.size, 0);
});

test('live change during handshake cannot leave an older schedule editable', async () => {
  const h = fixture({ probes: true }), revision = deferred(); await h.service.startConnecting();
  h.setProbe(() => revision.promise); const ready = h.service.onReconnect(); await tick();
  h.service.onRevisionSignal(2); h.setRead(async () => snapshot(2));
  revision.resolve({ ok: true, body: [{ revision: 1 }] }); await ready;
  assert.equal(h.service.getTrustedSnapshot().revision, 2); assert.equal(h.reads(), 2);
});

test('planner downloads all four independent modules together and initializes only when complete', async () => {
  const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
  const body = source.slice(source.indexOf('function renderWorkshopPlannerWhenReady()'), source.indexOf('function ensureDashboardWorkshopProjectionReady()'));
  const calls = [], gates = [], root = { innerHTML: '' }; let initialized = 0;
  const context = { app: { currentView: 'workshop', activeWorkshopPlannerStage: 'FITTING' }, window: {},
    WORKSHOP_PLANNER_SCRIPT_VERSION: 'test', $: () => root,
    loadExternalScript: url => { calls.push(url); const gate = deferred(); gates.push(gate); return gate.promise; },
    initWorkshopSharedServicesIfEnabled: () => initialized++ };
  vm.createContext(context); vm.runInContext(body, context); context.renderWorkshopPlannerWhenReady();
  assert.equal(calls.length, 4); assert.equal(initialized, 0);
  context.renderWorkshopPlannerWhenReady(); context.renderWorkshopPlannerWhenReady();
  assert.equal(calls.length, 4, 'rapid navigation joins one shared module load');
  gates.slice(0, 3).forEach(g => g.resolve()); await tick(); assert.equal(initialized, 0);
  context.app.activeWorkshopPlannerStage = 'TINT';
  context.renderWorkshopPlanner = () => {}; gates[3].resolve(); await tick();
  assert.equal(initialized, 1); assert.equal(context.window.__workshopPlannerModulesLoading, false);
});
