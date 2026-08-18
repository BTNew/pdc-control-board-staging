'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('async function saveSharedVehicleWorkStates(');
const end = app.indexOf('\nfunction reconcileVehicleLifecycleServerResult', start);
assert.ok(start >= 0 && end > start, 'shared work-state saver exists');
const saver = app.slice(start, end);
assert.ok(saver.includes('const savedPartsState = String(workStates.parts ||'), 'successful RPC reconciles Parts state');
assert.ok(saver.includes('vehicle.pdcCompleteParts = savedPartsState === \'complete\';'), 'successful Parts completion stays green in the current card');
assert.ok(!saver.includes('await refreshEmailVehicleLocations();'), 'stale email snapshot is not read before the card render');
console.log('Shared Parts post-save reconciliation contract passed.');
