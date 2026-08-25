'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const start = appSource.indexOf('function pdcWorkDestinationDateLabel');
const end = appSource.indexOf('\nconst PDC_JOB_BY_REQUIRE_KEY', start);
assert.ok(start > 0 && end > start);
const canonicalId = '11111111-1111-4111-8111-111111111111';
const context = {
  app: { vehicleWorkshopDetailCache: new Map([[canonicalId, { status: 'ready', detail: { bookings: [{
    booking_id: '22222222-2222-4222-8222-222222222222',
    stage_code: 'FITTING', status: 'planned', bay_number: 3,
    scheduled_start_at: '2026-08-25T05:00:00.000Z', scheduled_end_at: '2026-08-25T07:00:00.000Z',
  }] } }]]) },
  partsWorstEtaValue: vehicle => vehicle.pdcPartsWorstEta || '',
  pdcJobTriState: (vehicle, def) => vehicle[def.completeKey] === true ? 'complete' : vehicle[def.requireKey] === true ? 'required' : 'none',
  pdcJobRequired: (vehicle, def) => vehicle[def.requireKey] === true,
  pdcJobComplete: (vehicle, def) => vehicle[def.completeKey] === true,
  partsOrdered: vehicle => vehicle.pdcPartsOrdered === true,
  isActivePartsStoppage: () => false,
  pmbStageForPdcJob: def => def.key === 'fitting' ? 'FITTING' : '',
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: { FITTING: 'planner-fitting' },
  vehicleWorkshopDetailCanonicalId: () => canonicalId,
  vehicleWorkshopBookingsForStage: (rows, stage) => rows.filter(row => row.stage_code === stage),
  vehicleWorkshopBookingDateKey: booking => booking.scheduled_start_at.slice(0, 10),
  cleanNavisionText: value => String(value || '').trim(),
  escapeHtml: value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('"', '&quot;'),
};
vm.createContext(context);
vm.runInContext(appSource.slice(start, end), context);
const fitting = { key: 'fitting', label: 'FITTING', short: 'F', requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting' };
const vehicle = { pdcRequiresFitting: true };
const html = context.pdcJobTriStateControl(vehicle, fitting, false);
assert.match(html, /pdc-work-state-ordered/);
assert.match(html, />Booked</);
assert.match(html, /25\/08\/26 · Bay 3/);
assert.match(html, /data-vehicle-workshop-booking-id="22222222-2222-4222-8222-222222222222"/);
assert.match(html, /data-vehicle-workshop-booking-date="2026-08-25"/);
const parts = { key: 'parts', label: 'PARTS', short: 'P', requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts' };
const partsHtml = context.pdcJobTriStateControl({ pdcRequiresParts: true, pdcPartsOrdered: true, pdcPartsWorstEta: '2026-08-30' }, parts, false);
assert.match(partsHtml, /pdc-work-state-ordered/);
assert.match(partsHtml, /data-pdc-work-destination-view="parts"/);
assert.match(partsHtml, /ETA 30\/08\/26/);
assert.match(css, /grid-template-columns: repeat\(10, minmax\(82px, 1fr\)\)/);
assert.match(css, /\.pdc-work-destination-box/);
assert.match(css, /\.pdc-work-destination-pill/);
assert.match(appSource, /loadVehicleWorkshopDetail\(vehicle, \{ force: true \}\)/);
assert.match(appSource, /showView\(button\.dataset\.pdcWorkDestinationView\)/);
console.log('Vehicle detail one-row booking pills and orange booked state: PASS');
