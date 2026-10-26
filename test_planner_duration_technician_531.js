/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
const start = source.indexOf('function workshopDescribeSharedActionError(');
const end = source.indexOf('function workshopPersistPlanAction(', start);
const up = fs.readFileSync('supabase/migrations/20261026080000_r531_planner_duration_technician.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261026080000_r531_planner_duration_technician.down.sql', 'utf8');

function runtime() {
  const context = vm.createContext({ window: {}, workshopAdministratorCanMove: () => false });
  vm.runInContext(source.slice(start, end), context);
  return context.workshopDescribeSharedActionError;
}

const clash = {
  ok: false,
  error: 'technician_overlap',
  detail: 'Chelsea Rees # 2 is already booked on Key 411, stock 12710966, Fitting Fitting - PMB Bay 10, from 26 Oct 10:10 to 27 Oct 09:31 (Perth time). No booking was saved. Drop this vehicle on a bay whose mechanic is free for the whole job, use Best slot, or move that booking first.',
  conflict: {
    conflict_type: 'technician_overlap',
    existing_booking: {
      vehicle: { stock_number: '12710966', key_number: '411', customer_name: 'Example Customer Pty Ltd' },
      assignment: { technician_name: 'Chelsea Rees # 2' },
      stage: { display_name: 'Fitting' },
      bay: { display_name: 'Fitting - PMB Bay 10' },
      scheduled_start_at: '2026-10-26T02:10:00+00:00',
      scheduled_end_at: '2026-10-27T01:31:00+00:00',
    },
  },
};

test('technician overlap uses the server sentence and keeps the customer out', () => {
  const describe = runtime();
  const message = describe(clash);
  assert.match(message, /Chelsea Rees # 2/);
  assert.match(message, /Key 411/);
  assert.match(message, /stock 12710966/);
  assert.match(message, /Best slot/);
  assert.match(message, /No booking was saved/);
  assert.doesNotMatch(message, /Example Customer/);
});

test('a clash without server detail is built from the booking snapshot', () => {
  const describe = runtime();
  const message = describe({ ...clash, detail: '' });
  assert.match(message, /Chelsea Rees # 2 is already booked on Key 411, stock 12710966/);
  assert.match(message, /Fitting - PMB Bay 10/);
  assert.match(message, /Perth time/);
  assert.match(message, /Best slot/);
  assert.doesNotMatch(message, /Example Customer/);
});

test('a server sentence that names the customer is not shown', () => {
  const describe = runtime();
  const message = describe({
    ...clash,
    detail: 'Example Customer Pty Ltd already has Chelsea. No booking was saved.',
  });
  assert.doesNotMatch(message, /Example Customer/);
  assert.match(message, /Chelsea Rees # 2/);
  assert.match(message, /Best slot/);
});

test('an unnamed technician clash still tells the planner what to do', () => {
  const describe = runtime();
  const message = describe({ ok: false, error: 'technician_overlap' });
  assert.match(message, /already assigned to another booking/);
  assert.match(message, /No booking was saved/);
  assert.match(message, /Best slot/);
});

test('starting a job keeps its own technician message', () => {
  assert.match(source, /function workshopDescribeStartActionError/);
  assert.match(source, /This mechanic already has another running or stopped job/);
});

test('r531 drops the QC cache before the duration is chosen and does not relax validation', () => {
  const del = up.indexOf('DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = p_vehicle_id');
  const est = up.indexOf('workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id)');
  assert.ok(del > 0 && est > del);
  assert.match(up, /operation_estimate_duration_mismatch/);
  assert.match(up, /9efb08f2415c28ac57a14b401cf9f605/);
  assert.match(up, /f5375755bbb9c217198c4075e5c125ab/);
  assert.match(up, /272901e7cb918ab14dd3419b1bff5d58/);
  assert.match(up, /planner_duration_cache_531/);
  assert.match(up, /integer,public\.workshop_booking_status,uuid,boolean/);
  assert.match(up, /pdc_ops\.regression_checks_catalog_guard\(\)/);
  assert.match(down, /DROP FUNCTION pdc_ops\.regression_checks_catalog_guard\(\)/);
  assert.match(up, /technician_overlap_names_booking_531/);
  assert.match(up, /sort_order/);
  assert.equal((up.match(/312/g) || []).length > 0, true);
  assert.match(down, /c01d82df2e947fbe0b3ecabbe8e7eb70/);
  assert.match(down, /DROP FUNCTION pdc_cascade_private\.technician_overlap_detail_531\(uuid\)/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.workshop_validate_booking/);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.equal((app.match(/r531=2026\.10\.26\.r531/g) || []).length, 2);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('r531=2026.10.26.r531'), false);
  assert.equal(fs.readFileSync('karratha/workshop-planner.js', 'utf8').includes('workshopTechnicianOverlapDetail'), false);
});
