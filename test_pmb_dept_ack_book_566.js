/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r574 (F188) / sort 345. A department tick is labelled for that
// department, then that department can book a keyed vehicle into one of its
// bays with the existing planner calls. The vehicle then leaves that
// department's New to PMB list.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');

const upPath = 'supabase/migrations/20261027200000_r566_pmb_dept_ack_book.sql';
const downPath = 'supabase/rollbacks/20261027200000_r566_pmb_dept_ack_book.down.sql';
const up = fs.readFileSync(upPath, 'utf8');
const down = fs.readFileSync(downPath, 'utf8');
const check = up.slice(up.indexOf('$chk566$') + 8, up.lastIndexOf('$chk566$'));

function board() {
  const fixture = createFixture({ vehicleCount: 0 });
  const c = fixture.context;
  c.app.data = [{
    id: '55555555-5555-4555-8555-555555555555',
    stock: '13047270',
    keyNumber: '248',
    pdcLocation: 'PMB',
    pdcSheetVisible: true,
    source: 'microsoft_navision',
    vehicle: 'Hilux',
    client: 'Fixture',
  }];
  c.ensureDashboardWorkshopProjectionReady = () => false;
  c.PDC_WORKSHOP_DEPARTMENTS = {
    pmbBayLabel(stage, bay) {
      if (String(stage).toUpperCase() !== 'FITTING') return '';
      const number = Number(bay);
      if (number < 1 || number > 5) return '';
      return `Fitting · Bay ${String(number + 5).padStart(2, '0')}`;
    },
  };
  return { fixture, c };
}

function fittingDepartments({ fitting = true, hoist = true, electrical = true, fabricationPending = true, fabricationMine = false } = {}) {
  return [
    { station: 'FITTING', label: 'Fitting', pending: fitting, can_acknowledge: fitting },
    { station: 'HOIST', label: 'Hoist', pending: hoist, can_acknowledge: hoist },
    { station: 'ELECTRICAL', label: 'Electrical', pending: electrical, can_acknowledge: electrical },
    { station: 'FABRICATION', label: 'Fabrication', pending: fabricationPending, can_acknowledge: fabricationMine },
  ];
}

test('the signed-in departments each get their own tick, labelled for that department', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  c.app.pmbArrivalAck = new Map([[waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: fittingDepartments(),
  }]]);
  const row = c.incomingVehicleDetailRow(waiting, 'newpmb', { workshopProjectionAvailable: false });
  assert.match(row, /Acknowledge for Fitting/);
  assert.match(row, /Acknowledge for Hoist/);
  assert.match(row, /Acknowledge for Electrical/);
  assert.doesNotMatch(row, /Acknowledge for Fabrication/);
  assert.match(row, /data-pmb-ack-station="FITTING"/);
  assert.match(row, /data-pmb-ack-station="HOIST"/);
  assert.match(row, /data-pmb-ack-station="ELECTRICAL"/);
  assert.doesNotMatch(row, /data-pmb-ack-station="FABRICATION"/);
  assert.match(row, /pmb-ack-tick/);
  assert.equal(c.incomingBucketForVehicle(waiting), 'pmb');
  assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'newpmb');
});

