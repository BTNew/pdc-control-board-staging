/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const vm = require('node:vm');

const BAY_07 = '06bda616-299e-4a63-8650-cff768f46319';
const BAY_05 = 'b5bbe5dc-1c88-4d24-b710-c9211a18a085';
const BAY_06 = '4279ec85-5ea8-4fa5-b9a0-fa8eeb45d8de';
const ANDREW = 'a0e95365-9516-4af1-bf57-ead627de7212';
const KEY_515 = '71c23111-e789-444a-a446-66a155e7a54a';
const KEY_512 = '1f58b4a3-803c-462c-8c2c-44436e3f046d';
const planner = fs.readFileSync(require.resolve('./workshop-planner.js'), 'utf8');
const upPath = 'supabase/migrations/20261025100000_r527_qa_bay_technician.sql';
const downPath = 'supabase/rollbacks/20261025100000_r527_qa_bay_technician.down.sql';
const upSql = fs.readFileSync(upPath, 'utf8');
const downSql = fs.readFileSync(downPath, 'utf8');

function section(start, end) {
  const index = planner.indexOf(start);
  assert.ok(index >= 0, start);
  return planner.slice(index, planner.indexOf(end, index));
}

function dollarBody(source, tag) {
  const open = source.indexOf(tag);
  const close = source.indexOf(tag, open + tag.length);
  assert.ok(open >= 0 && close > open, tag);
  return source.slice(open + tag.length, close);
}

function qaBays() {
  return [
    { id: BAY_05, code: 'BUS_4X4-BAY-05', bay_number: 5, display_name: 'Progression - Bus4x4 Bay 05', version: 4, default_technician_id: null, is_active: true },
    { id: BAY_06, code: 'BUS_4X4-BAY-06', bay_number: 6, display_name: 'Progression - Bus4x4 Bay 06', version: 4, default_technician_id: null, is_active: true },
    { id: BAY_07, code: 'BUS_4X4-BAY-07', bay_number: 7, display_name: 'QA - Bus4x4 Bay 07', version: 5, default_technician_id: null, is_active: true },
  ];
}

function fixture(rows = qaBays()) {
  const calls = [];
  const assignments = [];
  const alerts = [];
  let snapshot = { bookings: [], active_stoppages: [] };
  const c = {
    app: { currentView: 'workshop' },
    WORKSHOP_PENDING_BAY_ASSIGNMENTS: new Set(),
    workshopNotify: message => alerts.push(message),
    cleanNavisionText: value => String(value || '').trim(),
    normalizePmbStage: value => String(value || '').trim().toUpperCase(),
    getPdcSupabaseAccessToken: () => 'operator-token',
    workshopSharedModeActive: () => true,
    workshopState: () => ({ stage: 'BUS_4X4', date: '2026-10-26' }),
    workshopReferenceTechnicianRef: name => (String(name).trim() === 'Andrew McCormick' ? { technicianId: ANDREW } : null),
    workshopLoadPlans: () => [],
    renderWorkshopPlanner() {},
    window: {
      PDC_AUTH_CONTEXT: { userId: 'operator-bhavesh', role: 'operator' },
      __workshopReferenceDataService: {
        getCachedWorkshopBays: () => ({ rows, state: 'connected_read_only' }),
        setBayDefaultTechnician: (...args) => { calls.push(args); return Promise.resolve({ ok: true }); },
      },
      __workshopDataService: { getLastSnapshot: () => snapshot },
      __workshopSharedActions: { assignBookingTechnician: args => { assignments.push(args); return Promise.resolve({ ok: true }); } },
    },
  };
  vm.createContext(c);
  vm.runInContext(section('function workshopQaBayLabel(', 'function workshopBayAvailabilityStatus(')
    + section('function workshopBayAssignmentError(', 'function bindWorkshopUnallocatedDrop('), c);
  return { c, calls, assignments, alerts, setRows: next => { rows = next; }, setSnapshot: value => { snapshot = value; }, setPlans: plans => { c.workshopLoadPlans = () => plans; } };
}

test('Dept 138 QA bays 5, 6 and 7 resolve to their shared BUS_4X4 bay rows', () => {
  const f = fixture();
  for (const [bay, id, code] of [[5, BAY_05, 'BUS_4X4-BAY-05'], [6, BAY_06, 'BUS_4X4-BAY-06'], [7, BAY_07, 'BUS_4X4-BAY-07']]) {
    const ref = f.c.workshopSharedBayRef('BUS_4X4', bay);
    assert.equal(ref.id, id, code);
    assert.equal(ref.code, code);
    assert.equal(ref.version, bay === 7 ? 5 : 4);
  }
  const labelled = fixture([{ id: BAY_07, code: 'BUS_4X4-BAY-7', bay_number: 7, display_name: 'QA - Bay 07', version: 5, default_technician_id: null, is_active: true }]);
  assert.equal(labelled.c.workshopSharedBayRef('BUS_4X4', 7).id, BAY_07);
  assert.equal(labelled.c.workshopQaBayLabel('QA · Bay 07', 7), true);
  assert.equal(labelled.c.workshopQaBayLabel('QA - Bus 4x4 Bay 07', 7), true);
  const electrical = fixture([{ id: 'electrical-bay-07', code: 'ELECTRICAL-BAY-07', bay_number: 7, display_name: 'QA - Bay 07', version: 1, default_technician_id: null, is_active: true }]);
  assert.equal(electrical.c.workshopSharedBayRef('BUS_4X4', 7), null);
});

