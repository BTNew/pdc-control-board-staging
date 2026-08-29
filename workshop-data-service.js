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
  PERMISSION_DENIED: 'permission_denied',
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
  'cascade_workshop_schedule',
  'cascade_workshop_booking_move',
  'set_workshop_stage_estimated_minutes_407',

  'create_workshop_admin_block',
  'move_workshop_admin_block',
  'resize_workshop_admin_block',
  'delete_workshop_admin_block',
  'administrator_move_workshop_booking',
  'administrator_schedule_workshop_vehicle',
  'undo_administrator_workshop_booking_move',
  'complete_pdc_vehicle_department_772'
]);

// Every RPC above requires exactly one non-null expected-version parameter.
// schedule_vehicle_work and administrator_schedule_workshop_vehicle key off the
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
  cascade_workshop_schedule: 'p_target_expected_version',
  cascade_workshop_booking_move: 'p_expected_version',
  set_workshop_stage_estimated_minutes_407: 'p_expected_booking_version',

  create_workshop_admin_block: 'p_expected_revision',
  move_workshop_admin_block: 'p_expected_version',
  resize_workshop_admin_block: 'p_expected_version',
  delete_workshop_admin_block: 'p_expected_version',
  administrator_move_workshop_booking: 'p_expected_version',
  administrator_schedule_workshop_vehicle: 'p_vehicle_expected_version',
  undo_administrator_workshop_booking_move: 'p_expected_version',
  complete_pdc_vehicle_department_772: 'p_expected_vehicle_version'
});

const WORKSHOP_READ_RPCS = Object.freeze([
  'get_workshop_admin_block_audit_771'
]);

const WORKSHOP_CANONICAL_MUTATION_ERRORS = new Set([
  'version_conflict', 'vehicle_version_conflict', 'location_ineligible',
  'missing_eta', 'it_eta_missing', 'it_before_eta',
  'vehicle_not_eligible_for_station', 'active_booking_exists',
  'canonical_requirement_missing_or_completed', 'parts_incomplete',
  'bay_overlap', 'vehicle_overlap', 'calendar_unavailable',
  'calendar_duration_mismatch', 'invalid_schedule_interval', 'minimum_duration',
  'bay_inactive_or_wrong_station', 'technician_inactive_or_missing',
  'technician_leave_conflict', 'technician_overlap', 'live_booking_conflict',
  'concurrent_queue_change', 'sublet_away',
  'admin_block_conflict', 'fixed_booking_conflict', 'invalid_admin_block_type',
  'admin_block_not_found', 'invalid_label', 'invalid_idempotency_key',
  'idempotency_conflict', 'no_available_slot',
  'protected_booking', 'receipt_not_found', 'undo_actor_mismatch',
  'already_undone', 'undo_expired', 'undo_conflict'
]);

