'use strict';

const assert = require('assert');
const {
  LIFECYCLE_RESOLUTION_OUTCOMES,
  vehicleLifecycleResolverRollbackEnabled,
  buildVehicleLifecycleIdentityInput,
  createVehicleLifecycleIdentityResolver,
} = require('./vehicle-lifecycle-actions.js');

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function fakeClient(responder) {
  const calls = [];
  return {
    calls,
    rpc: async (token, name, params) => {
      calls.push({ token, name, params });
      return responder(token, name, params, calls.length);
    },
  };
}

function resolvedBody(version = 3, extras = {}) {
  return {
    outcome: 'resolved',
    vehicle_id: '11111111-1111-4111-8111-111111111111',
    version,
    qc_completed_at: null,
    lifecycle_state: 'active',
    is_archived: false,
    resolver_revision: 7,
    matched_by: ['stock_number'],
    ...extras,
  };
}

(async () => {
  // 1. Rollback is explicit, false by default, and can only be enabled for the
  // guarded staging project. A production-shaped config cannot enable it.
  assert.strictEqual(vehicleLifecycleResolverRollbackEnabled(null), false);
  assert.strictEqual(vehicleLifecycleResolverRollbackEnabled({ vehicleLifecycle: {} }), false);
  assert.strictEqual(vehicleLifecycleResolverRollbackEnabled({
    projectRef: 'cdsmnqxtyyoeoznmbidd',
    url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co',
    vehicleLifecycle: { resolverRollbackDirectRead: true },
  }, { origin: 'https://btnew.github.io', pathname: '/pdc-control-board-staging/' }), true);
  assert.strictEqual(vehicleLifecycleResolverRollbackEnabled({
    projectRef: 'cdsmnqxtyyoeoznmbidd',
    url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co',
    vehicleLifecycle: { resolverRollbackDirectRead: true },
  }, { origin: 'https://example.com', pathname: '/pdc-control-board-staging/' }), false);
  assert.strictEqual(vehicleLifecycleResolverRollbackEnabled({
    projectRef: 'vjdtsswhroyguxyfjdkt',
    url: 'https://vjdtsswhroyguxyfjdkt.supabase.co',
    vehicleLifecycle: { resolverRollbackDirectRead: true },
  }, { origin: 'https://btnew.github.io', pathname: '/pdc-control-board-staging/' }), false);
  console.log('PASS 1: rollback direct-read mode is explicit and staging-only');

  // 2. Legacy objects are converted into typed resolver inputs without using
  // display text or a mutable local id as canonical identity.
  assert.deepStrictEqual(buildVehicleLifecycleIdentityInput({
    id: 'LOCAL-ROW-7',
    sharedVehicleId: '11111111-1111-4111-8111-111111111111',
    vehicle_id: '11111111-1111-4111-8111-111111111111',
    stock: ' STK-001 ',
    fullVin: '1HGCM82633A004352',
    pdcJobcard: ' JC-9 ',
    permanentVehicleId: ' PERM-1 ',
    toyotaOrder: ' ORD-4 ',
    sourceSystem: ' Navision ',
    sourceRecordId: ' ROW-8 ',
    vehicle: 'Display text must not be mapped',
  }), {
    p_vehicle_id: '11111111-1111-4111-8111-111111111111',
    p_stock_number: 'STK-001',
    p_vin: '1HGCM82633A004352',
    p_job_card_number: 'JC-9',
    p_permanent_vehicle_id: 'PERM-1',
    p_toyota_order_number: 'ORD-4',
    p_source_system: 'Navision',
    p_source_record_id: 'ROW-8',
  });
  const conflictingIdentity = buildVehicleLifecycleIdentityInput({ stock: 'STK-001', stockNumber: 'STK-002' });
  assert.strictEqual(conflictingIdentity.__invalidIdentityField, 'stock_number');
  assert.strictEqual(
    buildVehicleLifecycleIdentityInput({ stock: 'STK-001', pdcJobcard: 'JC-2' }).__invalidIdentityField,
    'job_card_source_system',
  );
  assert.strictEqual(
    buildVehicleLifecycleIdentityInput({ stock: 'STK-001', toyotaOrderNumber: 'ORDER-2' }).__invalidIdentityField,
    'toyota_order_source_system',
  );
  const invalidResolverClient = fakeClient(async () => { throw new Error('must not be called'); });
  const invalidIdentity = await createVehicleLifecycleIdentityResolver({ client: invalidResolverClient }).resolve(conflictingIdentity);
  assert.deepStrictEqual(invalidIdentity, { outcome: 'invalid_input', field: 'stock_number' });
  assert.strictEqual(invalidResolverClient.calls.length, 0);
  assert.strictEqual(buildVehicleLifecycleIdentityInput({ chassis: 'not-a-vin', frame: 'display-frame' }).p_vin, undefined);
  console.log('PASS 2: typed lifecycle identity input excludes local id and display text');

  // 3. Every call performs a fresh narrow RPC resolution. The browser never
  // reuses a prior first-match result as authority, and extra server fields are
  // stripped from the resolved projection.
  {
    const client = fakeClient(async () => ({
      ok: true,
      status: 200,
      body: resolvedBody(4, { customer_name: 'must not escape', workshop_status: 'must not escape' }),
    }));
    const resolver = createVehicleLifecycleIdentityResolver({ client, getAccessToken: () => 'token-a' });
    const input = { p_stock_number: 'STK-001' };
    const first = await resolver.resolve(input);
    const second = await resolver.resolve(input);
    assert.strictEqual(client.calls.length, 2);
    assert.strictEqual(client.calls[0].name, 'resolve_vehicle_lifecycle_identity');
    assert.strictEqual(client.calls[0].token, 'token-a');
    assert.deepStrictEqual(client.calls[0].params, input);
    assert.deepStrictEqual(first, second);
    assert.deepStrictEqual(Object.keys(first).sort(), [
      'isArchived', 'lifecycleState', 'matchedBy', 'outcome', 'qcCompletedAt',
      'resolverRevision', 'vehicleId', 'version',
    ].sort());
    assert.strictEqual(first.customer_name, undefined);
  }
  console.log('PASS 3: resolver is fresh-per-call and strips unrelated projection fields');

  // 4. The complete public outcome vocabulary is preserved. HTTP auth failures
  // expose no body; network/server failures become service_unavailable.
  {
    assert.deepStrictEqual([...LIFECYCLE_RESOLUTION_OUTCOMES].sort(), [
      'resolved', 'not_found', 'ambiguous', 'conflict', 'invalid_input',
      'unauthorized', 'service_unavailable',
    ].sort());
    const bodies = ['not_found', 'ambiguous', 'conflict', 'invalid_input', 'unauthorized'];
    for (const outcome of bodies) {
      const client = fakeClient(async () => ({ ok: true, status: 200, body: { outcome, diagnostic: 'safe' } }));
      const result = await createVehicleLifecycleIdentityResolver({ client }).resolve({ p_stock_number: 'x' });
      assert.strictEqual(result.outcome, outcome);
      assert.strictEqual(result.vehicleId, undefined);
    }
    const unauthorized = await createVehicleLifecycleIdentityResolver({
      client: fakeClient(async () => ({ ok: false, status: 401, body: { secret: 'no' } })),
    }).resolve({ p_stock_number: 'x' });
    assert.deepStrictEqual(unauthorized, { outcome: 'unauthorized' });
    const unavailable = await createVehicleLifecycleIdentityResolver({
      client: fakeClient(async () => { throw new Error('offline'); }),
    }).resolve({ p_stock_number: 'x' });
    assert.deepStrictEqual(unavailable, { outcome: 'service_unavailable' });
  }
  console.log('PASS 4: explicit outcome vocabulary maps auth and service failures safely');

  // 5. Concurrent stale responses cannot overwrite the latest observed
  // version in the resolver cache.
  {
    const slow = deferred();
    const client = fakeClient(async (_token, _name, _params, index) => {
      if (index === 1) return slow.promise;
      return { ok: true, status: 200, body: resolvedBody(9) };
    });
    const resolver = createVehicleLifecycleIdentityResolver({ client });
    const input = { p_stock_number: 'STK-001' };
    const oldRequest = resolver.resolve(input);
    const fresh = await resolver.resolve(input);
    slow.resolve({ ok: true, status: 200, body: resolvedBody(2) });
    const staleResult = await oldRequest;
    assert.deepStrictEqual(staleResult, { outcome: 'service_unavailable', reason: 'superseded' });
    assert.strictEqual(fresh.version, 9);
    assert.strictEqual(resolver.getLatest(input).version, 9);
  }
  console.log('PASS 5: stale in-flight response cannot replace a newer resolver version');

  // 6. One Realtime subscription refreshes every tracked typed input after a
  // revision change. start() is idempotent and stop() removes the subscription.
  {
    let handlers;
    let subscriptions = 0;
    let unsubscribes = 0;
    const refreshed = [];
    const client = fakeClient(async (_token, _name, _params, index) => ({
      ok: true, status: 200, body: resolvedBody(index),
    }));
    const resolver = createVehicleLifecycleIdentityResolver({
      client,
      subscribe: next => {
        subscriptions += 1;
        handlers = next;
        return { unsubscribe: () => { unsubscribes += 1; } };
      },
      onRefresh: item => refreshed.push(item),
    });
    await resolver.resolve({ p_stock_number: 'STK-001' });
    resolver.start();
    resolver.start();
    assert.strictEqual(subscriptions, 1);
    await handlers.onChange({ new: { revision: 8 } });
    assert.strictEqual(client.calls.length, 2);
    assert.strictEqual(resolver.getLatest({ p_stock_number: 'STK-001' }).version, 2);
    assert.strictEqual(refreshed.length, 1);
    resolver.stop();
    assert.strictEqual(unsubscribes, 1);
  }
  console.log('PASS 6: one Realtime channel deterministically refreshes tracked inputs');

  // 7. Every SUBSCRIBED transition performs an authoritative refresh so a
  // revision that lands while the channel is joining cannot be missed.
  {
    let handlers;
    const client = fakeClient(async (_token, _name, _params, index) => ({
      ok: true, status: 200, body: resolvedBody(index),
    }));
    const resolver = createVehicleLifecycleIdentityResolver({
      client,
      subscribe: next => { handlers = next; return { unsubscribe() {} }; },
    });
    await resolver.resolve({ p_vin: '1HGCM82633A004352' });
    resolver.start();
    await handlers.onStatus('SUBSCRIBED');
    assert.strictEqual(client.calls.length, 2);
    await handlers.onStatus('CHANNEL_ERROR');
    await handlers.onStatus('SUBSCRIBED');
    assert.strictEqual(client.calls.length, 3);
  }
  console.log('PASS 7: initial subscribe and reconnect both reconcile authoritatively');

  // 8. Invalid/malformed resolved bodies fail closed rather than constructing
  // a vehicle reference with a missing UUID or optimistic version.
  {
    const client = fakeClient(async () => ({ ok: true, status: 200, body: { outcome: 'resolved', version: 0 } }));
    const result = await createVehicleLifecycleIdentityResolver({ client }).resolve({ p_stock_number: 'x' });
    assert.deepStrictEqual(result, { outcome: 'service_unavailable' });
  }
  console.log('PASS 8: malformed resolver payloads fail closed');

  // 9. Stale refresh results are suppressed from both the authoritative cache
  // and the public onRefresh stream. stop() purges retained session state.
  {
    const slow = deferred();
    const refreshed = [];
    const client = fakeClient(async (_token, _name, _params, index) => {
      if (index === 2) return slow.promise;
      return { ok: true, status: 200, body: resolvedBody(index + 10) };
    });
    const input = { p_stock_number: 'STK-001' };
    const resolver = createVehicleLifecycleIdentityResolver({ client, onRefresh: item => refreshed.push(item) });
    await resolver.resolve(input);
    const oldRefresh = resolver.refreshTracked('old');
    const fresh = await resolver.resolve(input);
    slow.resolve({ ok: true, status: 200, body: resolvedBody(2) });
    await oldRefresh;
    assert.strictEqual(fresh.version, 13);
    assert.strictEqual(refreshed.length, 0);
    assert.strictEqual(resolver.getLatest(input).version, 13);
    assert.ok(resolver.getDiagnostics().some(item => item.stale === true && item.counters.staleSuppressed >= 1));
    resolver.stop();
    assert.strictEqual(resolver.getLatest(input), null);
    assert.deepStrictEqual(resolver.getDiagnostics(), []);
  }
  console.log('PASS 9: stale refresh events are suppressed and stop purges resolver state');

  // 9b. A locally invalid typed identity is never stripped and replayed as a
  // valid tracked RPC request during reconciliation.
  {
    const client = fakeClient(async () => ({ ok: true, status: 200, body: resolvedBody(99) }));
    const resolver = createVehicleLifecycleIdentityResolver({ client });
    const invalid = buildVehicleLifecycleIdentityInput({ stock: 'A-1', stockNumber: 'B-2' });
    assert.strictEqual((await resolver.resolve(invalid)).outcome, 'invalid_input');
    await resolver.reconcile('invalid_replay');
    assert.strictEqual(client.calls.length, 0);
    assert.strictEqual(resolver.getLatest({ p_stock_number: 'A-1' }), null);
  }
  console.log('PASS 9b: invalid typed identity is never replayed as a tracked request');

  // 9c. Teardown invalidates pending requests and prevents diagnostics from
  // repopulating after auth lockout.
  {
    const slow = deferred();
    const externalDiagnostics = [];
    const resolver = createVehicleLifecycleIdentityResolver({
      client: fakeClient(async () => slow.promise),
      onDiagnostic: item => externalDiagnostics.push(item),
    });
    const pending = resolver.resolve({ p_stock_number: 'STK-LOCK' });
    resolver.stop();
    slow.resolve({ ok: true, status: 200, body: resolvedBody(7) });
    assert.deepStrictEqual(await pending, { outcome: 'service_unavailable', reason: 'resolver_stopped' });
    assert.deepStrictEqual(resolver.getDiagnostics(), []);
    assert.strictEqual(externalDiagnostics.length, 0);
  }
  console.log('PASS 9c: stop invalidates pending results and suppresses post-lock diagnostics');

  // 10. Bursty reconciliation signals are bounded to one in-flight refresh
  // followed by one trailing authoritative refresh.
  {
    const slow = deferred();
    const client = fakeClient(async (_token, _name, _params, index) => {
      if (index === 2) return slow.promise;
      return { ok: true, status: 200, body: resolvedBody(index) };
    });
    const resolver = createVehicleLifecycleIdentityResolver({ client });
    await resolver.resolve({ p_stock_number: 'STK-001' });
    const first = resolver.reconcile('event-1');
    const second = resolver.reconcile('event-2');
    const third = resolver.reconcile('event-3');
    slow.resolve({ ok: true, status: 200, body: resolvedBody(2) });
    await Promise.all([first, second, third]);
    assert.strictEqual(client.calls.length, 3);
    assert.ok(resolver.getDiagnostics().some(item => item.counters.coalescedRefreshes >= 2));
  }
  console.log('PASS 10: refresh bursts are bounded to one in-flight plus one trailing refresh');
})().catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
