'use strict';

/*
 * Workshop realtime manager.
 *
 * Wraps a Supabase Realtime channel subscription to the workshop_revision
 * table (see migration 009) and turns row-change events into calls on a
 * WorkshopDataService instance. This file has no DOM dependency and does
 * not import workshop-planner.js or workshop-data-service.js directly --
 * callers wire the two together so each stays independently testable.
 *
 * Design goals (see PROJECT_BRIEF / migration plan "realtime requirements"):
 *   - never rely on receiving every individual row event in perfect order;
 *     every event, in whatever order, just triggers "go fetch a fresh
 *     authoritative snapshot" via the data service's own debounce
 *   - subscribe once per login session; unsubscribe cleanly on logout
 *   - detect a revision gap (event fires but socket dropped events in
 *     between) by comparing to the data service's own lastRevision, but
 *     since the data service always re-fetches the *complete* snapshot on
 *     any signal, gap detection reduces to "always safe to just refetch"
 *   - recover automatically on: channel error, channel closed, browser
 *     coming back online, and (via caller) visibility return / token
 *     refresh, which are wired directly to the data service instead
 */

const WORKSHOP_REALTIME_CHANNEL_NAME = 'workshop-revision-changes';

/**
 * createWorkshopRealtimeManager(options)
 *
 * options:
 *   - dataService: an object exposing onRevisionSignal(revision) and
 *     onReconnect() (matches createWorkshopDataService's public API)
 *   - subscribe(handlers): required. Caller-provided function that opens
 *     the actual realtime subscription and returns either a direct cleanup
 *     function or an object exposing unsubscribe() / destroy(). handlers =
 *     { onChange(newRow), onSubscribed(), onError(), onClosed() }. Adapters
 *     that return { requiresSubscribedStatus: true } are not reported healthy
 *     until onSubscribed() arrives; simple injected transports retain the
 *     existing synchronous-success contract.
 *     Kept as an injected function (rather than importing the Supabase JS
 *     client directly) so this module has zero hard dependency on the
 *     Supabase SDK and can be unit tested with a fake transport.
 *   - onStatusChange(status): optional callback with 'subscribed' |
 *     'reconnecting' | 'closed'.
 *   - maxBackoffMs / initialBackoffMs: reconnect backoff tuning.
 *   - scheduleTimeout/clearScheduledTimeout: same injectable-timer pattern
 *     as workshop-data-service.js, for deterministic tests.
 */
