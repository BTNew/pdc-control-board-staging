'use strict';

(function vehicleLocationLifecycleModule() {

const PDC_BUSINESS_TIME_ZONE = 'Australia/Perth';
const YARD_HOLD_STATUSES = Object.freeze(new Set([
  'waiting pd2',
  'vehicle delayed',
  'awaiting tray fit',
  'vehicle waiting wholesale',
  'vehicle waiting for wholesale',
]));
const BODY_BUILDER_RELEASE_STATUS = 'delivered - at body builder';
const DEALER_COMPLETION_STATUS = 'delivered - at dealer';

function normalizeLifecycleStatus(value = '') {
  return String(value == null ? '' : value)
    .replace(/[\r\n]+/g, ' ')
    .replace(/[‐‑‒–—−]/g, '-')
    .replace(/\s*-\s*/g, ' - ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function lifecycleStatusFromVehicle(vehicle = {}) {
  return normalizeLifecycleStatus(
    vehicle.navisionSubLocationDescription
    || vehicle.toyotaStatus
    || vehicle.vehicle_status
    || vehicle.navisionLocationStatus
    || vehicle.locationStatus
    || '',
  );
}

function businessDateInTimeZone(now = new Date(), timeZone = PDC_BUSINESS_TIME_ZONE) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  const value = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

function lifecycleDateKey(value = '') {
  const text = String(value || '').trim();
  let match = text.match(/^(\d{4})-(\d{2})-(\d{2})(?:$|T)/);
  if (match) return `${match[1]}-${match[2]}-${match[3]}`;
  match = text.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/);
  if (!match) return '';
  const year = match[3].length === 2 ? `20${match[3]}` : match[3];
  return `${year}-${match[2].padStart(2, '0')}-${match[1].padStart(2, '0')}`;
}

function lifecycleEta(vehicle = {}) {
  return vehicle.navisionKewdaleEta || vehicle.etaAtKewdale || vehicle.eta_to_kewdale || vehicle.etaAtDealer || '';
}

function canonicalLifecycleLocation(value = '') {
  const clean = String(value || '').trim().toUpperCase();
  if (clean === 'COMPLETED') return 'Completed';
  if (['YH', 'IT', 'PMB', 'PIT', 'QC', 'RFT', 'OTHER'].includes(clean)) return clean === 'OTHER' ? 'Other' : clean;
  return '';
}

function hasPmbLifecycleLatch(vehicle = {}) {
  const current = canonicalLifecycleLocation(vehicle.current_location || vehicle.currentLocation || vehicle.pdcLocation || vehicle.manualLocation || '');
  return Boolean(
    vehicle.date_to_pmb || vehicle.dateToPmb || vehicle.pmbEnteredAt || vehicle.pmbTransferredAt
    || ['PMB', 'PIT', 'QC', 'RFT', 'Completed'].includes(current),
  );
}

function isPreYardHoldTwaStatus(status = '') {
  const normalized = normalizeLifecycleStatus(status);
  return normalized.includes('from twa') && (normalized.includes('despatch') || normalized.includes('dispatch'));
}

function resolveVehicleLifecycleLocation(vehicle = {}, options = {}) {
  const status = lifecycleStatusFromVehicle(vehicle);
  const current = canonicalLifecycleLocation(vehicle.current_location || vehicle.currentLocation || vehicle.pdcLocation || vehicle.manualLocation || '');
  const completed = String(vehicle.lifecycle_state || vehicle.lifecycleState || '').trim().toLowerCase() === 'completed'
    || vehicle.completedVehicle === true || current === 'Completed';
  const pmbLatched = hasPmbLifecycleLatch(vehicle);
  const businessDate = options.businessDate || businessDateInTimeZone(options.now || new Date(), options.timeZone || PDC_BUSINESS_TIME_ZONE);
  const etaDate = lifecycleDateKey(lifecycleEta(vehicle));

  if (completed) return { location: 'Completed', transition: 'preserve_completed', status, businessDate, etaDate, pmbLatched: true };
  if (status === DEALER_COMPLETION_STATUS) {
    return pmbLatched
      ? { location: 'Completed', transition: 'dealer_completed', status, businessDate, etaDate, pmbLatched }
      : { location: current || 'Other', transition: 'dealer_before_pmb_ignored', status, businessDate, etaDate, pmbLatched };
  }
  if (['RFT', 'QC', 'PIT'].includes(current)) return { location: current, transition: 'preserve_manual_progress', status, businessDate, etaDate, pmbLatched };
  if (pmbLatched) return { location: 'PMB', transition: 'preserve_pmb_latch', status, businessDate, etaDate, pmbLatched };
  if (status === BODY_BUILDER_RELEASE_STATUS) return { location: 'PMB', transition: 'released_to_pmb', status, businessDate, etaDate, pmbLatched: false };
  if (current === 'YH') return { location: 'YH', transition: 'preserve_yh_latch', status, businessDate, etaDate, pmbLatched: false };
  if (YARD_HOLD_STATUSES.has(status) && etaDate && etaDate < businessDate) {
    return { location: 'YH', transition: 'yard_hold_eta_passed', status, businessDate, etaDate, pmbLatched: false };
  }
  if (isPreYardHoldTwaStatus(status) && etaDate) {
    return { location: 'IT', transition: 'pre_yh_twa_eta', status, businessDate, etaDate, pmbLatched: false };
  }
  return { location: current || 'Other', transition: 'no_lifecycle_change', status, businessDate, etaDate, pmbLatched: false };
}

function applyFirstLifecycleMilestones(vehicle = {}, decision = {}, date = decision.businessDate || businessDateInTimeZone()) {
  const next = { ...vehicle };
  if (decision.location === 'PMB' && !(next.dateToPmb || next.date_to_pmb)) next.dateToPmb = date;
  if (decision.location === 'RFT' && !(next.dateToRft || next.date_to_rft)) next.dateToRft = date;
  if (decision.location === 'Completed' && !(next.deliveredToDealerDate || next.delivered_to_dealer_date)) next.deliveredToDealerDate = date;
  return next;
}

const exported = {
  PDC_BUSINESS_TIME_ZONE,
  YARD_HOLD_STATUSES,
  BODY_BUILDER_RELEASE_STATUS,
  DEALER_COMPLETION_STATUS,
  normalizeLifecycleStatus,
  lifecycleStatusFromVehicle,
  businessDateInTimeZone,
  lifecycleDateKey,
  lifecycleEta,
  hasPmbLifecycleLatch,
  resolveVehicleLifecycleLocation,
  applyFirstLifecycleMilestones,
};
if (typeof module !== 'undefined' && module.exports) module.exports = exported;
if (typeof window !== 'undefined') window.PDC_VEHICLE_LOCATION_LIFECYCLE = exported;
})();
