'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const plannerSource = fs.readFileSync('workshop-planner.js', 'utf8');
const appSource = fs.readFileSync('app.js', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');
const eligibility = require('./workshop-eligibility.js');

function extractFunction(name) {
  const start = plannerSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  let parens = 0;
  let open = -1;
  for (let index = plannerSource.indexOf('(', start); index < plannerSource.length; index += 1) {
    if (plannerSource[index] === '(') parens += 1;
    if (plannerSource[index] === ')' && --parens === 0) {
      open = plannerSource.indexOf('{', index);
      break;
    }
  }
  assert.ok(open >= 0, `${name} body exists`);
  let depth = 0;
  for (let index = open; index < plannerSource.length; index += 1) {
    if (plannerSource[index] === '{') depth += 1;
    if (plannerSource[index] === '}' && --depth === 0) return plannerSource.slice(start, index + 1);
  }
  throw new Error(`unterminated ${name}`);
}

for (const location of ['YH', 'Yard Hold', 'PMB', 'Perth Motor Bodies']) {
  const result = eligibility.scheduleEligibility({ current_location: location, eta_to_kewdale: '2099-12-31' });
  assert.strictEqual(result.enabled, true, `${location} bypasses future ETA after authoritative arrival/progress`);
  assert.strictEqual(result.earliestDateKey, '', `${location} has no ETA-derived earliest booking date`);
}
for (const location of ['IT', 'In Transit']) {
  const result = eligibility.scheduleEligibility({ current_location: location, eta_to_kewdale: '2099-12-31' });
  assert.strictEqual(result.enabled, true, `${location} remains ETA-governed`);
  assert.strictEqual(result.earliestDateKey, '2100-01-07', `${location} keeps the authoritative ETA + 7 calendar-day gate`);
}
assert.strictEqual(eligibility.scheduleEligibility({ current_location: 'Other', eta_to_kewdale: '2099-12-31' }).enabled, false, 'not-arrived Other remains ineligible');

const snapshotVehicle = {
  id: 'vehicle-13015144',
  stock_number: '13015144',
  current_location: 'PMB',
  customer_name: 'OAKES',
  model: 'HiAce Dsl LWB Van A/T',
};
const bookedVehicle = {
  id: 'vehicle-13061263',
  stock_number: '13061263',
  current_location: 'PMB',
  customer_name: 'BOOKED',
  model: 'Test vehicle',
};
const completedOnlyVehicle = {
  id: 'vehicle-13000000',
  stock_number: '13000000',
  current_location: 'PMB',
  customer_name: 'COMPLETED',
  model: 'Historical vehicle',
};
const snapshot = {
  vehicles: [snapshotVehicle, bookedVehicle, completedOnlyVehicle],
  work_items: [],
  outstanding_candidates: [{
    vehicle_id: snapshotVehicle.id,
    stage_code: 'TINT',
    schedule_enabled: false,
    disabled_reason: 'estimated_duration_missing',
  }],
};
const context = {
  app: { data: [], workshopEligibilitySnapshot: { candidates: [] } },
  window: { __workshopDataService: { getTrustedSnapshot: () => snapshot } },
  cleanNavisionText: value => String(value || '').trim(),
  workshopSnapshotVehicleToPlannerRow: vehicle => ({
    id: vehicle.id,
    sharedVehicleId: vehicle.id,
    vehicleKey: vehicle.stock_number,
    stockNumber: vehicle.stock_number,
    currentLocation: vehicle.current_location,
    customerName: vehicle.customer_name,
    model: vehicle.model,
  }),
  workshopState: () => ({ stage: 'TINT' }),
  workshopVehicleSearchText: vehicle => [vehicle.vehicleKey, vehicle.stockNumber, vehicle.customerName, vehicle.model].join(' ').toLowerCase(),
  workshopSharedModeActive: () => true,
  workshopSharedVehicleRef: ({ vehicleKey }) => ({ vehicleId: `vehicle-${vehicleKey}` }),
  workshopSortBookingsClosest: rows => rows,
  workshopPlanVehicleIdentity: entry => `shared:${entry.sharedVehicleId}`,
  normalizePmbStage: value => String(value || '').toUpperCase(),
  vehicleKey: vehicle => vehicle.vehicleKey,
  workshopSearchRank: () => 0,
  statusCategory: () => 'pmb',
  displayStockNumber: vehicle => vehicle.stockNumber,
};
vm.createContext(context);
vm.runInContext(`${extractFunction('workshopSearchMatches')}\nthis.search = workshopSearchMatches;`, context);

const plans = [
  { id: 'booking-1', sharedVehicleId: bookedVehicle.id, vehicleKey: bookedVehicle.stock_number, status: 'planned', startAt: '2026-09-10T08:00:00+08:00' },
  { id: 'booking-completed', sharedVehicleId: completedOnlyVehicle.id, vehicleKey: completedOnlyVehicle.stock_number, status: 'completed', startAt: '2026-09-01T08:00:00+08:00' },
];
const exactUnallocated = context.search('13015144', plans);
assert.strictEqual(exactUnallocated.length, 1, 'exact stock search returns a visible unallocated candidate even when a separate hours gate disables scheduling');
assert.strictEqual(exactUnallocated[0].bookings.length, 0);
assert.strictEqual(exactUnallocated[0].candidateAvailable, false);
assert.strictEqual(exactUnallocated[0].candidateDisabledReason, 'estimated_duration_missing');
assert.strictEqual(context.search('130151', plans).length, 1, 'partial stock search returns the unallocated candidate');
assert.strictEqual(context.search('13061263', plans).length, 1, 'booked vehicle search remains supported');
assert.strictEqual(context.search('13000000', plans).length, 0, 'vehicle with only completed booking history and no current candidate is omitted');
assert.strictEqual(context.search('99999999', plans).length, 0, 'absent stock remains absent');

const eligibilitySql = fs.readFileSync('supabase/staging_only/20260826170000_411_yh_workshop_eligibility_hide_test_fleet.sql', 'utf8');
const gateSql = fs.readFileSync('supabase/staging_only/20260903010000_workshop_eta_plus_seven_authority_20260903.sql', 'utf8');
assert.match(eligibilitySql, /current_location,''\)\)\) IN\('PMB','YH','IT'\)/i, 'shared candidate eligibility includes PMB, YH, and IT');
assert.match(eligibilitySql, /current_location,''\)\)\)<>'IT' OR v\.eta_to_kewdale IS NOT NULL/i, 'shared candidate eligibility requires ETA only for IT');
assert.match(gateSql, /IF v_candidate\.current_location='IT'[\s\S]*v_schedule_date<v_candidate\.eta_to_kewdale\+7/i, 'server schedule gate applies ETA timing only to IT');
assert.match(appSource, /WORKSHOP_PLANNER_SCRIPT_VERSION = '2026\.09\.09\.03-fitting-duration-coherence'/, 'planner module cache version includes this remediation and its successor');
assert.match(indexSource, /workshop-search=2026\.09\.08\.01/, 'entry-point cache key releases this remediation');

