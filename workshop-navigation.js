'use strict';

/*
 * Dependency-free navigation helpers shared by Workshop tiles and search.
 * The module deliberately returns intents/state rather than touching the DOM;
 * app.js/workshop-planner.js may inject their own routing and highlight hooks.
 */

const WORK_BOOKINGS_VIEW = 'work-bookings';
const WORKSHOP_HIGHLIGHT_CLASS = 'workshop-navigation-highlight';
const WORKSHOP_PULSE_CLASS = 'workshop-navigation-pulse';
const WORKSHOP_REDUCED_MOTION_CLASS = 'workshop-navigation-pulse-reduced-motion';

function present(value) {
  return value !== undefined && value !== null && String(value).trim() !== '';
}

function firstPresent(object, keys) {
  for (const key of keys) {
    if (present(object && object[key])) return object[key];
  }
  return null;
}

function text(value) {
  return present(value) ? String(value).trim() : null;
}

function normalizeToken(value) {
  return text(value)?.toUpperCase() || null;
}

function normalizeBay(value) {
  const normalized = text(value);
  if (!normalized) return null;
  return /^\d+$/.test(normalized) ? String(Number(normalized)) : normalized.toUpperCase();
}

function normalizeInstant(value) {
  if (!present(value)) return null;
  const raw = String(value).trim();
  const parsed = Date.parse(raw);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : raw;
}

function dateKey(value) {
  if (!present(value)) return null;
  const raw = String(value).trim();
  const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  if (match) return match[1];
  const parsed = Date.parse(raw);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString().slice(0, 10) : raw;
}

/**
 * Convert a station or bay tile into a deterministic Vehicle Detail intent.
 * Unknown fields are omitted instead of becoming wildcard/undefined strings.
 */
function buildWorkBookingsNavigationIntent(tile = {}) {
  const station = text(firstPresent(tile, ['station', 'stationCode', 'stageCode', 'stage', 'station_id']));
  const bay = text(firstPresent(tile, ['bay', 'bayNumber', 'bayId', 'bay_number']));
  const vehicleId = text(firstPresent(tile, ['vehicleId', 'vehicle_id', 'sharedVehicleId']));
  const stockNumber = text(firstPresent(tile, ['stockNumber', 'stockNo', 'stock', 'stock_number']));
  const filters = {};
  if (station) filters.station = station;
  if (bay) filters.bay = bay;

  return Object.freeze({
    route: 'vehicle-detail',
    view: WORK_BOOKINGS_VIEW,
    tab: WORK_BOOKINGS_VIEW,
    vehicleId,
    stockNumber,
    filters: Object.freeze(filters),
  });
}

function bookingFields(booking = {}) {
  const start = firstPresent(booking, ['scheduledStartAt', 'scheduled_start_at', 'startAt', 'start', 'time']);
  return {
    bookingId: text(firstPresent(booking, ['bookingId', 'booking_id', 'id'])),
    vehicleId: text(firstPresent(booking, ['vehicleId', 'vehicle_id', 'sharedVehicleId'])),
    stockNumber: normalizeToken(firstPresent(booking, ['stockNumber', 'stockNo', 'stock', 'stock_number'])),
    station: normalizeToken(firstPresent(booking, ['station', 'stationCode', 'stageCode', 'stage', 'stage_code'])),
    bay: normalizeBay(firstPresent(booking, ['bay', 'bayNumber', 'bayId', 'bay_number'])),
    date: dateKey(firstPresent(booking, ['date', 'dateKey', 'bookingDate', 'scheduledDate']) || start),
    start: normalizeInstant(start),
    rawStart: text(start),
  };
}

function targetFields(result = {}) {
  const nested = result.booking && typeof result.booking === 'object' ? result.booking : {};
  const merged = Object.assign({}, result, nested);
  return bookingFields(merged);
}

/**
 * Resolve a stock-search result to one exact booking. A supplied locator is a
 * constraint, never a hint; ambiguous or absent matches return null.
 */
function resolveStockResultTarget(result = {}, bookings = []) {
  const wanted = targetFields(result);
  const constraints = ['bookingId', 'vehicleId', 'stockNumber', 'station', 'bay', 'date'];
  const hasConstraint = constraints.some(key => present(wanted[key])) || present(wanted.start) || present(wanted.rawStart);
  if (!hasConstraint) return null;

  const matches = (Array.isArray(bookings) ? bookings : []).filter(booking => {
    const candidate = bookingFields(booking);
    if (wanted.bookingId && candidate.bookingId !== wanted.bookingId) return false;
    if (wanted.vehicleId && candidate.vehicleId !== wanted.vehicleId) return false;
    if (wanted.stockNumber && candidate.stockNumber !== wanted.stockNumber) return false;
    if (wanted.station && candidate.station !== wanted.station) return false;
    if (wanted.bay && candidate.bay !== wanted.bay) return false;
    if (wanted.date && candidate.date !== wanted.date) return false;
    if (wanted.start && candidate.start !== wanted.start) return false;
    if (!wanted.start && wanted.rawStart && candidate.rawStart !== wanted.rawStart) return false;
    return true;
  });

  if (matches.length !== 1) return null;
  const selected = bookingFields(matches[0]);
  return Object.freeze({
    booking: matches[0],
    bookingId: selected.bookingId,
    vehicleId: selected.vehicleId,
    stockNumber: selected.stockNumber,
    station: selected.station,
    bay: selected.bay,
    date: selected.date,
    scheduledStartAt: selected.rawStart,
    filters: Object.freeze({
      ...(selected.station ? { station: selected.station } : {}),
      ...(selected.bay ? { bay: selected.bay } : {}),
      ...(selected.date ? { date: selected.date } : {}),
    }),
  });
}

