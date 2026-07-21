'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { createWorkshopRealtimeManager } = require('./workshop-realtime.js');

const appSource = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

function extractFunction(name) {
  const start = appSource.indexOf(`function ${name}(`);
  assert(start >= 0, `missing ${name}`);
  const open = appSource.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < appSource.length; i += 1) {
    if (appSource[i] === '{') depth += 1;
    if (appSource[i] === '}') depth -= 1;
    if (depth === 0) return appSource.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

function dataService(label = '') {
  const revisions = [];
  return {
    label,
    revisions,
    reconnects: 0,
    destroyed: false,
    onRevisionSignal(revision) { revisions.push(revision); },
    onReconnect() { this.reconnects += 1; },
    destroy() { this.destroyed = true; }
  };
}

function managerFor(cleanup, options = {}) {
  const service = options.service || dataService();
  const statuses = [];
  const manager = createWorkshopRealtimeManager({
    dataService: service,
    subscribe: options.subscribe || (() => cleanup),
    onStatusChange: status => statuses.push(status),
    scheduleTimeout: options.scheduleTimeout,
    clearScheduledTimeout: options.clearScheduledTimeout
  });
  manager.start();
  return { manager, service, statuses };
}

function testSupportedCleanupContracts() {
  let direct = 0;
  const directCase = managerFor(() => { direct += 1; });
  directCase.manager.stop();
  directCase.manager.stop();
  assert.strictEqual(direct, 1, 'direct cleanup function runs exactly once');

  let unsubscribed = 0;
  const objectCase = managerFor({ unsubscribe() { unsubscribed += 1; } });
  objectCase.manager.stop();
  objectCase.manager.stop();
  assert.strictEqual(unsubscribed, 1, 'unsubscribe object runs exactly once');

  let destroyed = 0;
  const destroyCase = managerFor({ destroy() { destroyed += 1; } });
  destroyCase.manager.stop();
  assert.strictEqual(destroyed, 1, 'codebase destroy disposal contract is supported');

  const missingCase = managerFor(null);
  assert.doesNotThrow(() => missingCase.manager.stop(), 'missing cleanup is safe');

  let timerCleared = 0;
  let throwingHandlers = null;
  const throwingCase = managerFor(null, {
    subscribe: handlers => {
      throwingHandlers = handlers;
      return { unsubscribe() { throw new Error('cleanup failed'); } };
    },
    scheduleTimeout: () => 17,
    clearScheduledTimeout: () => { timerCleared += 1; }
  });
  throwingHandlers.onError();
  assert.doesNotThrow(() => throwingCase.manager.stop(), 'cleanup exception is contained');
  assert.strictEqual(throwingCase.manager.isSubscribed(), false, 'throwing cleanup still marks manager stopped');
  assert.deepStrictEqual(throwingCase.statuses, ['subscribed', 'reconnecting', 'closed'], 'throwing cleanup does not prevent remaining close work');
  assert.strictEqual(timerCleared, 1, 'throwing cleanup does not prevent pending reconnect timer cleanup');

  console.log('PASS 1: direct, unsubscribe, destroy, missing, throwing and repeated cleanup contracts');
}

function createComposedHarness() {
  const channels = new Set();
  const records = [];
  const client = {
    channel(name) {
      const record = { name, active: true, change: null, status: null };
      const channel = {
        on(_kind, _spec, callback) { record.change = callback; return channel; },
        subscribe(callback) { record.status = callback; channels.add(channel); records.push(record); return channel; }
      };
      record.channel = channel;
      return channel;
    },
    removeChannel(channel) {
      channels.delete(channel);
      const record = records.find(item => item.channel === channel);
      if (record) record.active = false;
    }
  };
  const adapter = vm.runInNewContext(`(${extractFunction('createPdcSupabaseRealtimeSubscription')})`, {
    window: { PDC_SUPABASE: client }
  });

  let current = null;
  let route = 'control-board';
  const services = [];

  function leave() {
    if (!current) return;
    current.manager.stop();
    current.service.destroy();
    current = null;
  }

  function open(stage, reason = 'route') {
    leave();
    route = stage;
    const service = dataService(`${stage}:${reason}`);
    const manager = createWorkshopRealtimeManager({
      dataService: service,
      subscribe: handlers => adapter({}, handlers, { stageCode: stage })
    });
    manager.start();
    current = { stage, service, manager, record: records.at(-1) };
    services.push(service);
    assert.strictEqual(channels.size, 1, `exactly one channel after opening ${stage}`);
    return current;
  }

  function controlBoard() {
    leave();
    route = 'control-board';
    assert.strictEqual(channels.size, 0, 'zero channels on Control Board');
  }

  function authRefresh() {
    if (route === 'control-board') return;
    open(route, 'auth-refresh');
  }

  return { channels, records, services, open, controlBoard, authRefresh, get current() { return current; } };
}

function testRealAdapterRouteLifecycle() {
  const h = createComposedHarness();

  const a = h.open('TINT', 'direct-refresh');
  a.record.change({ new: { revision: 1 } });
  assert.deepStrictEqual(a.service.revisions, [1], 'direct station refresh receives its scoped update');

  const b = h.open('HOIST', 'route-a-to-b');
  assert.strictEqual(a.service.destroyed, true, 'route A service destroyed on A to B');
  assert.strictEqual(a.record.active, false, 'route A channel removed on A to B');
  a.record.change({ new: { revision: 2 } });
  assert.deepStrictEqual(a.service.revisions, [1], 'stale route A callback is inert');
  b.record.change({ new: { revision: 3 } });
  assert.deepStrictEqual(b.service.revisions, [3], 'route B receives only route B update');

  h.controlBoard();
  assert.strictEqual(b.service.destroyed, true, 'route B service destroyed on Control Board');
  b.record.change({ new: { revision: 4 } });
  assert.deepStrictEqual(b.service.revisions, [3], 'Control Board receives no stale planner delivery');

  const back = h.open('TINT', 'browser-back');
  const forward = h.open('HOIST', 'browser-forward');
  assert.strictEqual(back.record.active, false, 'browser Forward releases Back-route channel');
  const refreshed = h.open('HOIST', 'same-station-reopen');
  assert.strictEqual(forward.record.active, false, 'reopening same station releases prior channel');

  const beforeAuth = refreshed;
  h.authRefresh();
  assert.strictEqual(beforeAuth.record.active, false, 'auth refresh releases prior planner channel');
  beforeAuth.record.change({ new: { revision: 9 } });
  assert.deepStrictEqual(beforeAuth.service.revisions, [], 'auth refresh leaves old callback inert');

  for (let i = 0; i < 5; i += 1) {
    h.open(i % 2 ? 'TINT' : 'HOIST', 'repeated-route-change');
  }
  assert.strictEqual(h.channels.size, 1, 'repeated route changes never grow subscriptions');
  const active = h.current;
  const staleRecords = h.records.filter(record => record !== active.record);
  const staleServices = h.services.filter(service => service !== active.service);
  const revisionCountsBeforeStaleCallbacks = staleServices.map(service => service.revisions.length);
  staleRecords.forEach((record, index) => record.change({ new: { revision: 100 + index } }));
  assert.deepStrictEqual(
    staleServices.map(service => service.revisions.length),
    revisionCountsBeforeStaleCallbacks,
    'no duplicate stale callback delivery after repeated routes'
  );

  h.controlBoard();
  assert.strictEqual(h.channels.size, 0, 'all channels removed after final teardown');
  h.authRefresh();
  assert.strictEqual(h.channels.size, 0, 'auth refresh on Control Board cannot recreate a background planner');

  console.log('PASS 2: real adapter route, auth, history, refresh, reopen and stale-callback lifecycle');
}

function testAppTeardownReleasesRemainingResources() {
  let serviceDestroyed = 0;
  let rootCleared = 0;
  const context = {
    window: {
      __workshopRealtimeManager: { stop() { throw new Error('transport stop failed'); } },
      __workshopDataService: { destroy() { serviceDestroyed += 1; } },
      __workshopSharedActions: {},
      __activeWorkshopPlannerStage: 'TINT'
    },
    document: {
      getElementById() { return { replaceChildren() { rootCleared += 1; } }; }
    }
  };
  const teardown = vm.runInNewContext(`(${extractFunction('teardownWorkshopPlannerScope')})`, context);
  assert.doesNotThrow(() => teardown(), 'one cleanup exception must not block remaining route resources');
  assert.strictEqual(serviceDestroyed, 1, 'station-scoped data service still destroyed');
  assert.strictEqual(rootCleared, 1, 'planner DOM still cleared');
  assert.strictEqual(context.window.__workshopRealtimeManager, null);
  assert.strictEqual(context.window.__workshopDataService, null);
  assert.strictEqual(context.window.__activeWorkshopPlannerStage, '');
  console.log('PASS 3: app teardown releases service, guards and DOM despite cleanup exception');
}

testSupportedCleanupContracts();
testRealAdapterRouteLifecycle();
testAppTeardownReleasesRemainingResources();
console.log('station_planner_realtime_lifecycle: PASS');
