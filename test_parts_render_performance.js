'use strict';
const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const email = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

const rowsSlice = app.slice(app.indexOf('function partsDepartmentRows'), app.indexOf('function renderPartsSummary'));
assert(/function partsDepartmentRows\(sourceRows\s*=\s*partsDepartmentSourceRows\(\)\)/.test(rowsSlice), 'Parts filtering must accept one pre-reconciled source snapshot');
assert(rowsSlice.includes('return sourceRows'), 'Parts filtering must consume the supplied source snapshot');

const counterSlice = app.slice(app.indexOf('function refreshPartsEtaCounters'), app.indexOf('function partsWorstEtaSortValue'));
assert(/function refreshPartsEtaCounters\(sourceRows\s*=\s*null\)/.test(counterSlice), 'ETA refresh must accept a shared source snapshot');
assert(!counterSlice.includes('selectedVehicle('), 'ETA refresh must never rebuild the full board once per rendered row');
assert(counterSlice.includes('const rowsByKey = new Map()'), 'ETA refresh must use a keyed snapshot lookup');

const renderSlice = app.slice(app.indexOf('function renderPartsHome'), app.indexOf('async function markVehiclePartsOrdered'));
assert(renderSlice.includes('const sourceRows = partsDepartmentSourceRows();'), 'Parts render must reconcile the board exactly once');
assert(renderSlice.includes('partsDepartmentRows(sourceRows)'));
assert(renderSlice.includes('renderPartsSummary(sourceRows)'));
assert(renderSlice.includes('partsIssuedStoppagePickerHtml(sourceRows)'));
assert.strictEqual((renderSlice.match(/setupPartsEtaCounterClock\(/g) || []).length, 1, 'Parts render must initialize/refresh ETA counters once');

assert(email.includes('const localStockIndexes = new Map();') && email.includes('const localVinIndexes = new Map();'), 'Email reconciliation must use identity indexes instead of scanning every local row for each server row');
assert(!email.includes('local.map((row, i) => rowIdentities(row).stock === serverId.stock'), 'Quadratic email stock scan must be removed');
assert(app.includes('const sharedByStock = new Map();'), 'Navision reconciliation must index authoritative rows by stock');
assert(!app.includes("const matches = currentShared.filter(item => sharedNavisionIdentityRelation(vehicle, item) === 'match');"), 'Quadratic local-to-shared match scan must be removed');

console.log('Parts render performance contracts passed');
