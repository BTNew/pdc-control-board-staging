'use strict';

/*
 * Workshop shared data service.
 *
 * This module is the ONLY place the Workshop Planner is allowed to talk to
 * Supabase for operational (shared) workshop data. It intentionally has NO
 * dependency on workshop-planner.js rendering/interaction code so it can be
 * unit tested in isolation and so the planner runtime is not modified by
 * introducing it.
 *
 * Shared mode is explicit opt-in: window.PDC_SUPABASE_CONFIG.workshop &&
 * window.PDC_SUPABASE_CONFIG.workshop.sharedData === true. When shared mode
 * is not enabled, or initialization/auth/RPC checks fail, this service
 * fails closed: it exposes no writable operational path and reports a
 * clear connection state instead of silently falling back to localStorage.
 *
 * Connection states (see WORKSHOP_CONNECTION_STATE):
 *   - 'disabled'            shared mode not configured; planner stays on
 *                            existing local behaviour untouched by this file
 *   - 'connecting'           initial snapshot/auth in flight
 *   - 'connected_editable'   authenticated with operator/administrator role
 *   - 'connected_read_only'  authenticated but viewer role, or write attempt
 *                            blocked by role
 *   - 'reconnecting'         realtime/network recovery in progress
 *   - 'offline_read_only'    network/realtime unavailable; last known
 *                            snapshot retained read-only
 *   - 'incompatible'         backend contract missing (RPCs/tables absent)
 */

const WORKSHOP_CONNECTION_STATE = Object.freeze({
  DISABLED: 'disabled',
  CONNECTING: 'connecting',
  CONNECTED_EDITABLE: 'connected_editable',
  CONNECTED_READ_ONLY: 'connected_read_only',
  RECONNECTING: 'reconnecting',
  OFFLINE_READ_ONLY: 'offline_read_only',
  INCOMPATIBLE: 'incompatible'
});

const WORKSHOP_MUTATION_RPCS = Object.freeze([
  'schedule_vehicle_work',
  'move_workshop_booking',
  'resize_workshop_booking',
  'change_booking_bay',
  'assign_booking_technician',
  'start_workshop_work',
  'stop_workshop_work',
  'resume_workshop_work',
  'complete_workshop_work',
  'return_completed_work',
  'return_work_to_queue',
  'cancel_workshop_booking',
  'restore_workshop_booking',
  'approve_parts_incomplete_override'
]);

// Every RPC above requires exactly one non-null expected-version parameter.
// schedule_vehicle_work and approve_parts_incomplete_override key off the
// vehicle's version instead of a booking version; all others key off the
// booking version.
const WORKSHOP_MUTATION_VERSION_PARAM = Object.freeze({
  schedule_vehicle_work: 'p_vehicle_expected_version',
  move_workshop_booking: 'p_expected_version',
  resize_workshop_booking: 'p_expected_version',
  change_booking_bay: 'p_expected_version',
  assign_booking_technician: 'p_expected_version',
  start_workshop_work: 'p_expected_version',
  stop_workshop_work: 'p_expected_version',
  resume_workshop_work: 'p_expected_version',
  complete_workshop_work: 'p_expected_version',
  return_completed_work: 'p_expected_version',
  return_work_to_queue: 'p_expected_version',
  cancel_workshop_booking: 'p_expected_version',
  restore_workshop_booking: 'p_expected_version',
  approve_parts_incomplete_override: 'p_vehicle_expected_version'
});

function workshopSharedModeEnabled(config) {
  return !!(config && config.workshop && config.workshop.sharedData === true);
}

/**
 * Minimal fetch-based Supabase REST/RPC client. Kept dependency-free so this
 * file can run under Node for unit tests and in the browser without a
 * bundler. Not exported as a class instance globally; callers construct
 * their own for testability.
 */
