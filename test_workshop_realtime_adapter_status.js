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

function timerHarness() {
  const pending = [];
  let nextId = 1;
  return {
    scheduleTimeout(fn, ms) {
      const id = nextId++;
      pending.push({ id, fn, ms });
      return id;
    },
    clearScheduledTimeout(id) {
      const index = pending.findIndex(timer => timer.id === id);
      if (index >= 0) pending.splice(index, 1);
    },
    count() { return pending.length; },
    delays() { return pending.map(timer => timer.ms); },
    flushOne() {
      assert(pending.length, 'expected one pending timer');
      pending.shift().fn();
    }
  };
}

function clientHarness(options = {}) {
  const records = [];
  const active = new Set();
  const client = {
    channel(name) {
      const record = {
        name,
        active: true,
        removeCalls: 0,
        status: null,
        change: null
      };
      const channel = {
        on(_kind, _spec, callback) {
          record.change = callback;
          return channel;
        },
        subscribe(callback) {
          record.status = callback;
          record.channel = channel;
          records.push(record);
          active.add(channel);
          return channel;
        }
      };
      return channel;
    },
    removeChannel(channel) {
      const record = records.find(item => item.channel === channel);
      if (record) {
        record.removeCalls += 1;
        record.active = false;
      }
      active.delete(channel);
      if (options.throwOnRemove) throw new Error('simulated remove failure');
    }
  };
  return { client, records, active };
}

function serviceHarness(options = {}) {
  return {
    reconnects: 0,
    revisions: [],
    onRevisionSignal(revision) { this.revisions.push(revision); },
    onReconnect() {
      this.reconnects += 1;
      if (options.throwOnReconnect === this.reconnects) throw new Error('simulated resync failure');
    }
  };
}

const adapterFactory = context => vm.runInNewContext(
  `(${extractFunction('createPdcSupabaseRealtimeSubscription')})`,
  context
);

function composedHarness(options = {}) {
  const transport = clientHarness(options);
  const timers = timerHarness();
  const service = serviceHarness(options);
  const statuses = [];
  const adapter = adapterFactory({ window: { PDC_SUPABASE: transport.client } });
  const manager = createWorkshopRealtimeManager({
    dataService: service,
    subscribe: handlers => adapter({}, handlers, { stageCode: options.stageCode || 'TINT' }),
    onStatusChange: status => statuses.push(status),
    scheduleTimeout: timers.scheduleTimeout,
    clearScheduledTimeout: timers.clearScheduledTimeout,
    initialBackoffMs: 1000,
    maxBackoffMs: 4000
  });
  manager.start();
  transport.records[0].status('SUBSCRIBED');
  return { ...transport, timers, service, statuses, manager };
}

function assertSingleFailure(status) {
  const h = composedHarness();
  const failed = h.records[0];
  failed.status(status);
  assert.strictEqual(h.manager.isSubscribed(), false, `${status}: manager inactive before retry`);
  assert.strictEqual(h.timers.count(), 1, `${status}: exactly one retry timer`);
  assert.deepStrictEqual(h.timers.delays(), [1000], `${status}: bounded initial backoff`);
  assert.strictEqual(failed.removeCalls, 1, `${status}: failed channel removed exactly once`);
  assert.strictEqual(h.active.size, 0, `${status}: no failed channel remains active`);
  return h;
}