test('an empty bay cache still resolves QA Bay 07 from the live booking snapshot', () => {
  const f = fixture([]);
  f.setSnapshot({ bookings: [{ stage: { code: 'BUS_4X4' }, bay: { id: BAY_07, code: 'BUS_4X4-BAY-07', bay_number: 7, display_name: 'QA - Bus4x4 Bay 07', is_active: true } }], active_stoppages: [] });
  const ref = f.c.workshopSharedBayRef('BUS_4X4', 7);
  assert.equal(ref.id, BAY_07);
  assert.equal(ref.code, 'BUS_4X4-BAY-07');
  assert.equal(ref.version, 0);
  assert.equal(ref.default_technician_id, null);
});

test('an operator sets Andrew McCormick on QA Bay 07 and Key 515 is assigned', async () => {
  const f = fixture();
  f.setPlans([
    { id: 'key-515', sharedBookingId: KEY_515, sharedVersion: 1, stage: 'BUS_4X4', bay: 7, status: 'planned', assignee: '' },
    { id: 'key-512', sharedBookingId: KEY_512, sharedVersion: 1049, stage: 'BUS_4X4', bay: 7, status: 'planned', assignee: '' },
    { id: 'other-bay', sharedBookingId: 'other-booking', sharedVersion: 3, stage: 'BUS_4X4', bay: 6, status: 'planned', assignee: '' },
  ]);
  assert.equal(f.c.window.PDC_AUTH_CONTEXT.role, 'operator');
  await f.c.saveWorkshopBayMechanic('BUS_4X4', 7, 'Andrew McCormick');
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.calls[0].slice(0, 3), [BAY_07, 5, ANDREW]);
  assert.equal(f.calls[0][3].observedTechnicianId, null);
  assert.deepEqual(f.assignments.map(row => [row.bookingId, row.expectedVersion, row.technicianId]), [
    [KEY_515, 1, ANDREW],
    [KEY_512, 1049, ANDREW],
  ]);
  assert.equal(f.alerts.length, 0);
  assert.doesNotMatch(planner.slice(planner.indexOf('function workshopBayAssignmentError('), planner.indexOf('function saveWorkshopBayMechanic(')), /administrator account/i);
});

test('r527 SQL is staging-only, leaves Department 135 and bay active alone, and is not applied by this test', () => {
  const newBody = dollarBody(upSql, '$r527$');
  const oldBody = dollarBody(downSql, '$r527down$');
  const md5 = text => crypto.createHash('md5').update(text).digest('hex');
  assert.equal(md5(fs.readFileSync(upPath)), 'dc761f5ae365bf5df0ec58bfd88dabe4');
  assert.equal(md5(fs.readFileSync(downPath)), '0455fa33ebf239420c266e378fa33cf4');
  assert.equal(md5(newBody), '51415343720a6d3a02fb2597109db9b1');
  assert.equal(md5(oldBody), '4849edd770bac33b569ae65023cf7aac');
  assert.match(newBody, /s\.code in \('BUS_4X4','TINT','TYRE'\)/);
  assert.match(newBody, /is distinct from 'operator'/);
  assert.doesNotMatch(newBody, /require_pdc_role/);
  assert.match(oldBody, /perform public\.require_pdc_role\('administrator'\)/);
  assert.match(upSql, /cdsmnqxtyyoeoznmbidd/);
  assert.match(upSql, /pdc_production_environment_sentinel/);
  assert.doesNotMatch(upSql, /create\s+(or replace\s+)?function\s+karratha135_pdc/i);
  assert.match(upSql, /karratha135_pdc\.set_bay_default_technician/);
  assert.match(upSql, /fbdf5fefaff3d68c2e2240037ec14064/);
  assert.match(downSql, /4849edd770bac33b569ae65023cf7aac/);
  assert.match(upSql, /b1410527-1410-4410-8410-00000000b141/);
  assert.match(upSql, /Bhavesh Patel/);
  assert.match(upSql, /ARRAY\['BUS_4X4'\]/);
  assert.match(upSql, /bhavesh\.patel@pmgwa.com.au/);
  assert.match(downSql, /DELETE FROM public\.workshop_technicians/);
  assert.match(downSql, /r527 undo: Bhavesh roster row is in use/);
  assert.equal((upSql.match(/update public\.workshop_bays/gi) || []).length, 1);
  assert.equal((upSql.match(/workshop_bookings/g) || []).length, 1);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.equal((app.match(/r527=2026\.10\.25\.r527/g) || []).length, 3);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('r527=2026.10.25.r527'), false);
  assert.equal(fs.readFileSync('karratha/workshop-planner.js', 'utf8').includes('function workshopQaBayLabel('), false);
  assert.equal(fs.readFileSync('karratha/workshop-reference-data-service.js', 'utf8').includes('a refused technician write is not a refused bay list'), false);
});