function createWorkshopSupabaseClient(config, fetchImpl) {
  const url = config.url;
  const key = config.publishableKey;
  const fetchFn = fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  if (!fetchFn) {
    throw new Error('workshop-data-service: no fetch implementation available');
  }

  function headers(accessToken) {
    return {
      apikey: key,
      Authorization: `Bearer ${accessToken || key}`,
      'Content-Type': 'application/json'
    };
  }

  async function rpc(accessToken, name, params) {
    const res = await fetchFn(`${url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: headers(accessToken),
      body: JSON.stringify(params || {})
    });
    let body = null;
    try {
      body = await res.json();
    } catch (_err) {
      body = null;
    }
    return { status: res.status, ok: res.ok, body };
  }

  return { rpc };
}

/**
 * WorkshopDataService owns: opt-in gating, snapshot load, RPC mutation
 * dispatch with mandatory non-null version, connection-state tracking, and
 * revision-driven resynchronisation scheduling (debounced). It does not
 * touch the DOM and does not import workshop-planner.js.
 */
function createWorkshopDataService(options) {
  const config = options.config || null;
  const client = options.client; // { rpc(accessToken, name, params) }
  const getAccessToken = options.getAccessToken || (() => null);
  const getRole = options.getRole || (() => null); // 'viewer' | 'operator' | 'administrator' | null
  const onStateChange = options.onStateChange || (() => {});
  const onSnapshot = options.onSnapshot || (() => {});
  const debounceMs = typeof options.debounceMs === 'number' ? options.debounceMs : 250;
  const scheduleTimeout = options.scheduleTimeout || ((fn, ms) => setTimeout(fn, ms));
  const clearScheduledTimeout = options.clearScheduledTimeout || clearTimeout;

  const enabled = workshopSharedModeEnabled(config);

  let state = enabled ? WORKSHOP_CONNECTION_STATE.CONNECTING : WORKSHOP_CONNECTION_STATE.DISABLED;
  let lastSnapshot = null;
  let lastRevision = null;
  let pendingReloadTimer = null;
  let reloadInFlight = false;
  let trailingReloadRequested = false;

  function setState(next) {
    if (state === next) return;
    state = next;
    onStateChange(state);
  }

  function isEditable() {
    return state === WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE;
  }

  async function loadSnapshot(reason) {
    if (!enabled) {
      setState(WORKSHOP_CONNECTION_STATE.DISABLED);
      return null;
    }
    if (reloadInFlight) {
      trailingReloadRequested = true;
      return lastSnapshot;
    }
    reloadInFlight = true;
    try {
      const token = getAccessToken();
      const result = await client.rpc(token, 'get_workshop_snapshot', {});
      if (!result.ok) {
        if (result.status === 404) {
          setState(WORKSHOP_CONNECTION_STATE.INCOMPATIBLE);
        } else if (result.status === 401 || result.status === 403) {
          setState(WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY);
        } else {
          setState(WORKSHOP_CONNECTION_STATE.OFFLINE_READ_ONLY);
        }
        return lastSnapshot;
      }
      lastSnapshot = result.body;
      lastRevision = result.body && result.body.revision;
      const role = getRole();
      setState(role === 'operator' || role === 'administrator'
        ? WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE
        : WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY);
      onSnapshot(lastSnapshot, reason || 'load');
      return lastSnapshot;
    } catch (_err) {
      setState(WORKSHOP_CONNECTION_STATE.OFFLINE_READ_ONLY);
      return lastSnapshot;
    } finally {
      reloadInFlight = false;
      if (trailingReloadRequested) {
        trailingReloadRequested = false;
        // A newer change arrived while we were mid-fetch; reload again so we
        // never settle on a stale intermediate snapshot.
        await loadSnapshot('trailing');
      }
    }
  }

  function scheduleSnapshotReload(reason) {
    if (!enabled) return;
    if (pendingReloadTimer) {
      clearScheduledTimeout(pendingReloadTimer);
    }
    pendingReloadTimer = scheduleTimeout(() => {
      pendingReloadTimer = null;
      loadSnapshot(reason);
    }, debounceMs);
  }

  function onRevisionSignal(newRevision) {
    if (newRevision != null && newRevision === lastRevision) {
      return; // duplicate/no-op signal; debounce discards it safely
    }
    scheduleSnapshotReload('revision_changed');
  }

  function onReconnect() {
    setState(WORKSHOP_CONNECTION_STATE.RECONNECTING);
    loadSnapshot('reconnect');
  }

  function onVisibilityReturn() {
    if (!enabled) return;
    loadSnapshot('visibility_return');
  }

  function onTokenRefresh() {
    if (!enabled) return;
    loadSnapshot('token_refresh');
  }

  async function mutate(rpcName, params) {
    if (!WORKSHOP_MUTATION_RPCS.includes(rpcName)) {
      throw new Error(`workshop-data-service: unknown mutation RPC ${rpcName}`);
    }
    if (!enabled) {
      throw new Error('workshop-data-service: shared mode is not enabled; no writable operational path exists');
    }
    if (!isEditable()) {
      return { ok: false, error: 'not_editable', state };
    }
    // Every mutation requires exactly one non-null expected-version param.
    // Check the specific required key for this RPC (not just "any key that
    // happens to be present") so an entirely missing parameter is rejected
    // exactly the same as an explicit null.
    const versionKey = WORKSHOP_MUTATION_VERSION_PARAM[rpcName];
    if (versionKey && (params == null || params[versionKey] === null || params[versionKey] === undefined)) {
      return { ok: false, error: 'missing_expected_version' };
    }

    const token = getAccessToken();
    const result = await client.rpc(token, rpcName, params);
    if (!result.ok) {
      if (result.status === 401 || result.status === 403) {
        setState(WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY);
      }
      return { ok: false, error: 'request_failed', status: result.status, body: result.body };
    }
    const body = result.body || {};
    if (body.ok === false && body.error === 'version_conflict') {
      // Never display an unsaved move as successful: force a fresh
      // authoritative snapshot so the caller reconciles from truth.
      loadSnapshot('rejected_stale_mutation');
      return body;
    }
    if (body.ok === true) {
      // Successful mutation: reconcile from the confirmed result rather
      // than trusting an optimistic local guess.
      loadSnapshot('successful_mutation');
    }
    return body;
  }

  function destroy() {
    if (pendingReloadTimer) {
      clearScheduledTimeout(pendingReloadTimer);
      pendingReloadTimer = null;
    }
  }

  return {
    isEnabled: () => enabled,
    getState: () => state,
    getLastSnapshot: () => lastSnapshot,
    getLastRevision: () => lastRevision,
    loadSnapshot,
    onRevisionSignal,
    onReconnect,
    onVisibilityReturn,
    onTokenRefresh,
    mutate,
    destroy
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    WORKSHOP_CONNECTION_STATE,
    WORKSHOP_MUTATION_RPCS,
    WORKSHOP_MUTATION_VERSION_PARAM,
    workshopSharedModeEnabled,
    createWorkshopSupabaseClient,
    createWorkshopDataService
  };
}
if (typeof window !== 'undefined') {
  window.WORKSHOP_CONNECTION_STATE = WORKSHOP_CONNECTION_STATE;
  window.WORKSHOP_MUTATION_RPCS = WORKSHOP_MUTATION_RPCS;
  window.WORKSHOP_MUTATION_VERSION_PARAM = WORKSHOP_MUTATION_VERSION_PARAM;
  window.workshopSharedModeEnabled = workshopSharedModeEnabled;
  window.createWorkshopSupabaseClient = createWorkshopSupabaseClient;
  window.createWorkshopDataService = createWorkshopDataService;
}
