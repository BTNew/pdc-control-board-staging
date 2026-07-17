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
 *     the actual realtime subscription and returns an unsubscribe
 *     function. handlers = { onChange(newRow), onError(), onClosed() }.
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

  let unsubscribeFn = null;
  let reconnectTimer = null;
  let currentBackoffMs = initialBackoffMs;
  let destroyed = false;
  let subscribed = false;

  function handleChange(row) {
    const revision = row && (row.revision != null ? row.revision : (row.new && row.new.revision));
    dataService.onRevisionSignal(revision);
  }

  function scheduleReconnect() {
    if (destroyed) return;
    subscribed = false;
    onStatusChange('reconnecting');
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

  function openSubscription() {
    if (destroyed) return;
    try {
      unsubscribeFn = subscribeFn({
        onChange: handleChange,
        onError: handleError,
        onClosed: handleClosed
      });
      subscribed = true;
      currentBackoffMs = initialBackoffMs;
      onStatusChange('subscribed');
      // A fresh subscription may have missed events while we were
      // reconnecting; always resynchronise once on (re)connect.
      dataService.onReconnect();
    } catch (_err) {
      scheduleReconnect();
    }
  }

  function start() {
    if (destroyed) return;
    openSubscription();
  }

  function isSubscribed() {
    return subscribed;
  }

  function stop() {
    destroyed = true;
    subscribed = false;
    if (reconnectTimer) {
      clearScheduledTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    if (typeof unsubscribeFn === 'function') {
      try {
        unsubscribeFn();
      } catch (_err) {
        // best-effort cleanup; nothing else to do on logout teardown
      }
      unsubscribeFn = null;
    }
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
