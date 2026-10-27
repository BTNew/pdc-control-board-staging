/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r563 (F177) / sort 336. Craig approved go-live 27 Oct 2026 08:40 AWST.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');

const up = fs.readFileSync('supabase/migrations/20261027120000_r563_pmb_arrival_age.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027120000_r563_pmb_arrival_age.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk563$') + 8, up.lastIndexOf('$chk563$'));

function board(rows) {
  const fixture = createFixture({ vehicleCount: 0 });
  const c = fixture.context;
  const realDate = Date;
  c.Date = class extends realDate {
    constructor(...args) { super(...(args.length ? args : ['2026-10-27T12:00:00+08:00'])); }
  };
  c.app.data = rows;
  c.ensureDashboardWorkshopProjectionReady = () => false;
  return c;
}

test('the earlier of the key and the Tune import is the PMB age', () => {
  const keyEarlier = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    stock: '13070060',
    pdcLocation: 'PMB',
    keyNumber: '318',
    keyAssignedAt: '2026-10-19T09:15:00+08:00',
    tuneImportedAt: '2026-10-19T10:19:00+08:00',
    pmbEnteredAt: '2026-10-01T08:00:00+08:00',
  };
  const tuneEarlier = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    stock: '12238967',
    pdcLocation: 'PMB',
    keyNumber: '512',
    keyAssignedAt: '2026-10-06T16:35:00+08:00',
    tuneImportedAt: '2026-09-17T14:33:00+08:00',
    dateToPmb: '2026-10-06',
  };
  const keylessTune = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
    stock: '13047383',
    pdcLocation: 'PMB',
    tuneImportedAt: '2026-10-06T16:37:00+08:00',
    dateToPmb: '2026-10-06',
  };
  const fallback = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
    stock: 'SYN-NONE',
    pdcLocation: 'PMB',
    pmbEnteredAt: '2026-10-01T08:00:00+08:00',
    firstEnteredPmbAt: '2026-10-01T08:00:00+08:00',
  };
  const missing = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5',
    stock: 'SYN-MISS',
    pdcLocation: 'PMB',
  };
  const c = board([keyEarlier, tuneEarlier, keylessTune, fallback, missing]);
  assert.equal(c.incomingVehicleAge(keyEarlier, 'pmb').label, '8 days');
  assert.equal(c.incomingVehicleAge(keyEarlier, 'pmb').title, 'Days since the key number was assigned');
  assert.equal(c.pmbArrivalAgeFlagHtml(keyEarlier), '');
  assert.equal(c.incomingVehicleAge(tuneEarlier, 'pmb').label, '40 days');
  assert.equal(c.incomingVehicleAge(tuneEarlier, 'pmb').title, 'Days since this vehicle first appeared in a Tune import');
  assert.equal(c.incomingVehicleAge(keylessTune, 'newpmb').label, '21 days');
  assert.equal(c.incomingVehicleAge(keylessTune, 'pmb').title, 'Days since this vehicle first appeared in a Tune import');
  assert.notEqual(c.incomingVehicleAge(keylessTune, 'pmb').label, 'No key');
  assert.equal(c.incomingVehicleAge(fallback, 'pmb').label, '26 days');
  assert.match(c.incomingVehicleAge(fallback, 'pmb').title, /board arrival/);
  assert.match(c.pmbArrivalAgeFlagHtml(fallback), /class="badge pmb-age-fallback"/);
  assert.match(c.pmbArrivalAgeFlagHtml(fallback), />Board arrival</);
  assert.doesNotMatch(c.pmbArrivalAgeFlagHtml(fallback), /orange|#f59e0b/i);
  assert.equal(c.incomingVehicleAge(missing, 'pmb').label, 'No key');
  assert.match(c.pmbArrivalAgeFlagHtml(missing), /Arrival date not on file/);
  const report = c.pmbArrivalAgeReportHtml([keyEarlier, tuneEarlier, keylessTune, fallback, missing]);
  assert.match(report, /Arrival date not on file/);
  assert.match(report, /SYN-NONE/);
  assert.match(report, /SYN-MISS/);
  assert.doesNotMatch(report, /13070060|12238967|13047383/);
  c.app.pmbArrivalAck = new Map([[keylessTune.id, {
    vehicle_id: keylessTune.id, viewer_pending: true, source: 'location', departments: [
      { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
    ],
  }]]);
  const blocked = c.incomingVehicleDetailRow(keylessTune, 'newpmb', { workshopProjectionAvailable: false });
  assert.match(blocked, /Key number needed/);
  assert.match(blocked, /pmb-push-disabled/);
  assert.match(blocked, /21 days|Days since this vehicle first appeared in a Tune import/);
  const fromList = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6',
    stock: '13000001',
    pdcLocation: 'QC',
  };
  c.app.pmbArrivalAge = new Map([[fromList.id, {
    vehicle_id: fromList.id, basis: 'tune', tune_at: '2026-10-20T08:00:00+08:00', arrived_at: '2026-10-20T08:00:00+08:00', key_at: null,
  }]]);
  assert.equal(c.incomingVehicleAge(fromList, 'qc').label, '7 days');
  assert.equal(c.incomingVehicleAge(fromList, 'qc').title, 'Days since this vehicle first appeared in a Tune import');
});

test('regression check is r563 / F177 / sort 336 and does not add a pin', () => {
  assert.match(up, /sort_order=336/);
  assert.match(up, /fault_id='F177'/);
  assert.match(up, /added_in='r563'/);
  assert.match(up, /TUNE\/PMG:/);
  assert.match(up, /tune_pmb_complete_receipts/);
  assert.match(up, /tune_checkout_receipts/);
  assert.match(up, /pdc_tune_intake_evidence_v5/);
  assert.match(up, /pdc_vehicle_key_assigned_562/);
  assert.match(up, /pmb_key_gate_562/);
  assert.match(up, /fallback/);
  assert.match(up, /list_pmb_arrival_age_563/);
  assert.match(up, /zz_pdc_arrival_age_563_key/);
  assert.match(up, /zz_pdc_arrival_age_563_pmb/);
  assert.match(up, /zz_pdc_arrival_age_563_out/);
  assert.match(up, /zz_pdc_arrival_age_563_evidence/);
  assert.match(up, /zz_pdc_arrival_age_563_veh_upd/);
  assert.match(up, /AFTER UPDATE OF stock_number, permanent_vehicle_id, source_system, source_payload/);
  assert.match(check, /::pg_catalog\.text/);
  assert.match(check, /trg\.n = 6/);
  assert.doesNotMatch(check, /regprocedure|to_regprocedure/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /count\(\*\) FROM pdc_ops\.expected_function_md5\)<>241/);
  assert.match(up, /\$chk561\$, true, 336, 'r563'/);
  assert.match(down, /DROP TABLE IF EXISTS public\.pdc_vehicle_pmb_arrival_age_563/);
  assert.match(down, /pdc_vehicle_key_assigned_562/);
  assert.match(down, /sort_order=336/);
  assert.doesNotMatch(down, /DROP TABLE IF EXISTS public\.pdc_vehicle_key_assigned_562/);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /r563|pmb-age-fallback|list_pmb_arrival_age_563/);
  const css = fs.readFileSync('styles.css', 'utf8');
  const badge = css.slice(css.lastIndexOf('r563 (F177)'));
  assert.match(badge, /#e2e8f0/);
  assert.match(badge, /pmb-age-fallback/);
  assert.doesNotMatch(badge, /orange|#f59e0b|#ff8/i);
});
