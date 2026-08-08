'use strict';

/* Staging-only, read-only consumer of authenticated email vehicle imports. */
const PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
const PDC_EMAIL_VEHICLE_REVISION_TABLE = 'pdc_email_vehicle_revision';
const PDC_EMAIL_VEHICLE_SNAPSHOT_RPC = 'get_pdc_email_vehicle_location_snapshot';
const PDC_SUBLET_UPDATE_RPC = 'update_pdc_sublet_booking_field';
const PDC_PARTS_ETA_UPDATE_RPC = 'update_pdc_parts_eta';
const PDC_PARTS_ORDERED_RPC = 'mark_pdc_parts_ordered';
const PDC_VEHICLE_HISTORY_RPC = 'get_pdc_vehicle_provenance_history';
const PDC_SUBLET_CANONICAL_ERRORS = new Set(['version_conflict', 'workshop_booking_conflict', 'sublet_away']);
const WORK_FIELDS = Object.freeze({
  bus4x4: ['pdcRequiresBus4x4', 'pdcCompleteBus4x4'], tint: ['pdcRequiresTint', 'pdcCompleteTint'], hoist: ['pdcRequiresHoist', 'pdcCompleteHoist'], fitting: ['pdcRequiresFitting', 'pdcCompleteFitting'], fabrication: ['pdcRequiresFabrication', 'pdcCompleteFabrication'], electrical: ['pdcRequiresElectrical', 'pdcCompleteElectrical'], tyre: ['pdcRequiresTyre', 'pdcCompleteTyre'], sublet: ['pdcRequiresSublet', 'pdcCompleteSublet'], pitinspection: ['pdcRequiresPitInspection', 'pdcCompletePitInspection'], parts: ['pdcRequiresParts', 'pdcCompleteParts'],
});
function projectRef(url = '') { const match = String(url || '').trim().match(/^https:\/\/([a-z0-9]+)\.supabase\.co(?:\/|$)/i); return match ? match[1].toLowerCase() : ''; }
function identity(value = '') { return String(value || '').trim().toUpperCase().replace(/[\s-]+/g, ''); }
function subletResponseCode(body, status) {
  const direct = String(body?.code || body?.error || '').trim();
  if (PDC_SUBLET_CANONICAL_ERRORS.has(direct)) return direct;
  const message = String(body?.message || body?.details || '').trim();
  const match = message.match(/["']error["']\s*:\s*["']([a-z0-9_]+)["']/i);
  const extracted = String(match?.[1] || '').toLowerCase();
  return PDC_SUBLET_CANONICAL_ERRORS.has(extracted) ? extracted : (direct || `HTTP ${status}`);
}
function canonicalWorkKey(value = '') {
  const key = String(value || '').trim().toLowerCase().replace(/[^a-z0-9]/g, '');
  if (['pit', 'pitinspection', 'inspectionpit', 'pitinspect'].includes(key)) return 'pitinspection';
  if (['bus4x4', 'bus4wd', '4x4bus'].includes(key)) return 'bus4x4';
  if (['tyres', 'tire', 'tires'].includes(key)) return 'tyre';
  if (['part', 'partsrequired'].includes(key)) return 'parts';
  return key;
}
function mapServerVehicle(row = {}) {
  const mapped = {
    id: String(row.permanent_vehicle_id || row.id || ''), permanentVehicleId: String(row.permanent_vehicle_id || ''), stock: String(row.stock_number || '').trim(), vin: String(row.vin || '').trim(), jobCardNumber: String(row.job_card_number || '').trim(), jobcard: String(row.job_card_number || '').trim(), client: String(row.customer_name || '').trim(), vehicle: String(row.vehicle_description || '').trim(), salesperson: String(row.salesperson_reference || '').trim(), registration: String(row.registration || '').trim(), rego: String(row.registration || '').trim(), navisionKewdaleEta: row.eta_to_kewdale || '', etaAtDealer: row.eta_to_kewdale || '', pdcLocation: String(row.current_location || 'Other').trim() || 'Other', pdcSheetVisible: row.visible_on_board !== false, source: String(row.source_system || 'Authenticated email auto-import'), sourceRecordId: String(row.source_record_id || ''), updatedAt: row.updated_at || '', __emailVehicleServerAuthoritative: true, __emailVehicleReadOnly: true, __emailVehicleId: String(row.id || ''), __emailVehicleVersion: Number(row.version || 0), __subletBookingVersion: Number(row.sublet_booking?.version || 0),
  };
  for (const [requiredKey, completeKey] of Object.values(WORK_FIELDS)) { mapped[requiredKey] = false; mapped[completeKey] = false; }
  for (const item of Array.isArray(row.work_items) ? row.work_items : []) {
    const fields = WORK_FIELDS[canonicalWorkKey(item?.work_key)]; if (!fields) continue;
    mapped[fields[0]] = item.required === true; mapped[fields[1]] = item.completed === true;
    if (item.completed_at) mapped[`${fields[1]}At`] = item.completed_at;
    if (item.completed_by) mapped[`${fields[1]}By`] = item.completed_by;
  }
  const allowedOperationKeys = new Set(['bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'pitinspection', 'parts']);
  mapped.pdcEmailOperationLines = (Array.isArray(row.operation_lines) ? row.operation_lines : []).slice(0, 50).map(item => ({
    operation_line_id: String(item?.operation_line_id || '').trim().toLowerCase(),
    operation_no: String(item?.operation_no || '').trim().toUpperCase(),
    work_key: canonicalWorkKey(item?.work_key),
    job_card_number: String(item?.job_card_number || item?.jobCardNumber || '').trim().slice(0, 80),
    description: String(item?.description || '').trim().slice(0, 180),
    estimatedHours: item?.estimated_hours != null && item?.estimated_hours !== '' && Number.isFinite(Number(item.estimated_hours))
      ? Number(item.estimated_hours)
      : null,
    estimatedHoursSource: ['job_card', 'ai_estimate'].includes(String(item?.estimated_hours_source || '').trim().toLowerCase())
      ? String(item.estimated_hours_source).trim().toLowerCase()
      : null,
    source_uid: String(item?.source_uid || '').trim().slice(0, 100),
  })).filter(item => /^(?:OP(?:[1-9]|[1-9][0-9]{1,2})|PD[0-9]{3}-[A-F0-9]{8})$/.test(item.operation_no)
    && allowedOperationKeys.has(item.work_key) && item.description.length > 0);
  if (row.parts_required != null) mapped.pdcRequiresParts = row.parts_required === true;
  if (row.parts_completed != null) mapped.pdcCompleteParts = row.parts_completed === true;
  const partsUpdate = row.parts_update && typeof row.parts_update === 'object' ? row.parts_update : {};


  mapped.pdcPartsOrdered = partsUpdate.parts_ordered === true;
  mapped.pdcPartsStoppage = partsUpdate.parts_stoppage === true;
  mapped.pdcPartsStoppageReason = String(partsUpdate.parts_stoppage_reason || '');
  mapped.pdcPartsWorstEta = partsUpdate.worst_eta || '';
  mapped.pdcPartsPreviousWorstEta = partsUpdate.previous_worst_eta || '';
  mapped.pdcPartsWorstEtaUpdatedAt = partsUpdate.updated_at || '';

  const sublet = row.sublet_booking && typeof row.sublet_booking === 'object' ? row.sublet_booking : {};
  mapped.pmbSubletProvider = String(sublet.provider || '');
  mapped.pmbSubletProviderEmail = String(sublet.provider_email || '');
  mapped.pmbSubletPoSentDate = sublet.po_sent_date || '';
  mapped.pmbSubletBookingDate = sublet.booking_date || '';
  mapped.pmbSubletExpectedReturnDate = sublet.expected_return_date || '';
  mapped.pmbSubletActualReturnDate = sublet.actual_return_date || '';
  mapped.pmbSubletNotes = String(sublet.notes || '');
  mapped.pmbSubletEmailSent = sublet.email_sent === true;
  return mapped;
}
function rowIdentities(row = {}) { return { stock: identity(row.stock_number ?? row.stock), vin: identity(row.vin ?? row.VIN ?? row.chassis ?? row.chassisNo) }; }
function reconcileVehicleRows(localRows = [], serverRows = []) {
  const local = Array.isArray(localRows) ? localRows : [];
  const visibleServer = (Array.isArray(serverRows) ? serverRows : []).filter(row => row && row.visible_on_board !== false);
  const replaced = new Set(); const conflicts = new Set(); const additions = [];
  for (const serverRow of visibleServer) {
    const serverId = rowIdentities(serverRow);
    const stockMatches = serverId.stock ? local.map((row, i) => rowIdentities(row).stock === serverId.stock ? i : -1).filter(i => i >= 0) : [];
    const vinMatches = serverId.vin ? local.map((row, i) => rowIdentities(row).vin === serverId.vin ? i : -1).filter(i => i >= 0) : [];
    const candidates = new Set([...stockMatches, ...vinMatches]);
    const stockIndex = stockMatches.length === 1 ? stockMatches[0] : -1; const vinIndex = vinMatches.length === 1 ? vinMatches[0] : -1;
    const ambiguous = stockMatches.length > 1 || vinMatches.length > 1 || (stockIndex >= 0 && vinIndex >= 0 && stockIndex !== vinIndex);
    if (ambiguous) { candidates.forEach(index => conflicts.add(index)); continue; }
    const index = stockIndex >= 0 ? stockIndex : vinIndex; const mapped = mapServerVehicle(serverRow);
    if (index >= 0) { additions.push({ ...local[index], ...mapped }); replaced.add(index); } else additions.push(mapped);
  }
  const retained = local.filter((_row, index) => !replaced.has(index)).map((row, index) => conflicts.has(index) ? { ...row, __locationIdentityReadOnly: true, __emailVehicleIdentityConflict: true } : row);
  return { rows: retained.concat(additions), conflictCount: conflicts.size };
}
function createPdcEmailVehicleLocationService(options = {}) {
  const config = options.config || {};
  if (projectRef(config.url) !== PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF) throw new Error('Authenticated email vehicle locations are staging-only.');
  const getAccessToken = typeof options.getAccessToken === 'function' ? options.getAccessToken : () => null;
  const subscribeRealtime = typeof options.subscribeRealtime === 'function' ? options.subscribeRealtime : null;
  const request = options.fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  const url = String(config.url || '').replace(/\/$/, ''); const key = String(config.publishableKey || '');
  if (!request || !key) throw new Error('Authenticated email vehicle locations require the staging browser client.');
  async function snapshot() {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_EMAIL_VEHICLE_SNAPSHOT_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}' });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || `HTTP ${response.status}`, data: null };
      return { ok: true, code: body.code || 'ok', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'snapshot_unavailable', data: null }; }
  }
  async function updateSublet(vehicleId = '', expectedVersion = 0, field = '', value = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_SUBLET_UPDATE_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0, p_field: field, p_value: String(value ?? '') }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: subletResponseCode(body, response.status), data: body?.data || null };
      return { ok: true, code: body.code || 'updated', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'sublet_update_unavailable', data: null }; }
  }
  async function updatePartsEta(vehicleId = '', expectedVersion = 0, value = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_PARTS_ETA_UPDATE_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0, p_worst_eta: String(value || '') || null }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'updated', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'parts_eta_update_unavailable', data: null }; }
  }
  async function markPartsOrdered(vehicleId = '', expectedVersion = 0) {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_PARTS_ORDERED_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0 }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'updated', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'parts_ordered_update_unavailable', data: null }; }
  }
  async function vehicleHistory(vehicleId = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_VEHICLE_HISTORY_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'ok', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'vehicle_history_unavailable', data: null }; }
  }
  function subscribe(onRevision) {
    if (!subscribeRealtime) return { unsubscribe() {} };
    return subscribeRealtime(PDC_EMAIL_VEHICLE_REVISION_TABLE, event => { if (typeof onRevision === 'function') onRevision(event?.new?.revision ?? null, event); });
  }
  return { authority: 'supabase_staging_authenticated_email_vehicle', snapshot, updateSublet, updatePartsEta, markPartsOrdered, vehicleHistory, subscribe };
}
const exported = { PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF, PDC_EMAIL_VEHICLE_REVISION_TABLE, PDC_EMAIL_VEHICLE_SNAPSHOT_RPC, PDC_SUBLET_UPDATE_RPC, PDC_PARTS_ETA_UPDATE_RPC, PDC_PARTS_ORDERED_RPC, PDC_VEHICLE_HISTORY_RPC, canonicalWorkKey, mapServerVehicle, reconcileVehicleRows, createPdcEmailVehicleLocationService };
if (typeof module !== 'undefined' && module.exports) module.exports = exported;
if (typeof window !== 'undefined') window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE = exported;
