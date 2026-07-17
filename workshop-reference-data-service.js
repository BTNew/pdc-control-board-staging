'use strict';

/*
 * Workshop reference/configuration data service (Stage 2A).
 *
 * This is the ONLY place the frontend is allowed to read or write shared
 * workshop lookup/configuration data: mechanics/technicians, salespeople,
 * sublet providers, workshop bays, and workshop configuration (operating
 * hours/days, minimum booking duration, closures). It has no dependency on
 * app.js or workshop-planner.js rendering code so it can be unit tested in
 * isolation, mirroring workshop-data-service.js's existing pattern for the
 * workshop planner's operational (booking) data.
 *
 * Unlike workshop-data-service.js's booking data (which stays behind an
 * explicit shared-mode opt-in flag while the legacy local-plan fallback is
 * retired in a later stage), this service is NOT behind a feature flag.
 * Per the Stage 2A instruction, Supabase must be authoritative for this
 * data immediately: browser storage must not be able to override shared
 * mechanic/salesperson/sublet-provider/bay/configuration values. If this
 * service cannot reach Supabase (auth missing, network down, RPC/table
 * absent), it reports a clear error/offline state and returns EMPTY data
 * -- it never silently falls back to a stale local snapshot or to the old
 * hard-coded DEFAULT_MECHANICS/DEFAULT_SALESPERSONS/DEFAULT_SUBLET_PROVIDERS
 * arrays.
 *
 * Connection states (mirrors workshop-data-service.js's naming):
 *   - 'connecting'           initial load in flight
 *   - 'connected_editable'   authenticated with a role that can mutate this
 *                            resource (varies per resource -- see below)
 *   - 'connected_read_only'  authenticated but role-restricted, or a write
 *                            attempt was blocked by the database
 *   - 'reconnecting'         realtime/network recovery in progress
 *   - 'offline_error'        auth/network/RPC failure; no stale fallback
 *   - 'permission_denied'    signed in but this account cannot read this
 *                            resource at all (should not normally happen
 *                            for viewer+, but handled explicitly rather
 *                            than assumed away)
 */

const WORKSHOP_REFERENCE_CONNECTION_STATE = Object.freeze({
  CONNECTING: 'connecting',
  CONNECTED_EDITABLE: 'connected_editable',
  CONNECTED_READ_ONLY: 'connected_read_only',
  RECONNECTING: 'reconnecting',
  OFFLINE_ERROR: 'offline_error',
  PERMISSION_DENIED: 'permission_denied'
});

// Resource -> { listRpc, addRpc, editRpc, setActiveRpc, table, realtimeTable }
// One narrow set of RPCs per resource, matching the protected functions in
// supabase/migrations/023_stage2a_workshop_reference_rpcs.sql exactly. There
// is deliberately no generic "mutate any reference resource" entry point.
const WORKSHOP_REFERENCE_RESOURCES = Object.freeze({
  technicians: {
    listRpc: 'list_technicians',
    addRpc: 'add_technician',
    editRpc: 'edit_technician',
    setActiveRpc: 'set_technician_active',
    table: 'workshop_technicians'
  },
  salespeople: {
    listRpc: 'list_salespeople',
    addRpc: 'add_salesperson',
    editRpc: 'edit_salesperson',
    setActiveRpc: 'set_salesperson_active',
    table: 'salespeople'
  },
  subletProviders: {
    listRpc: 'list_sublet_providers',
    addRpc: 'add_sublet_provider',
    editRpc: 'edit_sublet_provider',
    setActiveRpc: 'set_sublet_provider_active',
    table: 'sublet_providers'
  },
  workshopBays: {
    listRpc: 'list_workshop_bays',
    addRpc: null,
    editRpc: null,
    setActiveRpc: 'set_workshop_bay_active',
    table: 'workshop_bays'
  }
});

