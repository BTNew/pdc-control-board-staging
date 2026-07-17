'use strict';

/*
 * Real (non-mocked) unit tests for workshop-reference-data-service.js.
 * Exercises the actual module logic with a fake fetch-free RPC client
 * (dependency-injected, not mocked-out module internals) and a fake
 * realtime subscription transport, mirroring the existing pattern used by
 * test_workshop_data_service.js for the sibling booking-data service.
 */
const assert = require('assert');
const {
  WORKSHOP_REFERENCE_CONNECTION_STATE,
  createWorkshopReferenceDataService
} = require('./workshop-reference-data-service.js');

let passed = 0;
let failed = 0;

function check(label, fn) {
  try {
    fn();
    console.log(`PASS  ${label}`);
    passed++;
  } catch (err) {
    console.log(`FAIL  ${label}  ${err.message}`);
    failed++;
  }
}

function makeFakeClient(responses) {
  const calls = [];
  return {
    calls,
    rpc: async (token, name, params) => {
      calls.push({ token, name, params });
      const responder = responses[name];
      if (typeof responder === 'function') return responder(params, token);
      if (responder) return responder;
      return { status: 404, ok: false, body: { message: 'no fake response configured' } };
    }
  };
}

// ---------------------------------------------------------------------
// 1. No access token -> permission_denied, never returns stale data
// ---------------------------------------------------------------------
(async () => {
  const client = makeFakeClient({});
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => null });
  const rows = await service.listTechnicians();
  check('1a no access token returns empty array, not a stale/fallback list', () => assert.deepStrictEqual(rows, []));
  check('1b no access token sets state to permission_denied', () =>
    assert.strictEqual(service.getState('technicians'), WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED));
})();

// ---------------------------------------------------------------------
// 2. Successful list -> connected_read_only by default
// ---------------------------------------------------------------------
(async () => {
  const client = makeFakeClient({
    list_technicians: { status: 200, ok: true, body: [{ id: 't1', name: 'A', active: true, version: 1 }] }
  });
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => 'tok' });
  const rows = await service.listTechnicians();
  check('2a successful list returns the real rows', () => assert.strictEqual(rows.length, 1));
  check('2b successful list defaults to connected_read_only (never assumes editable)', () =>
    assert.strictEqual(service.getState('technicians'), WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_READ_ONLY));
  check('2c getCachedTechnicians returns the same rows without a new call', () =>
    assert.strictEqual(service.getCachedTechnicians().rows.length, 1));
})();

// ---------------------------------------------------------------------
// 3. 403 from the database (permission denied by require_pdc_role) is
//    classified as permission_denied, not offline_error
// ---------------------------------------------------------------------
(async () => {
  const client = makeFakeClient({
    list_technicians: { status: 200, ok: true, body: [] },
    add_technician: { status: 403, ok: false, body: { code: '42501', message: 'PDC role administrator required' } }
  });
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => 'tok' });
  const result = await service.addTechnician('New Tech');
  check('3a 403/42501 add_technician is classified as permission_denied', () => assert.strictEqual(result.error, 'permission_denied'));
  check('3b permission-denied write leaves resource state permission_denied', () =>
    assert.strictEqual(service.getState('technicians'), WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED));
})();

// ---------------------------------------------------------------------
// 4. Successful add -> state becomes connected_editable, and the service
//    automatically re-loads the list afterward (resync, not a guess)
// ---------------------------------------------------------------------
(async () => {
  let listCallCount = 0;
  const client = makeFakeClient({
    list_technicians: () => {
      listCallCount += 1;
      return { status: 200, ok: true, body: listCallCount === 1 ? [] : [{ id: 't1', name: 'New Tech', active: true, version: 1 }] };
    },
    add_technician: { status: 200, ok: true, body: { ok: true, technician: { id: 't1', name: 'New Tech', active: true, version: 1 } } }
  });
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => 'tok' });
  await service.listTechnicians();
  const result = await service.addTechnician('New Tech');
  check('4a add_technician reports ok:true', () => assert.strictEqual(result.ok, true));
  check('4b state becomes connected_editable after a successful write', () =>
    assert.strictEqual(service.getState('technicians'), WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_EDITABLE));
  check('4c the service re-loaded the list after the mutation (2 list calls total)', () => assert.strictEqual(listCallCount, 2));
  check('4d cached rows reflect the post-mutation reload, not a client-side guess', () =>
    assert.strictEqual(service.getCachedTechnicians().rows[0].name, 'New Tech'));
})();

