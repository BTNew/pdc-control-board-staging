/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
const reply = revision => ({ ok: true, json: async () => ({ ok: true, data: { revision, vehicles: [] } }) });
function runtime(options = {}) {
  let token = 'first-user';
  const reads = [], timers = [], cleared = [];
  const service = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-key' },
    getAccessToken: () => token,
    scheduleTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearScheduledTimeout: id => cleared.push(id),
    ...options,
    fetchImpl: (url, options) => { const gate = deferred(); reads.push({ url, options, gate }); return gate.promise; },
  });
  return { service, reads, timers, cleared, setToken: value => { token = value; } };
}

test('a stalled board read releases one coalesced fresh import refresh after the bounded 45-second deadline', async () => {
  const r = runtime();
  const stalled = r.service.snapshot();
  const updates = Array.from({ length: 50 }, () => r.service.snapshot());
  assert.equal(r.reads.length, 1);
  assert.equal(r.timers[0].ms, 45000);
  r.timers[0].fn();
  assert.equal((await stalled).code, 'snapshot_timeout');
  assert.equal(r.reads[0].options.signal.aborted, true);
  assert.equal(r.reads.length, 2);
  r.reads[1].gate.resolve(reply(52));
  for (const response of await Promise.all(updates)) assert.equal(response.data.revision, 52);
  assert.deepEqual(r.cleared, [1, 2]);
  assert.ok(r.reads.every(read => read.url.endsWith('/rpc/get_pdc_email_vehicle_board_snapshot_conditional')));
});

test('a stalled response body times out; its late result cannot block or replace the fresh read', async () => {
  const r = runtime(); const body = deferred();
  const first = r.service.snapshot();
  r.reads[0].gate.resolve({ ok: true, json: () => body.promise }); await tick();
  const fresh = r.service.snapshot();
  r.timers[0].fn(); assert.equal((await first).code, 'snapshot_timeout');
  body.resolve({ ok: true, data: { revision: 1, vehicles: [] } }); await tick();
  assert.equal(r.reads.length, 2);
  r.reads[1].gate.resolve(reply(2)); assert.equal((await fresh).data.revision, 2);
  const next = r.service.snapshot(); assert.equal(r.reads.length, 3);
  r.reads[2].gate.resolve(reply(3)); assert.equal((await next).data.revision, 3);
});

test('logout while a read stalls prevents queued import refreshes from using old authority', async () => {
  const r = runtime(); const first = r.service.snapshot(); const next = r.service.snapshot();
  r.setToken(null); r.timers[0].fn();
  assert.equal((await first).code, 'not_authenticated');
  assert.equal((await next).code, 'not_authenticated');
  assert.equal(r.reads.length, 1);
});

test('a new login has its own queue and ignores the former user timeout', async () => {
  const r = runtime(); const old = r.service.snapshot(); const oldQueued = r.service.snapshot();
  r.setToken('second-user'); const current = r.service.snapshot(); const currentQueued = r.service.snapshot();
  assert.equal((await oldQueued).code, 'not_authenticated');
  r.timers[0].fn(); assert.equal((await old).code, 'not_authenticated');
  assert.equal(r.reads.length, 2);
  r.reads[1].gate.resolve(reply(10)); assert.equal((await current).data.revision, 10);
  assert.equal(r.reads.length, 3);
  assert.equal(r.reads[2].options.headers.Authorization, 'Bearer second-user');
  r.reads[2].gate.resolve(reply(11)); assert.equal((await currentQueued).data.revision, 11);
});

test('successful and failed reads clear deadlines and allow subsequent refreshes', async () => {
  const r = runtime({ snapshotTimeoutMs: 2000 });
  const failed = r.service.snapshot(); r.reads[0].gate.reject(new Error('offline'));
  assert.equal((await failed).code, 'snapshot_unavailable');
  const denied = r.service.snapshot(); r.reads[1].gate.resolve({ ok: false, status: 403, json: async () => ({ code: 'forbidden' }) });
  assert.equal((await denied).code, 'forbidden');
  const success = r.service.snapshot(); r.reads[2].gate.resolve(reply(3));
  assert.equal((await success).data.revision, 3);
  assert.deepEqual(r.cleared, [1, 2, 3]);
  assert.ok(r.timers.every(timer => timer.ms === 2000));
  assert.equal(r.reads[2].options.signal.aborted, false);
});

test('a revision reconnect recovers when its in-flight board snapshot stalls', async () => {
  const r = runtime(); const first = r.service.snapshot();
  const reconnect = r.service.snapshot({ reconcile: true, knownRevision: 1 });
  r.reads[1].gate.resolve({ ok: true, json: async () => [{ revision: 2 }] }); await tick();
  r.timers[0].fn(); assert.equal((await first).code, 'snapshot_timeout'); await tick();
  assert.equal(r.reads.length, 3);
  r.reads[2].gate.resolve(reply(2)); assert.equal((await reconnect).data.revision, 2);
});

test('a valid slow board read and body transfer finish without the former 15-second cutoff', async () => {
  let now = 0, nextId = 0; const deadlines = new Map();
  const r = runtime({
    scheduleTimeout: (fn, ms) => { const id = ++nextId; deadlines.set(id, { at: now + ms, fn }); return id; },
    clearScheduledTimeout: id => deadlines.delete(id),
  });
  async function advance(ms) {
    now += ms;
    for (const [id, timer] of [...deadlines]) if (timer.at <= now) { deadlines.delete(id); timer.fn(); }
    await tick();
  }
  let settled = false; const pending = r.service.snapshot().then(value => { settled = true; return value; });
  await advance(15000);
  assert.equal(settled, false, 'a valid read may take more than fifteen seconds');
  await advance(6240);
  const body = deferred();
  r.reads[0].gate.resolve({ ok: true, json: () => body.promise }); await tick();
  await advance(13760);
  assert.equal(settled, false, 'the response body also needs transfer time');
  body.resolve({ ok: true, data: { revision: 15, vehicles: Array.from({ length: 439 }, (_, i) => ({ id: `fixture-${i}` })) } });
  const result = await pending;
  assert.equal(result.ok, true); assert.equal(result.data.vehicles.length, 439);
  assert.equal(r.reads[0].options.signal.aborted, false);
  assert.equal(deadlines.size, 0);
});

test('operational refresh exposes the actual snapshot failure instead of a generic error', async () => {
  const fs = require('node:fs'), vm = require('node:vm');
  const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
  const start = source.indexOf('function operationalRefreshCommonLoaders(route)');
  const end = source.indexOf('function getOperationalRefreshCoordinator()', start);
  const context = { app: { emailVehicleLocationService: {}, emailVehicleLocationError: '' },
    initEmailVehicleLocationsIfAvailable() {},
    refreshEmailVehicleLocations: async () => { context.app.emailVehicleLocationError = 'snapshot_timeout'; return false; } };
  vm.createContext(context); vm.runInContext(source.slice(start, end), context);
  const result = await context.operationalRefreshCommonLoaders('dashboard').operationalVehicleSnapshot({ generation: 1 });
  assert.equal(result.ok, false); assert.equal(result.error, 'snapshot_timeout');
  context.refreshEmailVehicleLocations = async () => true;
  const recovered = await context.operationalRefreshCommonLoaders('dashboard').operationalVehicleSnapshot({ generation: 2 });
  assert.equal(recovered.ok, true); assert.equal(recovered.error, '');
});
