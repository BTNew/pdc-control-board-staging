/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r582 (F195) / sort 353. A body-builder delivery waits in New to PMB until To PMB.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const pmg = require('./vehicle-location-lifecycle.js');
const karratha = require('./karratha/vehicle-location-lifecycle.js');

const up = fs.readFileSync('supabase/migrations/20261027233000_r574_bodybuilder_new_to_pmb.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027233000_r574_bodybuilder_new_to_pmb.down.sql', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const check = up.slice(up.indexOf('$chk574$') + 8, up.lastIndexOf('$chk574$'));
const capture = up.slice(up.indexOf('$capture574$') + 12, up.indexOf('$capture574$', up.indexOf('$capture574$') + 12));

function board() {
  const fixture = createFixture({ vehicleCount: 0 });
  const c = fixture.context;
  c.app.data = [{
    id: '55555555-5555-4555-8555-555555555555',
    stock: '13094088',
    pdcLocation: 'PMB',
    current_location: 'PMB',
    pdcSheetVisible: true,
    source: 'microsoft_navision',
    vehicle: 'Hilux',
    client: 'Fixture',
    keyNumber: '418',
    navisionSubLocationDescription: 'Delivered - At Body Builder',
    navisionLocationStatus: 'OD',
  }];
  c.ensureDashboardWorkshopProjectionReady = () => false;
  return c;
}

test('the preview keeps the body-builder delivery in New to PMB until To PMB', () => {
  for (const phrase of ['deliveredatbodybuilder', 'deliveredtobodybuilder', 'oddeliveredtobodybuilder']) {
    assert.ok(up.includes(`'${phrase}'`), phrase);
  }
  assert.ok(up.includes('PDC_574_TO_PMB_ONLY'));
  assert.ok(up.includes("release_action = 'to_pmb'"));
  assert.equal(capture.includes('UPDATE public.vehicles'), false);
  assert.ok(up.includes('pins.n = 241'));
  assert.ok(up.includes('sort_order, added_in) VALUES'));
  assert.ok(up.includes(", 353, 'r582'"));
  assert.ok(up.includes("'F195'"));
  assert.equal(up.includes(", 345, 'r574'"), false);
  assert.equal(up.includes("fault_id = 'F188'"), false);
  assert.equal(/CREATE OR REPLACE FUNCTION karratha135_pdc/i.test(up), false);
  assert.ok(up.includes('Broome Sales 37047 and Karratha Sales 14450 are not written.'));
  assert.equal((up.match(/37047/g) || []).length, 1);
  assert.equal((up.match(/14450/g) || []).length, 1);
  assert.ok(check.includes('AS ok'));
  assert.ok(check.includes('AS detail'));
  assert.ok(check.includes('slipped.n = 0'));
  assert.ok(check.includes('reached.n = 0'));
  assert.ok(check.includes('k135_loc_md5'));
  assert.ok(check.includes('sales_tile_md5'));
  assert.equal(check.includes("current_setting('pdc.r574_"), false);
  assert.equal(/pg_catalog\.position\s*\(/i.test(check), false);
  assert.ok(check.includes('pg_catalog.strpos'));
  const badge = css.slice(css.indexOf('.badge.pmb-bodybuilder-hold'), css.indexOf('.badge.pmb-bodybuilder-hold') + 180);
  assert.match(badge, /#1d4ed8/);
  assert.match(badge, /#dbeafe/);
  assert.doesNotMatch(badge, /orange|#f97316|#ea580c|#c2410c/i);
});

test('OD Delivered to body builder holds for To PMB, and a dealer delivery does not', () => {
  const held = pmg.resolveVehicleLifecycleLocation({
    navisionLocationStatus: 'OD',
    navisionSubLocationDescription: 'OD - Delivered To Bodybuilder',
    current_location: 'YH',
  });
  assert.equal(held.location, 'PMB');
  assert.equal(held.transition, 'new_to_pmb_hold');
  assert.equal(held.holdUntilToPmb, true);
  const live = pmg.resolveVehicleLifecycleLocation({
    navisionSubLocationDescription: 'Delivered - At Body Builder',
    current_location: 'IT',
  });
  assert.equal(live.location, 'PMB');
  assert.equal(live.holdUntilToPmb, true);
  const dealer = pmg.resolveVehicleLifecycleLocation({
    navisionSubLocationDescription: 'Delivered - At Dealer',
    current_location: 'YH',
  });
  assert.equal(dealer.location, 'YH');
  assert.equal(dealer.holdUntilToPmb, undefined);
  const despatched = pmg.resolveVehicleLifecycleLocation({
    navisionSubLocationDescription: 'Despatched - From Body Builder',
    current_location: 'YH',
  });
  assert.equal(despatched.holdUntilToPmb, undefined);
  assert.equal(despatched.location, 'YH');
  const local = karratha.resolveVehicleLifecycleLocation({ toyotaStatus: 'Delivered - At Body Builder' });
  assert.equal(local.location, 'PMB');
  assert.notEqual(local.holdUntilToPmb, true);
});

test('a keyed body-builder delivery stays on New to PMB until To PMB', () => {
  const c = board();
  const vehicle = c.app.data[0];
  c.app.pmbArrivalAck = new Map([[vehicle.id, {
    vehicle_id: vehicle.id,
    viewer_pending: false,
    closed: false,
    source: 'bodybuilder',
    departments: [],
  }]]);
  assert.equal(c.vehicleLocationsDisplayBucket(vehicle), 'newpmb');
  const row = c.incomingVehicleDetailRow(vehicle, 'newpmb', { workshopProjectionAvailable: false });
  assert.match(row, /class="badge pmb-bodybuilder-hold"/);
  assert.match(row, /Delivered to body builder/);
  assert.match(row, /Check the key number, then press To PMB/);
  const action = c.pmbArrivalActionHtml(vehicle, '13094088');
  assert.match(action, /data-pmb-push="13094088"/);
  assert.match(action, />To PMB</);
  assert.doesNotMatch(action, /pmb-push-disabled/);
});

test('To PMB stays disabled until the key number is present', () => {
  const c = board();
  const vehicle = c.app.data[0];
  delete vehicle.keyNumber;
  c.app.pmbArrivalAck = new Map([[vehicle.id, {
    vehicle_id: vehicle.id,
    viewer_pending: true,
    closed: false,
    source: 'bodybuilder',
    departments: [],
  }]]);
  const action = c.pmbArrivalActionHtml(vehicle, '13094088');
  assert.match(action, /pmb-push-disabled/);
  assert.match(action, /disabled/);
  assert.doesNotMatch(action, /data-pmb-push/);
  assert.match(c.incomingVehicleDetailRow(vehicle, 'newpmb', { workshopProjectionAvailable: false }), /Key number needed/);
});

test('a closed body-builder arrival stays on the PMB tile', () => {
  const c = board();
  const vehicle = c.app.data[0];
  c.app.pmbArrivalAck = new Map([[vehicle.id, {
    vehicle_id: vehicle.id,
    viewer_pending: false,
    closed: true,
    source: 'bodybuilder',
    departments: [],
  }]]);
  assert.equal(c.vehicleLocationsDisplayBucket(vehicle), 'pmb');
  assert.equal(c.pmbBodybuilderHoldHtml(vehicle), '');
  assert.equal(c.pmbArrivalActionHtml(vehicle, '13094088'), '');
});

test('the down file restores the live mapping and drops the hold', () => {
  const loc = down.slice(down.indexOf('$loc$') + 5, down.indexOf('$loc$', down.indexOf('$loc$') + 5));
  assert.match(loc, /v_status='deliveredatbodybuilder'/);
  assert.equal(loc.includes('bodybuilder_status_574'), false);
  assert.ok(down.includes('DROP TABLE IF EXISTS pdc_pmb_ack_private.bodybuilder_hold_574'));
  assert.ok(down.includes('DROP FUNCTION IF EXISTS pdc_pmb_ack_private.bodybuilder_status_574(text)'));
  assert.equal((down.match(/UPDATE public\.vehicles/g) || []).length, 1);
  assert.equal(/DELETE FROM public\.vehicles/i.test(down), false);
  assert.equal(/DELETE FROM public\.pdc_pmb_arrival_557/i.test(down), false);
});
