'use strict';

/* Exact authenticated vehicle-card identity and one bounded save retry. */

function vehicleIdentityValue(row = {}) {
  return String(row.__emailVehicleId || row.sharedVehicleId || row.canonicalVehicleId || row.id || row.permanent_vehicle_id || row.permanentVehicleId || '').trim();
}

function vehicleIdentityValues(row = {}) {
  return new Set([
    row.__emailVehicleId,
    row.sharedVehicleId,
    row.canonicalVehicleId,
    row.id,
    row.permanent_vehicle_id,
    row.permanentVehicleId,
  ].map(value => String(value || '').trim()).filter(Boolean));
}

function vehicleStockValue(row = {}) {
  return String(row.stock_number || row.stock || row.stockNumber || row.batch || '').trim();
}

function resolveExactAuthoritativeVehicleRow(rows = [], identity = {}) {
  const canonicalId = String(identity.canonicalId || '').trim();
  const stock = String(identity.stock || identity.stockBaseline || '').trim();
  if (!canonicalId || !stock) return { ok: false, code: 'invalid_identity', row: null };
  const canonicalRows = (Array.isArray(rows) ? rows : []).filter(row => vehicleIdentityValues(row).has(canonicalId));
  if (!canonicalRows.length) return { ok: false, code: 'not_found', row: null };
  const stocks = new Set(canonicalRows.map(vehicleStockValue).filter(Boolean));
  const exactRows = canonicalRows.filter(row => vehicleStockValue(row) === stock);
  if (stocks.size > 1) return { ok: false, code: 'conflicting_stock', row: null };
  if (canonicalRows.length > 1 || exactRows.length > 1) return { ok: false, code: 'duplicate_identity', row: null };
  if (!exactRows.length) return { ok: false, code: 'stock_mismatch', row: null };
  return { ok: true, code: 'exact_match', row: exactRows[0] };
}

const RETRYABLE_SAVE_CODES = new Set(['version_conflict', 'vehicle_version_conflict', 'stale_projection', 'authority_superseded']);

async function saveWithOneExactRebindRetry({ vehicle = {}, changes = {}, save, refreshAndRebind } = {}) {
  if (typeof save !== 'function') return { ok: false, code: 'save_unavailable' };
  const first = await save(vehicle, changes);
  if (!first || first.ok === true || !RETRYABLE_SAVE_CODES.has(String(first.code || first.error || '').trim())) return first || { ok: false, code: 'save_failed' };
  if (typeof refreshAndRebind !== 'function') return first;
  const rebound = await refreshAndRebind();
  if (rebound?.ok === false && rebound.code) return { ok: false, code: rebound.code, data: null };
  if (!rebound || rebound.ok !== true || !rebound.vehicle) return first;
  const oldId = vehicleIdentityValue(vehicle);
  const oldStock = vehicleStockValue(vehicle);
  if (!oldId || !oldStock || vehicleIdentityValue(rebound.vehicle) !== oldId || vehicleStockValue(rebound.vehicle) !== oldStock) {
    return { ok: false, code: 'identity_changed', data: null };
  }
  return save(rebound.vehicle, changes);
}

const exported = {
  RETRYABLE_SAVE_CODES,
  resolveExactAuthoritativeVehicleRow,
  saveWithOneExactRebindRetry,
};
if (typeof module !== 'undefined' && module.exports) module.exports = exported;
if (typeof window !== 'undefined') window.PDC_VEHICLE_MODAL_IDENTITY = exported;
