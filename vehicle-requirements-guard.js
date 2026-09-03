'use strict';

const REQUIREMENT_KEYS = Object.freeze([
  'bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical',
  'tyre', 'pitInspection', 'sublet', 'parts',
]);

const ACTIVE_BOOKING_STATUSES = new Set(['queued', 'planned', 'started', 'stoppage']);

const WORKSHOP_STAGE_BY_WORK_KEY = Object.freeze({
  bus4x4: 'BUS_4X4',
  tint: 'TINT',
  hoist: 'HOIST',
  fitting: 'FITTING',
  fabrication: 'FABRICATION',
  electrical: 'ELECTRICAL',
  tyre: 'TYRE',
  pitInspection: 'PIT_INSPECTION',
});

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

function normalizedWorkKey(value) {
  const compact = clean(value).toLowerCase().replace(/[^a-z0-9]+/g, '');
  return REQUIREMENT_KEYS.find(key => key.toLowerCase() === compact) || '';
}

function normalizeVehicleIdentity(value = '') {
  const normalized = clean(value).toUpperCase().replace(/[\s-]+/g, '');
  return (/^[A-HJ-NPR-Z0-9]{17}$/.test(normalized) || /^REBHV1[0-9]{8}$/.test(normalized))
    ? normalized
    : '';
}

function bookingMatchesWorkKey(booking = {}, workKey = '') {
  const key = normalizedWorkKey(workKey);
  if (!key) return false;
  const bookingKey = normalizedWorkKey(booking.work_key || booking.workKey);
  if (bookingKey) return bookingKey === key;
  const stage = clean(booking.stage_code || booking.stageCode || booking.stage).toUpperCase().replace(/[ -]+/g, '_');
  return Boolean(WORKSHOP_STAGE_BY_WORK_KEY[key] && stage === WORKSHOP_STAGE_BY_WORK_KEY[key]);
}

/**
 * Project one authoritative department state for every Control Board surface.
 * Required/complete flags, active planner bookings, Parts ordering and Sublet
 * bookings all enter here instead of being reinterpreted by each renderer.
 */
function projectWorkState({ workKey = '', required = false, completed = false, bookings = [], partsOrdered = false, subletBookings = [] } = {}) {
  const key = normalizedWorkKey(workKey);
  if (completed === true) return Object.freeze({ state: 'completed', marker: '✓', label: 'Completed' });
  const activeWorkshopBooking = Array.isArray(bookings) && bookings.some(booking => (
    booking
    && booking.deleted_at == null
    && booking.deletedAt == null
    && ACTIVE_BOOKING_STATUSES.has(clean(booking.status).toLowerCase())
    && bookingMatchesWorkKey(booking, key)
  ));
  const activeSubletBooking = key === 'sublet' && Array.isArray(subletBookings) && subletBookings.some(booking => (
    booking
    && booking.deleted_at == null
    && booking.deletedAt == null
    && ['active', 'booked', 'planned', 'started'].includes(clean(booking.status).toLowerCase())
  ));
  if (required === true && ((key === 'parts' && partsOrdered === true) || activeWorkshopBooking || activeSubletBooking)) {
    return Object.freeze({ state: 'booked', marker: '!', label: key === 'parts' ? 'Ordered' : 'Booked' });
  }
  if (required === true) return Object.freeze({ state: 'required', marker: '•', label: 'Required' });
  return Object.freeze({ state: 'none', marker: '–', label: 'Not required' });
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
  normalizeVehicleIdentity,
  mergeRequirementPatch,
  projectWorkState,
  bookingDateForVehicle,
  partsRiskState,
  exactBookingNavigationTarget,
  deleteConfirmationIncludes,
});

if (typeof module !== 'undefined' && module.exports) module.exports = guard;
if (typeof window !== 'undefined') window.VehicleRequirementsGuard = guard;