console.log('Workshop arrived ETA bypass and unallocated search regression: PASS');

// The board row and station projection share one canonical identity but have
// different local keys. They must not create duplicate vehicle choices.
context.app.data = [{ vehicleKey: snapshotVehicle.stock_number, stockNumber: snapshotVehicle.stock_number, customerName: 'Full board customer', model: 'Hilux DCC SR', __emailVehicleServerAuthoritative: true, __emailVehicleId: snapshotVehicle.id }];
const duplicateSources = context.search(snapshotVehicle.stock_number, plans);
assert.strictEqual(duplicateSources.length, 1, 'board plus snapshot yields one canonical vehicle');
assert.strictEqual(duplicateSources[0].vehicle.model, 'Hilux DCC SR', 'retain the full board description');
context.app.workshopEligibilitySnapshot.candidates = [{vehicle: snapshotVehicle}];
assert.strictEqual(context.search(snapshotVehicle.stock_number, plans).length, 1, 'third eligibility projection remains one choice');
const twoBookings = [{id:'a', sharedVehicleId:snapshotVehicle.id,status:'planned'}, {id:'b',sharedVehicleId:snapshotVehicle.id,status:'planned'}];
assert.strictEqual(context.search(snapshotVehicle.stock_number, twoBookings)[0].bookings.length, 2, 'independent bookings remain available');
context.workshopSharedVehicleRef = ({sharedVehicleId,vehicleKey}) => ({vehicleId:sharedVehicleId || `vehicle-${vehicleKey}`});
context.app.data.push({sharedVehicleId:'different-canonical-vehicle',vehicleKey:snapshotVehicle.stock_number,stockNumber:snapshotVehicle.stock_number});
const distinctPlans=[...twoBookings,{id:'c',sharedVehicleId:'different-canonical-vehicle',status:'planned'}];
assert.strictEqual(context.search(snapshotVehicle.stock_number, distinctPlans).length, 2, 'different canonical IDs with the same stock remain distinct');