function workshopCanonicalMutationError(body) {
  if (!body || typeof body !== 'object') return '';
  const direct = String(body.error || '').trim();
  if (WORKSHOP_CANONICAL_MUTATION_ERRORS.has(direct)) return direct;
  const message = String(body.message || body.details || '').trim();
  const match = message.match(/["']error["']\s*:\s*["']([a-z0-9_]+)["']/i);
  const extracted = match ? String(match[1] || '').toLowerCase() : '';
  return WORKSHOP_CANONICAL_MUTATION_ERRORS.has(extracted) ? extracted : '';
}

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
function normalizeWorkshopSnapshotScope(value) {
  if (!value || typeof value !== 'object') return null;
  const stageCode = String(value.stageCode || '').trim().toUpperCase();
  const dateFrom = String(value.dateFrom || '').slice(0, 10);
  const dateTo = String(value.dateTo || dateFrom).slice(0, 10);
  if (!/^[A-Z0-9_]+$/.test(stageCode) || !/^\d{4}-\d{2}-\d{2}$/.test(dateFrom) || !/^\d{4}-\d{2}-\d{2}$/.test(dateTo)) return null;
  return { stageCode, dateFrom, dateTo };
}

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
  let scope = normalizeWorkshopSnapshotScope(options.scope);

  const enabled = workshopSharedModeEnabled(config);

  let state = enabled ? WORKSHOP_CONNECTION_STATE.CONNECTING : WORKSHOP_CONNECTION_STATE.DISABLED;
  let lastSnapshot = null;
  let lastRevision = null;
  // A retained snapshot can still be useful to the planner while offline,
  // but advisory rules must never present it as current operational truth.
  // This flag is cleared before every refresh/revision and on every failure;
  // only a successful authenticated snapshot response restores trust.
  let snapshotTrusted = false;
  let pendingReloadTimer = null;
  let activeLoadToken = null;
  let trailingReloadRequested = false;
  let destroyed = false;
  let lifecycleGeneration = 0;
  let scopeGeneration = 0;

  function invalidateAuthority(nextState = WORKSHOP_CONNECTION_STATE.RECONNECTING) {
    lifecycleGeneration += 1;
    snapshotTrusted = false;
    lastSnapshot = null;
    lastRevision = null;
    trailingReloadRequested = false;
    // Detach any unresolved request from the current authority session. Its
    // finally block checks identity before changing current-session state.
    activeLoadToken = null;
    if (pendingReloadTimer) {
      clearScheduledTimeout(pendingReloadTimer);
      pendingReloadTimer = null;
    }
    if (!destroyed) setState(nextState);
  }

  function setState(next) {
    if (state === next) return;
    state = next;
    onStateChange(state);
  }

  function isEditable() {
    return state === WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE;
  }

  async function loadSnapshot(reason) {
    if (!enabled || destroyed) {
      snapshotTrusted = false;
      if (!destroyed) setState(WORKSHOP_CONNECTION_STATE.DISABLED);
      return null;
    }
    const token = getAccessToken();
    if (!token) {
      // Check authority before coalescing with an active request. Otherwise a
      // token loss during that request could return retained prior-user rows.
      invalidateAuthority(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED);
      return null;
    }
    if (activeLoadToken) {
      snapshotTrusted = false;
      trailingReloadRequested = true;
      return lastSnapshot;
    }
    snapshotTrusted = false;
    const generation = lifecycleGeneration;
    const requestScopeGeneration = scopeGeneration;
    const loadToken = {};
    activeLoadToken = loadToken;
    try {
      const mutationRole = getRole();
      if (mutationRole === 'operator' || mutationRole === 'administrator') {
        const recoveryKey = `snapshot-recovery-${scope?.stageCode || 'all'}-${scope?.dateFrom || 'all'}-${Math.floor(Date.now() / 60000)}`;
        // Future-only recovery is maintenance, not display authority. A single
        // historical overlap can reject recovery while the scoped snapshot is
        // still valid and readable. Never blank every station for that reason;
        // the server keeps the conflicting booking unchanged and the snapshot
        // remains the authoritative visible state.
        try {
          await client.rpc(token, 'recover_overdue_planned_workshop_bookings', {
            p_idempotency_key: recoveryKey,
            p_as_of: new Date().toISOString(),
          });
        } catch (_recoveryError) {
          // Continue to the authenticated snapshot. Its own status remains the
          // authority for connected/offline/permission state.
        }
      }
      const rpcName = scope ? 'get_station_workshop_snapshot' : 'get_workshop_snapshot';
      const rpcParams = scope ? {
        p_stage_code: scope.stageCode,
        p_date_from: scope.dateFrom,
        p_date_to: scope.dateTo,
      } : {};
      const result = await client.rpc(token, rpcName, rpcParams);
      if (destroyed || generation !== lifecycleGeneration) return null;
      if (requestScopeGeneration !== scopeGeneration) return null;
      if (!result.ok) {
        if (result.status === 404) {
          setState(WORKSHOP_CONNECTION_STATE.INCOMPATIBLE);
        } else if (result.status === 401 || result.status === 403) {
          // Authentication/authorization loss invalidates both mutation
          // authority and display authority for every retained row.
          invalidateAuthority(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED);
          return null;
        } else {
          setState(WORKSHOP_CONNECTION_STATE.OFFLINE_READ_ONLY);
        }
        return lastSnapshot;
      }
      lastSnapshot = result.body;
      lastRevision = result.body && result.body.revision;
      snapshotTrusted = Boolean(lastSnapshot && typeof lastSnapshot === 'object' && lastRevision != null);
      const role = getRole();
      setState(role === 'operator' || role === 'administrator'
        ? WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE
        : WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY);
      onSnapshot(lastSnapshot, reason || 'load');
      return lastSnapshot;
    } catch (_err) {
      if (destroyed || generation !== lifecycleGeneration) return null;
      if (requestScopeGeneration !== scopeGeneration) return null;
      setState(WORKSHOP_CONNECTION_STATE.OFFLINE_READ_ONLY);
      return lastSnapshot;
    } finally {
      if (activeLoadToken !== loadToken) return;
      activeLoadToken = null;
      if (!destroyed && generation === lifecycleGeneration && trailingReloadRequested) {
        trailingReloadRequested = false;
        // A newer change arrived while we were mid-fetch; reload again so we
        // never settle on a stale intermediate snapshot.
        await loadSnapshot('trailing');
      }
    }
  }

  function scheduleSnapshotReload(reason) {
    if (!enabled || destroyed) return;
    // A newer revision is known to exist, so the retained snapshot is not
    // current during debounce or reload and must not feed advisory output.
    snapshotTrusted = false;
    // Retain the last snapshot for visual continuity, but make every action
    // non-editable immediately rather than waiting for the debounced refetch.
    setState(WORKSHOP_CONNECTION_STATE.RECONNECTING);
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
    if (destroyed) return;
    setState(WORKSHOP_CONNECTION_STATE.RECONNECTING);
    return loadSnapshot('reconnect');
  }

  function onAuthorityLost() {
    if (!enabled || destroyed) return;
    invalidateAuthority(WORKSHOP_CONNECTION_STATE.RECONNECTING);
  }

  function onVisibilityReturn() {
    if (!enabled || destroyed) return;
    loadSnapshot('visibility_return');
  }

  function onTokenRefresh() {
    if (!enabled || destroyed) return;
    invalidateAuthority(WORKSHOP_CONNECTION_STATE.RECONNECTING);
    return loadSnapshot('token_refresh');
  }

  async function setScope(nextScope) {
    const normalized = normalizeWorkshopSnapshotScope(nextScope);
    if (JSON.stringify(normalized) === JSON.stringify(scope)) return lastSnapshot;
    scope = normalized;
    scopeGeneration += 1;
    invalidateAuthority(WORKSHOP_CONNECTION_STATE.CONNECTING);
    return loadSnapshot('scope_changed');
  }

  async function recoverEditableAuthority() {
    for (let attempt = 0; attempt < 20; attempt += 1) {
      await loadSnapshot(attempt === 0 ? 'mutation_preflight' : 'mutation_preflight_wait');
      if (isEditable() && snapshotTrusted && !pendingReloadTimer && !activeLoadToken && !trailingReloadRequested) return true;
      if (!enabled || destroyed || !getAccessToken()) return false;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    return false;
  }

  function ensureEditable() {
    if (isEditable() && snapshotTrusted && !pendingReloadTimer && !activeLoadToken && !trailingReloadRequested) return true;
    if (!enabled || destroyed || !getAccessToken()) return false;
    return recoverEditableAuthority();
  }

  async function mutate(rpcName, params) {
    if (!WORKSHOP_MUTATION_RPCS.includes(rpcName)) {
      throw new Error(`workshop-data-service: unknown mutation RPC ${rpcName}`);
    }
    if (destroyed) {
      return { ok: false, error: 'destroyed', state };
    }
    if (!enabled) {
      throw new Error('workshop-data-service: shared mode is not enabled; no writable operational path exists');
    }
    const administratorReconnectMutation = (
      getRole() === 'administrator'
      && Boolean(getAccessToken())
      && ['administrator_move_workshop_booking', 'administrator_schedule_workshop_vehicle'].includes(rpcName)
      && [WORKSHOP_CONNECTION_STATE.CONNECTING, WORKSHOP_CONNECTION_STATE.RECONNECTING].includes(state)
    );
    // A valid authenticated session may transiently remain in reconnecting
    // under continuous Realtime revision traffic. The two Administrator-only
    // receipt RPCs may cross that UI state because PostgreSQL still enforces
    // role, expected version, lock/protection, overlap, cascade and receipt
    // idempotency atomically. No local data is accepted as authority and all
    // other mutations continue to require a trusted connected snapshot.
    const editable = administratorReconnectMutation ? true : ensureEditable();
    if (!(editable === true || (editable && await editable))) {
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
    if (!token) {
      invalidateAuthority(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED);
      return { ok: false, error: 'permission_denied', state: WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED };
    }
    const generation = lifecycleGeneration;
    const result = await client.rpc(token, rpcName, params);
    // Sign-out, role/token refresh, scope teardown, or destroy makes every
    // result from the prior authority generation inert before caller/UI code
    // can interpret it as a successful operation.
    if (destroyed || generation !== lifecycleGeneration) {
      return { ok: false, error: destroyed ? 'destroyed' : 'authority_superseded', state };
    }
    if (!getAccessToken()) {
      invalidateAuthority(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED);
      return { ok: false, error: 'permission_denied', state: WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED };
    }
    if (!result.ok) {
      if (result.status === 401 || result.status === 403) {
        // Purge immediately. A 403 can be action-specific (for example an
        // administrator-only override), so re-establish read authority only
        // through a fresh authenticated snapshot rather than retaining rows.
        invalidateAuthority(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED);
        if (!destroyed && getAccessToken()) await loadSnapshot('mutation_permission_recheck');
      }
      const canonicalError = workshopCanonicalMutationError(result.body);
      if (![401, 403].includes(result.status) && !destroyed && getAccessToken()) {
        await loadSnapshot(canonicalError ? 'rejected_canonical_mutation' : 'rejected_http_mutation');
      }
      const body = result.body;
      const serverCode = body && typeof body === 'object' ? (body.code || body.error || body.error_code) : null;
      const serverMessage = body && typeof body === 'object'
        ? (body.message || body.error_description || body.details || body.hint)
        : (typeof body === 'string' ? body : null);
      return { ok: false, error: canonicalError || serverCode || 'request_failed', code: serverCode || null, message: serverMessage || null, status: result.status, body };
    }
    const body = result.body || {};
    if (body.ok === false && ['version_conflict', 'vehicle_version_conflict'].includes(body.error)) {
      // Never display an unsaved move as successful: force a fresh
      // authoritative snapshot so the caller reconciles from truth. Await the
      // refresh: returning while it is still in flight lets the UI immediately
      // reuse the same stale vehicle/booking version and fail forever.
      await loadSnapshot('rejected_stale_mutation');
      return body;
    }
    if (body.ok === true) {
      // Successful mutation: reconcile from the confirmed result rather
      // than trusting an optimistic local guess. The shared-action caller
      // renders only after this authoritative refresh has completed.
      await loadSnapshot('successful_mutation');
    }
    return body;
  }

  async function readAdminBlockAudit(params = {}) {
    if (!enabled || destroyed) return { ok: false, error: 'not_available', state };
    if (!['operator', 'administrator'].includes(String(getRole() || '').trim().toLowerCase())) {
      return { ok: false, error: 'permission_denied', state };
    }
    const token = getAccessToken();
    if (!token) return { ok: false, error: 'permission_denied', state: WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED };
    const result = await client.rpc(token, WORKSHOP_READ_RPCS[0], params);
    if (!result?.ok) {
      return { ok: false, error: result?.status === 401 || result?.status === 403 ? 'permission_denied' : 'request_failed', status: result?.status, body: result?.body };
    }
    return result.body && typeof result.body === 'object' ? result.body : { ok: false, error: 'invalid_response' };
  }

  function destroy() {
    if (destroyed) return;
    destroyed = true;
    invalidateAuthority(WORKSHOP_CONNECTION_STATE.DISABLED);
  }

  return {
    isEnabled: () => enabled,
    getState: () => state,
    getLastSnapshot: () => lastSnapshot,
    // Advisory consumers use this method rather than getLastSnapshot(). It
    // deliberately returns null for retained offline, unauthorized, pending,
    // reconnecting, or superseded snapshots.
    getTrustedSnapshot: () => (
      snapshotTrusted
      && !destroyed
      && !pendingReloadTimer
      && !activeLoadToken
      && !trailingReloadRequested
      && [WORKSHOP_CONNECTION_STATE.CONNECTED_READ_ONLY, WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE].includes(state)
        ? lastSnapshot
        : null
    ),
    getLastRevision: () => lastRevision,
    getScope: () => (scope ? { ...scope } : null),
    loadSnapshot,
    setScope,
    onRevisionSignal,
    onReconnect,
    onAuthorityLost,
    onVisibilityReturn,
    onTokenRefresh,
    mutate,
    readAdminBlockAudit,
    destroy
  };
}

/**
 * Authenticated migration-235 bridge. Kept separate from booking mutations
 * because removal has its own receipt/idempotency contract. The UI role check
 * is only presentation; the protected RPC remains lifecycle/RLS authority.
 */
function createWorkshopOperationRemovalService(options = {}) {
  const client = options.client;
  const getAccessToken = options.getAccessToken || (() => null);
  const getRole = options.getRole || (() => null);
  const refresh = options.refresh || (async () => {});
  let generation = 0;

  function administratorReady() {
    return ['operator', 'administrator'].includes(String(getRole() || '').trim().toLowerCase())
      && Boolean(getAccessToken()) && client && typeof client.rpc === 'function';
  }

  async function invoke(name, params) {
    if (!administratorReady()) return { ok: false, error: 'permission_denied' };
    const token = getAccessToken();
    const requestGeneration = generation;
    let output;
    try {
      const response = await client.rpc(token, name, params);
      if (requestGeneration !== generation || token !== getAccessToken()) return { ok: false, error: 'authority_superseded' };
      if (!response || !response.ok) {
        output = { ok: false, error: response?.status === 401 || response?.status === 403 ? 'permission_denied' : 'request_failed', status: response?.status, body: response?.body };
      } else {
        const body = response.body && typeof response.body === 'object' ? response.body : {};
        output = body.ok === true ? body : { ...body, ok: false, error: body.code || body.error || 'request_failed' };
      }
    } catch (_error) {
      output = { ok: false, error: 'network_failure' };
    }
    try { await refresh(output); } catch (_error) {
      return { ok: false, error: 'authoritative_refresh_failed', mutationResult: output };
    }
    return output;
  }

  function canonicalJson(value) {
    if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
    if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
    return JSON.stringify(value);
  }

  async function requestHash(value) {
    const subtle = globalThis.crypto?.subtle;
    if (!subtle || typeof TextEncoder !== 'function') return '';
    const bytes = await subtle.digest('SHA-256', new TextEncoder().encode(canonicalJson(value)));
    return Array.from(new Uint8Array(bytes), byte => byte.toString(16).padStart(2, '0')).join('');
  }

  return Object.freeze({
    isAdministratorReady: administratorReady,
    async removeOperation({ operationLineId, vehicleId, stockNumber, jobCardNumber, operationNo, description, department, expectedVehicleVersion, expectedAdjustmentVersion, confirmation, reason, sourceEvidence, idempotencyKey, requestSha256 } = {}) {
      const cleanReason = String(reason || '').trim();
      const cleanKey = String(idempotencyKey || '').trim();
      if (!operationLineId || !vehicleId || !stockNumber || !jobCardNumber || !operationNo || !description || !department || !confirmation || !Number.isInteger(Number(expectedVehicleVersion)) || cleanReason.length < 3 || cleanReason.length > 500 || cleanKey.length < 8 || cleanKey.length > 160 || !sourceEvidence || typeof sourceEvidence !== 'object' || Array.isArray(sourceEvidence)) {
        return { ok: false, error: 'invalid_input' };
      }
      const payload = { contract: 'operation-delete-772', vehicle_id: vehicleId, stock_number: stockNumber, job_card_number: jobCardNumber, operation_line_id: operationLineId, operation_no: operationNo, description, department: String(department).toUpperCase(), expected_vehicle_version: Number(expectedVehicleVersion), expected_adjustment_version: Number(expectedAdjustmentVersion || 0), confirmation, reason: cleanReason, idempotency_key: cleanKey };
      const hash = String(requestSha256 || await requestHash(payload)).trim();
      if (!/^[a-f0-9]{64}$/.test(hash)) return { ok: false, error: 'request_hash_unavailable' };
      return invoke('delete_pdc_authenticated_operation_line_772', {
        p_vehicle_id: vehicleId, p_stock_number: stockNumber, p_job_card_number: jobCardNumber, p_operation_line_id: operationLineId,
        p_operation_no: operationNo, p_description: description, p_department: String(department).toUpperCase(), p_expected_vehicle_version: Number(expectedVehicleVersion), p_expected_adjustment_version: Number(expectedAdjustmentVersion || 0), p_confirmation: confirmation, p_reason: cleanReason, p_idempotency_key: cleanKey, p_request_hash: hash, p_source_evidence: sourceEvidence,
      });
    },
    async undoRemoval({ receiptId, vehicleId, operationLineId, expectedVehicleVersion, reason, idempotencyKey, requestSha256 } = {}) {
      const cleanReason = String(reason || '').trim();
      const cleanKey = String(idempotencyKey || '').trim();
      if (!receiptId || !vehicleId || !operationLineId || !Number.isInteger(Number(expectedVehicleVersion)) || cleanReason.length < 3 || cleanReason.length > 500 || cleanKey.length < 8) return { ok: false, error: 'invalid_input' };
      const payload = { contract: 'operation-undo-772', receipt_id: receiptId, vehicle_id: vehicleId, operation_line_id: operationLineId, expected_vehicle_version: Number(expectedVehicleVersion), idempotency_key: cleanKey, reason: cleanReason };
      const hash = String(requestSha256 || await requestHash(payload)).trim();
      if (!/^[a-f0-9]{64}$/.test(hash)) return { ok: false, error: 'request_hash_unavailable' };
      return invoke('undo_pdc_authenticated_operation_line_772', { p_receipt_id: receiptId, p_vehicle_id: vehicleId, p_operation_line_id: operationLineId, p_expected_vehicle_version: Number(expectedVehicleVersion), p_idempotency_key: cleanKey, p_request_hash: hash, p_reason: cleanReason });
    },
    invalidateAuthority() { generation += 1; },
  });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    WORKSHOP_CONNECTION_STATE,
    WORKSHOP_MUTATION_RPCS,
    WORKSHOP_READ_RPCS,
    WORKSHOP_MUTATION_VERSION_PARAM,
    workshopSharedModeEnabled,
    normalizeWorkshopSnapshotScope,
    createWorkshopSupabaseClient,
    createWorkshopDataService,
    createWorkshopOperationRemovalService
  };
}
if (typeof window !== 'undefined') {
  window.WORKSHOP_CONNECTION_STATE = WORKSHOP_CONNECTION_STATE;
  window.WORKSHOP_MUTATION_RPCS = WORKSHOP_MUTATION_RPCS;
  window.WORKSHOP_READ_RPCS = WORKSHOP_READ_RPCS;
  window.WORKSHOP_MUTATION_VERSION_PARAM = WORKSHOP_MUTATION_VERSION_PARAM;
  window.workshopSharedModeEnabled = workshopSharedModeEnabled;
  window.createWorkshopSupabaseClient = createWorkshopSupabaseClient;
  window.createWorkshopDataService = createWorkshopDataService;
  window.createWorkshopOperationRemovalService = createWorkshopOperationRemovalService;
}
