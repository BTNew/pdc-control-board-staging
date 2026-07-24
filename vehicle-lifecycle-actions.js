'use strict';

/*
 * Vehicle lifecycle shared actions bridge (QC complete -> RFT -> Collected).
 *
 * Mirrors the existing workshop-shared-actions.js pattern: maps each
 * frontend action to the exact protected transactional RPC name/parameter
 * shape defined by migration 016, over the same minimal fetch-based
 * Supabase REST/RPC client used by workshop-data-service.js
 * (createWorkshopSupabaseClient), so this file has no new dependency and no
 * DOM code. app.js is responsible for calling the right bridge function
 * when vehicleLifecycleSharedModeActive() is true, and for reloading/
 * re-rendering from authoritative vehicle data afterwards either way.
 *
 * Shared mode is opt-in and independent of the workshop planner's own
 * sharedData flag (a site could enable shared workshop scheduling without
 * yet enabling shared QC/RFT/Collected, or vice versa) - see
 * window.PDC_SUPABASE_CONFIG.vehicleLifecycle.sharedData.
 */

function vehicleLifecycleSharedModeEnabled(config) {
  return !!(config && config.vehicleLifecycle && config.vehicleLifecycle.sharedData === true);
}

const STAGE2B_STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
const STAGE2B_STAGING_SUPABASE_URL = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
const STAGE2B_STAGING_SITE_ORIGIN = 'https://btnew.github.io';
const STAGE2B_STAGING_SITE_PATHS = new Set([
  '/pdc-control-board-staging/',
  '/pdc-control-board-staging/index.html',
]);
const LIFECYCLE_RESOLUTION_OUTCOMES = Object.freeze([
  'resolved',
  'not_found',
  'ambiguous',
  'conflict',
  'invalid_input',
  'unauthorized',
  'service_unavailable',
]);
const LIFECYCLE_RESOLUTION_OUTCOME_SET = new Set(LIFECYCLE_RESOLUTION_OUTCOMES);

function vehicleLifecycleResolverRollbackEnabled(config, runtimeLocation) {
  const location = runtimeLocation || (typeof window !== 'undefined' ? window.location : null);
  const origin = String(location && location.origin || '').replace(/\/$/, '');
  const pathname = String(location && location.pathname || '');
  return !!(
    config
    && config.projectRef === STAGE2B_STAGING_PROJECT_REF
    && String(config.url || '').replace(/\/$/, '') === STAGE2B_STAGING_SUPABASE_URL
    && origin === STAGE2B_STAGING_SITE_ORIGIN
    && STAGE2B_STAGING_SITE_PATHS.has(pathname)
    && config.vehicleLifecycle
    && config.vehicleLifecycle.resolverRollbackDirectRead === true
  );
}

function lifecycleIdentityTextValues(values = []) {
  return values
    .map(value => String(value == null ? '' : value).trim())
    .filter(Boolean);
}

function chooseLifecycleIdentityText(field, values, normalize, state) {
  const texts = lifecycleIdentityTextValues(values);
  if (!texts.length) return null;
  const normalized = new Set(texts.map(normalize).filter(Boolean));
  if (normalized.size > 1 && !state.invalidField) state.invalidField = field;
  return texts[0];
}

function normalizeLifecycleStockOrVin(value) {
  return String(value || '').trim().toUpperCase().replace(/[\s-]+/g, '');
}

function normalizeLifecycleSourceIdentifier(value) {
  return String(value || '').trim().toUpperCase();
}