/**
 * Minimal fetch-based Supabase REST/RPC client, kept dependency-free so
 * this file can run under Node for unit tests and in the browser without a
 * bundler -- mirrors createWorkshopSupabaseClient() in
 * workshop-data-service.js exactly, duplicated rather than imported because
 * the two files must remain independently loadable/testable and neither
 * should depend on load order of the other.
 */
function createWorkshopReferenceSupabaseClient(config, fetchImpl) {
  const url = config.url;
  const key = config.publishableKey;
  const fetchFn = fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  if (!fetchFn) {
    throw new Error('workshop-reference-data-service: no fetch implementation available');
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
 * createWorkshopReferenceDataService(options) -> service object.
 *
 * options:
 *   config          window.PDC_SUPABASE_CONFIG (must have .url/.publishableKey)
 *   client           optional pre-built { rpc(token, name, params) } client
 *                     (tests inject a fake one; production omits this and a
 *                     real one is built from `config`)
 *   getAccessToken   () => string|null -- current Supabase access token
 *   subscribeRealtime(tableName, handlers) -> { unsubscribe() } -- injected
 *                     so this module never touches window.PDC_SUPABASE
 *                     directly (mirrors workshop-data-service.js's
 *                     dependency-injection style for testability)
 *   onStateChange    optional (resourceKey, state) => void
 */
function createWorkshopReferenceDataService(options) {
  const config = options.config || null;
  const client = options.client || (config ? createWorkshopReferenceSupabaseClient(config) : null);
  const getAccessToken = typeof options.getAccessToken === 'function' ? options.getAccessToken : () => null;
  const subscribeRealtime = typeof options.subscribeRealtime === 'function' ? options.subscribeRealtime : null;
  const onStateChange = typeof options.onStateChange === 'function' ? options.onStateChange : null;

  // Disposable runtime cache only -- explicitly never treated as a durable
  // store, never written to localStorage, and always discarded/rebuilt on
  // reload. Keyed by resource name; each entry is { rows, state, error }.
  const cache = {};
  const realtimeSubscriptions = {};
  // Monotonic per-resource request generation counter. Realtime onChange
  // events and mutation-triggered resyncs can both call loadResource()
  // for the same resource close together; without sequencing, a stale
  // in-flight request that started EARLIER but resolves LATER (out-of-
  // order network response) would silently overwrite a fresher result
  // that already landed -- exactly the "always one edit behind" bug this
  // fixes. Only the response matching the most recently STARTED request
  // for a resource is ever allowed to write the cache.
  const loadGeneration = {};

  function setState(resourceKey, state, error) {
    cache[resourceKey] = cache[resourceKey] || { rows: [], state: WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTING, error: null };
    cache[resourceKey].state = state;
    cache[resourceKey].error = error || null;
    if (onStateChange) onStateChange(resourceKey, state, error || null);
  }

  function classifyRpcFailure(resourceKey, status, body) {
    if (status === 401 || status === 403 || (body && body.code === '42501')) {
      setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED, body);
      return;
    }
    setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.OFFLINE_ERROR, body || { message: `HTTP ${status}` });
  }

  async function loadResource(resourceKey, includeInactive) {
    const resource = WORKSHOP_REFERENCE_RESOURCES[resourceKey];
    if (!resource) throw new Error(`workshop-reference-data-service: unknown resource '${resourceKey}'`);
    if (!client) {
      setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.OFFLINE_ERROR, { message: 'no Supabase client configured' });
      return [];
    }

    // Capture whether this resource was already known-editable BEFORE
    // transitioning to 'connecting' below, which would otherwise
    // overwrite that knowledge and make every post-mutation resync
    // incorrectly downgrade back to read-only.
    const wasEditable = cache[resourceKey]?.state === WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_EDITABLE;

    // Claim this generation BEFORE the await below, so any
    // concurrently-started request for the same resource can tell it is
    // now stale the moment a newer one begins (not just when the newer
    // one's response arrives).
    loadGeneration[resourceKey] = (loadGeneration[resourceKey] || 0) + 1;
    const myGeneration = loadGeneration[resourceKey];

    setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTING);
    const token = getAccessToken();
    if (!token) {
      // Never silently fall back to a stale cached list when there is no
      // authenticated session -- report the real state instead.
      if (loadGeneration[resourceKey] !== myGeneration) return cache[resourceKey]?.rows || [];
      setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED, { message: 'not authenticated' });
      cache[resourceKey] = { rows: [], state: WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED, error: { message: 'not authenticated' } };
      return [];
    }

    const { status, ok, body } = await client.rpc(token, resource.listRpc, { p_include_inactive: !!includeInactive });

    // A newer loadResource() call for this same resource started while
    // this one was in flight -- discard this now-stale response rather
    // than let it overwrite whatever the newer call already wrote (or is
    // about to write). This is the actual fix for the "cache always
    // shows the previous edit, one event behind" race.
    if (loadGeneration[resourceKey] !== myGeneration) return cache[resourceKey]?.rows || [];

    if (!ok || !Array.isArray(body)) {
      classifyRpcFailure(resourceKey, status, body);
      cache[resourceKey] = { rows: [], state: cache[resourceKey].state, error: body };
      return [];
    }

    // Whether this account CAN mutate the resource is determined by the
    // database on the next write attempt (never guessed client-side from
    // role name alone) -- but we can optimistically mark connected_editable
    // vs connected_read_only for UI purposes based on whether a mutation
    // RPC exists at all for this resource and whether the account has
    // already been observed to succeed a write this session (captured in
    // wasEditable above, before this reload overwrote that state).
    // Default to read-only until a write actually succeeds, which is the
    // safer default (never show edit controls as if they will work when
    // they may not).
    //
    // CRITICAL ORDERING: write the fresh rows into the cache BEFORE
    // calling setState() -- setState() synchronously invokes
    // onStateChange(), which is what the frontend uses to trigger its
    // render (see app.js's onStateChange -> renderAdminLists() ->
    // loadMechanics() -> getCachedTechnicians()). If setState() ran
    // first, that render would read the OLD cache (this fetch's result
    // not yet written), rendering stale data even though the fetch
    // itself succeeded and the state correctly flipped to
    // connected_read_only/editable -- exactly the "cache is right but
    // the UI never updates" bug this fixes.
    const nextState = wasEditable
      ? WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_EDITABLE
      : WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_READ_ONLY;
    cache[resourceKey] = { rows: body, state: nextState, error: null };
    setState(resourceKey, nextState);
    return body;
  }

  async function mutate(resourceKey, rpcName, params) {
    const resource = WORKSHOP_REFERENCE_RESOURCES[resourceKey];
    if (!resource) throw new Error(`workshop-reference-data-service: unknown resource '${resourceKey}'`);
    if (!client) return { ok: false, error: 'no_client' };

    const token = getAccessToken();
    if (!token) return { ok: false, error: 'not_authenticated' };

    const { status, ok, body } = await client.rpc(token, rpcName, params);
    if (status === 401 || status === 403 || (body && body.code === '42501')) {
      setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED, body);
      return { ok: false, error: 'permission_denied', detail: body };
    }
    if (!ok) {
      setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.OFFLINE_ERROR, body);
      return { ok: false, error: 'request_failed', detail: body };
    }
    if (body && body.ok === true) {
      setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_EDITABLE);
    }
    // Always re-load after a mutation so the cache reflects the real
    // database state (including the new version number) rather than the
    // caller guessing what changed -- consistent with
    // workshop-data-service.js's resync-after-mutation behaviour.
    await loadResource(resourceKey, true);
    return body || { ok: false, error: 'empty_response' };
  }

  function getCached(resourceKey) {
    return cache[resourceKey] || { rows: [], state: WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTING, error: null };
  }

  function subscribeToResource(resourceKey) {
    const resource = WORKSHOP_REFERENCE_RESOURCES[resourceKey];
    if (!resource || !subscribeRealtime) return { unsubscribe: () => {} };
    // Prevent duplicate subscriptions to the same resource -- calling this
    // twice for the same resourceKey reuses the existing subscription
    // rather than opening a second realtime channel.
    if (realtimeSubscriptions[resourceKey]) return realtimeSubscriptions[resourceKey];

    let reconnectAttempt = 0;
    const subscription = subscribeRealtime(resource.table, {
      onChange: () => {
        // A change happened -- re-load from the authoritative source
        // rather than trying to patch the cache from the realtime payload
        // alone (the payload does not carry role-filtered visibility, the
        // full re-read via the RPC does).
        loadResource(resourceKey, true).catch(() => {});
      },
      onStatus: (status) => {
        if (status === 'SUBSCRIBED') {
          // Reconcile immediately after a reconnect: any change made by
          // another session while THIS socket was disconnected produced
          // no postgres_changes event on this channel (there was no live
          // channel to deliver it to), so the cache can be silently
          // behind after a network blip/reconnect with no other signal.
          // Only do this for a genuine reconnect (reconnectAttempt > 0),
          // not the very first subscribe, which already gets its initial
          // load from the explicit listX() call made alongside
          // subscribeX() at boot.
          if (reconnectAttempt > 0) loadResource(resourceKey, true).catch(() => {});
          reconnectAttempt = 0;
          return;
        }
        if (status === 'CLOSED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          reconnectAttempt += 1;
          setState(resourceKey, WORKSHOP_REFERENCE_CONNECTION_STATE.RECONNECTING, { attempt: reconnectAttempt });
        }
      }
    });
    realtimeSubscriptions[resourceKey] = subscription;
    return subscription;
  }

  function unsubscribeAll() {
    Object.keys(realtimeSubscriptions).forEach((key) => {
      try { realtimeSubscriptions[key].unsubscribe(); } catch (_err) { /* ignore */ }
      delete realtimeSubscriptions[key];
    });
  }

  // workshop_settings is not a list/add/edit resource like the four
  // above -- it is a fixed set of named settings read/written as a
  // whole object via get/update RPCs (see getWorkshopConfiguration /
  // updateWorkshopConfiguration below). It still needs its own realtime
  // subscription so a settings change made in one browser session is
  // reflected live in another, without requiring a page refresh --
  // this reuses the same generation-guarded cache-then-notify pattern
  // as the four list-shaped resources, just keyed under
  // 'workshopSettings' with a plain object payload instead of rows.
  const SETTINGS_RESOURCE_KEY = 'workshopSettings';
  async function loadWorkshopConfiguration() {
    if (!client) {
      setState(SETTINGS_RESOURCE_KEY, WORKSHOP_REFERENCE_CONNECTION_STATE.OFFLINE_ERROR, { message: 'no Supabase client configured' });
      return {};
    }
    loadGeneration[SETTINGS_RESOURCE_KEY] = (loadGeneration[SETTINGS_RESOURCE_KEY] || 0) + 1;
    const myGeneration = loadGeneration[SETTINGS_RESOURCE_KEY];
    const token = getAccessToken();
    if (!token) {
      if (loadGeneration[SETTINGS_RESOURCE_KEY] !== myGeneration) return cache[SETTINGS_RESOURCE_KEY]?.rows || {};
      cache[SETTINGS_RESOURCE_KEY] = { rows: {}, state: WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED, error: { message: 'not authenticated' } };
      setState(SETTINGS_RESOURCE_KEY, WORKSHOP_REFERENCE_CONNECTION_STATE.PERMISSION_DENIED, { message: 'not authenticated' });
      return {};
    }
    const { status, ok, body } = await client.rpc(token, 'get_workshop_configuration', {});
    if (loadGeneration[SETTINGS_RESOURCE_KEY] !== myGeneration) return cache[SETTINGS_RESOURCE_KEY]?.rows || {};
    if (!ok || typeof body !== 'object' || body === null) {
      classifyRpcFailure(SETTINGS_RESOURCE_KEY, status, body);
      cache[SETTINGS_RESOURCE_KEY] = { rows: {}, state: cache[SETTINGS_RESOURCE_KEY]?.state, error: body };
      return {};
    }
    // Cache-then-notify ordering (see loadResource() above for why this
    // order matters): write the fresh configuration before firing
    // onStateChange, so any render triggered by the state change reads
    // the new values, not the previous ones.
    cache[SETTINGS_RESOURCE_KEY] = { rows: body, state: WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_READ_ONLY, error: null };
    setState(SETTINGS_RESOURCE_KEY, WORKSHOP_REFERENCE_CONNECTION_STATE.CONNECTED_READ_ONLY);
    return body;
  }

  function subscribeWorkshopSettings() {
    if (!subscribeRealtime) return { unsubscribe: () => {} };
    if (realtimeSubscriptions[SETTINGS_RESOURCE_KEY]) return realtimeSubscriptions[SETTINGS_RESOURCE_KEY];
    let reconnectAttempt = 0;
    const subscription = subscribeRealtime('workshop_settings', {
      onChange: () => { loadWorkshopConfiguration().catch(() => {}); },
      onStatus: (status) => {
        if (status === 'SUBSCRIBED') {
          if (reconnectAttempt > 0) loadWorkshopConfiguration().catch(() => {});
          reconnectAttempt = 0;
          return;
        }
        if (status === 'CLOSED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          reconnectAttempt += 1;
          setState(SETTINGS_RESOURCE_KEY, WORKSHOP_REFERENCE_CONNECTION_STATE.RECONNECTING, { attempt: reconnectAttempt });
        }
      }
    });
    realtimeSubscriptions[SETTINGS_RESOURCE_KEY] = subscription;
    return subscription;
  }

  // ---------------------------------------------------------------------
  // Typed, resource-specific functions exposed to the UI. Deliberately
  // NOT one generic mutate(resourceKey, rpcName, params) surface for
  // callers -- each function below is explicit about which real RPC it
  // calls and what parameters it takes, matching the "no generic update"
  // instruction at the RPC layer.
  // ---------------------------------------------------------------------

  return {
    STATE: WORKSHOP_REFERENCE_CONNECTION_STATE,

    // Technicians / mechanics
    listTechnicians: (includeInactive) => loadResource('technicians', includeInactive),
    getCachedTechnicians: () => getCached('technicians'),
    addTechnician: (name, roleType, code, canFitStages) =>
      mutate('technicians', 'add_technician', { p_name: name, p_role_type: roleType || 'technician', p_code: code || null, p_can_fit_stages: canFitStages || [] }),
    editTechnician: (technicianId, expectedVersion, fields = {}) =>
      mutate('technicians', 'edit_technician', {
        p_technician_id: technicianId,
        p_expected_version: expectedVersion,
        p_name: fields.name ?? null,
        p_role_type: fields.roleType ?? null,
        p_code: fields.code ?? null,
        p_can_fit_stages: fields.canFitStages ?? null
      }),
    setTechnicianActive: (technicianId, expectedVersion, active) =>
      mutate('technicians', 'set_technician_active', { p_technician_id: technicianId, p_expected_version: expectedVersion, p_active: !!active }),
    subscribeTechnicians: () => subscribeToResource('technicians'),

    // Salespeople
    listSalespeople: (includeInactive) => loadResource('salespeople', includeInactive),
    getCachedSalespeople: () => getCached('salespeople'),
    addSalesperson: (name, email, code) =>
      mutate('salespeople', 'add_salesperson', { p_name: name, p_email: email || null, p_code: code || null }),
    editSalesperson: (salespersonId, expectedVersion, fields = {}) =>
      mutate('salespeople', 'edit_salesperson', {
        p_salesperson_id: salespersonId,
        p_expected_version: expectedVersion,
        p_name: fields.name ?? null,
        p_email: fields.email ?? null,
        p_code: fields.code ?? null
      }),
    setSalespersonActive: (salespersonId, expectedVersion, active) =>
      mutate('salespeople', 'set_salesperson_active', { p_salesperson_id: salespersonId, p_expected_version: expectedVersion, p_active: !!active }),
    subscribeSalespeople: () => subscribeToResource('salespeople'),

    // Sublet providers
    listSubletProviders: (includeInactive) => loadResource('subletProviders', includeInactive),
    getCachedSubletProviders: () => getCached('subletProviders'),
    addSubletProvider: (name, email, phone) =>
      mutate('subletProviders', 'add_sublet_provider', { p_name: name, p_email: email || null, p_phone: phone || null }),
    editSubletProvider: (providerId, expectedVersion, fields = {}) =>
      mutate('subletProviders', 'edit_sublet_provider', {
        p_provider_id: providerId,
        p_expected_version: expectedVersion,
        p_name: fields.name ?? null,
        p_email: fields.email ?? null,
        p_phone: fields.phone ?? null
      }),
    setSubletProviderActive: (providerId, expectedVersion, active) =>
      mutate('subletProviders', 'set_sublet_provider_active', { p_provider_id: providerId, p_expected_version: expectedVersion, p_active: !!active }),
    subscribeSubletProviders: () => subscribeToResource('subletProviders'),

    // Workshop bays
    listWorkshopBays: (includeInactive) => loadResource('workshopBays', includeInactive),
    getCachedWorkshopBays: () => getCached('workshopBays'),
    setWorkshopBayActive: (bayId, expectedVersion, active) =>
      mutate('workshopBays', 'set_workshop_bay_active', { p_bay_id: bayId, p_expected_version: expectedVersion, p_active: !!active }),
    setBayDefaultTechnician: (bayId, expectedVersion, technicianId) =>
      mutate('workshopBays', 'set_bay_default_technician', { p_bay_id: bayId, p_expected_version: expectedVersion, p_technician_id: technicianId || null }),
    subscribeWorkshopBays: () => subscribeToResource('workshopBays'),

    // Workshop configuration (not a "resource" in the same list/add/edit
    // shape as the four above -- it is a fixed set of named settings, read
    // and written as a whole object via get/update RPCs).
    getWorkshopConfiguration: async () => {
      const configuration = await loadWorkshopConfiguration();
      return { ok: true, configuration };
    },
    getCachedWorkshopConfiguration: () => getCached(SETTINGS_RESOURCE_KEY),
    subscribeWorkshopSettings,
    updateWorkshopConfiguration: async (key, expectedVersion, value) => {
      if (!client) return { ok: false, error: 'no_client' };
      const token = getAccessToken();
      if (!token) return { ok: false, error: 'not_authenticated' };
      const { status, ok, body } = await client.rpc(token, 'update_workshop_configuration', {
        p_key: key, p_expected_version: expectedVersion, p_value: value
      });
      if (status === 401 || status === 403 || (body && body.code === '42501')) return { ok: false, error: 'permission_denied', detail: body };
      if (!ok) return { ok: false, error: 'request_failed', detail: body };
      return body || { ok: false, error: 'empty_response' };
    },

    // Lifecycle
    unsubscribeAll,
    getState: (resourceKey) => getCached(resourceKey).state,
    getError: (resourceKey) => getCached(resourceKey).error
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    WORKSHOP_REFERENCE_CONNECTION_STATE,
    WORKSHOP_REFERENCE_RESOURCES,
    createWorkshopReferenceSupabaseClient,
    createWorkshopReferenceDataService
  };
}
