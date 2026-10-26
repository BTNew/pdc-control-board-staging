/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r548 (F162): a vehicle's own unallocated bookings do not block a bay drop,
// and a missing bay reads Unallocated. Department 135 is not edited.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const layout = require('./pdc-workshop-departments.js');

const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');
const planner = read('workshop-planner.js');
const app = read('app.js');
const up = read('supabase/migrations/20261026230000_r548_unallocated_bay_rechain.sql');
const down = read('supabase/rollbacks/20261026230000_r548_unallocated_bay_rechain.down.sql');

function extract(src, name) {
  const body = src.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(body, name);
  return body[0];
}

const notices = [];
const ctx = {
  notices,
  layout,
  workshopDepartmentLayout: () => layout,
  workshopPad: value => String(value).padStart(2, '0'),
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  workshopEntryStart: row => new Date(row.startAt),
  workshopEntryEnd: row => new Date(row.endAt),
  workshopIntervalsOverlap: (startA, endA, startB, endB) => Number(startA) < Number(endB) && Number(startB) < Number(endA),
  parseIsoTimestamp: value => new Date(value),
  pmbStageLabel: value => ({ BUS_4X4: 'Bus 4x4', BUS_ELECTRICAL: 'Electrical', BUS_QA: 'QA' }[value] || value),
  workshopNotify: message => { notices.push(message); },
  window: { PDC_WORKSHOP_DEPARTMENTS: layout },
};
vm.runInNewContext(`
${extract(planner, 'workshopBayText')}
${extract(planner, 'workshopOtherDepartmentOverlaps')}
${extract(planner, 'workshopConfirmOtherDepartmentPlans')}
${extract(app, 'pdcBayText')}
this.workshopBayText = workshopBayText;
this.workshopOtherDepartmentOverlaps = workshopOtherDepartmentOverlaps;
this.workshopConfirmOtherDepartmentPlans = workshopConfirmOtherDepartmentPlans;
this.pdcBayText = pdcBayText;
`, ctx);

const vehicle = '8d6d045a-ba11-4592-aab2-ac220d0fb627';
const windowStart = '2026-10-26T01:00:00.000Z';
const windowEnd = '2026-10-29T23:54:00.000Z';

test('r548: placing a vehicle ignores its own null-bay bookings', () => {
  notices.length = 0;
  const candidate = { id: 'e72552d3-475f-495a-a4b1-142a0ffff90c', vehicleKey: vehicle, stage: 'BUS_4X4', bay: 1, startAt: windowStart, endAt: windowEnd };
  const siblings = [
    { id: 'faf85955-5e70-4098-828b-a96f8ce8863e', vehicleKey: vehicle, stage: 'BUS_4X4', bay: 0, status: 'queued', startAt: windowStart, endAt: windowEnd },
    { id: '4d9dc515-0b33-4fac-a857-bb278be2b948', vehicleKey: vehicle, stage: 'BUS_4X4', bay: null, status: 'queued', startAt: windowStart, endAt: windowEnd },
    { id: 'blank-bay', vehicleKey: vehicle, stage: 'BUS_4X4', bay: '', status: 'stoppage', startAt: windowStart, endAt: windowEnd },
  ];
  assert.deepEqual(ctx.workshopOtherDepartmentOverlaps(candidate, siblings), []);
  assert.equal(ctx.workshopConfirmOtherDepartmentPlans(candidate, siblings), true);
  assert.deepEqual(notices, []);
});

test('r548: a booking that already has a bay still blocks, and the toast does not say Bay 00', () => {
  notices.length = 0;
  const candidate = { id: 'moving', vehicleKey: vehicle, stage: 'BUS_4X4', bay: 1, startAt: windowStart, endAt: windowEnd };
  const rows = [
    { id: 'null-sibling', vehicleKey: vehicle, stage: 'BUS_4X4', bay: 0, status: 'queued', startAt: windowStart, endAt: windowEnd },
    { id: 'real-bay', vehicleKey: vehicle, stage: 'BUS_4X4', bay: 2, status: 'planned', startAt: '2026-10-26T02:00:00.000Z', endAt: '2026-10-26T06:00:00.000Z' },
    { id: 'other-vehicle', vehicleKey: 'other', stage: 'BUS_4X4', bay: 1, status: 'planned', startAt: windowStart, endAt: windowEnd },
    { id: 'after', vehicleKey: vehicle, stage: 'BUS_4X4', bay: 3, status: 'planned', startAt: '2026-10-30T00:00:00.000Z', endAt: '2026-10-30T04:00:00.000Z' },
  ];
  const hits = ctx.workshopOtherDepartmentOverlaps(candidate, rows);
  assert.deepEqual(hits.map(row => row.id), ['real-bay']);
  assert.equal(ctx.workshopConfirmOtherDepartmentPlans(candidate, rows), false);
  assert.equal(notices.length, 1);
  assert.match(notices[0], /This vehicle already has an active booking in the requested time window/);
  assert.match(notices[0], /Bay 02/);
  assert.equal(notices[0].includes('Bay 00'), false);
  assert.equal(notices[0].includes('Unallocated'), false);
});

