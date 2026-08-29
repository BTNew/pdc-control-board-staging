'use strict';
const assert = require('assert');
const fs = require('fs');
const guard = require('./vehicle-requirements-guard.js');

const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const guardSource = fs.readFileSync('vehicle-requirements-guard.js', 'utf8');

const base = { hoist: 'complete', fitting: 'complete', electrical: 'required', parts: 'complete' };
const omission = guard.mergeRequirementPatch(base, { electrical: 'complete' });
assert.strictEqual(omission.ok, true);
assert.strictEqual(omission.value.hoist, 'complete', 'omitted requirements must be preserved');
assert.strictEqual(omission.value.fitting, 'complete', 'omitted work routing must be preserved');
assert.strictEqual(omission.value.parts, 'complete', 'omitted Parts state must be preserved');
assert.strictEqual(guard.mergeRequirementPatch(base, { unknown: 'none' }).ok, false);

const bookings = [{ status: 'planned', scheduled_start_at: '2026-09-10T01:00:00Z' }];
assert.deepStrictEqual(guard.partsRiskState({ partsEta: '2026-09-09', vehicle: {}, bookings }).risk, false);
assert.deepStrictEqual(guard.partsRiskState({ partsEta: '2026-09-10', vehicle: {}, bookings }).risk, false);
assert.deepStrictEqual(guard.partsRiskState({ partsEta: '2026-09-11', vehicle: {}, bookings }).risk, true);
assert.strictEqual(guard.partsRiskState({ partsEta: '2026-12-01', vehicle: { navisionKewdaleEta: '2026-01-01' } }).reason, 'booking_date_missing');
assert.strictEqual(guard.partsRiskState({ partsEta: '2026-12-01', partsComplete: true, vehicle: {}, bookings }).risk, false);

const target = guard.exactBookingNavigationTarget({
  bookingId: '085af1b4-4252-49b8-b9c9-334f972b1234',
  vehicleId: 'b02645d9-f411-5de0-97d1-905966b5feae',
  stockNumber: '13017855', department: 'FITTING', date: '2026-09-10', bay: '2',
});
assert.strictEqual(target.vehicleId, 'b02645d9-f411-5de0-97d1-905966b5feae');
assert.strictEqual(guard.exactBookingNavigationTarget({ bookingId: 'booking', vehicleId: 'vehicle', stockNumber: '13017855', department: 'FITTING', date: '2026-09-10', bay: '2' }), null);
assert(guard.deleteConfirmationIncludes({ confirmation: 'Delete OP7 Tow Bar fitting', operationNo: 'OP7', description: 'Tow Bar', department: 'Fitting' }));
assert(!guard.deleteConfirmationIncludes({ confirmation: 'Delete OP7', operationNo: 'OP7', description: 'Tow Bar', department: 'Fitting' }));

for (const marker of [
  'VehicleRequirementsGuard', 'mergeRequirementPatch', 'partsRiskState', 'exactBookingNavigationTarget',
  'data-vehicle-workshop-booking-vehicle-id',
  'data-vehicle-workshop-booking-stock', 'data-vehicle-workshop-booking-bay',
]) assert(app.includes(marker) || index.includes(marker), `missing frontend protection marker: ${marker}`);
for (const marker of ['mergeRequirementPatch', 'partsRiskState', 'exactBookingNavigationTarget', 'deleteConfirmationIncludes']) {
  assert(guardSource.includes(marker), `missing guard implementation: ${marker}`);
}
assert(planner.includes('lazy') || planner.includes('requestAnimationFrame'), 'planner must defer exact target scroll until rendered');
assert(css.includes('workshop-navigation-pulse'), 'exact planner navigation highlight styling must remain present');
console.log('Stock 13017855 requirement/Parts/navigation safety contract passed');
