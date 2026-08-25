'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const reconcileStart = source.indexOf('function reconcileVehicleLifecycleServerResult');
const reconcileEnd = source.indexOf('function vehicleReadyForQualityControl', reconcileStart);
assert.ok(reconcileStart >= 0 && reconcileEnd > reconcileStart, 'lifecycle reconciliation helper exists');
const context = {
  normalizePdcLocation: value => String(value || '').trim().toUpperCase(),
};
vm.createContext(context);
vm.runInContext(`${source.slice(reconcileStart, reconcileEnd)} this.reconcile = reconcileVehicleLifecycleServerResult;`, context);
for (const result of [
  {vehicle: {current_location: 'QC', qc_completed_at: null}},
  {data: {vehicle: {current_location: 'QC', qc_completed_at: null}}},
]) {
  const vehicle = {pdcLocation: 'PMB', manualLocation: 'PMB'};
  assert.strictEqual(context.reconcile(vehicle, result), true);
  assert.strictEqual(vehicle.pdcLocation, 'QC');
  assert.strictEqual(vehicle.manualLocation, 'QC');
  assert.strictEqual(vehicle.pdcQcComplete, false);
}
assert.strictEqual(context.reconcile({}, {ok: true}), false);

const markStart = source.indexOf('async function markVehicleReadyForQualityControl');
const markEnd = source.indexOf('function qualityControlVehicleHtml', markStart);
assert.ok(markStart >= 0 && markEnd > markStart, 'Ready for QC action exists');
const markSource = source.slice(markStart, markEnd);
assert.match(markSource, /await Promise\.all\(\[/, 'post-commit authoritative refresh is awaited');
assert.match(markSource, /refreshEmailVehicleLocations\(\)/, 'vehicle/QC snapshot refreshes immediately after commit');
assert.match(markSource, /loadSnapshot\('ready_for_qc'\)/, 'Workshop snapshot refreshes with the QC transition');
assert.match(markSource, /if \(!locationsRefreshed\) renderAll\(\)/, 'committed response renders even when snapshot is temporarily unavailable');
assert.doesNotMatch(markSource, /location\.reload|window\.reload/, 'no hard refresh is required');
console.log('Ready-for-QC immediate projection refresh: PASS');
