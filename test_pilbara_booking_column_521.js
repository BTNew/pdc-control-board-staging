/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r521 (F135): the Vehicle Locations Booking column does not use a Pilbara service
// job card as a read-only badge. Eligible vehicles get the same booking control as
// any other eligible vehicle. The flag stays a job-card fact on the row.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const emailVehicles = require('./pdc-email-vehicle-location-service.js');
const table = require('./pdc-vehicle-locations-table.js');

const OLD_BADGE = 'Pilbara Service Review · R/O loaded';
const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

function boardVehicle(overrides = {}) {
  const vehicle = emailVehicles.mapServerVehicle({
    id: 'f53058d8-b4b8-4f90-9b04-4e51e8ec92a4',
    version: 23,
    stock_number: '13018393',
    job_card_number: 'J139125903',
    customer_name: 'Dept 139 customer',
    vehicle_description: 'Hilux',
    current_location: 'PMB',
    lifecycle_state: 'active',
    visible_on_board: true,
    eta_to_kewdale: '2026-11-10',
  });
  return { ...vehicle, ...overrides };
}

function bookingColumn(ctx, vehicle) {
  const bucket = ctx.incomingBucketForVehicle(vehicle);
  const card = ctx.incomingVehicleDetailRow(vehicle, bucket, { workshopProjectionAvailable: false });
  const row = table.tableRowHtml(card, bucket, { key: ctx.vehicleKey(vehicle) });
  const cell = (row.match(/<td class="c-action">([\s\S]*?)<\/td>/) || [])[1] || '';
  assert.ok(cell, 'Booking column cell is present');
  return cell;
}

function setup() {
  const fixture = createFixture({ vehicleCount: 0 });
  const ctx = fixture.context;
  ctx.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd', environment: 'staging' };
  ctx.PDC_AUTH_CONTEXT = { userId: 'fixture-operator', role: 'operator' };
  ctx.app.emailVehicleLocationService = {};
  fixture.loadHelper('pdc-book-all-stations.js');
  assert.equal(typeof ctx.PDC_BOOK_ALL_STATIONS.actionHtml, 'function');
  return ctx;
}

test('the Booking column source no longer prefers the Pilbara read-only wording', () => {
  assert.doesNotMatch(app, /Pilbara Service Review/);
  assert.doesNotMatch(app, /R\/O loaded/);
  assert.doesNotMatch(app, /pilbaraServiceJobCard \?/);
  assert.match(app, /r521 \(F135\)/);
  assert.match(html, /app\.js\?[^"]*r521=2026\.10\.24\.r521/);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes(OLD_BADGE), true);
});

test('an eligible vehicle with the job-card flag gets the same Booking column as one without it', () => {
  const ctx = setup();
  const flagged = boardVehicle({ pilbaraServiceJobCard: true, current_location: 'PMB', pdcLocation: 'PMB' });
  const plain = boardVehicle({ pilbaraServiceJobCard: false, current_location: 'PMB', pdcLocation: 'PMB' });
  assert.equal(ctx.PDC_BOOK_ALL_STATIONS.eligible(flagged), true);
  const flaggedCell = bookingColumn(ctx, flagged);
  const plainCell = bookingColumn(ctx, plain);
  assert.equal(flaggedCell, plainCell);
  assert.match(flaggedCell, /Book all stations/);
  assert.doesNotMatch(flaggedCell, /Pilbara|R\/O loaded|badge neutral/);
});

test('a location that is not eligible keeps the same source badge with or without the job-card flag', () => {
  const ctx = setup();
  const flagged = boardVehicle({
    pilbaraServiceJobCard: true,
    stock: '13018393',
    stock_number: '13018393',
    current_location: 'Other',
    pdcLocation: 'Other',
    jobCardNumber: 'J139125903',
    jobcard: 'J139125903',
  });
  const plain = { ...flagged, pilbaraServiceJobCard: false };
  assert.equal(ctx.PDC_BOOK_ALL_STATIONS.eligible(flagged), false);
  const flaggedCell = bookingColumn(ctx, flagged);
  const plainCell = bookingColumn(ctx, plain);
  assert.equal(flaggedCell, plainCell);
  assert.match(flaggedCell, /Imported by email · Read only/);
  assert.doesNotMatch(flaggedCell, /Pilbara|R\/O loaded|Book all stations/);
});

test('an identity conflict stays read only when the vehicle also has the job-card flag', () => {
  const ctx = setup();
  const vehicle = boardVehicle({ pilbaraServiceJobCard: true, __locationIdentityReadOnly: true, current_location: 'PMB', pdcLocation: 'PMB' });
  assert.equal(ctx.PDC_BOOK_ALL_STATIONS.eligible(vehicle), false);
  const cell = bookingColumn(ctx, vehicle);
  assert.match(cell, /Identity conflict · Read only/);
  assert.doesNotMatch(cell, /Pilbara|R\/O loaded|Book all stations/);
});

test('book all stations still removes the old wording if a stale badge is passed in', () => {
  const ctx = setup();
  const vehicle = boardVehicle({ pilbaraServiceJobCard: true, current_location: 'PMB', pdcLocation: 'PMB' });
  const htmlOut = ctx.PDC_BOOK_ALL_STATIONS.actionHtml(vehicle, `<span class="badge neutral">${OLD_BADGE}</span>`);
  assert.match(htmlOut, /Book all stations/);
  assert.doesNotMatch(htmlOut, /Pilbara|R\/O loaded/);
});
