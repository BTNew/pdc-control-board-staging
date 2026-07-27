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

assert.strictEqual(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED, 'permission_denied', 'authorization failures require an explicit stable UI state');

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

  // 7b. Vehicle-level version conflicts are common when email/Navision updates
  //      land while a planner tab is open. mutate() must not return until the
  //      replacement authoritative snapshot is actually available for retry.
  {
    let resolveRefresh;
    const refreshResponse = new Promise(resolve => { resolveRefresh = resolve; });
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: [{ id: 'v', version: 1 }] } },
      { status: 200, ok: true, body: { ok: false, error: 'vehicle_version_conflict' } },
      refreshResponse,
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    let settled = false;
    const mutation = service.mutate('schedule_vehicle_work', {
      p_vehicle_id: 'v', p_vehicle_expected_version: 1, p_stage_code: 'TYRE', p_bay_number: 1,
      p_scheduled_start_at: '2030-07-15T03:00:00Z', p_duration_minutes: 60,
    }).then(result => { settled = true; return result; });
    await new Promise(resolve => setImmediate(resolve));
    assert.strictEqual(settled, false, '7b conflict result must wait for authoritative refresh');
    resolveRefresh({ status: 200, ok: true, body: { revision: 2, vehicles: [{ id: 'v', version: 2 }] } });
    const result = await mutation;
    assert.strictEqual(result.error, 'vehicle_version_conflict');
    assert.strictEqual(service.getTrustedSnapshot().vehicles[0].version, 2, '7c retry consumers receive the refreshed vehicle version');
    console.log('PASS 7b: vehicle version conflict waits for a trusted authoritative refresh');
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
    const staleMutation = await service.mutate('move_workshop_booking', { p_booking_id: 'stale', p_expected_version: 1 });
    assert.deepStrictEqual(staleMutation.error, 'not_editable', '8a mutation must fail closed while a newer revision is pending');
    assert.strictEqual(timers.pendingCount(), 1, '8b duplicate revision signals collapse into a single scheduled reload');
    await timers.flushAll();
    assert.strictEqual(service.getLastRevision(), 2, '8c reload eventually applies new revision');
    service.onRevisionSignal(2); // exact same revision again -> no reload should be scheduled at all
    assert.strictEqual(timers.pendingCount(), 0, '8d exact-duplicate revision after sync triggers no reload');
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

  // 11. Permission failures purge retained planner/advisory rows immediately;
  //     pending revisions keep offline continuity but fail advisory trust.
  {
    const timers = makeTimerHarness();
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: ['current'] } },
      { status: 403, ok: false, body: { error: 'forbidden' } },
      { status: 200, ok: true, body: { revision: 2, vehicles: ['refreshed'] } }
    ]);
    let accessToken = 'tok';
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => accessToken,
      getRole: () => 'viewer',
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    await service.loadSnapshot('initial');
    assert.strictEqual(service.getTrustedSnapshot().vehicles[0], 'current', '11a successful revision-bearing snapshot is trusted');
    await service.loadSnapshot('permission-check');
    assert.strictEqual(service.getLastSnapshot(), null, '11b planner must purge retained operational rows after 403');
    assert.strictEqual(service.getTrustedSnapshot(), null, '11c advisor must reject all snapshot authority after 403');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED, '11d permission loss remains explicit after purge');
    service.onRevisionSignal(2);
    assert.strictEqual(service.getTrustedSnapshot(), null, '11e pending newer revision remains untrusted during debounce');
    await timers.flushAll();
    assert.strictEqual(service.getTrustedSnapshot().vehicles[0], 'refreshed', '11f successful reload restores trust at the new revision');
    accessToken = null;
    assert.strictEqual(await service.loadSnapshot('token-lost'), null, '11g token loss returns no retained snapshot');
    assert.strictEqual(service.getLastSnapshot(), null, '11h token loss purges refreshed operational rows');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED, '11i token loss enters permission_denied');
    console.log('PASS 11: permission loss purges retained rows and pending revisions fail advisory trust');
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

  // 14. Realtime authority loss invalidates an in-flight request. Its late
  //     response cannot restore actionable state; only a fresh-generation
  //     resync after the replacement subscription may restore authority.
  {
    let resolveOld;
    let calls = 0;
    let snapshots = 0;
    const client = {
      rpc: async () => {
        calls += 1;
        if (calls === 1) return new Promise(resolve => { resolveOld = resolve; });
        return { status: 200, ok: true, body: { revision: 2, vehicles: ['fresh'] } };
      }
    };
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } },
      client,
      getAccessToken: () => 'tok',
      getRole: () => 'operator',
      onSnapshot: () => { snapshots += 1; }
    });
    const oldLoad = service.loadSnapshot('old-channel');
    service.onAuthorityLost();
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.RECONNECTING);
    assert.strictEqual(service.getLastSnapshot(), null);
    resolveOld({ status: 200, ok: true, body: { revision: 1, vehicles: ['stale'] } });
    await oldLoad;
    assert.strictEqual(service.getLastSnapshot(), null, '14a failed-generation response remains inert');
    assert.strictEqual(service.getTrustedSnapshot(), null, '14b failed-generation response cannot restore trust');
    assert.strictEqual(snapshots, 0, '14c failed-generation response cannot render');
    await service.onReconnect();
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'fresh', '14d replacement generation installs fresh snapshot');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE);
    assert.strictEqual(snapshots, 1, '14e only fresh-generation snapshot renders');
    console.log('PASS 14: authority generation rejects late failed-channel responses');
  }

  // 15. Mutation authorization denial purges first, then may restore only a
  //     freshly revalidated readable snapshot for action-specific 403s.
  {
    const states = [];
    const client = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: ['STALE'] } },
      { status: 403, ok: false, body: { error: 'admin_only' } },
      { status: 200, ok: true, body: { revision: 2, vehicles: ['FRESH'] } }
    ]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } }, client,
      getAccessToken: () => 'tok', getRole: () => 'operator',
      onStateChange: state => states.push(state)
    });
    await service.loadSnapshot('initial');
    const denied = await service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    assert.strictEqual(denied.ok, false, '15a denied mutation remains denied');
    assert.ok(states.includes(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED), '15b denial atomically announces purged authority');
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'FRESH', '15c only a fresh read-authorized snapshot may return after action-specific denial');
    assert.strictEqual(service.getLastRevision(), 2, '15d stale revision authority is replaced');

    const deniedClient = fakeClient([
      { status: 200, ok: true, body: { revision: 1, vehicles: ['SECRET'] } },
      { status: 401, ok: false, body: { error: 'expired' } },
      { status: 401, ok: false, body: { error: 'expired' } }
    ]);
    const deniedService = createWorkshopDataService({
      config: { workshop: { sharedData: true } }, client: deniedClient,
      getAccessToken: () => 'expired', getRole: () => 'operator'
    });
    await deniedService.loadSnapshot('initial');
    await deniedService.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    assert.strictEqual(deniedService.getLastSnapshot(), null, '15e failed read revalidation retains no operational rows');
    assert.strictEqual(deniedService.getLastRevision(), null, '15f failed read revalidation retains no revision authority');
    assert.strictEqual(deniedService.getState(), WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED, '15g failed revalidation remains terminal denied');
    console.log('PASS 15: mutation denial purges stale rows and re-establishes only freshly proven read authority');
  }

  // 16. A missing mutation token purges authority before any RPC dispatch.
  {
    let token = 'tok';
    const client = fakeClient([{ status: 200, ok: true, body: { revision: 1, vehicles: ['SECRET'] } }]);
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } }, client,
      getAccessToken: () => token, getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    token = null;
    const before = client.calls.length;
    const denied = await service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    assert.strictEqual(denied.error, 'permission_denied', '16a missing token is explicit');
    assert.strictEqual(client.calls.length, before, '16b publishable-key mutation fallback is never called');
    assert.strictEqual(service.getLastSnapshot(), null, '16c missing token purges rows');
    console.log('PASS 16: missing mutation token purges authority before dispatch');
  }

  // 17. Token loss while a snapshot request is active supersedes that request
  //     rather than coalescing onto retained prior-authority rows.
  {
    let token = 'tok';
    let resolveRefresh;
    let calls = 0;
    const client = { rpc: async () => {
      calls += 1;
      if (calls === 1) return { status: 200, ok: true, body: { revision: 1, vehicles: ['SECRET'] } };
      return new Promise(resolve => { resolveRefresh = resolve; });
    } };
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } }, client,
      getAccessToken: () => token, getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    const pending = service.loadSnapshot('refresh');
    token = null;
    assert.strictEqual(await service.loadSnapshot('token-lost-mid-flight'), null, '17a token loss never returns retained rows');
    assert.strictEqual(service.getLastSnapshot(), null, '17b token loss purges while the old request is unresolved');
    resolveRefresh({ status: 200, ok: true, body: { revision: 2, vehicles: ['LATE'] } });
    await pending;
    assert.strictEqual(service.getLastSnapshot(), null, '17c late old-token response remains inert');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED, '17d authority remains denied');
    console.log('PASS 17: token loss supersedes active snapshot loads');
  }

  // 18. Destroy or auth-generation replacement makes in-flight mutation
  //     success inert before caller-side render/retry logic can observe it.
  {
    let resolveMutation;
    let calls = 0;
    const client = { rpc: async () => {
      calls += 1;
      if (calls === 1) return { status: 200, ok: true, body: { revision: 1, vehicles: [] } };
      return new Promise(resolve => { resolveMutation = resolve; });
    } };
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } }, client,
      getAccessToken: () => 'tok', getRole: () => 'operator'
    });
    await service.loadSnapshot('initial');
    const pending = service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    service.destroy();
    resolveMutation({ status: 200, ok: true, body: { ok: true, booking: { id: 'PRIOR_AUTH' } } });
    const result = await pending;
    assert.strictEqual(result.ok, false, '18a late mutation is not reported successful');
    assert.strictEqual(result.error, 'destroyed', '18b destroyed authority is explicit');
    assert.strictEqual(service.getLastSnapshot(), null, '18c no late reconciliation can restore rows');
    assert.strictEqual(calls, 2, '18d no post-success reload is dispatched');
    console.log('PASS 18: in-flight mutation results are generation-bound and inert after teardown');
  }

  // 19. A live role/token refresh invalidates an in-flight operator mutation
  //     and establishes the new role only from a fresh snapshot.
  {
    let role = 'operator';
    let resolveMutation;
    let calls = 0;
    const client = { rpc: async () => {
      calls += 1;
      if (calls === 1) return { status: 200, ok: true, body: { revision: 1, vehicles: ['OPERATOR'] } };
      if (calls === 2) return new Promise(resolve => { resolveMutation = resolve; });
      return { status: 200, ok: true, body: { revision: 2, vehicles: ['VIEWER'] } };
    } };
    const service = createWorkshopDataService({
      config: { workshop: { sharedData: true } }, client,
      getAccessToken: () => 'tok', getRole: () => role
    });
    await service.loadSnapshot('initial');
    const pendingMutation = service.mutate('start_workshop_work', { p_booking_id: 'x', p_expected_version: 1 });
    role = 'viewer';
    await service.onTokenRefresh();
    resolveMutation({ status: 200, ok: true, body: { ok: true, booking: { id: 'OLD_ROLE' } } });
    const mutation = await pendingMutation;
    assert.strictEqual(mutation.error, 'authority_superseded', '19a prior-role mutation result is suppressed');
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY, '19b fresh role is read-only');
    assert.strictEqual(service.getLastSnapshot().vehicles[0], 'VIEWER', '19c only fresh-role rows remain');
    assert.strictEqual(service.getLastRevision(), 2, '19d prior revision authority is replaced');
    assert.strictEqual(calls, 3, '19e stale mutation success triggers no reconciliation request');
    console.log('PASS 19: live role refresh supersedes prior-role mutations and snapshots');
  }

  console.log('Workshop data service unit tests passed');
}

run().catch((err) => {
  console.error('Workshop data service unit tests FAILED:', err);
  process.exitCode = 1;
});