function reducedMotionValue(value) {
  if (typeof value === 'function') return !!value();
  if (value && typeof value.matches === 'boolean') return value.matches;
  return !!value;
}

function highlightPresentation(prefersReducedMotion) {
  const reducedMotion = reducedMotionValue(prefersReducedMotion);
  return Object.freeze({
    active: true,
    reducedMotion,
    highlightClass: WORKSHOP_HIGHLIGHT_CLASS,
    pulseClass: reducedMotion ? WORKSHOP_REDUCED_MOTION_CLASS : WORKSHOP_PULSE_CLASS,
    animate: !reducedMotion,
  });
}

/**
 * Stateful stale-highlight replacement. Callbacks receive (target, state) and
 * are optional, allowing consumers to map the contract to DOM, canvas, etc.
 */
function createWorkshopHighlightController(options = {}) {
  const clearHighlight = typeof options.clearHighlight === 'function' ? options.clearHighlight : () => {};
  const applyHighlight = typeof options.applyHighlight === 'function' ? options.applyHighlight : () => {};
  let current = null;

  function clear() {
    if (!current) return null;
    const stale = current;
    current = null;
    clearHighlight(stale.target, stale.presentation);
    return stale;
  }

  function replace(target, callOptions = {}) {
    clear();
    if (!present(target)) return null;
    const motionPreference = Object.prototype.hasOwnProperty.call(callOptions, 'prefersReducedMotion')
      ? callOptions.prefersReducedMotion
      : options.prefersReducedMotion;
    current = Object.freeze({ target, presentation: highlightPresentation(motionPreference) });
    applyHighlight(current.target, current.presentation);
    return current;
  }

  return Object.freeze({
    replace,
    highlight: replace,
    clear,
    getCurrent: () => current,
  });
}

function numericHours(value) {
  if (value === '' || value === null || value === undefined) return null;
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}

/**
 * Manual/protected hours are authoritative, source hours are next, and AI is
 * fallback-only. Zero is a valid explicit estimate. Evidence explains both
 * the selected value and rejected/absent candidates without inventing hours.
 */
function projectWorkshopHours(input = {}) {
  const sourceEstimatedHours = numericHours(firstPresent(input, ['sourceEstimatedHours', 'source_estimated_hours']));
  const aiEstimatedHours = numericHours(firstPresent(input, ['aiEstimatedHours', 'ai_estimated_hours']));
  const protectedInput = firstPresent(input, ['protectedHours', 'protected_hours']);
  const manualInput = firstPresent(input, ['manualOverrideHours', 'manual_override_hours']);
  const protectedHours = numericHours(protectedInput);
  const manualOverrideHours = numericHours(manualInput);

  let schedulingHours = null;
  let rule = 'unavailable';
  let selectedField = null;
  if (manualOverrideHours !== null) {
    schedulingHours = manualOverrideHours;
    rule = 'manual_override';
    selectedField = 'manualOverrideHours';
  } else if (protectedHours !== null) {
    schedulingHours = protectedHours;
    rule = 'protected';
    selectedField = 'protectedHours';
  } else if (sourceEstimatedHours !== null) {
    schedulingHours = sourceEstimatedHours;
    rule = 'source';
    selectedField = 'sourceEstimatedHours';
  } else if (aiEstimatedHours !== null) {
    schedulingHours = aiEstimatedHours;
    rule = 'ai_fallback';
    selectedField = 'aiEstimatedHours';
  }

  return Object.freeze({
    sourceEstimatedHours,
    aiEstimatedHours,
    protectedHours,
    manualOverrideHours,
    schedulingHours,
    rule,
    evidence: Object.freeze({
      selectedField,
      precedence: Object.freeze(['manualOverrideHours', 'protectedHours', 'sourceEstimatedHours', 'aiEstimatedHours']),
      hasManualOverride: manualOverrideHours !== null,
      hasProtectedHours: protectedHours !== null,
      hasSourceEstimate: sourceEstimatedHours !== null,
      hasAiEstimate: aiEstimatedHours !== null,
    }),
  });
}

const workshopNavigation = Object.freeze({
  WORK_BOOKINGS_VIEW,
  WORKSHOP_HIGHLIGHT_CLASS,
  WORKSHOP_PULSE_CLASS,
  WORKSHOP_REDUCED_MOTION_CLASS,
  buildWorkBookingsNavigationIntent,
  resolveStockResultTarget,
  highlightPresentation,
  createWorkshopHighlightController,
  projectWorkshopHours,
});

if (typeof module !== 'undefined' && module.exports) module.exports = workshopNavigation;
if (typeof window !== 'undefined') window.WorkshopNavigation = workshopNavigation;