function normalizeLifecycleSourceSystem(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeLifecycleUuid(value) {
  return String(value || '').trim().toLowerCase();
}

function buildVehicleLifecycleIdentityInput(vehicle = {}) {
  const state = { invalidField: null };
  const sourceSystem = chooseLifecycleIdentityText('source_system', [
    vehicle.sourceSystem, vehicle.source_system,
  ], normalizeLifecycleSourceSystem, state);
  const jobCardNumber = chooseLifecycleIdentityText('job_card_number', [
    vehicle.pdcJobcard, vehicle.jobcard, vehicle.jobCard, vehicle.jobcardNumber,
    vehicle.jobCardNumber, vehicle.jcJobcard, vehicle.jc,
  ], normalizeLifecycleSourceIdentifier, state);
  if (jobCardNumber && !sourceSystem && !state.invalidField) state.invalidField = 'job_card_source_system';
  const result = {
    p_vehicle_id: chooseLifecycleIdentityText('vehicle_id', [
      vehicle.sharedVehicleId, vehicle.shared_vehicle_id, vehicle.vehicleId,
      vehicle.vehicle_id, vehicle.canonicalVehicleId, vehicle.canonical_vehicle_id,
    ], normalizeLifecycleUuid, state),
    p_stock_number: chooseLifecycleIdentityText('stock_number', [
      vehicle.stock, vehicle.stockNumber, vehicle.stock_number,
    ], normalizeLifecycleStockOrVin, state),
    p_vin: chooseLifecycleIdentityText('vin', [
      vehicle.vin, vehicle.VIN, vehicle.fullVin, vehicle.frameVin,
      vehicle.vinNumber, vehicle.autocareVin,
    ], normalizeLifecycleStockOrVin, state),
    p_job_card_number: jobCardNumber,
    p_permanent_vehicle_id: chooseLifecycleIdentityText('permanent_vehicle_id', [
      vehicle.permanentVehicleId, vehicle.permanent_vehicle_id, vehicle.sharedPermanentVehicleId,
    ], normalizeLifecycleSourceIdentifier, state),
    p_source_system: sourceSystem,
    p_source_record_id: chooseLifecycleIdentityText('source_record_id', [
      vehicle.sourceRecordId, vehicle.source_record_id,
    ], normalizeLifecycleSourceIdentifier, state),
  };
  const clean = Object.fromEntries(Object.entries(result).filter(([, value]) => value !== null));
  if (clean.p_source_record_id && !clean.p_source_system && !state.invalidField) {
    state.invalidField = 'source_identity';
  }
  if (state.invalidField) {
    Object.defineProperty(clean, '__invalidIdentityField', {
      value: state.invalidField,
      enumerable: false,
      configurable: false,
    });
  }
  return clean;
}

function lifecycleIdentityCacheKey(input = {}) {
  return JSON.stringify(Object.keys(input).sort().map(key => [key, String(input[key] == null ? '' : input[key]).trim()]));
}

function mapLifecycleResolutionResponse(result) {
  if (!result || result.ok !== true) {
    if (result && (result.status === 401 || result.status === 403)) return { outcome: 'unauthorized' };
    return { outcome: 'service_unavailable' };
  }
  const body = result.body && typeof result.body === 'object' ? result.body : null;
  if (!body || !LIFECYCLE_RESOLUTION_OUTCOME_SET.has(body.outcome)) return { outcome: 'service_unavailable' };
  if (body.outcome !== 'resolved') {
    if (body.outcome === 'unauthorized') return { outcome: 'unauthorized' };
    const response = { outcome: body.outcome };
    if (typeof body.reason === 'string') response.reason = body.reason;
    if (typeof body.field === 'string') response.field = body.field;
    if (Number.isInteger(body.candidate_count) && body.candidate_count > 0) response.candidateCount = body.candidate_count;
    return response;
  }
  const vehicleId = String(body.vehicle_id || '').trim();
  const version = Number(body.version);
  const resolverRevision = Number(body.resolver_revision);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(vehicleId)
      || !Number.isInteger(version) || version < 1
      || !Number.isInteger(resolverRevision) || resolverRevision < 1) {
    return { outcome: 'service_unavailable' };
  }
  return {
    outcome: 'resolved',
    vehicleId,
    version,
    qcCompletedAt: body.qc_completed_at || null,
    lifecycleState: typeof body.lifecycle_state === 'string' ? body.lifecycle_state : null,
    isArchived: body.is_archived === true,
    resolverRevision,
    matchedBy: Array.isArray(body.matched_by) ? body.matched_by.filter(value => typeof value === 'string') : [],
  };
}

