'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');
const { createNavisionBackendService } = require('./navision-backend-service');
const appSource = fs.readFileSync(require.resolve('./app.js'), 'utf8');
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
const reply = body => ({ ok: true, json: async () => body });
const snapshotReply = revision => reply({ ok: true, data: { revision, vehicles: [{ stock_number: 'TEST', version: revision }] } });
function emailRuntime(options = {}) {
  let token = 'session-one';
  const reads = [];
  const service = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-key' },
    getAccessToken: () => token,
    ...options,
    fetchImpl: (url, options) => { const gate = deferred(); reads.push({ url, options, gate }); return gate.promise; },
  });
  return { service, reads, token: value => { token = value; } };
}
function probeClock() {
  const timers = []; const cleared = [];
  return { timers, cleared, options: {
    scheduleTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearScheduledTimeout: id => { cleared.push(id); },
  } };
}

test('initial subscribe reuses the in-flight snapshot only when its revision covers the subscription check', async () => {
  const r = emailRuntime();
  const first = r.service.snapshot();
  const reconciled = r.service.snapshot({ reconcile: true, knownRevision: null });
  assert.equal(r.reads.length, 2);
  assert.match(r.reads[1].url, /pdc_email_vehicle_revision\?select=revision/);
  r.reads[1].gate.resolve(reply([{ revision: 4 }])); await tick();
  r.reads[0].gate.resolve(snapshotReply(4));
  assert.equal((await first).data.revision, 4);
  assert.equal((await reconciled).data.revision, 4);
  assert.equal(r.reads.length, 2, 'only one full snapshot');
});

test('a write missed before subscription requires a newer snapshot', async () => {
  const r = emailRuntime();
  const first = r.service.snapshot();
  const reconciled = r.service.snapshot({ reconcile: true, knownRevision: 3 });
  r.reads[1].gate.resolve(reply([{ revision: 5 }])); await tick();
  r.reads[0].gate.resolve(snapshotReply(4)); await first; await tick();
  assert.equal(r.reads.length, 3);
  r.reads[2].gate.resolve(snapshotReply(5));
  assert.equal((await reconciled).data.revision, 5);
});

test('unchanged reconnect returns no vehicle payload and does not download the board', async () => {
  const r = emailRuntime();
  const result = r.service.snapshot({ reconcile: true, knownRevision: 12 });
  r.reads[0].gate.resolve(reply([{ revision: 12 }]));
  const value = await result;
  assert.equal(value.unchanged, true);
  assert.equal(value.data.vehicles, undefined);
  assert.equal(r.reads.length, 1);
});

test('revision failure falls back to a fresh authorized snapshot', async () => {
  const r = emailRuntime();
  const result = r.service.snapshot({ reconcile: true, knownRevision: 12 });
  r.reads[0].gate.resolve(reply([])); await tick();
  assert.equal(r.reads.length, 2);
  r.reads[1].gate.resolve(snapshotReply(13));
  assert.equal((await result).data.revision, 13);
});

test('logout during revision reconciliation never starts another read', async () => {
  const r = emailRuntime();
  const result = r.service.snapshot({ reconcile: true, knownRevision: null });
  r.token(null); r.reads[0].gate.resolve(reply([{ revision: 12 }]));
  assert.equal((await result).code, 'not_authenticated');
  assert.equal(r.reads.length, 1);
});

test('reconnection check does not weaken a simultaneous mutation readback', async () => {
  const r = emailRuntime();
  const initial = r.service.snapshot();
  const reconcile = r.service.snapshot({ reconcile: true, knownRevision: null });
  r.reads[1].gate.resolve(reply([{ revision: 4 }])); await tick();
  const mutation = r.service.snapshot();
  r.reads[0].gate.resolve(snapshotReply(4)); await initial; await reconcile;
  assert.equal(r.reads.length, 3);
  r.reads[2].gate.resolve(snapshotReply(5));
  assert.equal((await mutation).data.revision, 5);
});

test('a never-settling email revision probe aborts after five seconds and falls back once', async () => {
  const clock = probeClock(); const r = emailRuntime(clock.options);
  const reconciled = r.service.snapshot({ reconcile: true, knownRevision: 12 });
  assert.equal(clock.timers[0].ms, 5000);
  clock.timers[0].fn(); await tick();
  assert.equal(r.reads[0].options.signal.aborted, true);
  assert.equal(r.reads.length, 2, 'a fresh authorized snapshot recovers the stalled probe');
  r.reads[1].gate.resolve(snapshotReply(13));
  const response = await reconciled;
  assert.equal(response.data.revision, 13); assert.notEqual(response.unchanged, true);
  assert.deepEqual(clock.cleared, [1]);
  r.reads[0].gate.resolve(reply([{ revision: 12 }])); await tick();
  assert.equal(r.reads.length, 2, 'late probe cannot add reads or replace the fresh snapshot');
});

