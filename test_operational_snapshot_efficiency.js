'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');
const { createPdcOperationalRefreshCoordinator } = require('./vehicle-locations-refresh');
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
const response = revision => ({ ok: true, json: async () => ({ ok: true, data: { revision, vehicles: [] } }) });

function snapshotRuntime() {
  let token = 'first-session'; let active = 0; let maxActive = 0;
  const requests = [];
  const service = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-public-key' },
    getAccessToken: () => token,
    fetchImpl: (_url, options) => {
      const gate = deferred(); requests.push({ gate, options }); maxActive = Math.max(maxActive, ++active);
      return gate.promise.finally(() => { active--; });
    },
  });
  return { service, requests, setToken: value => { token = value; }, maxActive: () => maxActive };
}

test('40 overlapping board reads download two snapshots and every trailing caller gets post-change data', async () => {
  const r = snapshotRuntime();
  const first = r.service.snapshot();
  const waiting = Array.from({ length: 40 }, () => r.service.snapshot());
  assert.equal(r.requests.length, 1);
  assert.ok(waiting.every(promise => promise === waiting[0]));
  r.requests[0].gate.resolve(response(10));
  assert.equal((await first).data.revision, 10);
  assert.equal(r.requests.length, 2);
  r.requests[1].gate.resolve(response(11));
  const results = await Promise.all(waiting);
  assert.ok(results.every(result => result.data.revision === 11));
  assert.equal(r.maxActive(), 1);
  const later = r.service.snapshot();
  assert.equal(r.requests.length, 3, 'completed snapshots are never cached for mutation readback');
  r.requests[2].gate.resolve(response(12));
  assert.equal((await later).data.revision, 12);
});

test('a write during the trailing read requires another fresh snapshot', async () => {
  const r = snapshotRuntime(); const first = r.service.snapshot(); const second = r.service.snapshot();
  r.requests[0].gate.resolve(response(1)); await first;
  const afterAnotherWrite = r.service.snapshot();
  r.requests[1].gate.resolve(response(2)); assert.equal((await second).data.revision, 2);
  r.requests[2].gate.resolve(response(3)); assert.equal((await afterAnotherWrite).data.revision, 3);
  assert.equal(r.maxActive(), 1);
});

test('sign-out discards both a pending snapshot and queued readbacks', async () => {
  const r = snapshotRuntime(); const first = r.service.snapshot(); const queued = r.service.snapshot();
  r.setToken(null); r.requests[0].gate.resolve(response(1));
  assert.equal((await first).code, 'not_authenticated');
  assert.equal((await queued).code, 'not_authenticated');
  assert.equal(r.requests.length, 1);
  assert.equal((await r.service.snapshot()).code, 'not_authenticated');
});

test('a changed session can read immediately without receiving the old operator snapshot', async () => {
  const r = snapshotRuntime(); const first = r.service.snapshot(); const oldQueued = r.service.snapshot();
  r.setToken('second-session'); const fresh = r.service.snapshot();
  assert.equal(r.requests.length, 2); assert.equal((await oldQueued).code, 'not_authenticated');
  assert.equal(r.requests[1].options.headers.Authorization, 'Bearer second-session');
  r.requests[0].gate.resolve(response(1)); assert.equal((await first).code, 'not_authenticated');
  r.requests[1].gate.resolve(response(2)); assert.equal((await fresh).data.revision, 2);
});

test('failed snapshots release the queue for an authoritative retry', async () => {
  const r = snapshotRuntime(); const first = r.service.snapshot(); const queued = r.service.snapshot();
  r.requests[0].gate.resolve({ ok: false, status: 503, json: async () => ({ code: 'server_busy' }) });
  assert.equal((await first).ok, false); assert.equal(r.requests.length, 2);
  r.requests[1].gate.resolve(response(2)); assert.equal((await queued).ok, true);
});

function loaderRuntime() {
  const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
  const start = source.indexOf('function operationalRefreshCommonLoaders(');
  const end = source.indexOf('\nfunction getOperationalRefreshCoordinator(', start);
  const calls = [];
  const context = {
    app: { emailVehicleLocationService: {}, workshopEligibilityRealtime: {}, vehicleModalIdentity: null },
    loadSharedNavisionVisibleRows: async () => { calls.push('navision'); return { ok: true }; },
    initEmailVehicleLocationsIfAvailable: () => {},
    refreshEmailVehicleLocations: async () => { calls.push('vehicles'); return true; },
    workshopEligibilitySharedAuthorityEnabled: () => true,
    loadWorkshopEligibilitySnapshot: async () => { calls.push('eligibility'); return { ok: true }; },
    refreshWorkshopReferenceData: async () => { calls.push('references'); return { ok: true }; },
  };
  vm.runInNewContext(source.slice(start, end), context);
  return { calls, loaders: context.operationalRefreshCommonLoaders('dashboard') };
}

test('vehicle revisions reload vehicle and scheduling authority without reloading unrelated source/reference tables', async () => {
  const r = loaderRuntime();
  const coordinator = createPdcOperationalRefreshCoordinator({ loaders: r.loaders });
  assert.equal((await coordinator.refresh({ source: 'email_revision' })).ok, true);
  assert.deepEqual(r.calls.sort(), ['eligibility', 'vehicles']);
  r.calls.length = 0;
  assert.equal((await coordinator.refresh()).ok, true);
  assert.deepEqual(r.calls.sort(), ['eligibility', 'navision', 'references', 'vehicles']);
});

test('a newer email event cannot downgrade a queued full refresh', async () => {
  for (const fullFirst of [true, false]) {
    const gate = deferred(); const sources = []; let calls = 0;
    const coordinator = createPdcOperationalRefreshCoordinator({ loaders: { board: context => {
      sources.push(context.sources); return calls++ === 0 ? gate.promise : { ok: true };
    } } });
    const first = coordinator.refresh({ source: 'email_revision' });
    const queued = coordinator.refresh({ supersede: true, deferSupersede: true, ...(fullFirst ? {} : { source: 'email_revision' }) });
    coordinator.refresh({ supersede: true, deferSupersede: true, ...(fullFirst ? { source: 'email_revision' } : {}) });
    gate.resolve({ ok: true }); await first; await queued;
    assert.ok(sources[1].includes('full')); assert.ok(sources[1].includes('email_revision'));
  }
});

test('failed and signed-out revision reads do not leave a queued lightweight refresh running', async () => {
  const gate = deferred(); let calls = 0;
  const coordinator = createPdcOperationalRefreshCoordinator({ loaders: { board: () => { calls++; return gate.promise; } } });
  const first = coordinator.refresh({ source: 'email_revision' });
  const queued = coordinator.refresh({ source: 'email_revision', supersede: true, deferSupersede: true });
  coordinator.invalidate(); gate.resolve({ ok: false });
  assert.equal((await first).stale, true); assert.equal((await queued).stale, true);
  await tick(); assert.equal(calls, 1);
});
