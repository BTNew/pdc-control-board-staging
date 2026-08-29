'use strict';

const REQUIREMENT_KEYS = Object.freeze([
  'bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical',
  'tyre', 'pitInspection', 'sublet', 'parts',
]);

const ACTIVE_BOOKING_STATUSES = new Set(['queued', 'planned', 'started', 'stoppage']);

function clean(value) {
  return value === null || value === undefined ? '' : String(value).trim();
}

function canonicalDate(value) {
  const raw = clean(value);
  const iso = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  if (iso) return iso[1];
  const au = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  return au ? `${au[3]}-${String(au[2]).padStart(2, '0')}-${String(au[1]).padStart(2, '0')}` : '';
}

function requirementState(value) {
  const state = clean(value).toLowerCase();
  return ['none', 'required', 'complete'].includes(state) ? state : null;
}

/**
 * Merge a submitted requirement patch without interpreting omission as a
 * destructive instruction. This is deliberately UUID-independent because
 * work-state keys are canonical department keys, while operation mutations
 * use the separate exact UUID contract.
 */
function mergeRequirementPatch(current = {}, submitted = {}) {
  if (!submitted || typeof submitted !== 'object' || Array.isArray(submitted)) {
    return { ok: false, error: 'invalid_work_states' };
  }
  const unknown = Object.keys(submitted).filter(key => !REQUIREMENT_KEYS.includes(key));
  if (unknown.length) return { ok: false, error: 'invalid_work_state_keys', unknown };
  const next = { ...current };
  for (const key of Object.keys(submitted)) {
    const state = requirementState(submitted[key]);
    if (!state) return { ok: false, error: 'invalid_work_state', workKey: key };
    next[key] = state;
  }
  return Object.freeze({ ok: true, value: Object.freeze(next), patchedKeys: Object.freeze(Object.keys(submitted)) });
}

function bookingDateForVehicle(vehicle = {}, extraBookings = []) {
  const candidates = [
    ...(Array.isArray(vehicle.workshopBookings) ? vehicle.workshopBookings : []),
    ...(Array.isArray(vehicle.__workshopBookings) ? vehicle.__workshopBookings : []),
    ...(Array.isArray(vehicle.pdcWorkshopBookings) ? vehicle.pdcWorkshopBookings : []),
    ...(Array.isArray(extraBookings) ? extraBookings : []),
  ];
  const dates = candidates
    .filter(booking => ACTIVE_BOOKING_STATUSES.has(clean(booking.status).toLowerCase()) && booking.deleted_at == null && booking.deletedAt == null)
    .map(booking => canonicalDate(booking.scheduled_start_at || booking.scheduledStartAt || booking.bookingDate || booking.date))
    .filter(Boolean)
    .sort();
  return dates[0] || '';
}

function partsRiskState({ partsEta = '', partsComplete = false, partsStoppage = false, vehicle = {}, bookings = [] } = {}) {
  const eta = canonicalDate(partsEta);
  const bookingDate = bookingDateForVehicle(vehicle, bookings);
  if (partsComplete === true) return Object.freeze({ risk: false, reason: 'parts_complete', eta, bookingDate });
  if (!eta) return Object.freeze({ risk: false, reason: 'parts_eta_missing', eta, bookingDate });
  if (!bookingDate) return Object.freeze({ risk: false, reason: 'booking_date_missing', eta, bookingDate });
  return Object.freeze({
    risk: eta > bookingDate,
    reason: partsStoppage === true ? 'parts_stoppage' : 'scheduled_booking_date',
    eta,
    bookingDate,
  });
}

function exactBookingNavigationTarget({ bookingId, vehicleId, stockNumber, department, date, bay } = {}) {
  const target = {
    bookingId: clean(bookingId),
    vehicleId: clean(vehicleId),
    stockNumber: clean(stockNumber),
    department: clean(department).toUpperCase(),
    date: canonicalDate(date),
    bay: clean(bay),
  };
  if (Object.values(target).some(value => !value)) return null;
  if (!/^[0-9a-f-]{36}$/i.test(target.bookingId) || !/^[0-9a-f-]{36}$/i.test(target.vehicleId)) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(target.date)) return null;
  return Object.freeze({ ...target, view: `planner-${target.department.toLowerCase()}` });
}

function deleteConfirmationIncludes({ confirmation = '', operationNo = '', description = '', department = '' } = {}) {
  const text = clean(confirmation).toLowerCase();
  return Boolean(text && clean(operationNo) && clean(description) && clean(department)
    && text.includes(clean(operationNo).toLowerCase())
    && text.includes(clean(description).toLowerCase())
    && text.includes(clean(department).toLowerCase()));
}

const guard = Object.freeze({
  REQUIREMENT_KEYS,
  mergeRequirementPatch,
  bookingDateForVehicle,
  partsRiskState,
  exactBookingNavigationTarget,
  deleteConfirmationIncludes,
});

if (typeof module !== 'undefined' && module.exports) module.exports = guard;
if (typeof window !== 'undefined') window.VehicleRequirementsGuard = guard;
