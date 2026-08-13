'use strict';
const assert = require('assert');

global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.cleanNavisionText = value => String(value || '').trim();
global.escapeHtml = value => String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
global.vehicleKey = vehicle => vehicle.id;
global.isPdcBlocked = () => false;
global.vehiclePdcLocation = vehicle => vehicle.current_location || 'PMB';
global.statusCategory = () => 'pmb';
global.partsDepartmentStatus = () => 'notrequired';
global.partsDepartmentStatusLabel = () => 'Not required';
global.partsWorstEtaLabel = () => '';
global.partsWorstEtaCountdownLabel = () => '';
global.vehicleJobcardNumber = vehicle => vehicle.jobCard || '';
global.displayStockNumber = vehicle => vehicle.stock || '';
global.vehicleCustomerName = () => '';
global.pmbStageLabel = stage => ({ HOIST: 'Hoist', FITTING: 'Fitting' }[stage] || stage);
global.pmbStageJobDef = stage => ({ key: String(stage || '').toLowerCase(), label: String(stage || '') });
global.pmbJobDefForStage = global.pmbStageJobDef;
global.pdcRequirementDefinitions = () => [
  { key: 'hoist', label: 'Hoist' },
  { key: 'sublet', label: 'Sublet' },
];
global.pdcJobRequired = (vehicle, def) => vehicle.pmbJobs?.[def.key]?.required === true;
global.pdcJobComplete = (vehicle, def) => vehicle.pmbJobs?.[def.key]?.completed === true;
global.parseIsoTimestamp = value => { const d = new Date(value); return Number.isNaN(d.getTime()) ? null : d; };

global.app = { data: [] };
const planner = require('./workshop-planner.js');

const bookedOutstanding = {
  id: 'vehicle-1', stock: 'SANITIZED-1', current_location: 'PMB',
  pmbJobs: { hoist: { required: true, completed: false }, sublet: { required: true, completed: false } },
  __workshopOutstanding: { existingBooking: true, scheduleEnabled: true, disabledReason: '' },
};
const html = planner.workshopQueueCardHtml(bookedOutstanding, 'HOIST', '2026-07-23', []);
assert(html.includes('Requirements: Hoist, Sublet'), 'left candidate column must show Sublet as a requirement');
assert(html.includes('Active booking exists · shown here because the requirement remains outstanding'), 'booked outstanding candidate must remain discoverable');
assert(html.includes('draggable="false"') && html.includes('Already booked'), 'booked candidate must not create a duplicate booking');
assert(!html.includes('data-workshop-best-slot-vehicle'), 'booked candidate must not offer another best slot');

const authorityBlocked = {
  id: 'vehicle-2', stock: 'SANITIZED-2', current_location: 'Other',
  pmbJobs: { hoist: { required: true, completed: false } },
  __workshopOutstanding: { existingBooking: false, scheduleEnabled: false, disabledReason: 'location_ineligible' },
};
const blockedHtml = planner.workshopQueueCardHtml(authorityBlocked, 'HOIST', '2026-07-23', []);
assert(blockedHtml.includes('draggable="false"'), 'authoritative ineligible candidate must not be draggable');
assert(blockedHtml.includes('disabled') && blockedHtml.includes('Vehicle location is not eligible'), 'authoritative location rejection must disable scheduling with a clear reason');
assert(blockedHtml.includes('workshop-scheduling-unavailable-reason'), 'authoritative disabled reason must be visible on the card, not title-only');
assert(!blockedHtml.includes('data-workshop-best-slot-vehicle'), 'authoritative ineligible candidate must not offer Best slot');