test('a keyed tick offers that department’s bays and Best slot, then the vehicle leaves that list', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  c.app.pmbArrivalAck = new Map([[waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: fittingDepartments({ hoist: false, electrical: false, fabricationPending: true, fabricationMine: false }),
  }]]);
  const calls = [];
  const afterTick = {
    vehicle_id: waiting.id,
    source: 'location',
    viewer_pending: false,
    closed: false,
    departments: [
      { station: 'FITTING', label: 'Fitting', pending: false, can_acknowledge: false, acknowledged_by_name: 'Oleg', acknowledged_by_role: 'fitter', acknowledged_at: '2026-10-27T01:46:00.000Z' },
      { station: 'FABRICATION', label: 'Fabrication', pending: true, can_acknowledge: false },
    ],
  };
  c.PDC_SUPABASE = {
    rpc(name, args) {
      calls.push({ name, args });
      if (name === 'list_pmb_arrival_ack_557') return Promise.resolve({ data: [afterTick] });
      if (name === 'acknowledge_pmb_arrival_557') return Promise.resolve({ data: { ok: true, data: afterTick } });
      return Promise.resolve({ data: [] });
    },
  };
  c.PDC_AUTH_CONTEXT = { role: 'fitter' };
  const before = c.incomingVehicleDetailRow(waiting, 'newpmb', { workshopProjectionAvailable: false });
  assert.match(before, /Acknowledge for Fitting/);
  assert.doesNotMatch(before, /Book into a Fitting bay/);
  return c.acknowledgePmbArrival(c.vehicleKey(waiting), 'FITTING').then(() => {
    const ack = calls.filter(call => call.name === 'acknowledge_pmb_arrival_557');
    assert.equal(ack.length, 1);
    assert.equal(ack[0].args.p_station, 'FITTING');
    assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'pmb', 'Fitting has ticked, so Fitting no longer sees New to PMB');
    assert.match(c.pmbArrivalNoteHtml(waiting), /Fitting: Oleg/);
    assert.match(c.pmbArrivalNoteHtml(waiting), /Fabrication awaiting acknowledgement/);
    assert.equal(c.pmbArrivalActionHtml(waiting, c.vehicleKey(waiting)), '');
    const offer = c.pmbArrivalBayBookingHtml(waiting, 'FITTING', 'Fitting');
    assert.match(offer, /Book into a Fitting bay/);
    assert.match(offer, /Best slot/);
    assert.match(offer, /Book this bay/);
    assert.match(offer, /Fitting · Bay 06/);
    assert.match(offer, /Fitting · Bay 10/);
    assert.match(offer, /data-pmb-book-station="FITTING"/);
    assert.doesNotMatch(offer, /orange|#f59e0b|#ff8/i);
    assert.equal(c.app.pmbArrivalBookOffer.station, 'FITTING');
    c.app.pmbArrivalAck.set(waiting.id, {
      vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
        { station: 'FITTING', label: 'Fitting', pending: false, can_acknowledge: false, acknowledged_by_name: 'Oleg', acknowledged_at: '2026-10-27T01:46:00.000Z' },
        { station: 'FABRICATION', label: 'Fabrication', pending: true, can_acknowledge: true },
      ],
    });
    assert.equal(c.vehicleLocationsDisplayBucket(waiting), 'newpmb', 'Fabrication has not ticked, so Fabrication still sees it');
    const fabrication = c.pmbArrivalActionHtml(waiting, c.vehicleKey(waiting));
    assert.match(fabrication, /Acknowledge for Fabrication/);
    assert.doesNotMatch(fabrication, /Acknowledge for Fitting/);
  });
});

test('booking calls the existing planner functions and does not add a booking RPC', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  const slots = [];
  const scheduled = [];
  c.workshopNormalizeStartDate = date => date;
  c.workshopDateKey = () => '2026-10-27';
  c.workshopDateKeyNotBefore = dateKey => dateKey;
  c.workshopMinuteOffset = () => 480;
  c.workshopDefaultBookingHours = () => 2;
  c.workshopLoadPlans = () => [];
  c.workshopVehicle = () => waiting;
  c.workshopSchedulingDuration = () => ({ hours: 2 });
  c.workshopFirstAvailableStartSlot = (...args) => { slots.push(args); return { dateKey: '2026-10-27', startMinutes: 480 }; };
  c.scheduleWorkshopVehicle = async payload => { scheduled.push(payload); return true; };
  c.workshopScheduleVehicleNextAvailable = async payload => { scheduled.push({ best: payload }); return true; };
  return c.pmbArrivalBookIntoBay(c.vehicleKey(waiting), 'FITTING', 1).then(saved => {
    assert.equal(saved, true);
    assert.equal(slots[0][0], 'FITTING');
    assert.equal(slots[0][1], 1);
    assert.equal(scheduled[0].stage, 'FITTING');
    assert.equal(scheduled[0].bay, 1);
    assert.equal(scheduled[0].cascadeNewBooking, true);
    return c.pmbArrivalBookBestSlot(c.vehicleKey(waiting), 'FITTING');
  }).then(saved => {
    assert.equal(saved, true);
    assert.equal(scheduled[1].best.stage, 'FITTING');
    const app = fs.readFileSync('app.js', 'utf8');
    const block = app.slice(app.indexOf('function pmbArrivalBookBestSlot'), app.indexOf('function closePmbArrivalBayBooking'));
    assert.match(block, /workshopScheduleVehicleNextAvailable/);
    assert.match(block, /workshopFirstAvailableStartSlot/);
    assert.match(block, /scheduleWorkshopVehicle/);
    assert.doesNotMatch(block, /\.rpc\(/);
    assert.doesNotMatch(up, /CREATE (OR REPLACE )?FUNCTION public\.workshop_/);
    assert.doesNotMatch(up, /CREATE (OR REPLACE )?FUNCTION public\.schedule_vehicle_work/);
  });
});

