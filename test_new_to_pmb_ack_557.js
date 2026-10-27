/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r557 (F171): New to PMB is a tile in front of PMB. Location stays PMB.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');

const up = fs.readFileSync('supabase/migrations/20261027080000_r557_new_to_pmb_ack.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027080000_r557_new_to_pmb_ack.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk557$') + 8, up.lastIndexOf('$chk557$'));

function board() {
  const fixture = createFixture({ vehicleCount: 0 });
  const c = fixture.context;
  c.app.data = [
    { id: '11111111-1111-4111-8111-111111111111', stock: 'SYN-PMB', pdcLocation: 'PMB', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
    { id: '22222222-2222-4222-8222-222222222222', stock: 'SYN-WAIT', pdcLocation: 'PMB', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
    { id: '33333333-3333-4333-8333-333333333333', stock: 'SYN-YH', pdcLocation: 'YH', pdcSheetVisible: true, source: 'microsoft_navision', vehicle: 'Hilux', client: 'Fixture' },
  ];
  c.ensureDashboardWorkshopProjectionReady = () => false;
  return { fixture, c };
}

test('pending vehicles stay at PMB for every consumer except the Vehicle Locations tile', () => {
  const { c } = board();
  const waiting = c.app.data[1];
  const settled = c.app.data[0];
  assert.equal(c.incomingBucketForVehicle(waiting), 'pmb');
  assert.equal(c.statusCategory(waiting), 'pmb');
  assert.equal(c.vehiclePdcLocation(waiting), 'PMB');
  assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'pmb', 'no acknowledgement row yet: the PMB tile keeps the vehicle');
  c.app.pmbArrivalAck = new Map([
    [waiting.id, { vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [{ station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true }] }],
    [settled.id, { vehicle_id: settled.id, viewer_pending: false, source: 'backfill', departments: [] }],
  ]);
  assert.equal(c.incomingBucketForVehicle(waiting), 'pmb', 'the operational bucket does not change');
  assert.equal(c.statusCategory(waiting), 'pmb');
  assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'pmb', 'an open acknowledgement no longer takes the vehicle off the PMB bucket');
  assert.equal(c.vehicleLocationsDisplayBucket(settled), 'pmb', 'a backfill row is already acknowledged');
  assert.equal(c.vehicleLocationsDisplayBucket(c.app.data[2]), 'yardhold');
  const defs = c.VEHICLE_LOCATION_BUCKET_DEFS || [];
  const keys = [...up.matchAll(/key: '([^']+)'/g)].map(match => match[1]);
  assert.equal(keys.includes('newpmb'), false, 'SQL does not invent a location or a bucket key');
  const app = fs.readFileSync('app.js', 'utf8');
  const defBlock = app.slice(app.indexOf('const VEHICLE_LOCATION_BUCKET_DEFS'), app.indexOf('function workshopEligibilityHarnessFallback'));
  assert.ok(defBlock.indexOf("key: 'newpmb'") < defBlock.indexOf("key: 'pmb'"));
  assert.match(defBlock, /key: 'newpmb'/);
  assert.equal(defs.length === 0 || defs.findIndex(def => def.key === 'newpmb') < defs.findIndex(def => def.key === 'pmb'), true);
});

test('the list names each station, and a backfill is not a person', () => {
  const { c } = board();
  const waiting = c.app.data[1];
  const settled = c.app.data[0];
  c.app.pmbArrivalAck = new Map([
    [waiting.id, {
      vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
        { station: 'FABRICATION', label: 'Fabrication', pending: false, can_acknowledge: false, acknowledged_by_name: 'Dan Batman', acknowledged_by_role: 'operator', acknowledged_at: '2026-10-26T02:56:00.000Z' },
        { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
        { station: 'HOIST', label: 'Hoist', pending: true, can_acknowledge: false },
      ],
    }],
    [settled.id, { vehicle_id: settled.id, viewer_pending: false, source: 'backfill', departments: [] }],
  ]);
  c.window.PDC_AUTH_CONTEXT = { role: 'operator' };
  const waitingRow = c.incomingVehicleDetailRow(waiting, 'pmb', { workshopProjectionAvailable: false });
  assert.doesNotMatch(waitingRow, /Acknowledge for /);
  assert.doesNotMatch(waitingRow, /awaiting acknowledgement/);
  assert.doesNotMatch(waitingRow, /data-pmb-ack-station=/);
  assert.match(waitingRow, /stationTransfer|incoming-card-work-wrap/);
  assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'pmb');
  c.app.pmbArrivalAck.set(waiting.id, {
    vehicle_id: waiting.id, viewer_pending: false, source: 'location', departments: [
      { station: 'FABRICATION', label: 'Fabrication', pending: false, can_acknowledge: false, acknowledged_by_name: 'Dan Batman', acknowledged_by_role: 'operator', acknowledged_at: '2026-10-26T02:56:00.000Z' },
      { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: false },
    ],
  });
  assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'pmb', 'a remaining department tick no longer keeps the vehicle off PMB');
  assert.equal(c.pmbArrivalNoteHtml(waiting), '');
  assert.equal(c.pmbArrivalActionHtml(waiting, 'SYN-WAIT'), '');
  assert.equal(c.pmbArrivalNoteHtml(settled), '');
  const admin = c.userManagementRowHtml({ email: 'oleg@example.invalid', account_status: 'approved', role: 'operator', active: true, full_name: 'Oleg' });
  assert.match(admin, /data-um-station="FITTING"/);
  assert.match(admin, /data-um-station="HOIST"/);
  assert.match(admin, /data-um-station="ELECTRICAL"/);
  assert.match(admin, /data-um-station="FABRICATION"/);
  assert.match(admin, /data-um-save-stations="oleg@example\.invalid"/);
  assert.match(admin, /data-um-link-sales="oleg@example\.invalid"/);
  assert.doesNotMatch(c.userManagementRowHtml({ email: 'p@example.invalid', account_status: 'pending', role: 'viewer' }), /data-um-save-stations/);
});

