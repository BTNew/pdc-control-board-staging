'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const boardStart = app.indexOf('function vehicleLocationBoardRows(');
const boardEnd = app.indexOf('function sharedNavisionLocationsStatusHtml', boardStart);
assert.ok(boardStart >= 0 && boardEnd > boardStart, 'Vehicle Locations projection function is present');
const board = app.slice(boardStart, boardEnd);

const canonicalMap = board.indexOf('sharedByCanonicalVehicleId');
const canonicalLookup = board.indexOf('vehicle.__emailVehicleId');
const stockLookup = board.indexOf('sharedByStock.get(localIdentity.stock)');
assert.ok(canonicalMap >= 0, 'projection builds a canonical shared-row index');
assert.ok(canonicalLookup > canonicalMap, 'authenticated email rows bind projection lookup to vehicles.id');
assert.ok(stockLookup > canonicalLookup, 'stock remains only the fallback projection identity');
assert.ok(board.includes('const candidates = canonicalCandidates.length ? canonicalCandidates : stockCandidates;'), 'canonical projection wins over display-stock fallback');

const actionStart = app.indexOf('async function markVehiclePartsOrdered');
const actionEnd = app.indexOf('async function markVehiclePartsComplete', actionStart);
const action = app.slice(actionStart, actionEnd);
assert.ok(action.includes('service.markPartsOrdered(vehicle.__emailVehicleId, vehicle.__emailVehicleVersion)'), 'Mark Ordered uses the projected canonical id/version');
assert.ok(action.includes('await refreshEmailVehicleLocations()'), 'Mark Ordered reconciles from a fresh authoritative snapshot');

const counterStart = app.indexOf('function refreshPartsEtaCounters');
const counterEnd = app.indexOf('function setupPartsEtaCounterClock', counterStart);
const counter = app.slice(counterStart, counterEnd);
assert.ok(counter.includes('const key = String(vehicleKey(vehicle) || \'\').trim();'), 'ETA counters use the same projected vehicle key as the row');
assert.ok(counter.includes('rowsByKey.has(key) ? null : vehicle'), 'duplicate projected keys fail closed rather than showing an unbound counter');

console.log('Parts projection identity regression contract passed.');