test('email revision timeout preserves logout authority and success cleans up its timer', async () => {
  const clock = probeClock(); const r = emailRuntime({ ...clock.options, revisionTimeoutMs: 10 });
  const pending = r.service.snapshot({ reconcile: true, knownRevision: 12 });
  r.token(null); clock.timers[0].fn();
  assert.equal((await pending).code, 'not_authenticated'); assert.equal(r.reads.length, 1);
  assert.deepEqual(clock.cleared, [1]); assert.equal(clock.timers[0].ms, 10);
  const successClock = probeClock(); const success = emailRuntime(successClock.options);
  const done = success.service.snapshot({ reconcile: true, knownRevision: 12 });
  success.reads[0].gate.resolve(reply([{ revision: 12 }])); await done;
  assert.deepEqual(successClock.cleared, [1]); assert.equal(success.reads[0].options.signal.aborted, false);
});

function navRuntime() {
  const pending = [];
  const service = { visibleSnapshot: (scope, cursor, limit, expectedRevision) => {
    const gate = deferred(); pending.push({ scope, cursor, limit, expectedRevision, gate }); return gate.promise;
  }, visibleRevision: async () => ({ ok: true, revision: 7 }) };
  const app = { sharedNavisionVisibleState: 'idle', sharedNavisionVisibleGeneration: 0,
    sharedNavisionVisibleRevision: null, sharedNavisionVisibleRows: [], sharedNavisionVisibleRealtimeState: 'subscribed',
    sharedNavisionVisibleRealtime: {}, sharedNavisionVisibleRealtimeGeneration: 2, vehicleLocationsRefreshGeneration: 1, currentView: 'workshop' };
  const ctx = { app, navisionSharedBackendService: () => service, console: { error() {} },
    subscribeSharedNavisionVisibility() {}, renderBackEndData() {}, renderIncomingDashboardBoard() {}, renderSharedNavisionVisibilityState() {},
    sharedNavisionVisibleData: result => result.data };
  vm.createContext(ctx);
  const start = appSource.indexOf('async function reconcileSharedNavisionVisibility(');
  const end = appSource.indexOf('\nfunction sharedNavisionIdentityToken(', start);
  vm.runInContext(appSource.slice(start, end), ctx);
  return { ctx, app, pending, service };
}
const navReply = (revision, id, extra = {}) => ({ ok: true, data: { revision, items: [{ id }], has_more: false, ...extra } });

test('four dealer scopes start together, retain scope order and one common revision', async () => {
  const r = navRuntime(); const result = r.ctx.loadSharedNavisionVisibleRows();
  assert.equal(r.pending.length, 4);
  assert.deepEqual(r.pending.map(p => p.scope.dealerCode), ['14450', '37047', '002345', '001234']);
  r.pending[3].gate.resolve(navReply(7, 'four'));
  r.pending[1].gate.resolve(navReply(7, 'two'));
  r.pending[0].gate.resolve(navReply(7, 'one', { has_more: true, next_record_id: 'cursor-one' }));
  r.pending[2].gate.resolve(navReply(7, 'three')); await tick();
  assert.equal(r.pending[4].expectedRevision, 7);
  assert.equal(r.pending[4].cursor.recordId, 'cursor-one');
  r.pending[4].gate.resolve(navReply(7, 'one-second-page'));
  assert.equal((await result).ok, true);
  assert.deepEqual(Array.from(r.app.sharedNavisionVisibleRows, x => x.id), ['one', 'one-second-page', 'two', 'three', 'four']);
});

test('a revision change across parallel scopes never publishes mixed data', async () => {
  const r = navRuntime(); const result = r.ctx.loadSharedNavisionVisibleRows();
  r.pending.forEach((p, i) => p.gate.resolve(navReply(i === 3 ? 8 : 7, String(i))));
  assert.equal((await result).ok, false);
  assert.equal(r.app.sharedNavisionVisibleRows.length, 0);
  assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, false);
});

test('Navision reconnect waits for its current load rather than superseding the entire download', async () => {
  const r = navRuntime(); const initial = r.ctx.loadSharedNavisionVisibleRows();
  const reconnect = r.ctx.reconcileSharedNavisionVisibility(2, r.app.sharedNavisionVisibleRealtime);
  await tick(); assert.equal(r.pending.length, 4);
  r.pending.forEach((p, i) => p.gate.resolve(navReply(7, String(i))));
  await initial; await reconnect;
  assert.equal(r.pending.length, 4);
  assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, true);
});

