'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function vehicleWorkshopStoppageBookings');
const end = source.indexOf('function fixFirstRowsHtml', start);
assert.ok(start >= 0 && end > start, 'Workshop STOPPAGE priority projection exists');

const stoppedVehicle = {
  stock: '13008242',
  salesWorkshopBookings: [
    {bookingId: 'booking-tyre-stop', status: 'stoppage', stageCode: 'TYRE', stageName: 'Tyres', bayName: 'Bay 1', stoppageReason: 'Awaiting replacement tyre', scheduledStartAt: '2026-08-24T23:00:00Z'},
    {bookingId: 'booking-planned', status: 'planned', stageName: 'Tyres'},
  ],
};
const context = {
  pdcSheetVehicles: () => [stoppedVehicle],
  vehicleHasBatchNumber: () => true,
  workflowVehiclesForStep: () => [],
  cleanNavisionText: value => String(value || '').trim(),
  partsDepartmentStatus: () => 'notordered',
  partsWorstEtaLabel: () => '',
  partsStoppageReason: () => '',
  isPdcBlocked: () => false,
  pdcBlockReason: () => '',
  vehicleKey: vehicle => vehicle.stock,
  partsWorstEtaSortValue: () => 0,
};
vm.createContext(context);
vm.runInContext(`${source.slice(start, end)} this.stoppages = vehicleWorkshopStoppageBookings; this.priority = workflowPriorityRows;`, context);
const bookings = context.stoppages(stoppedVehicle);
assert.strictEqual(bookings.length, 1);
assert.strictEqual(bookings[0].bookingId, 'booking-tyre-stop');
const rows = context.priority();
assert.strictEqual(rows.length, 1);
assert.strictEqual(rows[0].vehicle.stock, '13008242');
assert.strictEqual(rows[0].label, 'Tyres STOPPAGE');
assert.strictEqual(rows[0].detail, 'Awaiting replacement tyre · Bay 1');
assert.strictEqual(rows[0].bookingId, 'booking-tyre-stop');
assert.doesNotMatch(source.slice(start, end), /\.slice\(0,\s*8\)/, 'STOPPAGE list is not silently capped at eight');
console.log('Workshop STOPPAGE projects into Fix First: PASS');
