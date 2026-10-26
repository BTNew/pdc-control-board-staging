/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r550 (F164): Find a workshop booking is two boxes. Key number is an exact key match.
// The other box searches stock, job card, customer and vehicle, and not the key number.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
function slice(name, next) {
  const start = source.indexOf(`function ${name}`);
  const end = source.indexOf(`\nfunction ${next}`);
  return source.slice(start, end);
}
const vehicles = [
  { keyNumber: '364', stock: '13036499', pdcJobcard: 'J139136400', customerName: 'Acme', vehicle: 'Hilux' },
  { keyNumber: '0364', stock: '13000001', pdcJobcard: 'J1', customerName: 'Other', vehicle: 'Ranger' },
  { keyNumber: ' 364 ', stock: '13000002', pdcJobcard: 'J2', customerName: 'Third', vehicle: 'HiAce' },
  { keyNumber: '365', stock: 'STK364', pdcJobcard: 'JC-364', customerName: 'Key absent', vehicle: 'Prado 364' },
];
const ctx = {
  cleanNavisionText: value => String(value || '').replace(/\s+/g, ' ').trim(),
  vehicleKey: vehicle => String(vehicle.stock || ''),
  displayStockNumber: vehicle => String(vehicle.stock || ''),
  vehicleKeyNumber: vehicle => String(vehicle.keyNumber || '').replace(/\s+/g, ' ').trim(),
  vehicleJobcardNumber: vehicle => String(vehicle.pdcJobcard || ''),
  workshopSearchJobCards: vehicle => [vehicle.pdcJobcard].filter(Boolean),
  vehicleCustomerName: vehicle => String(vehicle.customerName || ''),
  displayVehicle: vehicle => String(vehicle.vehicle || ''),
};
vm.runInNewContext(
  slice('workshopSearchKeyToken', 'workshopVehicleKeyToken')
  + slice('workshopVehicleKeyToken', 'workshopSearchCriteria')
  + slice('workshopSearchCriteria', 'workshopSearchCriteriaKey')
  + slice('workshopSearchCriteriaKey', 'workshopSearchIsActive')
  + slice('workshopSearchIsActive', 'workshopSearchVehicleMatches')
  + slice('workshopSearchVehicleMatches', 'workshopVehicleSearchText')
  + slice('workshopVehicleSearchText', 'workshopSearchRank')
  + '\nthis.api = { workshopSearchKeyToken, workshopSearchVehicleMatches, workshopVehicleSearchText, workshopSearchControlHtml: null };',
  ctx,
);
const html = source.slice(source.indexOf('function workshopSearchControlHtml'), source.indexOf('\nfunction workshopHighlightScrollSignature'));
const ui = {
  escapeHtml: value => String(value ?? ''),
  workshopState: () => ({ search: '', searchKey: '364', searchOpen: true }),
  workshopSearchIsActive: () => true,
  workshopSearchKeyToken: value => String(value || ''),
  cleanNavisionText: value => String(value || ''),
  workshopSearchResultsHtml: () => '<button class="workshop-search-result">Key 364</button>',
  workshopLoadPlans: () => [],
};
vm.runInNewContext(`${html}\nthis.html = workshopSearchControlHtml('', []);`, ui);

test('r550: key 364 matches only that key, ignoring zeros, spaces and case', () => {
  assert.equal(ctx.workshopSearchKeyToken(' 0364 '), '364');
  assert.equal(ctx.workshopSearchKeyToken('KEY364'), 'key364');
  const hits = vehicles.filter(vehicle => ctx.workshopSearchVehicleMatches(vehicle, { key: '364', text: '' }));
  assert.deepEqual(hits.map(vehicle => vehicle.stock), ['13036499', '13000001', '13000002']);
  assert.equal(ctx.workshopSearchVehicleMatches(vehicles[3], { key: '364', text: '' }), false);
});

test('r550: the other box ignores the key number', () => {
  assert.equal(ctx.workshopVehicleSearchText(vehicles[0]).includes('364'), true);
  assert.equal(ctx.workshopVehicleSearchText(vehicles[0]).includes('key'), false);
  assert.equal(ctx.workshopSearchVehicleMatches({ keyNumber: '364', stock: '1', pdcJobcard: 'J9', customerName: 'No digits', vehicle: 'Van' }, { key: '', text: '364' }), false);
  assert.equal(ctx.workshopSearchVehicleMatches(vehicles[3], { key: '', text: '364' }), true);
  assert.equal(ctx.workshopSearchVehicleMatches(vehicles[0], { key: '364', text: 'hilux' }), true);
  assert.equal(ctx.workshopSearchVehicleMatches(vehicles[3], { key: '364', text: 'hilux' }), false);
});

test('r550: the planner draws both boxes and Clear still clears the search', () => {
  assert.match(ui.html, /Key number/);
  assert.match(ui.html, /value="364"/);
  assert.match(ui.html, /Stock, job card, customer or vehicle/);
  assert.match(ui.html, /data-workshop-search-clear/);
  assert.match(source, /workshopRevealSearchMatch\('', 'clear'\)/);
  assert.doesNotMatch(source, /placeholder="Key, stock, job card, customer or vehicle"/);
});
