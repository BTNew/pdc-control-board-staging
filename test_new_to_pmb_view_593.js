/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r593 (F207) / sort 363. New to PMB is a view. A Yard Hold or non-division
// vehicle ticked To PMB, with a key number, stays in the PMB bucket. A key
// under the window (4 days) is also listed in New to PMB. The counter is display only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');

const up = fs.readFileSync('supabase/migrations/20261028061000_r593_new_to_pmb_view.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028061000_r593_new_to_pmb_view.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk593$') + 8, up.lastIndexOf('$chk593$'));
const capture = up.slice(up.indexOf('$capture593$') + 12, up.indexOf('$capture593$', up.indexOf('$capture593$') + 12));

function board() {
  const fixture = createFixture({ vehicleCount: 0 });
  const c = fixture.context;
  const now = new Date();
  const recent = new Date(now.getTime() - 2 * 3600000).toISOString(); // r679: inside the 24-hour window
  const old = new Date(now.getTime() - 10 * 86400000).toISOString();
  c.app.data = [
    { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', stock: '13092999', keyNumber: '10', keyAssignedAt: recent, pdcLocation: 'PMB', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
    { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', stock: '13008249', keyNumber: '238', keyAssignedAt: old, pdcLocation: 'PMB', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
    { id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', stock: '12660039', pdcLocation: 'PMB', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
    { id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', stock: '13094088', keyNumber: '418', keyAssignedAt: old, pdcLocation: 'PMB', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
  ];
  c.app.pmbArrivalAck = new Map([[c.app.data[3].id, {
    vehicle_id: c.app.data[3].id, viewer_pending: true, source: 'bodybuilder', closed: false, departments: [],
  }]]);
  c.ensureDashboardWorkshopProjectionReady = () => false;
  return c;
}

test('a recent key is in both places and an old or missing key stays in PMB only', () => {
  const c = board();
  const [recent, aged, bare, held] = c.app.data;
  assert.equal(c.vehicleLocationsDisplayBuckets(recent).join(','), 'pmb,newpmb');
  assert.equal(c.vehicleLocationsDisplayBucket(recent), 'pmb');
  assert.equal(c.incomingBucketForVehicle(recent), 'pmb');
  assert.equal(c.vehicleLocationsDisplayBuckets(aged).join(','), 'pmb');
  assert.equal(c.pmbKeyIsNew(bare), false);
  assert.equal(c.vehicleLocationsDisplayBuckets(bare).join(','), 'pmb');
  assert.equal(c.vehicleLocationsDisplayBuckets(held).join(','), 'newpmb');
  assert.match(c.pmbNewTagHtml(recent), /class="badge pmb-new-tag"/);
  assert.match(c.pmbNewTagHtml(recent), /New to PMB/);
  assert.doesNotMatch(c.pmbNewTagHtml(recent), /orange|#f59e0b|#ff8/i);
  assert.equal(c.pmbNewTagHtml(aged), '');
  assert.equal(c.pmbNewTagHtml(bare), '');
  const recentCard = c.incomingVehicleDetailRow(recent, 'pmb', { workshopProjectionAvailable: false });
  assert.match(recentCard, /pmb-new-tag/);
  assert.doesNotMatch(recentCard, /Acknowledge for |data-pmb-ack|awaiting acknowledgement/);
  assert.match(recentCard, /data-pit-transfer|data-ready-for-qc/);
  const holdCard = c.incomingVehicleDetailRow(held, 'newpmb', { workshopProjectionAvailable: false });
  assert.match(holdCard, /data-pmb-push=/);
  assert.doesNotMatch(holdCard, /Acknowledge for /);
  assert.equal(c.pmbArrivalActionHtml(recent, '13092999'), '');
  const newOnes = c.app.data.filter(vehicle => c.vehicleLocationsDisplayBuckets(vehicle).includes('newpmb') && c.pmbKeyIsNew(vehicle));
  assert.deepEqual(newOnes.map(vehicle => vehicle.stock), ['13092999']);
});

test('the window is 24 hours (r679) and a missing setting does not invent a timestamp', () => {
  const c = board();
  assert.equal(c.newToPmbWindowDays(), 1);
  c.app.newToPmbWindowDays = 7;
  assert.equal(c.newToPmbWindowDays(), 1, 'a stored window no longer changes the 24 hours');
  const day = c.app.data[0];
  const saved = day.keyAssignedAt;
  day.keyAssignedAt = new Date(Date.now() - 25 * 3600000).toISOString();
  assert.equal(c.pmbKeyIsNew(day), false, 'a key older than 24 hours is not New to PMB');
  day.keyAssignedAt = saved;
  const recent = c.app.data[0];
  delete recent.keyAssignedAt;
  assert.equal(c.pmbKeyIsNew(recent), false);
});

test('To PMB asks for a key after the confirm, and a bulk move skips a vehicle with no key', () => {
  const app = fs.readFileSync('app.js', 'utf8');
  const single = app.slice(app.indexOf('async function transferYhVehicleToPmb'), app.indexOf('\nfunction ', app.indexOf('async function transferYhVehicleToPmb') + 20));
  assert.ok(single.indexOf('window.confirm') < single.indexOf('window.prompt'));
  assert.match(single, /set_pdc_vehicle_key_number_460/);
  const bulk = app.slice(app.indexOf('async function transferSelectedYhVehiclesToPmb'), app.indexOf('async function transferYhVehicleToPmb'));
  assert.match(bulk, /withKey/);
  assert.match(bulk, /no key number/);
});

test('the preview is r593 / F207 / sort 363, pins stay 241, and the capture no longer queues an acknowledgement', () => {
  assert.match(up, /sort_order=363|363, 'r593'/);
  assert.match(up, /'F207'/);
  assert.match(up, /new_to_pmb_view_593/);
  assert.match(up, /363, 'r593'/);
  assert.match(up, /count\(\*\) FROM pdc_ops\.expected_function_md5\) <> 241/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.match(up, /626ca8b23a2e5f02e2ca8f96a4533d6f/);
  assert.match(capture, /YARD HOLD/);
  assert.match(capture, /IN TRANSIT/);
  assert.match(capture, /OTHER/);
  assert.match(capture, /INSERT/);
  assert.match(capture, /location_override/);
  assert.match(capture, /PMB/);
  assert.match(capture, /QC/);
  assert.match(capture, /PIT/);
  assert.match(capture, /RFT/);
  assert.match(capture, /drop_read_caches_557/);
  assert.match(capture, /bodybuilder_hold_574/);
  assert.match(capture, /release_action = 'to_pmb'/);
  assert.match(capture, /r593_no_ack/);
  assert.match(capture, /IF NOT v_body THEN/);
  assert.equal(capture.includes('UPDATE public.vehicles'), false);
  assert.match(up, /PDC_562_KEY_NUMBER_NEEDED/);
  assert.match(up, /PDC_574_TO_PMB_ONLY/);
  assert.equal(up.includes('arrival_insert_guard_562'), false);
  assert.equal(up.includes('acknowledge_pmb_arrival_557'), false);
  assert.match(up, /pdc\.r593_release_ack/);
  const push = up.slice(up.indexOf('$push593$') + 9, up.indexOf('$push593$', up.indexOf('$push593$') + 9));
  assert.equal(push.includes('stations_outstanding'), false);
  assert.match(push, /key_number_needed|PDC_562_KEY_NUMBER_NEEDED|needs_key/);
  assert.match(push, /pdc\.bodybuilder_to_pmb_574/);
  assert.match(push, /release_action = 'to_pmb'/);
  assert.match(push, /released_by = v_actor/);
  assert.doesNotMatch(push, /UPDATE public\.vehicles/);
  assert.match(check, /AS ok/);
  assert.match(check, /AS detail/);
  assert.match(check, /pg_catalog\.strpos/);
  assert.match(check, /pins\.n = 241/);
  assert.doesNotMatch(check, /regprocedure|to_regprocedure/);
  assert.doesNotMatch(check, /expected_function_md5\)\s*=\s*[0-9]+/);
  assert.match(check, /workshop_create_booking/);
  assert.match(down, /stations_outstanding/);
  assert.match(down, /YARD HOLD/);
  assert.match(down, /DROP FUNCTION IF EXISTS public\.list_new_to_pmb_window_593/);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /r593|pmb-new-tag/);
  assert.doesNotMatch(fs.readFileSync('karratha/styles.css', 'utf8'), /pmb-new-tag/);
  const css = fs.readFileSync('styles.css', 'utf8');
  const badge = css.slice(css.lastIndexOf('.badge.pmb-new-tag'));
  assert.match(badge, /#1d4ed8/);
  assert.match(badge, /#dbeafe/);
  assert.doesNotMatch(badge.slice(0, 180), /orange|#f59e0b|#ff8/i);
});
