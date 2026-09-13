'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createPdcOperationalRefreshCoordinator: create } = require('./vehicle-locations-refresh');
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));

test('40 revisions during a slow read produce one trailing snapshot with the newest data', async () => {
  const gates = [deferred(), deferred()]; let calls = 0; let active = 0; let maxActive = 0; let latest = 0;
  const seen = [];
  const c = create({ getRoute: () => 'dashboard', loaders: { board: async () => {
    const i = calls++; const revision = latest; maxActive = Math.max(maxActive, ++active);
    await gates[i].promise; active--; return { ok: true, revision };
  } }, onFinish: result => seen.push(result.results[0].value.revision) });
  const first = c.refresh(); const waiting = [];
  for (let revision = 1; revision <= 40; revision++) { latest = revision; waiting.push(c.refresh({ supersede: true, deferSupersede: true })); }
  assert.equal(calls, 1); assert.ok(waiting.every(p => p === waiting[0]));
  gates[0].resolve(); await first; assert.equal(calls, 2);
  gates[1].resolve(); const results = await Promise.all(waiting);
  assert.equal(maxActive, 1); assert.deepEqual(seen, [0, 40]); assert.ok(results.every(r => r.ok)); assert.equal(c.isRefreshing(), false);
});

test('sign-out cancels queued reads and ignores late completion', async () => {
  const gate = deferred(); let calls = 0; let finished = 0;
  const c = create({ loaders: { board: () => { calls++; return gate.promise; } }, onFinish: () => finished++ });
  const running = c.refresh(); const queued = c.refresh({ supersede: true, deferSupersede: true });
  c.invalidate(); assert.equal((await queued).stale, true); gate.resolve({ ok: true });
  assert.equal((await running).stale, true); await tick(); assert.equal(calls, 1); assert.equal(finished, 0);
});

test('queued refresh follows current route and still runs when the prior read fails', async () => {
  const gate = deferred(); let route = 'dashboard'; const calls = [];
  const c = create({ getRoute: () => route, routeAdapters: {
    dashboard: { board: () => { calls.push('dashboard'); return gate.promise; } },
    sublet: { bookings: () => { calls.push('sublet'); return { ok: true }; } }
  } });
  const first = c.refresh(); const queued = c.refresh({ supersede: true, deferSupersede: true });
  route = 'sublet'; gate.resolve({ ok: false });
  assert.equal((await first).ok, false); assert.equal((await queued).route, 'sublet'); assert.deepEqual(calls, ['dashboard', 'sublet']);
});

test('a newer explicit refresh retains priority over an older in-flight read', async () => {
  const gates = [deferred(), deferred(), deferred()]; let calls = 0;
  const c = create({ loaders: { board: () => gates[calls++].promise } });
  const old = c.refresh(); const queued = c.refresh({ supersede: true, deferSupersede: true });
  const explicit = c.refresh({ supersede: true });
  gates[0].resolve({ ok: true }); assert.equal((await old).stale, true); assert.equal(calls, 2);
  gates[1].resolve({ ok: true }); await explicit; assert.equal(calls, 3);
  gates[2].resolve({ ok: true }); assert.equal((await queued).ok, true);
});
