/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r566 (F180): Vehicle Locations table uses the planner's two search boxes and matcher (Craig, 27 Oct 2026).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const table = require('./pdc-vehicle-locations-table.js');
const searchFactory = require('./pdc-workshop-vehicle-search.js');

const SOURCE = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');

const vehicles = [
  { keyNumber: '364', stock: '13036499', pdcJobcard: 'J139136400', customerName: 'Acme', vehicle: 'Hilux' },
  { keyNumber: '214', stock: '13000214', pdcJobcard: 'J214', customerName: 'Beta', vehicle: 'Ranger' },
  { keyNumber: '365', stock: 'STK364', pdcJobcard: 'JC-364', customerName: 'Key absent', vehicle: 'Prado 364' },
];

const deps = {
  cleanNavisionText: value => String(value || '').replace(/\s+/g, ' ').trim(),
  vehicleKey: vehicle => String(vehicle.stock || ''),
  displayStockNumber: vehicle => String(vehicle.stock || ''),
  vehicleKeyNumber: vehicle => String(vehicle.keyNumber || '').replace(/\s+/g, ' ').trim(),
  vehicleJobcardNumber: vehicle => String(vehicle.pdcJobcard || ''),
  vehicleCustomerName: vehicle => String(vehicle.customerName || ''),
  displayVehicle: vehicle => String(vehicle.vehicle || ''),
};
const api = searchFactory.create(() => deps);

test('r566: key 364 matches only that key (shared matcher)', () => {
  const hits = vehicles.filter(vehicle => api.workshopSearchVehicleMatches(vehicle, { key: '364', text: '' }));
  assert.deepEqual(hits.map(vehicle => vehicle.stock), ['13036499']);
  assert.equal(api.workshopSearchVehicleMatches(vehicles[2], { key: '364', text: '' }), false);
});

test('r566: text box ignores key digits; both boxes combine with AND', () => {
  assert.equal(api.workshopSearchVehicleMatches({ keyNumber: '100', stock: '13001000', pdcJobcard: 'J9', customerName: 'No digits', vehicle: 'Van' }, { key: '', text: '364' }), false);
  assert.equal(api.workshopSearchVehicleMatches(vehicles[2], { key: '', text: '364' }), true);
  assert.equal(api.workshopSearchVehicleMatches(vehicles[0], { key: '364', text: 'hilux' }), true);
  assert.equal(api.workshopSearchVehicleMatches(vehicles[2], { key: '364', text: 'hilux' }), false);
});

test('r566: summary label for the filter bar', () => {
  assert.equal(table.locationSearchSummaryLabel({ key: '214', text: '' }), 'key “214”');
  assert.equal(table.locationSearchSummaryLabel({ key: '', text: 'hilux' }), '“hilux”');
  assert.equal(table.locationSearchSummaryLabel({ key: '364', text: 'acme' }), 'key “364” · “acme”');
});

test('r566: table module wires dual search and the shared matcher', () => {
  assert.equal(table.VERSION, '2026.10.27.r566');
  assert.match(SOURCE, /ensureDualSearchPanel/);
  assert.match(SOURCE, /vehicleMatchesTableFilters/);
  assert.match(SOURCE, /PDC_WORKSHOP_VEHICLE_SEARCH/);
  assert.match(SOURCE, /Key number/);
  assert.match(SOURCE, /Stock, job card, customer or vehicle/);
  assert.match(planner, /pdc-workshop-vehicle-search\.js/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-workshop-vehicle-search\.js\?r566=2026\.10\.27\.r566/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /r566=2026\.10\.27\.r566/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-workshop-vehicle-search\.js\?r566=2026\.10\.27\.r566/);
  const css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  assert.match(css, /\.vlt-search-key-label/);
  const searchBar = css.slice(css.indexOf('vlt-search-key-label'), css.indexOf('body.vlt-table-on .vlt-slim-bar .incoming-filter-meta'));
  assert.match(searchBar, /#1d4ed8/);
  assert.doesNotMatch(searchBar, /#f59e0b|#ea580c/i, 'search labels stay blue, not orange');
});
