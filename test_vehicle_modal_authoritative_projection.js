'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const service = require('./pdc-email-vehicle-location-service.js');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function vehicleModalIdentityStock');
const end = source.indexOf('\nfunction selectedVehicle', start);
assert.ok(start > 0 && end > start, 'modal identity functions must be extractable');

const canonicalId = '6649dcd7-b681-547a-aec2-af4111d1af18';
const raw = {
  id: canonicalId,
  permanent_vehicle_id: 'PDC-PMB-4183988A639B79CF4CE415AA',
  stock_number: '12708288',
  version: 3,
  current_location: 'PMB',
  customer_name: 'MAIN ROADS',
  vehicle_description: 'Hilux DCC',
  job_card_number: 'J139124336',
  salesperson_code: 'CW',
  salesperson_name: 'Craig Watson',
  salesperson_email: 'craig.watson@broometoyota.com.au',
  visible_on_board: true,
  work_items: [
    { work_key: 'hoist', required: true, completed: true },
    { work_key: 'fitting', required: true, completed: false },
    { work_key: 'electrical', required: true, completed: false },
  ],
  workshop_bookings: [
    { booking_id: '310231b4-bf74-4ab4-bc22-4613168e0b77', stage_code: 'HOIST', stage_name: 'Hoist', bay_name: 'Hoist Bay 02', status: 'completed', scheduled_start_at: '2026-08-25T03:37:00Z', scheduled_end_at: '2026-08-25T06:37:00Z' },
    { booking_id: '41c9df9e-116a-4a07-bff2-b608b3420e8b', stage_code: 'FITTING', stage_name: 'Fitting', bay_name: 'Fitting Bay 01', status: 'planned', scheduled_start_at: '2026-08-25T08:45:00Z', scheduled_end_at: '2026-08-26T07:33:00Z' },
  ],
};
const staleLocal = { id: canonicalId, stock: '12708288', client: '', consultant: 'Unassigned', pdcRequiresElectrical: true };
const context = {
  app: { vehicleModalIdentity: { canonicalId, stockBaseline: '12708288' }, emailVehicleLocationRows: [raw], data: [staleLocal] },
  window: { PDC_EMAIL_VEHICLE_LOCATION_SERVICE: service },
  cleanNavisionText: value => String(value || '').trim(),
  displayStockNumber: vehicle => String(vehicle?.stock || '').trim(),
  vehicleWorkshopDetailCanonicalId: vehicle => String(vehicle?.__emailVehicleId || vehicle?.id || '').trim(),
  applySharedWorkStateCache: rows => rows,
};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);
const bound = context.vehicleModalBoundVehicle();
assert.equal(bound.__emailVehicleServerAuthoritative, true);
assert.equal(bound.__emailVehicleId, canonicalId);
assert.equal(bound.stock, '12708288');
assert.equal(bound.client, 'MAIN ROADS');
assert.equal(bound.salespersonCode, 'CW');
assert.equal(bound.salespersonName, 'Craig Watson');
assert.equal(bound.jobcard, 'J139124336');
assert.equal(bound.pdcRequiresHoist, true);
assert.equal(bound.pdcCompleteHoist, true);
assert.equal(bound.pdcRequiresFitting, true);
assert.equal(bound.pdcRequiresElectrical, true);
assert.deepEqual(Array.from(bound.salesWorkshopBookings, item => `${item.stageCode}:${item.status}:${item.bayName}`), [
  'HOIST:completed:Hoist Bay 02',
  'FITTING:planned:Fitting Bay 01',
]);

context.app.emailVehicleLocationRows = [raw, { ...raw }];
assert.equal(context.vehicleModalBoundVehicle(), null, 'duplicate raw UUID+Stock rows must fail closed');

assert.match(source, /const refreshedOk = await refreshEmailVehicleLocations\(\)/);
assert.match(source, /const cachedAuthoritative = vehicleModalBoundVehicle\(\)/);
assert.match(source, /const cachedReady = Boolean\(cachedAuthoritative/);
assert.match(source, /if \(cachedReady\) renderDetail\(\)/);
assert.match(source, /app\.vehicleModalIdentityReady = true/);
assert.match(source, /void Promise\.allSettled\(\[/);
assert.doesNotMatch(source, /await refreshSharedVehicleWorkState\(refreshed\)/);
assert.match(source, /Authoritative vehicle details could not be loaded/);
assert.match(source, /let authoritativeSaveVehicle = v/);
assert.match(source, /authoritativeSaveVehicle = authoritativeResult\.data\?\.authoritativeVehicle \|\| vehicleModalBoundVehicle\(\) \|\| v/);
assert.match(source, /saveSharedVehicleWorkStates\(authoritativeSaveVehicle, workStates\)/);

console.log('Vehicle modal authoritative projection and save sequencing: PASS');
