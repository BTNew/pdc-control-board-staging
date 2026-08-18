'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('async function saveSharedVehicleWorkStates(');
const end = app.indexOf('\nfunction reconcileVehicleLifecycleServerResult', start);
assert.ok(start >= 0 && end > start, 'shared work-state saver exists');
const saver = app.slice(start, end);
assert.ok(app.includes('function reconcileSharedWorkStatesInMemory('), 'successful RPC has a shared work-state reconciliation helper');
assert.ok(app.includes('PDC_JOB_DEFS.forEach(def => {'), 'reconciliation covers every required work definition');
assert.ok(app.includes('reconcileSharedWorkStatesInMemory(vehicle, ref.vehicleId, workStates, body.vehicle_version);'), 'successful RPC reconciles all work states into live rows');
assert.ok(!saver.includes('await refreshEmailVehicleLocations();'), 'stale email snapshot is not read before the card render');
console.log('Shared Parts post-save reconciliation contract passed.');