// ---------------------------------------------------------------------
// 5. Version conflict is passed through verbatim, not swallowed
// ---------------------------------------------------------------------
(async () => {
  const client = makeFakeClient({
    list_technicians: { status: 200, ok: true, body: [] },
    edit_technician: { status: 200, ok: true, body: { ok: false, error: 'version_conflict', current: { id: 't1', version: 3 } } }
  });
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => 'tok' });
  const result = await service.editTechnician('t1', 1, { name: 'Renamed' });
  check('5a version_conflict is surfaced to the caller, not hidden', () => assert.strictEqual(result.error, 'version_conflict'));
  check('5b the conflicting current row is included for the UI to react to', () => assert.strictEqual(result.current.version, 3));
})();

// ---------------------------------------------------------------------
// 6. Realtime subscription: no duplicate subscriptions, onChange
//    triggers a re-load, reconnect status updates the state
// ---------------------------------------------------------------------
(async () => {
  let subscribeCallCount = 0;
  let onChangeHandler = null;
  let onStatusHandler = null;
  let listCallCount = 0;
  const client = makeFakeClient({
    list_technicians: () => {
      listCallCount += 1;
      return { status: 200, ok: true, body: [] };
    }
  });
  const service = createWorkshopReferenceDataService({
    client,
    getAccessToken: () => 'tok',
    subscribeRealtime: (table, handlers) => {
      subscribeCallCount += 1;
      onChangeHandler = handlers.onChange;
      onStatusHandler = handlers.onStatus;
      return { unsubscribe: () => {} };
    }
  });

  const sub1 = service.subscribeTechnicians();
  const sub2 = service.subscribeTechnicians();
  check('6a a second subscribeTechnicians() call reuses the existing subscription (no duplicate)', () => assert.strictEqual(subscribeCallCount, 1));
  check('6b both calls return the same subscription object', () => assert.strictEqual(sub1, sub2));

  const beforeCount = listCallCount;
  onChangeHandler({});
  await new Promise((resolve) => setTimeout(resolve, 10));
  check('6c a realtime onChange event triggers a re-load from the authoritative source', () => assert.ok(listCallCount > beforeCount));

  onStatusHandler('TIMED_OUT');
  check('6d a TIMED_OUT realtime status sets state to reconnecting', () =>
    assert.strictEqual(service.getState('technicians'), WORKSHOP_REFERENCE_CONNECTION_STATE.RECONNECTING));

  onStatusHandler('SUBSCRIBED');
  service.unsubscribeAll();
})();

// ---------------------------------------------------------------------
// 7. Workshop configuration get/update round trip, including unknown-key
//    and permission-denied passthrough
// ---------------------------------------------------------------------
(async () => {
  const client = makeFakeClient({
    get_workshop_configuration: { status: 200, ok: true, body: { day_start_time: { value: '08:00', version: 1 } } },
    update_workshop_configuration: (params) => {
      if (params.p_key === 'not_a_real_key') return { status: 200, ok: true, body: { ok: false, error: 'unknown_setting_key' } };
      return { status: 200, ok: true, body: { ok: true, setting: { key: params.p_key, value: params.p_value, version: params.p_expected_version + 1 } } };
    }
  });
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => 'tok' });
  const config = await service.getWorkshopConfiguration();
  check('7a getWorkshopConfiguration returns real configuration', () => assert.strictEqual(config.configuration.day_start_time.value, '08:00'));

  const updateResult = await service.updateWorkshopConfiguration('day_start_time', 1, '07:30');
  check('7b updateWorkshopConfiguration succeeds with a valid key', () => assert.strictEqual(updateResult.ok, true));

  const badResult = await service.updateWorkshopConfiguration('not_a_real_key', 1, 'x');
  check('7c updateWorkshopConfiguration surfaces unknown_setting_key rather than silently succeeding', () => assert.strictEqual(badResult.error, 'unknown_setting_key'));
})();

