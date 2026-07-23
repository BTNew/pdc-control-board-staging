'use strict';

/*
 * Staging-only Shared Navision Backend Store client.
 *
 * The normal staging upload UI uses this service for preview/apply. Existing
 * browser-local data remains authoritative and is never mutated by this client.
 */

const NAVISION_STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
const NAVISION_REVISION_TABLE = 'navision_backend_revision';
const NAVISION_SOURCE_SYSTEM = 'microsoft_navision';
const NAVISION_DEALER_CODES = Object.freeze(['14450', '37047']);

function navisionProjectRefFromUrl(url = '') {
  const match = String(url).trim().match(/^https:\/\/([a-z0-9]+)\.supabase\.co(?:\/|$)/i);
  return match ? match[1].toLowerCase() : '';
}

function createNavisionRpcClient(config, fetchImpl) {
  const url = String(config?.url || '').replace(/\/$/, '');
  const publishableKey = String(config?.publishableKey || '');
  const projectRef = navisionProjectRefFromUrl(url);
  if (projectRef !== NAVISION_STAGING_PROJECT_REF) {
    throw new Error(`Shared Navision tooling is staging-only; expected ${NAVISION_STAGING_PROJECT_REF}, received ${projectRef || 'unknown project'}.`);
  }
  if (!publishableKey) throw new Error('Shared Navision tooling requires a staging publishable key.');
  const fetchFn = fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  if (!fetchFn) throw new Error('Shared Navision tooling has no fetch implementation.');

  async function rpc(accessToken, name, params = {}) {
    if (!accessToken) return { ok: false, status: 401, body: { ok: false, error: 'not_authenticated' } };
    const response = await fetchFn(`${url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(params),
    });
    let body = null;
    try { body = await response.json(); } catch { body = null; }
    return { ok: response.ok, status: response.status, body };
  }
  return { projectRef, rpc };
}

function createNavisionBackendService(options = {}) {
  const client = options.client || createNavisionRpcClient(options.config, options.fetchImpl);
  const configuredRef = navisionProjectRefFromUrl(options.config?.url);
  const suppliedRefs = [options.projectRef, client.projectRef, configuredRef].filter(Boolean);
  if (!suppliedRefs.length || suppliedRefs.some(ref => ref !== NAVISION_STAGING_PROJECT_REF)) {
    throw new Error(`Shared Navision tooling is staging-only; expected ${NAVISION_STAGING_PROJECT_REF}.`);
  }
  const projectRef = NAVISION_STAGING_PROJECT_REF;
  const getAccessToken = typeof options.getAccessToken === 'function' ? options.getAccessToken : () => null;
  const subscribeRealtime = typeof options.subscribeRealtime === 'function' ? options.subscribeRealtime : null;

  async function call(name, params) {
    const response = await client.rpc(getAccessToken(), name, params);
    if (!response.ok || !response.body || response.body.ok === false) {
      const reason = response.body?.code || response.body?.error || response.body?.message || `HTTP ${response.status}`;
      return { ok: false, error: reason, code: response.body?.code || null, status: response.status, data: response.body || null };
    }
    return { ok: true, status: response.status, data: response.body };
  }

  async function preview(rows, metadata = {}) {
    if (!Array.isArray(rows)) return { ok: false, error: 'rows_must_be_array' };
    const sourceSystem = String(metadata.sourceSystem || NAVISION_SOURCE_SYSTEM).trim().toLowerCase();
    const dealerCode = String(metadata.dealerCode || '').trim();
    if (sourceSystem !== NAVISION_SOURCE_SYSTEM) return { ok: false, error: 'invalid_source_system' };
    if (!NAVISION_DEALER_CODES.includes(dealerCode)) return { ok: false, error: 'invalid_dealer_code' };
    return call('preview_navision_backend_import', {
      p_rows: rows,
      p_source_system: sourceSystem,
      p_dealer_code: dealerCode,
      p_source_name: String(metadata.sourceName || 'navision.json').slice(0, 255),
      p_source_timestamp: metadata.sourceTimestamp || null,
    });
  }

  async function apply(rows, previewResult, options = {}) {
    if (options.confirmed !== true) return { ok: false, error: 'explicit_confirmation_required' };
    const sourceSystem = String(options.sourceSystem || NAVISION_SOURCE_SYSTEM).trim().toLowerCase();
    const dealerCode = String(options.dealerCode || '').trim();
    if (sourceSystem !== NAVISION_SOURCE_SYSTEM) return { ok: false, error: 'invalid_source_system' };
    if (!NAVISION_DEALER_CODES.includes(dealerCode)) return { ok: false, error: 'invalid_dealer_code' };
    const previewData = previewResult?.data?.data || previewResult?.data;
    if (!previewData?.preview_hash || !previewData?.source_hash || !Number.isInteger(previewData?.base_revision)) {
      return { ok: false, error: 'valid_preview_required' };
    }
    if (previewData.blocking === true) return { ok: false, error: 'preview_has_blocking_issues' };
    if (!options.idempotencyKey) return { ok: false, error: 'idempotency_key_required' };
    return call('apply_navision_backend_import', {
      p_idempotency_key: String(options.idempotencyKey),
      p_rows: rows,
      p_source_system: sourceSystem,
      p_dealer_code: dealerCode,
      p_source_name: String(options.sourceName || 'navision.json').slice(0, 255),
      p_source_timestamp: options.sourceTimestamp || null,
      p_source_hash: previewData.source_hash,
      p_preview_hash: previewData.preview_hash,
      p_expected_revision: previewData.base_revision,
    });
  }

  function scopedPageParams(scope = {}, cursor = {}, limit = 250, expectedRevision = null) {
    const sourceSystem = String(scope.sourceSystem || NAVISION_SOURCE_SYSTEM).trim().toLowerCase();
    const dealerCode = String(scope.dealerCode || '').trim();
    if (sourceSystem !== NAVISION_SOURCE_SYSTEM) return { ok: false, error: 'invalid_source_system' };
    if (!NAVISION_DEALER_CODES.includes(dealerCode)) return { ok: false, error: 'invalid_dealer_code' };
    const sourceRecordId = String(cursor?.sourceRecordId || '').trim();
    const recordId = String(cursor?.recordId || '').trim();
    if (Boolean(sourceRecordId) !== Boolean(recordId)) return { ok: false, error: 'invalid_cursor' };
    return { ok: true, params: {
      p_source_system: sourceSystem,
      p_dealer_code: dealerCode,
      p_after_source_record_id: sourceRecordId || null,
      p_after_record_id: recordId || null,
      p_page_size: Math.max(1, Math.min(500, Number(limit) || 250)),
      p_expected_revision: expectedRevision,
    } };
  }
  const snapshot = (scope = {}, cursor = {}, limit = 250, expectedRevision = null) => {
    const page = scopedPageParams(scope, cursor, limit, expectedRevision);
    return page.ok ? call('get_navision_backend_snapshot', page.params) : Promise.resolve(page);
  };
  const visibleSnapshot = (scope = {}, cursor = {}, limit = 250, expectedRevision = null) => {
    const sourceSystem = String(scope.sourceSystem || NAVISION_SOURCE_SYSTEM).trim().toLowerCase();
    const dealerCode = String(scope.dealerCode || '').trim();
    if (sourceSystem !== NAVISION_SOURCE_SYSTEM) return Promise.resolve({ ok: false, error: 'invalid_source_system' });
    if (!NAVISION_DEALER_CODES.includes(dealerCode)) return Promise.resolve({ ok: false, error: 'invalid_dealer_code' });
    const recordId = String(cursor?.recordId || '').trim();
    if (recordId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(recordId)) {
      return Promise.resolve({ ok: false, error: 'invalid_cursor' });
    }
    return call('get_navision_visible_snapshot', {
      p_source_system: sourceSystem,
      p_dealer_code: dealerCode,
      p_after_record_id: recordId || null,
      p_page_size: Math.max(1, Math.min(500, Number(limit) || 250)),
      p_expected_revision: expectedRevision,
    });
  };
  const exportRecords = (scope = {}, cursor = {}, limit = 250, expectedRevision = null) => {
    const page = scopedPageParams(scope, cursor, limit, expectedRevision);
    return page.ok ? call('export_navision_backend_records', page.params) : Promise.resolve(page);
  };
  const reconciliation = (batchId, offset = 0, limit = 250) => call('get_navision_reconciliation_report', {
    p_batch_id: batchId,
    p_after_row_index: Math.max(0, Number(offset) || 0),
    p_page_size: Math.max(1, Math.min(500, Number(limit) || 250)),
  });
  const rollback = (batchId, expectedRevision, idempotencyKey) => call('rollback_navision_backend_import', {
    p_idempotency_key: String(idempotencyKey || ''),
    p_target_batch_id: batchId,
    p_expected_revision: expectedRevision,
  });
  const link = (recordId, canonicalVehicleId, expectedRevision, idempotencyKey) => call('link_navision_backend_record', {
    p_idempotency_key: String(idempotencyKey || ''),
    p_backend_record_id: recordId,
    p_canonical_vehicle_id: canonicalVehicleId || null,
    p_expected_revision: expectedRevision,
  });

  function subscribe(onRevision) {
    if (!subscribeRealtime) return { unsubscribe() {} };
    return subscribeRealtime(NAVISION_REVISION_TABLE, {
      onChange: event => onRevision(event?.new?.revision ?? null, event),
    });
  }

  return {
    projectRef,
    authority: 'staging_shared_navision_backend_only',
    browserLocalAuthorityCutover: false,
    preview,
    apply,
    snapshot,
    visibleSnapshot,
    exportRecords,
    reconciliation,
    rollback,
    link,
    subscribe,
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { NAVISION_STAGING_PROJECT_REF, NAVISION_REVISION_TABLE, NAVISION_SOURCE_SYSTEM, NAVISION_DEALER_CODES, navisionProjectRefFromUrl, createNavisionRpcClient, createNavisionBackendService };
}
if (typeof window !== 'undefined') {
  window.PDC_NAVISION_BACKEND_SERVICE = { NAVISION_STAGING_PROJECT_REF, NAVISION_REVISION_TABLE, NAVISION_SOURCE_SYSTEM, NAVISION_DEALER_CODES, createNavisionRpcClient, createNavisionBackendService };
}
