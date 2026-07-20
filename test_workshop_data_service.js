'use strict';

// Real (non-mocked) unit tests for workshop-data-service.js. These exercise
// the actual module code: opt-in gating, connection-state transitions,
// debounced revision-driven reload, trailing-reload safety, non-null
// version enforcement, and fail-closed behaviour. This is supporting
// coverage only — it does not replace the real PostgreSQL integration
// tests run against the staging Supabase project.

const assert = require('assert');
const {
  WORKSHOP_CONNECTION_STATE,
  workshopSharedModeEnabled,
  createWorkshopDataService
} = require('./workshop-data-service.js');

function fakeClient(responses) {
  const calls = [];
  return {
    calls,
    rpc: async (token, name, params) => {
      calls.push({ token, name, params });
      const next = responses.shift();
      if (!next) throw new Error(`no fake response queued for rpc ${name}`);
      return next;
    }
  };
}

function makeTimerHarness() {
  const timers = [];
  let nextId = 1;
  return {
    scheduleTimeout: (fn, ms) => {
      const id = nextId++;
      timers.push({ id, fn, ms });
      return id;
    },
    clearScheduledTimeout: (id) => {
      const idx = timers.findIndex((t) => t.id === id);
      if (idx >= 0) timers.splice(idx, 1);
    },
    flushAll: async () => {
      while (timers.length) {
        const t = timers.shift();
        await t.fn();
      }
    },
    pendingCount: () => timers.length
  };
}