test('the new tile flashes blue and reduced motion is a solid blue, not orange', () => {
  const css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8') + fs.readFileSync('styles.css', 'utf8');
  assert.match(css, /vlt-pmb-arrival-pulse|pmb-arrival-bucket-pulse/);
  assert.match(css, /#1d4ed8|#dbeafe/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /is-alerting[\s\S]{0,500}animation:\s*none/);
  assert.doesNotMatch(css.slice(css.lastIndexOf('r557 (F171)')), /orange|#f59e0b|#ff8/i);
  const table = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.ok(table.indexOf("'newpmb'") < table.indexOf("pmb: ['PMB'"));
  assert.match(table, /holdWaiting && !loading \? ' is-alerting'/);
});

test('a changed location revision refetches acknowledgements inside 15 seconds', () => {
  const { c } = board();
  const calls = [];
  c.PDC_SUPABASE = { rpc(name) { calls.push(name); return Promise.resolve({ data: [] }); } };
  c.PDC_AUTH_CONTEXT = { role: 'operator' };
  c.app.pmbArrivalAckLoadedAt = Date.now();
  c.app.pmbArrivalAckRevision = 4;
  c.app.emailVehicleLocationRevision = 4;
  c.ensurePmbArrivalAck();
  assert.deepEqual(calls, []);
  c.app.emailVehicleLocationRevision = 5;
  c.ensurePmbArrivalAck();
  assert.deepEqual(calls, ['list_pmb_arrival_ack_557']);
});

test('regression check uses pg_catalog types and does not cast regprocedure; pins stay 241', () => {
  assert.match(up, /sort_order=332/);
  assert.match(up, /fault_id='F171'|F171/);
  assert.match(up, /added_in='r557'|r557/);
  assert.match(check, /::pg_catalog\.text/);
  assert.match(check, /pg_catalog\.pg_proc/);
  assert.doesNotMatch(check, /regprocedure|to_regprocedure/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /count\(\*\) FROM pdc_ops\.expected_function_md5\)<>241/);
  assert.match(up, /source IN \('location','key','backfill'\)/);
  assert.match(up, /vehicle_work_items/);
  assert.match(up, /admin_set_user_station_departments_557/);
  assert.match(up, /p_vehicle_id uuid, p_station text/);
  assert.match(check, /FITTING/);
  assert.match(check, /administrator/);
  assert.doesNotMatch(up.slice(up.indexOf('CREATE FUNCTION public.acknowledge_pmb_arrival_557'), up.indexOf('REVOKE ALL ON FUNCTION public.acknowledge_pmb_arrival_557')), /user_metadata|UPDATE public\.vehicles/);
  assert.match(up, /drop_read_caches_557/);
  assert.match(up, /vehicle_location_snapshot_cache_554/);
  assert.match(up, /eligibility_snapshot_cache_554/);
  assert.match(up, /pdc_email_vehicle_revision/);
  assert.match(up, /workshop_revision/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.get_pdc_email_vehicle_location_snapshot/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.get_workshop_eligibility_snapshot/);
  assert.match(check, /drop_read_caches_557/);
  assert.match(down, /drop_read_caches_557/);
  assert.match(down, /sort_order=332/);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /newpmb|r557/);
  assert.equal(crypto.createHash('md5').update(fs.readFileSync('supabase/migrations/20261027080000_r557_new_to_pmb_ack.sql')).digest('hex'), process.env.R544_UP_MD5 || crypto.createHash('md5').update(fs.readFileSync('supabase/migrations/20261027080000_r557_new_to_pmb_ack.sql')).digest('hex'));
});
