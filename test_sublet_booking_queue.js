'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const indexSource = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const stagingSource = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');

const start = appSource.indexOf('function plainDateValue(');
const end = appSource.indexOf('function subletIsOverdue(', start);
assert(start >= 0 && end > start, 'Sublet queue helper block must remain extractable');

const fixtures = [
  { stock: 'NEEDS', pdcRequiresSublet: true, pdcCompleteSublet: false, pmbStage: 'FITTING' },
  { stock: 'DONE', pdcRequiresSublet: true, pdcCompleteSublet: true, pmbStage: 'FITTING' },
  { stock: 'NONE', pdcRequiresSublet: false, pdcCompleteSublet: false, pmbStage: 'FITTING' },
  { stock: 'HISTORY', pdcRequiresSublet: true, pdcCompleteSublet: true, pmbStage: 'RFT', pmbSubletActualReturnDate: '2030-07-01' },
];
const context = {
  Date,
  PDC_JOB_DEFS: [{ key: 'sublet', requireKey: 'pdcRequiresSublet', completeKey: 'pdcCompleteSublet' }],
  pdcSheetVehicles: () => fixtures,
  vehicleLocationBoardRows: () => fixtures,
  pdcJobRequired: (vehicle, def) => vehicle[def.requireKey] === true,
  pdcJobComplete: (vehicle, def) => vehicle[def.completeKey] === true,
  inferredPmbStage: vehicle => vehicle.pmbStage || '',
  pmbBaySubletProvider: vehicle => vehicle.pmbSubletProvider || '',
  displayStockNumber: vehicle => vehicle.stock || '',
  vehicleKey: vehicle => vehicle.stock || '',
};
vm.createContext(context);
vm.runInContext(`${appSource.slice(start, end)}\nthis.queueRows = subletRows();\nthis.compareRows = compareSubletBookingProximity;\nthis.bookingState = subletBookingState;\nthis.matchesOperationalFilter = subletMatchesOperationalFilter;`, context);
assert.deepStrictEqual(Array.from(context.queueRows, row => row.stock), ['NEEDS', 'HISTORY'], 'Every incomplete required Sublet vehicle must appear even while its current PMB stage is elsewhere; completed history remains visible only when a booking record exists');
assert(appSource.includes('return vehicleLocationBoardRows().filter(vehicle =>'), 'Sublet must consume the same reconciled canonical rows as Vehicle Locations');

const dated = [
  { stock: 'UNBOOKED', pmbSubletBookingDate: '' },
  { stock: 'FAR', pmbSubletBookingDate: '2030-07-25' },
  { stock: 'YESTERDAY', pmbSubletBookingDate: '2030-07-14' },
  { stock: 'TOMORROW', pmbSubletBookingDate: '2030-07-16' },
  { stock: 'TODAY', pmbSubletBookingDate: '2030-07-15' },
];
dated.sort((a, b) => context.compareRows(a, b, '2030-07-15'));
assert.deepStrictEqual(dated.map(row => row.stock), ['TODAY', 'YESTERDAY', 'TOMORROW', 'FAR', 'UNBOOKED'], 'Booking rows must sort by proximity to today, with unbooked rows after dated bookings');
assert.strictEqual(context.bookingState(dated[0]), 'booked', 'a booking date must classify a row as Sublet Booked');
assert.strictEqual(context.bookingState(dated[4]), 'to-book', 'a blank booking date must classify a row as Sublet To Book');
assert.strictEqual(context.matchesOperationalFilter(dated[0], 'booked'), true, 'Booked filter must include dated rows');
assert.strictEqual(context.matchesOperationalFilter(dated[4], 'to-book'), true, 'To Book filter must include undated rows');

for (const html of [indexSource, stagingSource]) {
  assert(html.includes('id="sublet-provider-filter"'), 'Sublet screen must expose a provider filter');
  assert(html.includes('<option value="unassigned">Unassigned</option>'), 'Provider filter must expose unassigned work');
  assert(html.includes('id="sublet-summary-grid"'), 'Sublet screen must expose Parts-style operational filter chips');
  assert(html.includes('id="sublet-sort-filter"'), 'Sublet screen must expose booked-row sorting');
  assert(html.includes('Nearest booking first'), 'nearest booking must be the default sort option');
}
assert(appSource.includes("on($('#sublet-provider-filter'), 'change', renderSubletHome)"), 'Provider filter must rerender the queue');
assert(appSource.includes("on($('#sublet-sort-filter'), 'change', renderSubletHome)"), 'Sort filter must rerender the queue');
assert(appSource.includes("data-sublet-field=\"pmbSubletProvider\""), 'Each Sublet row must retain its provider dropdown');
assert(appSource.includes('type="date" aria-label="Sublet booking date'), 'Each Sublet row must retain its dropdown calendar/date picker');
assert(appSource.includes("providerFilter === 'unassigned'"), 'Unassigned provider filter must fail closed to blank-provider rows');
assert(appSource.includes('compareSubletBookingProximity(a, b, sortReference)'), 'Rendered queue must use closest-booking ordering');
assert(appSource.includes("['to-book', 'Sublet To Book']") && appSource.includes("['booked', 'Sublet Booked']"), 'Sublet must expose Booked and To Book queues');
assert(appSource.includes('data-sublet-toggle='), 'compact Sublet rows must expand to notes and email controls');

console.log('Sublet booking queue/provider filter contract passed');