function createWorkshopRealtimeManager(options) {
  const dataService = options.dataService;
  const subscribeFn = options.subscribe;
  const onStatusChange = options.onStatusChange || (() => {});
  const initialBackoffMs = typeof options.initialBackoffMs === 'number' ? options.initialBackoffMs : 1000;
  const maxBackoffMs = typeof options.maxBackoffMs === 'number' ? options.maxBackoffMs : 30000;
  const scheduleTimeout = options.scheduleTimeout || ((fn, ms) => setTimeout(fn, ms));
  const clearScheduledTimeout = options.clearScheduledTimeout || clearTimeout;

  let subscriptionCleanup = null;
  let subscriptionGeneration = 0;
  let reconnectTimer = null;
  let currentBackoffMs = initialBackoffMs;
  let destroyed = false;
  let subscribed = false;
  let connecting = false;
  let readyGeneration = 0;

  function handleChange(row) {
    if (destroyed || !subscribed) return;
    const revision = row && (row.revision != null ? row.revision : (row.new && row.new.revision));
    dataService.onRevisionSignal(revision);
  }

  function disposeSubscription(cleanup) {
    if (!cleanup) return;
    try {
      if (typeof cleanup === 'function') {
        cleanup();
      } else if (typeof cleanup.unsubscribe === 'function') {
        cleanup.unsubscribe();
      } else if (typeof cleanup.destroy === 'function') {
        // destroy() is the other disposal contract used by scoped services
        // in this codebase; accept it for injected subscription adapters too.
        cleanup.destroy();
      }
    } catch (_err) {
      // Best effort: references and generations were invalidated before the
      // adapter was called, so a throwing transport cannot retain callbacks
      // or prevent timers / sibling route resources from being released.
    }
  }

  function releaseSubscription() {
    const cleanup = subscriptionCleanup;
    subscriptionCleanup = null;
    subscriptionGeneration += 1;
    disposeSubscription(cleanup);
  }

  function scheduleReconnect() {
    if (destroyed) return;
    subscribed = false;
    connecting = false;
    releaseSubscription();
    onStatusChange('reconnecting');
    // Status observers are external code and may synchronously tear down the
    // owning route/session. Do not leave a retry timer behind after stop().
    if (destroyed) return;
    if (reconnectTimer) clearScheduledTimeout(reconnectTimer);
    reconnectTimer = scheduleTimeout(() => {
      reconnectTimer = null;
      currentBackoffMs = Math.min(maxBackoffMs, currentBackoffMs * 2);
      openSubscription();
    }, currentBackoffMs);
  }

  function handleError() {
    scheduleReconnect();
  }

  function handleClosed() {
    scheduleReconnect();
  }

  function markSubscriptionReady(generation) {
    if (destroyed || generation !== subscriptionGeneration || readyGeneration === generation) return;
    readyGeneration = generation;
    try {
      // A fresh subscription may have missed events while disconnected.
      // Complete the authoritative resynchronisation hand-off before
      // reporting healthy or resetting backoff.
      dataService.onReconnect();
      // The resync hand-off is external code. It can synchronously stop this
      // manager or replace the subscription, so revalidate ownership before
      // committing healthy state.
      if (destroyed || generation !== subscriptionGeneration) return;
      connecting = false;
      subscribed = true;
      currentBackoffMs = initialBackoffMs;
      onStatusChange('subscribed');
    } catch (_err) {
      scheduleReconnect();
    }
  }

  function openSubscription() {
    if (destroyed) return;
    // A healthy channel remains unavailable until its replacement has emitted
    // SUBSCRIBED and completed authoritative resynchronisation. Clear the old
    // readiness flag before releasing it so forceReconnect() cannot leak
    // pre-readiness events from the replacement.
    subscribed = false;
    connecting = true;
    releaseSubscription();
    const generation = ++subscriptionGeneration;
    try {
      const cleanup = subscribeFn({
        onChange: row => {
          if (generation !== subscriptionGeneration) return;
          handleChange(row);
        },
        onError: () => {
          if (generation !== subscriptionGeneration) return;
          handleError();
        },
        onSubscribed: () => {
          if (generation !== subscriptionGeneration) return;
          markSubscriptionReady(generation);
        },
        onClosed: () => {
          if (generation !== subscriptionGeneration) return;
          handleClosed();
        }
      });
      // A status callback may run synchronously inside subscribeFn(). If it
      // already failed or stopped this generation, dispose the just-returned
      // handle immediately rather than retaining a failed live channel until
      // the retry timer fires.
      if (destroyed || generation !== subscriptionGeneration) {
        disposeSubscription(cleanup);
        return;
      }
      subscriptionCleanup = cleanup;
      if (!subscriptionCleanup || subscriptionCleanup.requiresSubscribedStatus !== true) {
        markSubscriptionReady(generation);
      }
    } catch (_err) {
      scheduleReconnect();
    }
  }

  function start() {
    if (destroyed || subscribed || connecting) return;
    openSubscription();
  }

  function isSubscribed() {
    return subscribed;
  }

  function stop() {
    if (destroyed) return;
    destroyed = true;
    subscribed = false;
    connecting = false;
    if (reconnectTimer) {
      clearScheduledTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    releaseSubscription();
    onStatusChange('closed');
  }

  return {
    start,
    stop,
    isSubscribed,
    // Exposed for the browser network-recovery listener (window online
    // event) so callers do not need to reach into module internals.
    forceReconnect: () => {
      if (reconnectTimer) clearScheduledTimeout(reconnectTimer);
      reconnectTimer = null;
      currentBackoffMs = initialBackoffMs;
      openSubscription();
    }
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { WORKSHOP_REALTIME_CHANNEL_NAME, createWorkshopRealtimeManager };
}
if (typeof window !== 'undefined') {
  window.WORKSHOP_REALTIME_CHANNEL_NAME = WORKSHOP_REALTIME_CHANNEL_NAME;
  window.createWorkshopRealtimeManager = createWorkshopRealtimeManager;
}