// ---------------------------------------------------------------------
// 8. No client configured at all -> explicit error, never a silent
//    empty success
// ---------------------------------------------------------------------
(async () => {
  const service = createWorkshopReferenceDataService({ config: null, getAccessToken: () => 'tok' });
  const rows = await service.listTechnicians();
  check('8a no client configured returns empty array with offline_error state, not a silent success', () => {
    assert.deepStrictEqual(rows, []);
    assert.strictEqual(service.getState('technicians'), WORKSHOP_REFERENCE_CONNECTION_STATE.OFFLINE_ERROR);
  });
})();

// ---------------------------------------------------------------------
// 9. Out-of-order concurrent loadResource() responses: an earlier-
//    started, later-resolving request must never overwrite a
//    later-started, earlier-resolving one (the "always one edit behind"
//    realtime race this fixes).
// ---------------------------------------------------------------------
(async () => {
  let callIndex = 0;
  const resolvers = [];
  const client = {
    calls: [],
    rpc: async (token, name) => {
      const myIndex = callIndex++;
      if (name === 'list_technicians') {
        // Response ordering is deliberately reversed from call ordering:
        // the FIRST call's response resolves LAST.
        await new Promise((resolve) => { resolvers[myIndex] = resolve; });
        return { status: 200, ok: true, body: [{ id: 't1', name: `call-${myIndex}`, active: true, version: 1 }] };
      }
      return { status: 404, ok: false, body: {} };
    }
  };
  const service = createWorkshopReferenceDataService({ client, getAccessToken: () => 'tok' });

  const firstCallPromise = service.listTechnicians(); // starts call 0
  await new Promise((resolve) => setTimeout(resolve, 5));
  const secondCallPromise = service.listTechnicians(); // starts call 1, while call 0 is still in flight
  await new Promise((resolve) => setTimeout(resolve, 5));

  // Resolve out of order: call 1 (the newer one) resolves first, call 0
  // (the older, now-stale one) resolves second.
  resolvers[1]();
  await new Promise((resolve) => setTimeout(resolve, 5));
  resolvers[0]();
  await Promise.all([firstCallPromise, secondCallPromise]);

  check('9a the stale (earlier-started, later-resolving) response is discarded, not written to the cache', () =>
    assert.strictEqual(service.getCachedTechnicians().rows[0].name, 'call-1'));
})();

// ---------------------------------------------------------------------
// 10. Ordering: the cache MUST already contain the fresh rows by the
//    moment onStateChange fires, not one tick later. This is the exact
//    ordering bug found during Stage 2A two-browser acceptance testing:
//    setState() (which synchronously calls onStateChange -> the
//    frontend's render trigger) was previously called BEFORE the cache
//    write, so every render triggered by a state change read one-fetch-
//    stale data even though the fetch itself had already succeeded.
// ---------------------------------------------------------------------
(async () => {
  let observedDuringCallback = null;
  const client = {
    rpc: async (token, name) => {
      if (name === 'list_technicians') {
        return { status: 200, ok: true, body: [{ id: 't1', name: 'fresh-name', active: true, version: 1 }] };
      }
      return { status: 404, ok: false, body: {} };
    }
  };
  const service = createWorkshopReferenceDataService({
    client,
    getAccessToken: () => 'tok',
    onStateChange: () => {
      // Capture what the cache looks like AT THE MOMENT onStateChange
      // fires -- this is exactly what a real render callback would see.
      observedDuringCallback = service.getCachedTechnicians().rows.map(r => r.name);
    }
  });
  await service.listTechnicians();
  check('10a onStateChange fires only after the cache already holds the fresh rows (no stale-read window)', () =>
    assert.deepStrictEqual(observedDuringCallback, ['fresh-name']));
})();

