/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r562 (F176) / sort 335. Craig approved go-live 27 Oct 2026 08:10 AWST. A vehicle cannot leave New to PMB without a key number.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');

const up = fs.readFileSync('supabase/migrations/20261027103000_r562_pmb_key_gate.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027103000_r562_pmb_key_gate.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk562$') + 8, up.lastIndexOf('$chk562$'));

function board() {
  const fixture = createFixture({ vehicleCount: 0 });
  const c = fixture.context;
  c.app.data = [{
    id: '44444444-4444-4444-8444-444444444444',
    stock: '13102818',
    pdcLocation: 'PMB',
    pdcSheetVisible: true,
    source: 'microsoft_navision',
    vehicle: 'Hilux',
    client: 'Fixture',
    pmbEnteredAt: '2026-10-20T08:00:00+08:00',
    firstEnteredPmbAt: '2026-10-20T08:00:00+08:00',
  }];
  c.ensureDashboardWorkshopProjectionReady = () => false;
  return { fixture, c };
}

test('a vehicle with no key cannot complete the move into PMB', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  c.app.pmbArrivalAck = new Map([[waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
      { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
    ],
  }]]);
  const row = c.incomingVehicleDetailRow(waiting, 'newpmb', { workshopProjectionAvailable: false });
  assert.match(row, /Key number needed/);
  assert.match(row, /class="badge pmb-key-needed"/);
  assert.match(row, /pmb-push-disabled/);
  assert.match(row, /A key number is needed before this vehicle can move from New to PMB into PMB\./);
  assert.doesNotMatch(row, /data-pmb-ack=/);
  assert.match(row, /disabled/);
  assert.equal(c.incomingVehicleAge(waiting, 'newpmb').label, 'No key');
  assert.equal(c.pmbLifecycleAgeLabel(waiting), 'No key');
  const action = c.pmbArrivalActionHtml(waiting, '13102818');
  assert.match(action, /disabled/);
  assert.doesNotMatch(action, /data-pmb-ack/);
});

test('a non-closing station stays available, and a key enables the completing push', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  c.app.pmbArrivalAck = new Map([[waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
      { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
      { station: 'HOIST', label: 'Hoist', pending: true, can_acknowledge: false },
    ],
  }]]);
  const open = c.pmbArrivalActionHtml(waiting, '13102818');
  assert.match(open, /data-pmb-ack-station="FITTING"/);
  assert.doesNotMatch(open, /pmb-push-disabled/);
  waiting.keyNumber = '205';
  waiting.keyAssignedAt = '2026-10-20T08:00:00+08:00';
  c.app.pmbArrivalAck.set(waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
      { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
    ],
  });
  const closing = c.pmbArrivalActionHtml(waiting, '13102818');
  assert.match(closing, /data-pmb-ack-station="FITTING"/);
  assert.doesNotMatch(closing, /pmb-push-disabled/);
  assert.equal(c.pmbKeyNeededBadgeHtml(waiting), '');
  c.app.pmbArrivalAck.set(waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [],
  });
  delete waiting.keyNumber;
  const blockedPush = c.pmbArrivalActionHtml(waiting, '13102818');
  assert.match(blockedPush, />To PMB</);
  assert.match(blockedPush, /disabled/);
  assert.doesNotMatch(blockedPush, /data-pmb-push/);
  waiting.keyNumber = '205';
  const push = c.pmbArrivalActionHtml(waiting, '13102818');
  assert.match(push, /data-pmb-push="13102818"/);
  assert.doesNotMatch(push, /disabled/);
});

test('PMB age follows the key assignment, not the arrival', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  const realDate = Date;
  c.Date = class extends realDate {
    constructor(...args) { super(...(args.length ? args : ['2026-10-26T12:00:00+08:00'])); }
  };
  waiting.keyNumber = '205';
  waiting.keyAssignedAt = '2026-10-20T08:00:00+08:00';
  assert.equal(c.incomingVehicleAge(waiting, 'pmb').label, '6 days');
  assert.equal(c.incomingVehicleAge(waiting, 'pmb').title, 'Days since the key number was assigned');
  assert.equal(c.pmbLifecycleAgeLabel(waiting), '6 days');
  waiting.pmbEnteredAt = '2026-10-01T08:00:00+08:00';
  assert.equal(c.incomingVehicleAge(waiting, 'newpmb').label, '6 days');
  delete waiting.keyAssignedAt;
  c.app.pmbKeyAssigned = new Map([[waiting.id, { vehicle_id: waiting.id, assigned_at: '2026-10-25T08:00:00+08:00', has_key: true }]]);
  assert.equal(c.pmbAgeLabel(waiting), '1 day');
  delete waiting.keyNumber;
  c.app.pmbKeyAssigned = new Map();
  assert.equal(c.incomingVehicleAge(waiting, 'pmb').label, 'No key');
  assert.notEqual(c.incomingVehicleAge(waiting, 'pmb').label, '0 days');
});

test('the key list refetches when the location revision changes', () => {
  const { c } = board();
  const calls = [];
  c.PDC_SUPABASE = { rpc(name) { calls.push(name); return Promise.resolve({ data: [] }); } };
  c.PDC_AUTH_CONTEXT = { role: 'operator' };
  c.app.pmbKeyAssignedLoadedAt = Date.now();
  c.app.pmbKeyAssignedRevision = 4;
  c.app.emailVehicleLocationRevision = 4;
  c.ensurePmbKeyAssigned();
  assert.deepEqual(calls, []);
  c.app.emailVehicleLocationRevision = 5;
  c.ensurePmbKeyAssigned();
  assert.deepEqual(calls, ['list_pmb_key_assigned_562']);
});

test('regression check is r562 / F176 / sort 335 and does not add a pin', () => {
  assert.match(up, /sort_order=335/);
  assert.match(up, /fault_id='F176'/);
  assert.match(up, /added_in='r562'/);
  assert.match(up, /PDC_562_KEY_NUMBER_NEEDED/);
  assert.match(up, /key_number_needed/);
  assert.match(up, /location_override/);
  assert.match(up, /AFTER INSERT OR UPDATE OF current_location, key_number, location_override/);
  assert.match(up, /YARD HOLD/);
  assert.match(up, /IN TRANSIT/);
  assert.match(up, /OTHER/);
  assert.match(up, /audit_460/);
  assert.match(up, /audit_events/);
  assert.match(up, /service_snapshot/);
  assert.match(check, /::pg_catalog\.text/);
  assert.doesNotMatch(check, /regprocedure|to_regprocedure/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /count\(\*\) FROM pdc_ops\.expected_function_md5\)<>241/);
  assert.match(up, /bay_default_clock_gap_559/);
  assert.match(up, /new_to_pmb_ack_557/);
  assert.match(up, /r561 \/ F175 is the slim planner header/);
  assert.match(up, /\$chk562\$, true, 335, 'r562'/);
  assert.match(down, /DROP TABLE IF EXISTS public\.pdc_vehicle_key_assigned_562/);
  assert.match(down, /AFTER UPDATE OF current_location, key_number ON public\.vehicles/);
  assert.match(down, /YARD HOLD/);
  assert.match(down, /sort_order=335/);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /r560|pmb-key-needed|Key number needed/);
  const css = fs.readFileSync('styles.css', 'utf8');
  const badge = css.slice(css.lastIndexOf('r562 (F176)'));
  assert.match(badge, /#dbeafe/);
  assert.match(badge, /#1d4ed8/);
  assert.doesNotMatch(badge, /orange|#f59e0b|#ff8/i);
});