function createVehicleLifecycleIdentityResolver(options = {}) {
  const client = options.client;
  const getAccessToken = options.getAccessToken || (() => null);
  const subscribe = options.subscribe;
  const onDiagnostic = options.onDiagnostic || (() => {});
  const onRefresh = options.onRefresh || (() => {});
  const tracked = new Map();
  const latest = new Map();
  const generations = new Map();
  const diagnostics = [];
  const counters = {
    requests: 0,
    refreshes: 0,
    staleSuppressed: 0,
    coalescedRefreshes: 0,
    channelEvents: 0,
  };
  let subscription = null;
  let channelState = 'idle';
  let refreshLoop = null;
  let queuedRefreshReason = null;
  let lifecycleEpoch = 0;
  let active = true;

  function recordDiagnostic(type, detail = {}) {
    const item = {
      type,
      at: new Date().toISOString(),
      mode: detail.mode || 'resolver_rpc',
      channelState,
      counters: { ...counters },
      ...detail,
    };
    diagnostics.push(item);
    if (diagnostics.length > 100) diagnostics.shift();
    onDiagnostic(item);
  }

  async function resolve(input = {}, resolveOptions = {}) {
    if (!active) return { outcome: 'service_unavailable', reason: 'resolver_stopped' };
    const requestEpoch = lifecycleEpoch;
    const cleanInput = Object.fromEntries(Object.entries(input || {}).filter(([, value]) => value != null && String(value).trim() !== ''));
    const key = lifecycleIdentityCacheKey(cleanInput);
    const invalidField = input && input.__invalidIdentityField;
    if (!invalidField && resolveOptions.track !== false) tracked.set(key, cleanInput);
    const generation = (generations.get(key) || 0) + 1;
    generations.set(key, generation);
    counters.requests += 1;
    let mapped;
    let httpStatus = null;
    if (invalidField) {
      mapped = { outcome: 'invalid_input', field: invalidField };
    } else {
      try {
        if (!client || typeof client.rpc !== 'function') throw new Error('resolver client unavailable');
        const result = await client.rpc(getAccessToken(), 'resolve_vehicle_lifecycle_identity', cleanInput);
        httpStatus = Number.isInteger(result && result.status) ? result.status : null;
        mapped = mapLifecycleResolutionResponse(result);
      } catch (_err) {
        mapped = { outcome: 'service_unavailable' };
      }
    }
    if (!active || lifecycleEpoch !== requestEpoch) {
      return { outcome: 'service_unavailable', reason: 'resolver_stopped' };
    }
    const stale = generations.get(key) !== generation;
    if (!stale && !invalidField) latest.set(key, mapped);
    else if (stale) counters.staleSuppressed += 1;
    recordDiagnostic('resolution', {
      reason: resolveOptions.reason || 'consumer',
      outcome: mapped.outcome,
      stale,
      httpStatus,
      resolverRevision: mapped.resolverRevision || null,
      inputFields: Object.keys(cleanInput).sort(),
    });
    return stale ? { outcome: 'service_unavailable', reason: 'superseded' } : mapped;
  }

  async function refreshTracked(reason = 'realtime') {
    counters.refreshes += 1;
    const entries = [...tracked.values()];
    const results = await Promise.all(entries.map(async input => {
      const key = lifecycleIdentityCacheKey(input);
      const result = await resolve(input, { reason, track: false });
      if (latest.get(key) !== result) return null;
      const item = { input: { ...input }, result, reason };
      onRefresh(item);
      return item;
    }));
    return results.filter(Boolean);
  }

  function requestRefresh(reason = 'reconcile') {
    if (!active) return Promise.resolve([]);
    queuedRefreshReason = reason;
    if (refreshLoop) {
      counters.coalescedRefreshes += 1;
      return refreshLoop;
    }
    refreshLoop = (async () => {
      do {
        const nextReason = queuedRefreshReason;
        queuedRefreshReason = null;
        await refreshTracked(nextReason);
      } while (queuedRefreshReason);
    })().finally(() => {
      refreshLoop = null;
    });
    return refreshLoop;
  }

  function start() {
    if (subscription || typeof subscribe !== 'function') return;
    active = true;
    channelState = 'joining';
    subscription = subscribe({
      onChange: async payload => {
        counters.channelEvents += 1;
        recordDiagnostic('realtime_change', {
          mode: 'realtime',
          resolverRevision: payload && payload.new ? payload.new.revision : null,
        });
        await requestRefresh('realtime_change');
      },
      onStatus: async status => {
        counters.channelEvents += 1;
        channelState = status;
        recordDiagnostic('realtime_status', { mode: 'realtime', status });
        if (status === 'SUBSCRIBED') await requestRefresh('realtime_subscribed');
      },
    });
  }

  function stop() {
    active = false;
    lifecycleEpoch += 1;
    if (subscription && typeof subscription.unsubscribe === 'function') subscription.unsubscribe();
    subscription = null;
    channelState = 'stopped';
    queuedRefreshReason = null;
    tracked.clear();
    latest.clear();
    generations.clear();
    diagnostics.length = 0;
  }

  return {
    resolve,
    refreshTracked,
    reconcile: requestRefresh,
    start,
    stop,
    getLatest(input = {}) { return latest.get(lifecycleIdentityCacheKey(input)) || null; },
    getDiagnostics() { return diagnostics.map(item => ({ ...item, counters: { ...item.counters } })); },
  };
}