const sanitized = planner.workshopSnapshotVehicleToPlannerRow(
  { id: 'safe-1', stock_number: 'SAFE-1', customer_name: 'CUSTOMER-SENTINEL', toyotaCustomer: 'TOYOTA-SENTINEL', dealerCustomer: 'DEALER-SENTINEL', notes: 'VEHICLE-NOTES-SENTINEL' },
  [{ vehicle_id: 'safe-1', work_key: 'sublet', required: true, completed: false, notes: 'WORK-NOTES-SENTINEL' }],
  'HOIST'
);
assert.strictEqual(sanitized.client, 'CUSTOMER-SENTINEL', 'operator/admin station snapshot must retain the approved customer name');
assert.strictEqual(sanitized.customerName, 'CUSTOMER-SENTINEL', 'planner tile customer alias must retain the approved customer name');
assert.strictEqual(sanitized.pmbJobs.sublet.notes, '', 'work-item notes must be discarded');
assert(!('toyotaCustomer' in sanitized) && !('dealerCustomer' in sanitized) && !('notes' in sanitized), 'planner DTO must be an explicit allowlist');

global.app.data = [{ id: 'safe-1', stock: 'SAFE-1', toyotaCustomer: 'LOCAL-CUSTOMER-SENTINEL', dealerCustomer: 'LOCAL-DEALER-SENTINEL', notes: 'LOCAL-NOTES-SENTINEL', pmbJobs: { hoist: { required: true, completed: false } } }];
global.window = {
  __activeWorkshopPlannerStage: 'HOIST',
  PDC_SUPABASE_CONFIG: {},
  workshopSharedModeEnabled: () => true,
  __workshopDataService: {
    isEnabled: () => true,
    getLastSnapshot: () => ({
      vehicles: [{ id: 'safe-1', stock_number: 'SAFE-1', current_location: 'PMB', customer_name: 'SERVER-CUSTOMER-SENTINEL', notes: 'SERVER-NOTES-SENTINEL' }],
      work_items: [{ vehicle_id: 'safe-1', work_key: 'hoist', required: true, completed: false }],
      bookings: [],
      outstanding_candidates: [{ vehicle_id: 'safe-1', existing_booking: false, schedule_enabled: true, disabled_reason: null, requirements: [{ vehicle_id: 'safe-1', work_key: 'hoist', required: true, completed: false, completed_at: null }] }],
    }),
  },
};
const hydrated = planner.workshopPlannerVehiclesForStage('HOIST')[0];
assert(hydrated && hydrated.id === 'safe-1', 'authoritative candidate must hydrate');
assert.strictEqual(hydrated.customerName, 'SERVER-CUSTOMER-SENTINEL', 'authoritative operator/admin hydration must retain the approved customer name');
for (const sentinel of ['LOCAL-CUSTOMER-SENTINEL','LOCAL-DEALER-SENTINEL','LOCAL-NOTES-SENTINEL','SERVER-NOTES-SENTINEL']) {
  assert(!JSON.stringify(hydrated).includes(sentinel), `canonical hydration leaked ${sentinel}`);
}

const source = require('fs').readFileSync(require('path').join(__dirname, 'workshop-planner.js'), 'utf8');
assert(source.includes('const queue = unscheduled;'), 'candidate panel must contain only actionable vehicles not already assigned to a station bay');
assert(source.includes('const unscheduled = outstanding.filter'), 'unscheduled must be measured from authoritative active-booking state');
assert(source.includes('${selectedDateBookingCount} bookings on selected date'), 'calendar count must use the canonical selected-date measurement');
assert.strictEqual(planner.workshopSelectedDateBookingCount([{ id: 1 }, { id: 2 }], [{ id: 3 }]), 3, 'completed bookings must remain in local selected-date totals');
assert.strictEqual(planner.workshopSelectedDateBookingCount([{ id: 1 }], [{ id: 2 }], { counts: { selected_date_bookings: 7 } }, true), 7, 'dedicated planner must use the authoritative snapshot count');
assert(source.includes('<strong>Outstanding candidates · Admin / Unallocated vehicle pills</strong>'), 'left panel must retain canonical semantics and identify draggable pills');

console.log('Planner outstanding/unscheduled/selected-date UI semantics passed');
