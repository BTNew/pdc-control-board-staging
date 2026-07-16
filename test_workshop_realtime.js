'use strict';

// Real (non-mocked) unit tests for workshop-realtime.js. Exercises the
// actual reconnect/backoff state machine, revision-signal forwarding, and
// clean start/stop lifecycle using a fake injected transport and fake
// timers -- no mocking of the module under test itself.

const assert = require('assert');
const { createWorkshopRealtimeManager } = require('./workshop-realtime.js');

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
    flushOne: () => {
      if (!timers.length) return false;
      const t = timers.shift();
      t.fn();
      return true;
    },
    pendingCount: () => timers.length,
    pendingDelays: () => timers.map((t) => t.ms)
  };
}

function fakeDataService() {
  const revisionSignals = [];
  const reconnects = [];
  return {
    revisionSignals,
    reconnects,
    onRevisionSignal: (rev) => revisionSignals.push(rev),
    onReconnect: () => reconnects.push(true)
  };
}

function run() {
  // 1. Successful subscribe: status goes 'subscribed', triggers one reconnect resync
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    const statuses = [];
    let handlersRef = null;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: (handlers) => { handlersRef = handlers; return () => {}; },
      onStatusChange: (s) => statuses.push(s),
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    manager.start();
    assert.strictEqual(manager.isSubscribed(), true, '1a subscribed after start');
    assert.deepStrictEqual(statuses, ['subscribed'], '1b status callback fired once');
    assert.strictEqual(ds.reconnects.length, 1, '1c initial subscribe triggers a resync fetch');
    console.log('PASS 1: successful subscribe reports status and triggers resync');
  }

  // 2. Change event forwards the revision to the data service
  {
    const ds = fakeDataService();
    let handlersRef = null;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: (handlers) => { handlersRef = handlers; return () => {}; }
    });
    manager.start();
    handlersRef.onChange({ revision: 42 });
    assert.deepStrictEqual(ds.revisionSignals, [42], '2a revision forwarded verbatim');
    handlersRef.onChange({ new: { revision: 43 } });
    assert.deepStrictEqual(ds.revisionSignals, [42, 43], '2b nested new.revision shape also supported');
    console.log('PASS 2: change events forward the revision number to the data service');
  }

  // 3. Repeated FAILED subscribe attempts escalate backoff (doubling); a
  //    successful resubscribe resets backoff (covered separately in test 5).
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    let attempt = 0;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: () => {
        attempt += 1;
        if (attempt <= 3) {
          throw new Error('simulated transport failure');
        }
        return () => {};
      },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout,
      initialBackoffMs: 1000,
      maxBackoffMs: 8000
    });
    manager.start();
    assert.strictEqual(attempt, 1, '3a first attempt made immediately, and failed');
    assert.deepStrictEqual(timers.pendingDelays(), [1000], '3b first retry scheduled at initial backoff');

    timers.flushOne();
    assert.strictEqual(attempt, 2, '3c second attempt made, also failed');
    assert.deepStrictEqual(timers.pendingDelays(), [2000], '3d second retry backoff doubles');

    timers.flushOne();
    assert.strictEqual(attempt, 3, '3e third attempt made, also failed');
    assert.deepStrictEqual(timers.pendingDelays(), [4000], '3f third retry backoff doubles again');

    timers.flushOne();
    assert.strictEqual(attempt, 4, '3g fourth attempt made and succeeds');
    assert.strictEqual(manager.isSubscribed(), true, '3h finally subscribed');
    assert.strictEqual(timers.pendingCount(), 0, '3i no further retry scheduled once subscribed');

    console.log('PASS 3: repeated failed subscribe attempts escalate backoff via doubling');
  }

  // 4. Backoff is capped at maxBackoffMs across repeated failures
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: () => { throw new Error('always fails'); },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout,
      initialBackoffMs: 1000,
      maxBackoffMs: 3000
    });
    manager.start();
    assert.deepStrictEqual(timers.pendingDelays(), [1000]);
    timers.flushOne();
    assert.deepStrictEqual(timers.pendingDelays(), [2000]);
    timers.flushOne();
    assert.deepStrictEqual(timers.pendingDelays(), [3000], '4a capped at maxBackoffMs, not 4000');
    timers.flushOne();
    assert.deepStrictEqual(timers.pendingDelays(), [3000], '4b stays capped on further failures');
    console.log('PASS 4: exponential backoff is capped at maxBackoffMs');
  }

  // 5. Successful resubscribe resets backoff back to initial
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    let handlersRef = null;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: (handlers) => { handlersRef = handlers; return () => {}; },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout,
      initialBackoffMs: 1000,
      maxBackoffMs: 8000
    });
    manager.start();
    handlersRef.onError();
    timers.flushOne(); // backoff was 1000, now resubscribed successfully
    handlersRef.onError(); // should restart from 1000, not continue doubling from where it left off
    assert.deepStrictEqual(timers.pendingDelays(), [1000], '5a backoff reset to initial after a successful reconnect');
    console.log('PASS 5: successful resubscribe resets backoff to initial value');
  }

  // 6. Closed channel also triggers reconnect (same as error)
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    let handlersRef = null;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: (handlers) => { handlersRef = handlers; return () => {}; },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    manager.start();
    handlersRef.onClosed();
    assert.strictEqual(manager.isSubscribed(), false, '6a unsubscribed on closed');
    assert.strictEqual(timers.pendingCount(), 1, '6b reconnect scheduled on closed');
    console.log('PASS 6: closed channel triggers the same reconnect path as error');
  }

  // 7. stop() unsubscribes cleanly, cancels pending reconnect, and blocks further reconnect attempts
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    let unsubscribeCalls = 0;
    let handlersRef = null;
    let subscribeCount = 0;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: (handlers) => {
        handlersRef = handlers;
        subscribeCount += 1;
        return () => { unsubscribeCalls += 1; };
      },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout
    });
    manager.start();
    handlersRef.onError();
    assert.strictEqual(timers.pendingCount(), 1, '7a reconnect pending before stop');
    manager.stop();
    assert.strictEqual(unsubscribeCalls, 1, '7b unsubscribe function invoked on stop');
    assert.strictEqual(timers.pendingCount(), 0, '7c pending reconnect timer cancelled on stop');
    const subscribeCountAtStop = subscribeCount;
    // Any late-firing handler after stop must not cause a new subscription.
    handlersRef.onError();
    assert.strictEqual(subscribeCount, subscribeCountAtStop, '7d no resubscribe after stop even if a stale handler fires');
    console.log('PASS 7: stop() unsubscribes cleanly and blocks further reconnects');
  }

  // 8. forceReconnect() resets backoff and reopens immediately, bypassing any pending timer
  {
    const ds = fakeDataService();
    const timers = makeTimerHarness();
    let handlersRef = null;
    let subscribeCount = 0;
    const manager = createWorkshopRealtimeManager({
      dataService: ds,
      subscribe: (handlers) => { handlersRef = handlers; subscribeCount += 1; return () => {}; },
      scheduleTimeout: timers.scheduleTimeout,
      clearScheduledTimeout: timers.clearScheduledTimeout,
      initialBackoffMs: 1000,
      maxBackoffMs: 8000
    });
    manager.start();
    handlersRef.onError();
    handlersRef.onError(); // still same pending timer semantics
    assert.strictEqual(timers.pendingCount(), 1, '8a exactly one pending reconnect timer');
    manager.forceReconnect();
    assert.strictEqual(timers.pendingCount(), 0, '8b pending timer cleared by forceReconnect');
    assert.strictEqual(manager.isSubscribed(), true, '8c immediately resubscribed');
    handlersRef.onError();
    assert.deepStrictEqual(timers.pendingDelays(), [1000], '8d backoff restarted from initial after forceReconnect');
    console.log('PASS 8: forceReconnect bypasses backoff and resubscribes immediately');
  }

  console.log('Workshop realtime manager unit tests passed');
}

try {
  run();
} catch (err) {
  console.error('Workshop realtime manager unit tests FAILED:', err);
  process.exitCode = 1;
}
