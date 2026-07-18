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

function vehicleLifecycleResolverRollbackEnabled(config) {
  return !!(
    config
    && config.projectRef === STAGE2B_STAGING_PROJECT_REF
    && config.vehicleLifecycle
    && config.vehicleLifecycle.resolverRollbackDirectRead === true
  );
}

function firstLifecycleIdentityText(...values) {
  for (const value of values) {
    const text = String(value == null ? '' : value).trim();
    if (text) return text;
  }
  return null;
}

function buildVehicleLifecycleIdentityInput(vehicle = {}) {
  const sourceSystem = firstLifecycleIdentityText(vehicle.sourceSystem, vehicle.source_system);
  const result = {
    p_vehicle_id: firstLifecycleIdentityText(
      vehicle.sharedVehicleId, vehicle.shared_vehicle_id, vehicle.vehicleId,
      vehicle.canonicalVehicleId, vehicle.canonical_vehicle_id,
    ),
    p_stock_number: firstLifecycleIdentityText(vehicle.stock, vehicle.stockNumber, vehicle.stock_number),
    p_vin: firstLifecycleIdentityText(vehicle.vin, vehicle.VIN, vehicle.chassis, vehicle.chassisNo, vehicle.frame),
    p_job_card_number: sourceSystem ? firstLifecycleIdentityText(
      vehicle.pdcJobcard, vehicle.jobcard, vehicle.jobCard, vehicle.jobcardNumber,
      vehicle.jobCardNumber, vehicle.jcJobcard, vehicle.jc,
    ) : null,
    p_permanent_vehicle_id: firstLifecycleIdentityText(
      vehicle.permanentVehicleId, vehicle.permanent_vehicle_id, vehicle.sharedPermanentVehicleId,
    ),
    p_toyota_order_number: sourceSystem ? firstLifecycleIdentityText(
      vehicle.toyotaOrderNumber, vehicle.toyota_order_number, vehicle.toyotaOrder,
      vehicle.salesOrder, vehicle.order,
    ) : null,
    p_source_system: sourceSystem,
    p_source_record_id: firstLifecycleIdentityText(vehicle.sourceRecordId, vehicle.source_record_id),
  };
  return Object.fromEntries(Object.entries(result).filter(([, value]) => value !== null));
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
  let subscription = null;
  let disconnected = false;

  function recordDiagnostic(type, detail = {}) {
    const item = { type, at: new Date().toISOString(), ...detail };
    diagnostics.push(item);
    if (diagnostics.length > 100) diagnostics.shift();
    onDiagnostic(item);
  }

  async function resolve(input = {}, resolveOptions = {}) {
    const cleanInput = Object.fromEntries(Object.entries(input || {}).filter(([, value]) => value != null && String(value).trim() !== ''));
    const key = lifecycleIdentityCacheKey(cleanInput);
    if (resolveOptions.track !== false) tracked.set(key, cleanInput);
    const generation = (generations.get(key) || 0) + 1;
    generations.set(key, generation);
    let mapped;
    try {
      if (!client || typeof client.rpc !== 'function') throw new Error('resolver client unavailable');
      const result = await client.rpc(getAccessToken(), 'resolve_vehicle_lifecycle_identity', cleanInput);
      mapped = mapLifecycleResolutionResponse(result);
    } catch (_err) {
      mapped = { outcome: 'service_unavailable' };
    }
    const stale = generations.get(key) !== generation;
    if (!stale) latest.set(key, mapped);
    recordDiagnostic('resolution', {
      reason: resolveOptions.reason || 'consumer',
      outcome: mapped.outcome,
      stale,
      inputFields: Object.keys(cleanInput).sort(),
    });
    return mapped;
  }

  async function refreshTracked(reason = 'realtime') {
    const entries = [...tracked.values()];
    const results = await Promise.all(entries.map(async input => {
      const result = await resolve(input, { reason, track: false });
      const item = { input: { ...input }, result, reason };
      onRefresh(item);
      return item;
    }));
    return results;
  }

  function start() {
    if (subscription || typeof subscribe !== 'function') return;
    subscription = subscribe({
      onChange: async payload => {
        recordDiagnostic('realtime_change', { revision: payload && payload.new ? payload.new.revision : null });
        await refreshTracked('realtime_change');
      },
      onStatus: async status => {
        recordDiagnostic('realtime_status', { status });
        if (status === 'SUBSCRIBED') {
          if (disconnected) await refreshTracked('realtime_reconnect');
          disconnected = false;
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          disconnected = true;
        }
      },
    });
  }

  function stop() {
    if (subscription && typeof subscription.unsubscribe === 'function') subscription.unsubscribe();
    subscription = null;
    disconnected = false;
  }

  return {
    resolve,
    refreshTracked,
    start,
    stop,
    getLatest(input = {}) { return latest.get(lifecycleIdentityCacheKey(input)) || null; },
    getDiagnostics() { return diagnostics.map(item => ({ ...item })); },
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
