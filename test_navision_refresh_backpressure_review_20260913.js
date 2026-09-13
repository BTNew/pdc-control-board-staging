'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createPdcOperationalRefreshCoordinator: create } = require('./vehicle-locations-refresh');
const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
const start = source.indexOf('function subscribeSharedNavisionVisibility(');
const tail = source.slice(start);
const end = tail.slice(1).search(/\n(?:async )?function /);
const subscribeSource = tail.slice(0, end + 1);
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

test('the actual Navision revision callback coalesces a burst into one trailing authoritative refresh', async () => {
  const gates = [deferred(), deferred()];
  const snapshots = [], completions = [], waiting = [];
  let revision = 0, active = 0, peak = 0, callback;
  const coordinator = create({ getRoute: () => 'dashboard', loaders: { snapshot: async () => {
    const index = snapshots.length;
    snapshots.push(revision);
    peak = Math.max(peak, ++active);
    await gates[index].promise;
    active--;
    return { ok: true, revision: snapshots[index] };
  } }, onFinish: result => completions.push(result.results[0].value.revision) });
  const channel = { on(_kind, _filter, onChange) { callback = onChange; return this; }, subscribe() {} };
  const ctx = {
    window: { PDC_AUTH_CONTEXT: { userId: 'review-operator' }, PDC_SUPABASE: { channel: () => channel } },
    app: { vehicleLocationsRefreshCoordinator: coordinator, sharedNavisionVisibleRealtime: null,
      sharedNavisionVisibleRealtimeGeneration: 0, sharedNavisionVisibleRevision: 0 },
    clearSharedNavisionVisibilityReconnectTimer() {}, sharedNavisionVisibilityConfigured: () => true,
    refreshVehicleLocations(options) { const result = coordinator.refresh({ ...options, route: 'dashboard' }); waiting.push(result); return result; },
  };
  vm.createContext(ctx);
  vm.runInContext(subscribeSource, ctx);
  ctx.subscribeSharedNavisionVisibility();
  const first = coordinator.refresh();
  for (revision = 1; revision <= 30; revision++) callback({ new: { revision } });
  revision = 30;
  assert.equal(snapshots.length, 1);
  assert.equal(waiting.length, 30);
  assert.ok(waiting.every(promise => promise === waiting[0]));
  gates[0].resolve();
  await first;
  assert.deepEqual(snapshots, [0, 30]);
  gates[1].resolve();
  const results = await Promise.all(waiting);
  assert.ok(results.every(result => result.ok));
  assert.deepEqual(completions, [0, 30]);
  assert.equal(peak, 1);
  assert.equal(coordinator.isRefreshing(), false);

  // A detached prior subscription cannot schedule new reads for a later session.
  ctx.app.sharedNavisionVisibleRealtimeGeneration++;
  callback({ new: { revision: 31 } });
  assert.equal(waiting.length, 30);
});
