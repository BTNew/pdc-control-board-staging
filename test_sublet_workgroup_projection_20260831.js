'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

function section(startNeedle, endNeedle) {
  const start = app.indexOf(startNeedle);
  const end = app.indexOf(endNeedle, start);
  assert.ok(start >= 0 && end > start, `${startNeedle} section exists`);
  return app.slice(start, end);
}

const workRenderer = section('function incomingWorkChecklistHtml', 'function workStatusLegendHtml');
const activeSubletHelper = section('function canonicalActiveSubletBooking', 'function pdcWorkDestination');
const vehicleRenderer = section('function incomingVehicleDetailRow', 'const SALES_PREPARATION_FIELDS');

const subletDef = {
  key: 'sublet', label: 'Sublet', short: 'S', requireKey: 'pdcRequiresSublet', completeKey: 'pdcCompleteSublet',
};
const context = {
  vehicleKey: vehicle => String(vehicle.stock || vehicle.stock_number || ''),
  normalizePmbStage: value => String(value || '').toUpperCase(),
  inferredPmbStage: () => '',
  vehicleWorkshopBookingProjection: () => ({ bookingRequired: false, activeBookings: [] }),
  pdcJobDefsPartsFirst: () => [subletDef],
  pdcJobRequired: (vehicle, def) => vehicle[def.requireKey] === true,
  pdcJobComplete: (vehicle, def) => vehicle[def.completeKey] === true,
  pmbStageForPdcJob: () => '',
  PMB_STAGE_TO_JOB_KEY: {},
  isActivePartsStoppage: () => false,
  isPdcBlocked: () => false,
  partsOrdered: () => false,
  pdcGridJobLabel: () => 'Sublet',
  pdcJobCompletionTitle: () => 'Sublet complete',
  escapeHtml: value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('"', '&quot;'),
};
vm.createContext(context);
vm.runInContext(`${activeSubletHelper}\n${workRenderer} this.renderIncoming = incomingWorkChecklistHtml;`, context);

function mapped(status, workState = { required: true, completed: false }) {
  return mapServerVehicle({
    id: 'b3c293fb-0453-56da-86a6-9c3511cc2fe7',
    stock_number: '13080534',
    job_card_number: 'J139125425',
    current_location: 'Other',
    version: 11,
    work_items: [{ work_key: 'sublet', ...workState }],
    sublet_active_count: status === 'active' ? 1 : 0,
    sublet_bookings: status ? [{
      booking_id: '475efd0a-1cb9-4f3a-bf02-483afe6ff5ac',
      vehicle_id: 'b3c293fb-0453-56da-86a6-9c3511cc2fe7',
      provider_id: '4cbd486c-78c2-42ce-987a-99d45d1eeaf4',
      provider_name: 'Customer Sublet',
      out_date: '2026-09-05',
      expected_return_date: '2026-09-12',
      status,
      version: 1,
    }] : [],
  });
}

const activeVehicle = mapped('active');
assert.strictEqual(activeVehicle.stock, '13080534');
const activeHtml = context.renderIncoming(activeVehicle, {});
assert.match(activeHtml, /pdc-station-sublet is-required is-ordered/);
assert.match(activeHtml, /aria-label="Sublet booked"/);
assert.match(activeHtml, /title="Sublet booked"/);
assert.doesNotMatch(activeHtml, /Sublet Booked/);

const noBookingHtml = context.renderIncoming(mapped('', { required: true, completed: false }), {});
assert.match(noBookingHtml, /pdc-station-sublet is-required/);
assert.doesNotMatch(noBookingHtml, /pdc-station-sublet is-required is-ordered/);

const cancelledHtml = context.renderIncoming(mapped('cancelled', { required: true, completed: false }), {});
assert.doesNotMatch(cancelledHtml, /pdc-station-sublet is-required is-ordered/);

const returnedHtml = context.renderIncoming(mapped('returned', { required: true, completed: false }), {});
assert.doesNotMatch(returnedHtml, /pdc-station-sublet[^\n]*is-ordered/);
assert.match(returnedHtml, /is-required is-complete/);

const completedHtml = context.renderIncoming(mapped('', { required: true, completed: true }), {});
assert.match(completedHtml, /pdc-station-sublet is-required is-complete/);
assert.doesNotMatch(completedHtml, /pdc-station-sublet is-required is-ordered/);

assert.doesNotMatch(vehicleRenderer, /canonicalSubletPill|incoming-card-sublet/,
  'vehicle/model column must not render a duplicate Sublet booking badge');
assert.match(vehicleRenderer, /incoming-card-work-wrap/,
  'Sublet status must remain in the canonical workgroup strip');
assert.match(index, /sublet-workgroup=2026\.08\.31\.3300/);

console.log('Sublet workgroup active/no/cancelled/returned/completed DOM regression: PASS');
