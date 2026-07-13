'use strict';

const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const context = { window: {} };
vm.createContext(context);
vm.runInContext(fs.readFileSync('data.js', 'utf8'), context, { filename: 'data.js' });

const payload = context.window.VEHICLE_TRACKING_DATA;
const vehicles = payload.vehicles;
const jobs = [
  ['pdcRequiresTint', 'pdcCompleteTint'],
  ['pdcRequiresHoist', 'pdcCompleteHoist'],
  ['pdcRequiresFitting', 'pdcCompleteFitting'],
  ['pdcRequiresFabrication', 'pdcCompleteFabrication'],
  ['pdcRequiresElectrical', 'pdcCompleteElectrical'],
  ['pdcRequiresTyre', 'pdcCompleteTyre'],
  ['pdcRequiresPitInspection', 'pdcCompletePitInspection'],
  ['pdcRequiresParts', 'pdcCompleteParts'],
];

assert.strictEqual(payload.report.source, 'Master2021 (1).xlsx — visible EOS worksheet');
assert.strictEqual(payload.report.masterImport.importedVehicles, 321);
assert.strictEqual(vehicles.length, 321);
assert.strictEqual(new Set(vehicles.map(vehicle => vehicle.stock)).size, 321, 'Stocks must be unique');
assert.ok(vehicles.every(vehicle => vehicle.stock && vehicle.sourceRow.startsWith('EOS!')));
assert.ok(!vehicles.some(vehicle => vehicle.stock === '444555' || vehicle.client === 'Test'));

const pmB = vehicles.filter(vehicle => vehicle.pdcLocation === 'PMB');
const rft = vehicles.filter(vehicle => vehicle.pdcLocation === 'RFT');
const transit = vehicles.filter(vehicle => vehicle.toyotaStatus === 'In Transit to PMB');
assert.strictEqual(pmB.length, 276);
assert.strictEqual(rft.length, 17);
assert.strictEqual(transit.length, 28);
assert.ok(pmB.every(vehicle => /^\d+$/.test(vehicle.keyNumber)), 'Every numbered PMB vehicle needs its master key');
assert.ok(rft.every(vehicle => !vehicle.keyNumber && vehicle.masterHat === 'WPC'));
assert.ok(transit.every(vehicle => !vehicle.pdcLocation && !vehicle.keyNumber && vehicle.masterHat === 'IT'));

for (const vehicle of vehicles) {
  for (const [requiredKey, completeKey] of jobs) {
    assert.strictEqual(typeof vehicle[requiredKey], 'boolean', `${vehicle.stock}: ${requiredKey} must be boolean`);
    assert.strictEqual(typeof vehicle[completeKey], 'boolean', `${vehicle.stock}: ${completeKey} must be boolean`);
    assert.ok(!vehicle[completeKey] || vehicle[requiredKey], `${vehicle.stock}: ${completeKey} cannot be true when work is not required`);
  }
}
assert.ok(rft.every(vehicle => jobs.every(([requiredKey, completeKey]) => !vehicle[requiredKey] || vehicle[completeKey])), 'WPC/RFT vehicles must retain a passed work gate');
assert.strictEqual(vehicles.filter(vehicle => vehicle.pdcBlocked).length, 10);

const samplePmb = vehicles.find(vehicle => vehicle.stock === '12658649');
assert.ok(samplePmb && samplePmb.keyNumber === '3' && samplePmb.pdcLocation === 'PMB');
assert.ok(samplePmb.pdcCompleteFabrication && samplePmb.pdcCompleteParts && samplePmb.pdcCompleteFitting);

const sampleSublet = vehicles.find(vehicle => vehicle.stock === '12662987');
assert.ok(sampleSublet && sampleSublet.pmbStage === 'SUBLET' && sampleSublet.masterSubletStatus === '@');

const sampleHeld = vehicles.find(vehicle => vehicle.stock === '12238306');
assert.ok(sampleHeld && sampleHeld.pdcBlocked && sampleHeld.pmbStage === 'FITTING');

const sampleRft = vehicles.find(vehicle => vehicle.stock === '12050114');
assert.ok(sampleRft && sampleRft.pdcLocation === 'RFT' && sampleRft.rftTransferredAt);

const sampleTransit = vehicles.find(vehicle => vehicle.stock === '13017920');
assert.ok(sampleTransit && sampleTransit.toyotaStatus === 'In Transit to PMB' && sampleTransit.masterHat === 'IT');

console.log('Master sheet import regression checks passed.');