function run() {
  const channelError = assertSingleFailure('CHANNEL_ERROR');
  assert.deepStrictEqual(
    {
      reconnects: channelError.service.reconnects,
      timers: channelError.timers.count(),
      removed: channelError.records[0].removeCalls,
      isSubscribed: channelError.manager.isSubscribed()
    },
    { reconnects: 1, timers: 1, removed: 1, isSubscribed: false },
    'independent CHANNEL_ERROR reproduction is repaired through the production adapter'
  );
  console.log('PASS 1: CHANNEL_ERROR cleans up and schedules one controlled retry');

  assertSingleFailure('TIMED_OUT');
  assertSingleFailure('CLOSED');
  console.log('PASS 2: TIMED_OUT and unexpected CLOSED use the lifecycle retry path');

  {
    const h = composedHarness();
    const failed = h.records[0];
    failed.status('CHANNEL_ERROR');
    failed.status('CLOSED');
    failed.status('CHANNEL_ERROR');
    assert.strictEqual(h.timers.count(), 1, 'error/closed burst cannot multiply timers');
    assert.strictEqual(failed.removeCalls, 1, 'error/closed burst cannot remove twice');
    console.log('PASS 3: CHANNEL_ERROR followed by CLOSED is idempotent');
  }

  {
    const h = assertSingleFailure('CHANNEL_ERROR');
    const failed = h.records[0];
    h.timers.flushOne();
    assert.strictEqual(h.records.length, 2, 'timer creates exactly one replacement subscription');
    h.records[1].status('SUBSCRIBED');
    assert.strictEqual(h.active.size, 1, 'only replacement channel is active');
    assert.strictEqual(h.service.reconnects, 2, 'replacement triggers one authoritative resync');
    assert.strictEqual(h.manager.isSubscribed(), true, 'manager healthy after replacement resync hand-off');
    failed.change({ new: { revision: 11 } });
    assert.deepStrictEqual(h.service.revisions, [], 'event from removed channel is ignored');
    h.records[1].change({ new: { revision: 12 } });
    assert.deepStrictEqual(h.service.revisions, [12], 'replacement event is delivered once');
    console.log('PASS 4: retry creates one replacement, resyncs once and rejects stale events');
  }

  {
    const h = composedHarness({ throwOnReconnect: 2 });
    h.records[0].status('TIMED_OUT');
    h.timers.flushOne();
    h.records[1].status('SUBSCRIBED');
    assert.strictEqual(h.records.length, 2, 'resync-failing replacement was attempted once');
    assert.strictEqual(h.records[1].removeCalls, 1, 'resync-failing channel is cleaned up');
    assert.strictEqual(h.manager.isSubscribed(), false, 'resync failure is never reported healthy');
    assert.strictEqual(h.timers.count(), 1, 'resync failure follows controlled retry policy');
    assert.deepStrictEqual(h.statuses, ['subscribed', 'reconnecting', 'reconnecting'], 'no premature second subscribed status');
    console.log('PASS 5: synchronous resync refusal remains inactive and retries safely');
  }

  {
    const h = composedHarness();
    const stopped = h.records[0];
    h.manager.stop();
    stopped.status('CLOSED');
    assert.strictEqual(stopped.removeCalls, 1, 'intentional stop removes channel exactly once');
    assert.strictEqual(h.timers.count(), 0, 'intentional stop/late CLOSED never reconnects');
    console.log('PASS 6: intentional shutdown suppresses late CLOSED reconnect');
  }

  {
    const h = assertSingleFailure('CHANNEL_ERROR');
    const old = h.records[0];
    h.manager.forceReconnect();
    assert.strictEqual(h.timers.count(), 0, 'online recovery clears pending offline retry');
    assert.strictEqual(h.records.length, 2, 'online recovery opens one replacement');
    h.records[1].status('SUBSCRIBED');
    old.status('TIMED_OUT');
    assert.strictEqual(h.timers.count(), 0, 'stale offline statuses cannot create a hot loop');
    assert.strictEqual(h.active.size, 1, 'online recovery retains only one active channel');
    console.log('PASS 7: offline/online recovery does not hot-loop');
  }

  {
    const h = assertSingleFailure('CHANNEL_ERROR');
    h.timers.flushOne();
    assert.strictEqual(h.manager.isSubscribed(), false, 'replacement remains connecting before SUBSCRIBED');
    h.records[1].status('CHANNEL_ERROR');
    assert.deepStrictEqual(h.timers.delays(), [2000], 'unconfirmed offline retries escalate backoff');
    assert.strictEqual(h.records[1].removeCalls, 1, 'unconfirmed failed replacement is removed');
    console.log('PASS 8: repeated offline failures escalate instead of resetting into a hot loop');
  }

  {
    const transport = clientHarness();
    const timersA = timerHarness();
    const timersB = timerHarness();
    const adapter = adapterFactory({ window: { PDC_SUPABASE: transport.client } });
    const serviceA = serviceHarness();
    const serviceB = serviceHarness();
    const managerA = createWorkshopRealtimeManager({
      dataService: serviceA,
      subscribe: handlers => adapter({}, handlers, { stageCode: 'TINT' }),
      scheduleTimeout: timersA.scheduleTimeout,
      clearScheduledTimeout: timersA.clearScheduledTimeout
    });
    const managerB = createWorkshopRealtimeManager({
      dataService: serviceB,
      subscribe: handlers => adapter({}, handlers, { stageCode: 'HOIST' }),
      scheduleTimeout: timersB.scheduleTimeout,
      clearScheduledTimeout: timersB.clearScheduledTimeout
    });
    managerA.start();
    managerB.start();
    transport.records[0].status('SUBSCRIBED');
    transport.records[1].status('SUBSCRIBED');
    transport.records[0].status('CHANNEL_ERROR');
    assert.strictEqual(transport.records[0].removeCalls, 1, 'failed resource A removed');
    assert.strictEqual(transport.records[1].removeCalls, 0, 'resource B not removed by A failure');
    assert.strictEqual(managerB.isSubscribed(), true, 'resource B remains subscribed');
    transport.records[1].change({ new: { revision: 21 } });
    assert.deepStrictEqual(serviceA.revisions, [], 'resource A receives no resource B event');
    assert.deepStrictEqual(serviceB.revisions, [21], 'resource B receives its own event');
    assert.strictEqual(timersA.count(), 1);
    assert.strictEqual(timersB.count(), 0);
    console.log('PASS 9: multiple scoped resources cannot cross-wire lifecycle state');
  }

  {
    const h = composedHarness();
    h.records[0].change({ new: { revision: 31 } });
    h.records[0].change({ new: { revision: 32 } });
    assert.deepStrictEqual(h.service.revisions, [31, 32], 'normal changes remain exactly-once and ordered');
    h.records[0].status('SUBSCRIBED');
    assert.strictEqual(h.service.reconnects, 1, 'duplicate SUBSCRIBED status cannot duplicate resync');
    console.log('PASS 10: back-to-back normal events and duplicate status remain exactly-once');
  }

  {
    const h = composedHarness({ throwOnRemove: true });
    h.records[0].status('CHANNEL_ERROR');
    assert.strictEqual(h.manager.isSubscribed(), false, 'throwing cleanup cannot leave subscribed=true');
    assert.strictEqual(h.timers.count(), 1, 'throwing cleanup cannot block controlled retry');
    console.log('PASS 11: cleanup failure still leaves inactive state and one retry');
  }

  {
    const timers = timerHarness();
    const service = serviceHarness();
    let cleanupCalls = 0;
    const manager = createWorkshopRealtimeManager({
      dataService: service,
      subscribe: handlers => {
        handlers.onError('CHANNEL_ERROR');
        return { unsubscribe() { cleanupCalls += 1; } };
      },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    manager.start();
    assert.strictEqual(cleanupCalls, 1, 'synchronously failed returned handle is disposed immediately');
    assert.strictEqual(manager.isSubscribed(), false);
    assert.strictEqual(timers.count(), 1);
    console.log('PASS 12: synchronous status failure cannot retain a failed channel handle');
  }

  {
    const diagnostics = [];
    let statusCallback = null;
    const channel = {
      on() { return channel; },
      subscribe(callback) { statusCallback = callback; return channel; }
    };
    const adapter = adapterFactory({ window: { PDC_SUPABASE: { channel: () => channel, removeChannel() {} } } });
    let lifecycleFailures = 0;
    adapter({}, {
      onStatus: status => diagnostics.push(status),
      onError: () => { lifecycleFailures += 1; },
      onClosed: () => { lifecycleFailures += 1; }
    }, { stageCode: 'TINT' });
    statusCallback('SUBSCRIBED');
    statusCallback('UNKNOWN_STATUS');
    assert.deepStrictEqual(diagnostics, ['SUBSCRIBED', 'UNKNOWN_STATUS'], 'diagnostic statuses remain observable');
    assert.strictEqual(lifecycleFailures, 0, 'success/unknown statuses are not treated as failures');
    console.log('PASS 13: success and unknown statuses remain diagnostic-only');
  }

  console.log('Workshop production-adapter Realtime status tests passed');
}

try {
  run();
} catch (error) {
  console.error('Workshop production-adapter Realtime status tests FAILED:', error);
  process.exitCode = 1;
}