// ---------------------------------------------------------------------
// 11. workshop_settings realtime subscription: a change to
//    workshop_settings must trigger a re-load via subscribeWorkshopSettings(),
//    and the fresh configuration must be visible via
//    getCachedWorkshopConfiguration() the moment onStateChange fires --
//    settings were previously never subscribed to at all (real gap found
//    during Stage 2A two-browser acceptance testing).
// ---------------------------------------------------------------------
(async () => {
  let configVersion = 1;
  let onChangeHandler = null;
  const client = {
    rpc: async (token, name) => {
      if (name === 'get_workshop_configuration') {
        return { status: 200, ok: true, body: { default_booking_duration_minutes: { value: 100 * configVersion, version: configVersion, updated_at: 'now' } } };
      }
      return { status: 404, ok: false, body: {} };
    }
  };
  let observedDuringCallback = null;
  const service = createWorkshopReferenceDataService({
    client,
    getAccessToken: () => 'tok',
    subscribeRealtime: (table, handlers) => {
      if (table === 'workshop_settings') onChangeHandler = handlers.onChange;
      return { unsubscribe: () => {} };
    },
    onStateChange: (resourceKey) => {
      if (resourceKey === 'workshopSettings') {
        observedDuringCallback = service.getCachedWorkshopConfiguration().rows.default_booking_duration_minutes.value;
      }
    }
  });

  await service.getWorkshopConfiguration();
  check('11a getCachedWorkshopConfiguration reflects the initial load', () =>
    assert.strictEqual(service.getCachedWorkshopConfiguration().rows.default_booking_duration_minutes.value, 100));

  service.subscribeWorkshopSettings();
  check('11b subscribeWorkshopSettings registers a real onChange handler for the workshop_settings table', () =>
    assert.strictEqual(typeof onChangeHandler, 'function'));

  configVersion = 2;
  await onChangeHandler();
  check('11c a workshop_settings realtime change triggers a re-load with the new value', () =>
    assert.strictEqual(service.getCachedWorkshopConfiguration().rows.default_booking_duration_minutes.value, 200));
  check('11d onStateChange for the settings resource fires only after the cache already holds the fresh value', () =>
    assert.strictEqual(observedDuringCallback, 200));

  check('11e calling subscribeWorkshopSettings twice does not open a second channel', () => {
    let secondCallCount = 0;
    const service2 = createWorkshopReferenceDataService({
      client, getAccessToken: () => 'tok',
      subscribeRealtime: () => { secondCallCount += 1; return { unsubscribe: () => {} }; }
    });
    service2.subscribeWorkshopSettings();
    service2.subscribeWorkshopSettings();
    assert.strictEqual(secondCallCount, 1);
  });
})();

// ---------------------------------------------------------------------
// 12. Reconcile immediately after a channel reconnect: a change made
//    by another session while THIS socket was disconnected produces no
//    postgres_changes event on this channel (there is no live channel
//    to deliver it to), so a fresh resync must be triggered as soon as
//    the channel reports SUBSCRIBED again after a genuine reconnect --
//    not just on the very first (initial) subscribe.
// ---------------------------------------------------------------------
(async () => {
  let listCallCount = 0;
  let onStatusHandler = null;
  const client = {
    rpc: async () => {
      listCallCount += 1;
      return { status: 200, ok: true, body: [{ id: 't1', name: `call-${listCallCount}`, active: true, version: 1 }] };
    }
  };
  const service = createWorkshopReferenceDataService({
    client,
    getAccessToken: () => 'tok',
    subscribeRealtime: (table, handlers) => {
      onStatusHandler = handlers.onStatus;
      return { unsubscribe: () => {} };
    }
  });

  service.subscribeTechnicians();
  onStatusHandler('SUBSCRIBED'); // initial subscribe -- must NOT trigger an extra resync
  check('12a the initial SUBSCRIBED status does not trigger a duplicate resync', () =>
    assert.strictEqual(listCallCount, 0));

  onStatusHandler('CHANNEL_ERROR'); // connection drops
  onStatusHandler('SUBSCRIBED');    // reconnects -- THIS must trigger a resync
  await new Promise(resolve => setTimeout(resolve, 0));
  check('12b a genuine reconnect (after CHANNEL_ERROR) triggers a fresh resync', () =>
    assert.strictEqual(listCallCount, 1));

  onStatusHandler('TIMED_OUT');
  onStatusHandler('SUBSCRIBED');
  await new Promise(resolve => setTimeout(resolve, 0));
  check('12c reconnectAttempt resets after the reconcile, so the next drop/reconnect cycle also reconciles', () =>
    assert.strictEqual(listCallCount, 2));
})();

setTimeout(() => {
  console.log();
  console.log(`TOTAL: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exitCode = 1;
}, 200);