test('a tick without a key does not offer a bay, and the completing tick stays blocked', () => {
  const { c } = board();
  const waiting = c.app.data[0];
  delete waiting.keyNumber;
  c.app.pmbArrivalAck = new Map([[waiting.id, {
    vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
      { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
      { station: 'HOIST', label: 'Hoist', pending: true, can_acknowledge: false },
    ],
  }]]);
  const notes = [];
  c.pdcNotify = message => notes.push(message);
  c.PDC_SUPABASE = {
    rpc() {
      return Promise.resolve({ data: { ok: true, data: {
        source: 'location', viewer_pending: false, closed: false, departments: [
          { station: 'FITTING', label: 'Fitting', pending: false, acknowledged_by_name: 'Oleg', acknowledged_at: '2026-10-27T01:50:00.000Z' },
        ],
      } } });
    },
  };
  assert.equal(c.pmbArrivalBayBookingHtml(waiting, 'FITTING', 'Fitting'), '');
  return c.acknowledgePmbArrival(c.vehicleKey(waiting), 'FITTING').then(() => {
    assert.equal(c.app.pmbArrivalBookOffer, undefined);
    assert.match(notes.join(' '), /key number is needed before this vehicle can be booked/);
    c.app.pmbArrivalAck.set(waiting.id, {
      vehicle_id: waiting.id, viewer_pending: true, source: 'location', departments: [
        { station: 'FITTING', label: 'Fitting', pending: true, can_acknowledge: true },
      ],
    });
    const blocked = c.pmbArrivalActionHtml(waiting, c.vehicleKey(waiting));
    assert.match(blocked, /Acknowledge for Fitting/);
    assert.match(blocked, /disabled/);
    assert.doesNotMatch(blocked, /data-pmb-ack=/);
  });
});

test('the new paint is blue, Department 135 is untouched, and the check is r574 / F188 / sort 345', () => {
  const css = fs.readFileSync('styles.css', 'utf8');
  const slice = css.slice(css.lastIndexOf('r574 (F188)'));
  assert.match(slice, /#1d4ed8/);
  assert.match(slice, /#dbeafe/);
  assert.doesNotMatch(slice, /orange|#f59e0b|#ff8/i);
  assert.match(css, /pmb-arrival-bucket-pulse/);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /r574|pmb-book-card|Acknowledge for Fitting/);
  assert.doesNotMatch(fs.readFileSync('karratha/styles.css', 'utf8'), /pmb-book-card|pmb-ack-tick/);
  assert.match(up, /sort_order=345/);
  assert.match(up, /sort 345/);
  assert.match(up, /fault_id='F188'/);
  assert.match(up, /added_in='r574'/);
  assert.match(up, /check_name='pmb_dept_ack_book_574'/);
  assert.match(up, /hours_description_fits_573/);
  assert.match(up, /fault_id='F187'/);
  assert.match(up, /sort_order=344/);
  assert.match(up, /added_in='r573'/);
  assert.match(up, /pmb_key_gate_562/);
  assert.match(up, /pmb_arrival_age_563/);
  assert.match(up, /new_to_pmb_ack_557/);
  assert.match(up, /bay_job_pause_569/);
  assert.match(up, /count\(\*\) FROM pdc_ops\.expected_function_md5\)<>241/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up, /pmb_dept_ack_book_570|fault_id='F184'|sort_order=341|added_in='r570'|release\s*=\s*'r570'/);
  assert.match(check, /strpos\(p\.prosrc, 'r574'\)/);
  assert.match(check, /::pg_catalog\.text/);
  assert.match(check, /acknowledged_by/);
  assert.match(check, /acknowledged_at/);
  assert.match(check, /clock_timestamp/);
  assert.match(check, /workshop_create_booking/);
  assert.match(check, /schedule_vehicle_work/);
  assert.match(check, /administrator_schedule_workshop_vehicle/);
  assert.match(check, /FITTING/);
  assert.match(check, /no_dept_135|135/);
  assert.doesNotMatch(check, /regprocedure|to_regprocedure/);
  assert.doesNotMatch(check, /expected_function_md5\s*\)\s*(=|<>|!=)\s*[0-9]+/);
  assert.match(down, /sort_order=345/);
  assert.doesNotMatch(down, /sort_order=340|fault_id='F180'|added_in='r566'/);
  assert.doesNotMatch(down, /sort_order=341|fault_id='F184'|added_in='r570'|release='r570'|pmb_dept_ack_book_570/);
  assert.match(down, /pdc_pmb_arrival_dept_ack_557/);
  assert.match(down, /pdc_vehicle_key_assigned_562/);
  assert.doesNotMatch(down, /DROP TABLE|DROP FUNCTION/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /r574=2026\.10\.27\.r574/);
  assert.equal(crypto.createHash('md5').update(fs.readFileSync(upPath)).digest('hex'), crypto.createHash('md5').update(up).digest('hex'));
  assert.equal(crypto.createHash('md5').update(fs.readFileSync(downPath)).digest('hex'), crypto.createHash('md5').update(down).digest('hex'));
});
