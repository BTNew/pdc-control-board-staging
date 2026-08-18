'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('data-staging-empty.js', 'utf8');
const context = { window: {} };
vm.runInNewContext(source, context);
const vehicles = context.window.VEHICLE_TRACKING_DATA.vehicles;
assert.strictEqual(vehicles.length, 3, 'staging must include exactly three QC dummy vehicles');
assert.strictEqual(JSON.stringify(vehicles.map(vehicle => vehicle.stock)), JSON.stringify(['QC-DUMMY-001', 'QC-DUMMY-002', 'QC-DUMMY-003']));
vehicles.forEach(vehicle => {
  assert.strictEqual(vehicle.pdcLocation, 'QC');
  assert.strictEqual(vehicle.manualLocation, 'QC');
  assert.strictEqual(vehicle.pdcQcComplete, false);
  assert.strictEqual(vehicle.pdcCompleteParts, true);
  assert.strictEqual(vehicle.recordLifecycle, 'staging-qc-dummy');
});
assert.strictEqual(vehicles[0].pdcCompleteFitting, true, 'ready fixture is fully complete');
assert.strictEqual(vehicles[1].pdcCompleteFitting, false, 'outstanding fixture retains incomplete fitting');
assert.strictEqual(vehicles[2].pdcCompleteFabrication, false, 'mixed fixture retains incomplete fabrication');
console.log('Staging QC dummy fixture contract passed.');