test('r548: a missing bay reads Unallocated, and numbered bays keep their names', () => {
  for (const bay of [0, '0', null, '', undefined, -1, 0.5]) {
    assert.equal(ctx.workshopBayText('BUS_4X4', bay, true), 'Unallocated', `planner ${bay}`);
    assert.equal(ctx.pdcBayText('BUS_4X4', bay, true), 'Unallocated', `app ${bay}`);
    assert.equal(layout.bayLabel('BUS_4X4', bay), 'Unallocated', `departments ${bay}`);
  }
  assert.equal(ctx.workshopBayText('FITTING', 1), 'Fitting · Bay 06');
  assert.equal(ctx.pdcBayText('FITTING', 1), 'Fitting · Bay 06');
  assert.equal(ctx.workshopBayText('BUS_4X4', 4, true), 'Bay 04');
  assert.equal(ctx.pdcBayText('TINT', 1), 'Bay 1');
  assert.equal(layout.bayLabel('BUS_4X4', 1), 'Mechanical · Bay 01');
  assert.equal(layout.bayLabel('BUS_4X4', 2), 'Mechanical · Bay 02');
  assert.equal(layout.bayLabel('FITTING', 1), 'Fitting · Bay 06');
  for (const label of ['Unallocated', 'Bay 04', 'Bay 1', 'Mechanical · Bay 01', 'Fitting · Bay 06']) {
    assert.equal(label.includes('Bay 00'), false);
  }
});

test('r548: the migration widens the overlap guard, rechains in workshop order, and does not add a pin', () => {
  assert.match(up, /sort_order, added_in\) VALUES/);
  assert.match(up, /true, 324, 'r548'/);
  assert.match(up, /'F162'/);
  assert.match(up, /unallocated_bay_rechain_548/);
  assert.match(up, /b\.bay_id IS NOT NULL/);
  assert.match(up, /place_unallocated_after_548/);
  assert.match(up, /WHEN 'BUS_MECHANICAL' THEN 1/);
  assert.match(up, /WHEN 'BUS_ACCESSORIES' THEN 2/);
  assert.match(up, /WHEN 'BUS_ELECTRICAL' THEN 3/);
  assert.match(up, /WHEN 'BUS_QA' THEN 4/);
  assert.match(up, /WHEN 'BUS_PIT' THEN 5/);
  assert.match(up, /zz_pdc_rechain_unallocated_548/);
  assert.match(up, /zz_pdc_rechain_unallocated_ins_548/);
  assert.match(up, /GET DIAGNOSTICS v_n = ROW_COUNT/);
  assert.equal(up.includes('INSERT INTO pdc_ops.expected_function_md5'), false);
  assert.equal(up.includes('regprocedure'), false);
  assert.equal(up.includes('to_regprocedure'), false);
  const check = up.slice(up.indexOf('$chk548$') + 8, up.lastIndexOf('$chk548$'));
  assert.equal(check.includes('regprocedure'), false);
  assert.match(check, /position\('Bay 00' IN body\.prosrc\) = 0/);
  assert.match(check, /position\('Bay 00' IN chain\.prosrc\) = 0/);
  assert.match(check, /and b\.bay_id IS NOT NULL/);
  assert.match(check, /vehicle_overlap/);
  assert.match(check, /bay_overlap/);
  assert.match(down, /NOT \(b\.status=''queued'' AND b\.bay_id IS NULL\)/);
  assert.match(down, /DROP TRIGGER IF EXISTS zz_pdc_rechain_unallocated_ins_548/);
  assert.match(down, /9efb08f2415c28ac57a14b401cf9f605/);
  assert.equal((app.match(/r548=2026\.10\.26\.r548/g) || []).length, 2);
  assert.equal((app.match(/r540=2026\.10\.26\.r540/g) || []).length, 2);
  const html = read('index.html');
  assert.equal((html.match(/r548=2026\.10\.26\.r548/g) || []).length, 2);
  assert.equal(fs.existsSync(path.join(__dirname, 'karratha/pdc-workshop-departments.js')), false);
  for (const file of ['karratha/workshop-planner.js', 'karratha/app.js', 'karratha/index.html']) {
    const text = read(file);
    assert.equal(text.includes('place_unallocated_after_548'), false, file);
    assert.equal(text.includes('r548=2026.10.26.r548'), false, file);
    assert.equal(text.includes('unallocated_bay_rechain_548'), false, file);
  }
});