test('a pre-subscription download remains read-only until its revision is reconciled', async () => {
  for (const revisionAfterSubscribe of [7, 8]) {
    const r = navRuntime(); const revision = deferred();
    r.app.sharedNavisionVisibleRealtimeState = 'connecting';
    r.app.sharedNavisionVisibleRealtimeReconciled = false;
    r.service.visibleRevision = () => revision.promise;
    const initial = r.ctx.loadSharedNavisionVisibleRows();
    r.app.sharedNavisionVisibleRealtimeState = 'subscribed';
    const reconciliation = r.ctx.reconcileSharedNavisionVisibility(2, r.app.sharedNavisionVisibleRealtime);
    r.pending.forEach((p, i) => p.gate.resolve(navReply(7, String(i))));
    await initial;
    assert.equal(r.app.sharedNavisionVisibleState, 'ready');
    assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, false,
      'read begun before subscription cannot authorize actions while the revision probe is pending');
    revision.resolve({ ok: true, revision: revisionAfterSubscribe }); await tick();
    if (revisionAfterSubscribe === 8) {
      assert.equal(r.pending.length, 8, 'missed revision requires fresh dealer pages');
      assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, false);
      r.pending.slice(4).forEach((p, i) => p.gate.resolve(navReply(8, `new-${i}`)));
    }
    await reconciliation;
    assert.equal(r.app.sharedNavisionVisibleRevision, revisionAfterSubscribe);
    assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, true);
    if (revisionAfterSubscribe === 7) assert.equal(r.pending.length, 4, 'unchanged initial pages are reused');
  }
});

test('a load from a replaced subscription cannot authorize its retained rows', async () => {
  const r = navRuntime(); const initial = r.ctx.loadSharedNavisionVisibleRows();
  r.app.sharedNavisionVisibleRealtimeGeneration++;
  r.app.sharedNavisionVisibleRealtime = {};
  r.pending.forEach((p, i) => p.gate.resolve(navReply(7, String(i))));
  await initial;
  assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, false);
});

test('stale session callbacks cannot initiate a new Navision load', async () => {
  const r = navRuntime(); const gate = deferred(); r.service.visibleRevision = () => gate.promise;
  const reconnect = r.ctx.reconcileSharedNavisionVisibility(2, r.app.sharedNavisionVisibleRealtime);
  r.app.sharedNavisionVisibleRealtimeGeneration++;
  gate.resolve({ ok: true, revision: 8 }); await reconnect;
  assert.equal(r.pending.length, 0);
});

test('Navision revision reads are RLS-protected and reject changed sessions', async () => {
  let token = 'first'; const gate = deferred(); const requests = [];
  const service = createNavisionBackendService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-key' }, getAccessToken: () => token,
    fetchImpl: (url, options) => { requests.push({ url, options }); return gate.promise; },
  });
  const result = service.visibleRevision();
  assert.match(requests[0].url, /navision_backend_revision\?select=revision/);
  assert.equal(requests[0].options.headers.Authorization, 'Bearer first');
  token = 'second'; gate.resolve(reply([{ revision: 8 }]));
  assert.equal((await result).ok, false);
});

test('a never-settling Navision probe aborts and the existing reconciliation reloads safely', async () => {
  const clock = probeClock(); const probe = deferred(); const requests = [];
  const service = createNavisionBackendService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-key' },
    getAccessToken: () => 'session', ...clock.options,
    fetchImpl: (url, options) => { requests.push({ url, options }); return probe.promise; },
  });
  const r = navRuntime(); r.service.visibleRevision = service.visibleRevision;
  const reconciled = r.ctx.reconcileSharedNavisionVisibility(2, r.app.sharedNavisionVisibleRealtime);
  assert.equal(clock.timers[0].ms, 5000);
  clock.timers[0].fn(); await tick();
  assert.equal(requests[0].options.signal.aborted, true);
  assert.equal(r.pending.length, 4); assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, false);
  r.pending.forEach((p, i) => p.gate.resolve(navReply(8, String(i)))); await reconciled;
  assert.equal(r.app.sharedNavisionVisibleRevision, 8); assert.equal(r.app.sharedNavisionVisibleRealtimeReconciled, true);
  assert.deepEqual(clock.cleared, [1]);
  probe.resolve(reply([{ revision: 7 }])); await tick();
  assert.equal(r.pending.length, 4); assert.equal(r.app.sharedNavisionVisibleRevision, 8);
});

test('Navision probe timer cleanup preserves changed-token failure even on timeout', async () => {
  const clock = probeClock(); let token = 'first';
  const service = createNavisionBackendService({ projectRef: 'cdsmnqxtyyoeoznmbidd', getAccessToken: () => token,
    client: { visibleRevision: () => new Promise(() => {}) }, ...clock.options, revisionTimeoutMs: 10 });
  const result = service.visibleRevision(); token = 'second'; clock.timers[0].fn();
  assert.equal((await result).error, 'not_authenticated'); assert.deepEqual(clock.cleared, [1]);
  assert.equal(clock.timers[0].ms, 10);
  const successClock = probeClock();
  const success = createNavisionBackendService({ projectRef: 'cdsmnqxtyyoeoznmbidd', getAccessToken: () => 'session',
    client: { visibleRevision: async () => ({ ok: true, body: [{ revision: 9 }] }) }, ...successClock.options });
  assert.equal((await success.visibleRevision()).revision, 9); assert.deepEqual(successClock.cleared, [1]);
});