async function run() {
  // 1. Shared mode disabled by default (config missing or sharedData !== true)
  assert.strictEqual(workshopSharedModeEnabled(null), false, '1a null config is disabled');
  assert.strictEqual(workshopSharedModeEnabled({}), false, '1b empty config is disabled');
  assert.strictEqual(workshopSharedModeEnabled({ workshop: {} }), false, '1c missing sharedData flag is disabled');
  assert.strictEqual(workshopSharedModeEnabled({ workshop: { sharedData: false } }), false, '1d explicit false is disabled');
  assert.strictEqual(workshopSharedModeEnabled({ workshop: { sharedData: true } }), true, '1e explicit true is enabled');
  console.log('PASS 1: shared mode is explicit opt-in, never enabled-unless-false');

  // 2. Disabled service reports DISABLED state and never claims writable
  {
    const client = fakeClient([]);
    const service = createWorkshopDataService({
      config: null,
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator'
    });
    assert.strictEqual(service.isEnabled(), false);
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.DISABLED);
    let threw = false;
    try {
      await service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    } catch (err) {
      threw = true;
    }
    assert.strictEqual(threw, true, '2a disabled service must throw rather than silently writing');
    console.log('PASS 2: disabled service exposes no writable path');
  }

  // 3. Enabled service loads snapshot, becomes CONNECTED_EDITABLE for operator role
  {
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 5, vehicles: [] } }
    ]);
    const states = [];
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator',
      onStateChange: (s) => states.push(s)
    });
    const snap = await service.loadSnapshot('initial');
    assert.strictEqual(snap.revision, 5, '3a snapshot loaded');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE, '3b editable for operator role');
    assert.ok(states.includes(WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE), '3c state transition recorded');
    console.log('PASS 3: enabled + operator role => connected_editable after snapshot load');
  }

  // 4. Viewer role is read-only even though shared mode is enabled and RPC succeeds
  {
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: [] } }
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'viewer'
    });
    await service.loadSnapshot('initial');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY, '4a viewer stays read-only');
    let threw = false;
    try {
      const res = await service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
      assert.strictEqual(res.ok, false, '4b viewer mutation attempt rejected, not thrown as network error');
    } catch (e) { threw = true; }
    assert.strictEqual(threw, false, '4c viewer mutate() returns a rejection object rather than crashing');
    console.log('PASS 4: viewer role remains read-only regardless of shared-mode enablement');
  }

  // 5. Missing / null expected version is rejected client-side before any network call
  {
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: [] } }
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    const callsBefore = client.calls.length;
    const resNull = await service.mutate('resize_workshop_booking', { p_booking_id: 'x', p_expected_version: null, p_duration_minutes: 60 });
    assert.strictEqual(resNull.ok, false, '5a null version rejected');
    assert.strictEqual(resNull.error, 'missing_expected_version', '5b correct error code');
    const resMissing = await service.mutate('resize_workshop_booking', { p_booking_id: 'x', p_duration_minutes: 60 });
    assert.strictEqual(resMissing.ok, false, '5c missing version key rejected');
    assert.strictEqual(client.calls.length, callsBefore, '5d no network call made for rejected mutations');
    console.log('PASS 5: null/missing expected version rejected client-side, no RPC dispatched');
  }

  // 6. Successful mutation triggers a reconciling snapshot reload
  {
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: [] } }, // initial load
      { status: 200, ok: true, body: { ok: true, revision: 2, booking: {} } }, // mutation
      { status: 200, ok: true, body: { revision: 2, vehicles: ['synced'] } } // reconciling reload
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    await service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'synced', '6a snapshot reconciled after successful mutation');
    console.log('PASS 6: successful mutation reconciles from confirmed authoritative snapshot');
  }

  // 7. Rejected stale mutation (version_conflict) also forces a fresh snapshot,
  //    never displaying the unsaved move as successful.
  {
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: [] } },
      { status: 200, ok: true, body: { ok: false, error: 'version_conflict' } },
      { status: 200, ok: true, body: { revision: 3, vehicles: ['authoritative'] } }
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    const res = await service.mutate('move_workshop_booking', { p_booking_id: 'x', p_expected_version: 1, p_stage_code: 'HOIST', p_bay_number: 1, p_scheduled_start_at: '2026-01-01T00:00:00Z' });
    assert.strictEqual(res.ok, false, '7a conflict surfaced to caller');
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'authoritative', '7b planner refreshed to latest version after conflict');
    console.log('PASS 7: rejected stale mutation refreshes to the authoritative snapshot');
  }

  // 8. Revision signal debounces trailing duplicate updates and ignores exact repeats
  {
    const timers = makeTimerHarness();
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: [] } }, // initial
      { status: 200, ok: true, body: { revision: 2, vehicles: ['a'] } } // after revision signal
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator',
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    await service.loadSnapshot('initial');
    service.onRevisionSignal(2);
    service.onRevisionSignal(2); // duplicate signal within debounce window
    assert.strictEqual(timers.pendingCount(), 1, '8a duplicate revision signals collapse into a single scheduled reload');
    await timers.flushAll();
    assert.strictEqual(service.getLastRevision(), 2, '8b reload eventually applies new revision');
    service.onRevisionSignal(2); // exact same revision again -> no reload should be scheduled at all
    assert.strictEqual(timers.pendingCount(), 0, '8c exact-duplicate revision after sync triggers no reload');
    console.log('PASS 8: revision-driven reload is debounced and duplicate-safe');
  }

  // 9. Trailing reload safety: a reload requested while one is already in
  //    flight is not dropped -- it triggers one more reload after the first
  //    completes so we never settle on a stale intermediate snapshot.
  {
    let resolveFirst;
    const client = {
      calls: [],
      rpc: async (token, name) => {
        client.calls.push(name);
        if (client.calls.length === 1) {
          return { status: 200, ok: true, body: { revision: 1, vehicles: [] } };
        }
        if (client.calls.length === 2) {
          return new Promise((resolve) => { resolveFirst = () => resolve({ status: 200, ok: true, body: { revision: 2, vehicles: ['mid'] } }); });
        }
        return { status: 200, ok: true, body: { revision: 3, vehicles: ['final'] } };
      }
    };
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    const p1 = service.loadSnapshot('a');
    const p2 = service.loadSnapshot('b'); // requested while p1 in flight
    resolveFirst();
    await Promise.all([p1, p2]);
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'final', '9a trailing reload applied after in-flight reload completed');
    console.log('PASS 9: trailing reload requested mid-flight is not dropped');
  }

  // 10. destroy() clears pending timers so no reload fires after teardown
  {
    const timers = makeTimerHarness();
    const client = fakeClient([{ status: 200, ok: true, body: { revision: 1, vehicles: [] } }]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator',
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    await service.loadSnapshot('initial');
    service.onRevisionSignal(2);
    assert.strictEqual(timers.pendingCount(), 1, '10a reload scheduled');
    service.destroy();
    assert.strictEqual(timers.pendingCount(), 0, '10b destroy clears pending reload timer');
    assert.strictEqual(service.getTrustedSnapshot(), null, '10c destroy invalidates advisory snapshot trust');
    console.log('PASS 10: destroy() unsubscribes cleanly, preventing reloads after teardown');
  }

  // 11. Advisory snapshot trust is narrower than retained planner fallback:
  //     permission failures and pending revisions fail closed immediately.
  {
    const timers = makeTimerHarness();
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: ['current'] } },
      { status: 403, ok: false, body: { error: 'forbidden' } },
      { status: 200, ok: true, body: { revision: 2, vehicles: ['refreshed'] } }
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'viewer',
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    await service.loadSnapshot('initial');
    assert.strictEqual(service.getTrustedSnapshot().vehicles[0], 'current', '11a successful revision-bearing snapshot is trusted');
    await service.loadSnapshot('permission-check');
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'current', '11b planner may retain the last snapshot after 403');
    assert.strictEqual(service.getTrustedSnapshot(), null, '11c advisor must reject the retained snapshot after 403');
    service.onRevisionSignal(2);
    assert.strictEqual(service.getTrustedSnapshot(), null, '11d pending newer revision remains untrusted during debounce');
    await timers.flushAll();
    assert.strictEqual(service.getTrustedSnapshot().vehicles[0], 'refreshed', '11e successful reload restores trust at the new revision');
    console.log('PASS 11: advisory snapshot trust fails closed for permission errors and pending revisions');
  }

  // 12. A successful publishable-key response is not authenticated authority.
  {
    const client = fakeClient([{ status: 200, ok: true, body: { revision: 9, vehicles: ['must-not-load'] } }]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => null,
      getRole: () => 'viewer'
    });
    const result = await service.loadSnapshot('missing-token');
    assert.strictEqual(result, null, '12a no-token load returns no snapshot');
    assert.strictEqual(client.calls.length, 0, '12b no-token load does not call the publishable-key RPC path');
    assert.strictEqual(service.getTrustedSnapshot(), null, '12c no-token response can never become advisory authority');
    console.log('PASS 12: advisory trust requires a positive individual access token');
  }

  // 13. destroy() permanently invalidates an already in-flight load. A late
  //     response cannot restore trust, retain prior-account rows or callback.
  {
    let resolveLoad;
    let snapshotCallbacks = 0;
    const client = {
      calls: [],
      rpc: async (token, name, params) => {
        client.calls.push({ token, name, params });
        return new Promise(resolve => { resolveLoad = resolve; });
      }
    };
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'viewer',
      onSnapshot: () => { snapshotCallbacks += 1; }
    });
    const pending = service.loadSnapshot('in-flight-at-lock');
    service.destroy();
    assert.strictEqual(service.getLastSnapshot(), null, '13a destroy purges retained snapshot state');
    assert.strictEqual(service.getTrustedSnapshot(), null, '13b destroy immediately removes advisory trust');
    resolveLoad({ status: 200, ok: true, body: { revision: 77, vehicles: ['PRIOR_ACCOUNT_SENTINEL'] } });
    await pending;
    assert.strictEqual(service.getLastSnapshot(), null, '13c late response cannot repopulate retained prior-account data');
    assert.strictEqual(service.getTrustedSnapshot(), null, '13d late response cannot restore advisory trust');
    assert.strictEqual(snapshotCallbacks, 0, '13e late response cannot fire a post-lock render callback');
    const mutation = await service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    assert.strictEqual(mutation.error, 'destroyed', '13f captured destroyed service exposes no mutation path');
    assert.strictEqual(client.calls.length, 1, '13g destroyed mutation dispatches no network call');
    console.log('PASS 13: in-flight responses and captured service calls stay inert after destroy');
  }

  console.log('Workshop data service unit tests passed');
}

run().catch((err) => {
  console.error('Workshop data service unit tests FAILED:', err);
  process.exitCode = 1;
});
