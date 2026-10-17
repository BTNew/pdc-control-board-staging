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

test('a stalled board read releases one coalesced fresh import refresh after 15 seconds', async () => {
  const r = runtime();
  const stalled = r.service.snapshot();
  const updates = Array.from({ length: 50 }, () => r.service.snapshot());
  assert.equal(r.reads.length, 1);
  assert.equal(r.timers[0].ms, 15000);
  r.timers[0].fn();
  assert.equal((await stalled).code, 'snapshot_timeout');
  assert.equal(r.reads[0].options.signal.aborted, true);
  assert.equal(r.reads.length, 2);
  r.reads[1].gate.resolve(reply(52));
  for (const response of await Promise.all(updates)) assert.equal(response.data.revision, 52);
  assert.deepEqual(r.cleared, [1, 2]);
  assert.ok(r.reads.every(read => read.url.endsWith('/rpc/get_pdc_email_vehicle_board_snapshot')));
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