function buildVehicleLifecycleSharedActions(client, getAccessToken) {
  async function rpc(name, params) {
    const token = typeof getAccessToken === 'function' ? getAccessToken() : null;
    const result = await client.rpc(token, name, params);
    if (!result.ok) {
      return { ok: false, error: 'request_failed', status: result.status, body: result.body };
    }
    return result.body || {};
  }

  return {
    qcCompleteVehicle({ vehicleId, expectedVersion, workItemKey, completedSummary }) {
      return rpc('qc_complete_vehicle', {
        p_vehicle_id: vehicleId,
        p_expected_version: expectedVersion,
        p_work_item_key: workItemKey ?? 'QC',
        p_completed_summary: completedSummary ?? null,
      });
    },

    rftTransferVehicle({ vehicleId, expectedVersion }) {
      return rpc('rft_transfer_vehicle', {
        p_vehicle_id: vehicleId,
        p_expected_version: expectedVersion,
      });
    },

    rftCollectVehicle({ vehicleId, expectedVersion }) {
      return rpc('rft_collect_vehicle', {
        p_vehicle_id: vehicleId,
        p_expected_version: expectedVersion,
      });
    },

    retryVehicleNotification({ notificationId, recipientEmail }) {
      return rpc('retry_vehicle_notification', {
        p_notification_id: notificationId,
        p_recipient_email: recipientEmail ?? null,
      });
    },
  };
}

// Human-readable, non-technical mapping for the error codes the RPCs above
// can return, matching the pattern already established by
// workshopDescribeSharedActionError() in workshop-planner.js. Staff should
// never see a raw backend error code.
function describeVehicleLifecycleActionError(error = '') {
  const MESSAGES = {
    vehicle_version_conflict: 'This vehicle changed since you loaded it. The latest information has been reloaded - please check and try again.',
    already_qc_complete: 'QC has already been completed for this vehicle.',
    already_collected: 'This vehicle has already been collected and moved to Completed Vehicles.',
    qc_not_complete: 'QC sign-off is required before this vehicle can be transferred to RFT.',
    not_in_active_lifecycle: 'This vehicle is not currently active in PMB, so it cannot be transferred to RFT.',
    not_in_rft: 'This vehicle is not currently in RFT, so it cannot be marked collected.',
    request_failed: 'The change could not be saved. Please check your connection and try again.',
    missing_expected_version: 'This action is missing required version information and was not applied.',
  };
  return MESSAGES[error] || 'The change could not be saved. Please try again or contact an administrator.';
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    LIFECYCLE_RESOLUTION_OUTCOMES,
    vehicleLifecycleSharedModeEnabled,
    vehicleLifecycleResolverRollbackEnabled,
    buildVehicleLifecycleIdentityInput,
    createVehicleLifecycleIdentityResolver,
    buildVehicleLifecycleSharedActions,
    describeVehicleLifecycleActionError,
  };
}
if (typeof window !== 'undefined') {
  window.LIFECYCLE_RESOLUTION_OUTCOMES = LIFECYCLE_RESOLUTION_OUTCOMES;
  window.vehicleLifecycleSharedModeEnabled = vehicleLifecycleSharedModeEnabled;
  window.vehicleLifecycleResolverRollbackEnabled = vehicleLifecycleResolverRollbackEnabled;
  window.buildVehicleLifecycleIdentityInput = buildVehicleLifecycleIdentityInput;
  window.createVehicleLifecycleIdentityResolver = createVehicleLifecycleIdentityResolver;
  window.buildVehicleLifecycleSharedActions = buildVehicleLifecycleSharedActions;
  window.describeVehicleLifecycleActionError = describeVehicleLifecycleActionError;
}
