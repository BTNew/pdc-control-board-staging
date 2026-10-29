/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r565 (F179): Edit stays on the chip list. A drop uses the existing category and planner moves.
// Completed lines show who and when in blue/grey. A controller tick is set_panel_line_completion_565.
// Synthetic vehicles only. Nothing leaves the process.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const nodeCrypto = require('node:crypto');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { createDocument } = require('./qa/mini-dom-496.cjs');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service.js');
const slideout = require('./pdc-vehicle-slideout.js');

const STAGING_URL = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
const U = (v, n) => `00000000-0000-4000-8000-000000000${v}0${n}`;
const HOIST = '00000000-0000-4000-8000-0000000000aa';
const OPS = [[1, 'SIDE STEPS (SAMPLE)', 'BUS_MECHANICAL', 0.75], [2, 'BULL BAR (SAMPLE)', 'BUS_MECHANICAL', 5.18],
  [3, 'FIRE EXTINGUISHER (SAMPLE)', 'BUS_ACCESSORIES', 0.5], [4, 'LED LIGHT BAR (SAMPLE)', 'BUS_ELECTRICAL', 1.33]];

function syntheticVehicle(n) {
  const id = `00000000-0000-4000-8000-0000000004${String(n).padStart(2, '0')}`;
  const lines = OPS.map(([op, d, , h]) => ({ operation_no: `OP${op}`, description: d, work_key: 'bus4x4', stage_code: 'BUS_4X4', department: '138', operation_line_id: U(n, op), estimated_hours: h }));
  lines.push({ operation_no: 'OP9', description: 'HOIST SAMPLE', work_key: 'hoist', stage_code: 'HOIST', department: '138', operation_line_id: HOIST, estimated_hours: 1.5 });
  lines.push({ operation_no: 'OP8', description: 'TYRE SAMPLE', work_key: 'tyre', stage_code: 'TYRE', department: '138', operation_line_id: '00000000-0000-4000-8000-0000000000bb', estimated_hours: 1 });
  return { id, __emailVehicleId: id, permanentVehicleId: id, __emailVehicleServerAuthoritative: true, __emailVehicleVersion: 7,
    stock: `SYN-04${String(n).padStart(2, '0')}`, keyNumber: String(40 + n), jobcard: `JSYN04${n}`, client: 'Sample customer', vehicle: 'HiLux (sample)',
    dealerCode: '37047', pdcDepartmentCodes: ['138'], pdcJobCardNumbers: [`JSYN04${n}`], pdcLocation: 'PMB', source: 'Manual', pdcSheetVisible: true,
    pdcEmailOperationLines: lines };
}
function detailFor(vehicle, n) {
  const lines = OPS.map(([op, d, cat, h]) => ({ line_identity: `source:${U(n, op)}`, source_line_id: U(n, op), operation_no: String(op), description: d,
    work_category: cat, category_version: 0, stage_code: 'BUS_4X4', department: '138', estimated_hours: h, hours_provenance: 'job_card',
    category_rule: 'craig_jobcard_categories_20261015', source_kind: 'authenticated', active: true }));
  lines.push({ line_identity: `source:${HOIST}`, source_line_id: HOIST, operation_no: '9', description: 'HOIST SAMPLE', work_category: 'HOIST',
    category_version: 0, stage_code: 'HOIST', department: '138', estimated_hours: 1.5, hours_provenance: 'job_card', source_kind: 'authenticated', active: true });
  lines.push({ line_identity: 'source:00000000-0000-4000-8000-0000000000bb', source_line_id: '00000000-0000-4000-8000-0000000000bb', operation_no: '8', description: 'TYRE SAMPLE', work_category: 'TYRE',
    category_version: 0, stage_code: 'TYRE', department: '138', estimated_hours: 1, hours_provenance: 'job_card', source_kind: 'authenticated', active: true });
  const booking = (id, extra) => ({ booking_id: id, version: 1, scheduled_start_at: '2026-10-27T00:00:00.000Z', scheduled_end_at: '2026-10-27T01:30:00.000Z', ...extra });
  return { vehicle_id: vehicle.id, vehicle_version: 7, bookings: [
    booking('00000000-0000-4000-8000-000000000099', { plan_id: 'plan-hoist', work_category: 'HOIST', stage_code: 'HOIST', status: 'scheduled', default_duration_minutes: 90, technician_name: 'Sam Sample' }),
    booking('00000000-0000-4000-8000-000000000098', { plan_id: 'plan-done', work_category: 'TYRE', stage_code: 'TYRE', status: 'completed', default_duration_minutes: 60, technician_name: 'Pat Sample', actual_end_at: '2026-10-20T02:30:00.000Z' }),
  ], line_adjustments: [], work_categories: [], requirements: [], job_card_lines: lines };
}

function board({ role = 'administrator' } = {}) {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('pdc-workshop-departments.js');
  const c = fixture.context;
  const doc = createDocument();
  c.document = doc;
  c.CSS = { escape: value => String(value) };
  c.crypto = { randomUUID: () => nodeCrypto.randomUUID() };
  c.requestAnimationFrame = fn => { fn(); return 0; };
  c.PDC_AUTH_CONTEXT = { userId: 'user-a', role };
  c.PDC_SUPABASE_CONFIG = { url: STAGING_URL, publishableKey: 'test-only-not-a-key', projectRef: 'cdsmnqxtyyoeoznmbidd', dealerCode: '37047' };
  c.getPdcSupabaseAccessToken = () => 'test-only-token';
  const rows = [syntheticVehicle(1)];
  rows[0].pdcQcOperationLines = [{ source_line_id: U(1, 1), line_identity: `source:${U(1, 1)}`, completed: true, completed_by: 'Alex Sample', completed_at: '2026-10-20T02:30:00.000Z', active: true, description: 'SIDE STEPS (SAMPLE)' }];
  c.app.data = rows;
  const server = { details: new Map([[rows[0].id, detailFor(rows[0], 1)]]), calls: [], ticks: [] };
  const moves = [];
  const schedules = [];
  c.workshopLoadPlans = () => [{ id: 'plan-hoist', sharedBookingId: '00000000-0000-4000-8000-000000000099', stage: 'HOIST', workCategory: 'HOIST', vehicleKey: c.vehicleKey(rows[0]), status: 'scheduled', startAt: '2026-10-27T00:00:00.000Z', hours: 1.5 }];
  c.moveWorkshopDroppedPlan = (...args) => { moves.push(args); return true; };
  c.scheduleWorkshopVehicle = value => { schedules.push(value); return true; };
  c.fetch = async (url, init = {}) => {
    const name = String(url).split('/rpc/')[1] || String(url);
    const body = init.body ? JSON.parse(init.body) : {};
    server.calls.push({ name, body });
    let reply = { ok: false, code: 'not_in_test' };
    if (name === 'get_panel_line_completions_565') reply = { ok: true, lines: server.ticks.filter(row => row.vehicle_id === body.p_vehicle_id) };
    if (name === 'list_station_icon_completion_578') reply = { ok: true, stations: server.stations || [] };
    if (name === 'set_station_completion_override_578') {
      const row = { vehicle_id: body.p_vehicle_id, work_key: body.p_work_key, complete: body.p_completed === true, override: body.p_completed === true, override_email: 'controller@example.test', acted_at: '2026-10-27T07:30:00.000Z' };
      server.stations = (server.stations || []).filter(item => item.work_key !== row.work_key).concat(row);
      reply = { ok: true, code: 'saved', completed: row.complete, actor_email: row.override_email, acted_at: row.acted_at, work_key: row.work_key };
    }
    if (name === 'set_panel_line_completion_565') {
      const row = { vehicle_id: body.p_vehicle_id, line_identity: body.p_line_identity, completed: body.p_completed === true, actor_email: 'controller@example.test', actor_role: role, acted_at: '2026-10-27T01:15:00.000Z', version: 2 };
      server.ticks = server.ticks.filter(item => item.line_identity !== row.line_identity).concat(row);
      reply = { ok: true, code: 'saved', ...row };
    }
    if (name === 'get_vehicle_workshop_detail_scoped') reply = server.details.get(body.p_vehicle_id);
    if (name === 'administrator_move_workshop_booking') reply = server.moveReply || { ok: true, booking_id: body.p_booking_id };
    if (name === 'administrator_schedule_workshop_vehicle') reply = (server.scheduleReplies || []).shift() || { ok: true, booking_id: 'new' };
    if (name === 'set_vehicle_work_category') {
      const detail = server.details.get(body.p_vehicle_id);
      const line = detail.job_card_lines.find(item => item.line_identity === body.p_line_identity);
      if (line && body.p_vehicle_expected_version === detail.vehicle_version && body.p_category_expected_version === line.category_version) {
        line.work_category = body.p_category; line.category_version += 1; detail.vehicle_version += 1; reply = { ok: true };
      } else reply = { ok: false, error: 'version_conflict', message: 'Synthetic version conflict' };
    }
    if (name === 'save_vehicle_workshop_line_hours_batch_768') {
      const detail = server.details.get(body.p_vehicle_id);
      for (const row of body.p_estimated_rows) { const line = detail.job_card_lines.find(item => item.line_identity === row.line_key); if (line) line.estimated_hours = row.estimated_hours; }
      detail.vehicle_version += 1;
      reply = { ok: true, data: { receipt_id: 'syn-receipt', vehicle_id: body.p_vehicle_id, request_sha256: 'a'.repeat(64), changed_count: body.p_estimated_rows.length } };
    }
    return { ok: true, status: 200, json: async () => JSON.parse(JSON.stringify(reply)) };
  };
  c.app.emailVehicleLocationService = createPdcEmailVehicleLocationService({ config: { url: STAGING_URL, publishableKey: 'test-only-not-a-key' }, getAccessToken: () => 'test-only-token', fetchImpl: (...a) => c.fetch(...a) });
  c.pdcNotify = () => {};
  c.confirm = () => true;
  c.vehicleLocationsScreenRows = () => rows;
  c.openVehicleCardFromVisibleBoard = () => true;
  c.incomingVehicleDetailRow = vehicle => `<details class="incoming-vehicle-card"><summary>row</summary><button type="button" data-open-stock="${vehicle.stock}">${vehicle.stock}</button><div class="incoming-vehicle-detail-grid">${c.authenticatedEmailOperationLinesHtml(vehicle)}</div></details>`;
  const vlt = { TILE: {}, state: { view: 'table' }, splitCard: () => ({ key: null }), bindBoardHandlers() {}, drawerClosed() {}, render() {}, setDrawerOpener(o) { this.opener = o; } };
  c.PDC_VEHICLE_LOCATIONS_TABLE = vlt;
  fixture.loadHelper('pdc-vehicle-slideout.js');
  const panel = () => doc.getElementById('vso-shell').querySelector('.vso-panel');
  const openPanel = () => { vlt.opener.open(c.vehicleKey(rows[0]), 'pmb'); return panel(); };
  const settle = async () => { for (let i = 0; i < 8; i += 1) await new Promise(r => setImmediate(r)); };
  const writes = () => server.calls.filter(call => !['get_vehicle_workshop_detail_scoped', 'get_panel_line_completions_565', 'list_station_icon_completion_578'].includes(call.name));
  return { c, doc, rows, server, moves, schedules, vlt, panel, openPanel, settle, writes };
}
const drop = (chip, target) => { chip.dispatch('dragstart'); target.dispatch('dragover'); target.dispatch('drop'); };

test('chipMovePlan keeps the hours on the plan and refuses a completed chip', () => {
  const line = { kind: 'line', lineKey: `source:${U(1, 2)}`, hours: '5.18', category: 'BUS_MECHANICAL', completed: false };
  const moved = slideout.chipMovePlan(line, { kind: 'station', category: 'BUS_ACCESSORIES', stage: 'BUS_4X4' });
  assert.equal(moved.action, 'category');
  assert.equal(moved.hours, 5.18);
  assert.equal(moved.categoryChanged, true);
  const bay = slideout.chipMovePlan(line, { kind: 'bay', category: 'HOIST', stage: 'HOIST', bay: 2 });
  assert.equal(bay.action, 'bay');
  assert.equal(bay.hours, 5.18);
  assert.equal(bay.bay, 2);
  assert.deepEqual(slideout.chipMovePlan({ ...line, completed: true }, { kind: 'station', category: 'BUS_ACCESSORIES' }).reason, 'completed');
  assert.equal(slideout.chipMovePlan(line, { kind: 'station', category: 'BUS_MECHANICAL' }).reason, 'same');
  const jobChip = { kind: 'job', hours: 1.5, category: 'HOIST', stage: 'HOIST', planId: 'plan-hoist', bookingId: 'b1' };
  const job = slideout.chipMovePlan(jobChip, { kind: 'bay', category: 'HOIST', stage: 'HOIST', bay: 2 });
  assert.equal(job.action, 'move-booking');
  assert.equal(job.hours, 1.5);
  assert.equal(slideout.chipMovePlan(jobChip, { kind: 'station', category: 'FITTING', stage: 'FITTING' }).reason, 'bay');
});

test('a completed line is blue/grey with who and when, and the panel does not use orange', async () => {
  const b = board();
  const panel = b.openPanel();
  await b.settle();
  const line = panel.querySelector(`li[data-operation-source-id="${U(1, 1)}"]`);
  assert.equal(line.classList.contains('is-complete'), true);
  assert.equal(line.classList.contains('vso-done'), true);
  assert.match(line.querySelector('.vso-done-meta').textContent, /Complete · Alex Sample · 20 Oct 2026, 10:30/);
  assert.equal(line.querySelector('[data-vso-tick]').getAttribute('aria-checked'), 'false');
  assert.equal(line.querySelector('.vso-tick span').textContent, 'Tick');
  assert.equal(line.getAttribute('draggable'), null, 'a completed line is not draggable before edit either');
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');
  assert.match(css, /#vso-shell li\.vso-done\.is-complete \{ background: #edf9f1; color: #146c3b; \}/);
  assert.match(css, /#vso-shell \.vso-done-meta \{ color: #146c3b;/);
  assert.match(css, /li > \.vso-tick \{ grid-column: 5; grid-row: 1;/);
  assert.match(css, /\.vso-tick \{[^}]*white-space: nowrap;/);
  assert.doesNotMatch(css, /#f59e0b|#f97316|#ffedd5|#fffbeb/);
});

test('Edit keeps the chip list and a dirty drop saves the hours before the category move', async () => {
  const b = board();
  const panel = b.openPanel();
  assert.ok(panel.querySelector('.vso-open-vehicle'), 'Open Vehicle stays');
  assert.equal(panel.querySelector('[data-vso-full-editor]'), null, 'r694: no Open full editor');
  panel.querySelector('[data-vso-edit-toggle]').dispatch('click');
  await b.settle();
  const edited = b.panel();
  assert.equal(edited.querySelector('.vehicle-workshop-page'), null);
  assert.equal(edited.querySelector('.authenticated-operation-station-grid').hidden, false);
  const chip = edited.querySelector(`li[data-operation-source-id="${U(1, 2)}"]`);
  assert.equal(chip.getAttribute('draggable'), 'true');
  const input = chip.querySelector('[data-vehicle-workshop-hours-batch-input]');
  input.value = '4.5';
  input.dispatch('input');
  const target = edited.querySelector('[data-operation-category="bus_accessories"]');
  drop(chip, target);
  await b.settle();
  const names = b.writes().map(call => call.name);
  assert.deepEqual(names, ['save_vehicle_workshop_line_hours_batch_768', 'set_vehicle_work_category']);
  assert.deepEqual(b.writes()[0].body.p_estimated_rows.map(row => [row.line_key, row.estimated_hours]), [[`source:${U(1, 2)}`, 4.5]]);
  assert.equal(b.writes()[1].body.p_vehicle_expected_version, 8);
  assert.equal(b.writes()[1].body.p_line_identity, `source:${U(1, 2)}`);
  assert.equal(b.writes()[1].body.p_category, 'BUS_ACCESSORIES');
  assert.equal(b.panel().querySelector(`li[data-operation-source-id="${U(1, 2)}"]`).closest('[data-operation-category]').dataset.operationCategory, 'bus_accessories');
  assert.equal(b.moves.length, 0, 'a station drop does not also call the bay move');
});

// r694 (F304): no booking chips and no bay chips in the station lists. Bays are booked in "Move to a bay".
const pick = (row, bay, date, time) => {
  row.querySelector('[data-vso-book-bay]').value = String(bay);
  row.querySelector('[data-vso-book-date]').value = date;
  row.querySelector('[data-vso-book-time]').value = time;
  row.querySelector('[data-vso-book-go]').dispatch('click');
};
const bookRow = (panel, label) => panel.querySelectorAll('.vso-bookrow').find(li => li.querySelector('.vso-book-what strong').textContent.trim().startsWith(label));

test('r694: the station lists show jobs only (no bay or booking chips), in and out of Edit', async () => {
  const b = board();
  b.openPanel();
  await b.settle();
  assert.equal(b.panel().querySelector('.vso-bays'), null);
  assert.equal(b.panel().querySelector('.vso-job'), null);
  assert.equal(b.panel().querySelector('[data-vso-bay]'), null);
  b.panel().querySelector('[data-vso-edit-toggle]').dispatch('click');
  await b.settle();
  assert.equal(b.panel().querySelector('.vso-bays'), null, 'Edit has no bay chips');
  assert.equal(b.panel().querySelector('.vso-job'), null, 'Edit has no booking chips');
  assert.ok(b.panel().querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]'), 'Edit still works');
});

test('r694: Move to a bay moves an existing booking with the administrator move command (cascade on)', async () => {
  const b = board();
  b.server.details.get(b.rows[0].id).bookings[0].booking_version = 4;
  b.openPanel();
  await b.settle();
  const box = b.panel().querySelector('.vso-book');
  assert.ok(box, 'Move to a bay box drawn for an administrator');
  assert.equal(box.parentNode, b.panel().querySelector('.vso-body'), 'inside the panel body, after the operations');
  const hoist = bookRow(b.panel(), 'Hoist');
  assert.match(hoist.textContent, /Pick a bay to book or move it/, 'opening the panel reads no bookings');
  pick(hoist, 2, '2026-11-03', '09:30');
  await b.settle();
  const sent = b.server.calls.filter(call => call.name === 'administrator_move_workshop_booking');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].body.p_booking_id, '00000000-0000-4000-8000-000000000099');
  assert.equal(sent[0].body.p_expected_version, 4);
  assert.equal(sent[0].body.p_stage_code, 'HOIST');
  assert.equal(sent[0].body.p_bay_number, 2);
  assert.equal(sent[0].body.p_scheduled_start_at, '2026-11-03T01:30:00.000Z', '09:30 Perth');
  assert.equal(sent[0].body.p_duration_minutes, 90);
  assert.equal(sent[0].body.p_cascade, true);
  assert.match(b.panel().querySelector('.vso-book-msg').textContent, /Hoist .*booked into Express · Bay 02 at 09:30 on 2026-11-03/);
  assert.equal(b.moves.length + b.schedules.length, 0, 'the planner page is not needed');
});

test('r694: with no booking, Move to a bay books the vehicle with the open hours; a place-after answer is accepted once', async () => {
  const b = board();
  b.server.details.get(b.rows[0].id).bookings = [];
  b.server.scheduleReplies = [{ ok: false, warning: true, requires_confirmation: true, error: 'place_after_running', plan_hash: 'h1', message: 'Running job' }, { ok: true, booking_id: 'new' }];
  b.openPanel();
  await b.settle();
  const hoist = bookRow(b.panel(), 'Hoist');
  assert.match(hoist.textContent, /Book \/ Move/);
  pick(hoist, 2, '2026-11-03', '07:00');
  await b.settle();
  const sent = b.server.calls.filter(call => call.name === 'administrator_schedule_workshop_vehicle');
  assert.equal(sent.length, 2, 'sent, then sent again with the place-after answer');
  assert.equal(sent[0].body.p_vehicle_id, b.rows[0].id);
  assert.equal(sent[0].body.p_vehicle_expected_version, 7);
  assert.equal(sent[0].body.p_bay_number, 2);
  assert.equal(sent[0].body.p_duration_minutes, 90);
  assert.equal(sent[0].body.p_metadata.work_category, 'HOIST');
  assert.equal(sent[1].body.p_metadata.place_after_confirm.plan_hash, 'h1');
  assert.notEqual(sent[1].body.p_request_id, sent[0].body.p_request_id);
  assert.match(b.panel().querySelector('.vso-book-msg').textContent, /booked into Express · Bay 02/);
});

test('r694: no bay chosen books nothing; a refusal says nothing changed; operators and viewers get no box', async () => {
  const b = board();
  b.openPanel();
  await b.settle();
  let hoist = bookRow(b.panel(), 'Hoist');
  hoist.querySelector('[data-vso-book-bay]').value = '';
  hoist.querySelector('[data-vso-book-go]').dispatch('click');
  await b.settle();
  assert.equal(b.server.calls.filter(call => /administrator_(move|schedule)/.test(call.name)).length, 0);
  assert.match(b.panel().querySelector('.vso-book-msg').textContent, /Choose a bay for Hoist/);
  b.server.moveReply = { ok: false, error: 'bay_overlap', message: 'That bay is taken' };
  hoist = bookRow(b.panel(), 'Hoist');
  pick(hoist, 1, '2026-11-03', '07:00');
  await b.settle();
  assert.match(b.panel().querySelector('.vso-book-msg').textContent, /was not booked: That bay is taken\. Nothing was changed\./);
  for (const role of ['operator', 'viewer']) {
    const other = board({ role });
    other.openPanel();
    await other.settle();
    assert.equal(other.panel().querySelector('.vso-book'), null, role);
  }
});

test('a controller can tick and untick a line; another role sees a read-only tick', async () => {
  const b = board({ role: 'operator' });
  b.openPanel();
  await b.settle();
  const box = b.panel().querySelector(`li[data-operation-source-id="${U(1, 2)}"] [data-vso-tick]`);
  assert.equal(box.disabled, false);
  box.dispatch('click');
  await b.settle();
  const saved = b.server.calls.filter(call => call.name === 'set_panel_line_completion_565');
  assert.equal(saved.length, 1);
  assert.equal(saved[0].body.p_line_identity, `source:${U(1, 2)}`);
  assert.equal(saved[0].body.p_completed, true);
  const ticked = b.panel().querySelector(`li[data-operation-source-id="${U(1, 2)}"]`);
  assert.equal(ticked.classList.contains('is-complete'), true);
  assert.match(ticked.querySelector('.vso-done-meta').textContent, /Complete \(override by controller@example\.test\)/);
  assert.equal(ticked.querySelector('.vso-tick span').textContent, 'Complete');
  assert.equal(ticked.querySelector('[data-vso-tick]').getAttribute('aria-checked'), 'true');
  ticked.querySelector('[data-vso-tick]').dispatch('click');
  await b.settle();
  const again = b.server.calls.filter(call => call.name === 'set_panel_line_completion_565');
  assert.equal(again.length, 2);
  assert.equal(again[1].body.p_completed, false);
  assert.equal(b.panel().querySelector(`li[data-operation-source-id="${U(1, 2)}"]`).classList.contains('is-complete'), false);

  const viewer = board({ role: 'viewer' });
  viewer.openPanel();
  await viewer.settle();
  const locked = viewer.panel().querySelector(`li[data-operation-source-id="${U(1, 2)}"] [data-vso-tick]`);
  assert.equal(locked.disabled, true);
  assert.equal(locked.getAttribute('title'), 'Read-only for your role');
  locked.dispatch('click');
  await viewer.settle();
  assert.equal(viewer.server.calls.some(call => call.name === 'set_panel_line_completion_565'), false);
  assert.equal(viewer.panel().querySelector('[data-vso-edit-toggle]'), null);
  assert.equal(viewer.panel().querySelector('[data-vso-station-override]'), null);
});

test('a controller can override a whole station and undo it', async () => {
  const b = board({ role: 'operator' });
  b.openPanel();
  await b.settle();
  const button = b.panel().querySelector('[data-vso-station-override="bus4x4"]');
  assert.equal(button.textContent, 'Override');
  button.dispatch('click');
  await b.settle();
  const saved = b.server.calls.filter(call => call.name === 'set_station_completion_override_578');
  assert.equal(saved.length, 1);
  assert.equal(saved[0].body.p_work_key, 'bus4x4');
  assert.equal(saved[0].body.p_completed, true);
  const again = b.panel().querySelector('[data-vso-station-override="bus4x4"]');
  assert.equal(again.textContent, 'Undo override');
  assert.match(again.getAttribute('title'), /Complete \(override by controller@example\.test\)/);
  again.dispatch('click');
  await b.settle();
  const undone = b.server.calls.filter(call => call.name === 'set_station_completion_override_578');
  assert.equal(undone.length, 2);
  assert.equal(undone[1].body.p_completed, false);
  assert.equal(b.panel().querySelector('[data-vso-station-override="bus4x4"]').textContent, 'Override');
});

test('the regression check is sort 337 / F179 and the setter checks the controller role', () => {
  const up = fs.readFileSync('supabase/migrations/20261027150000_r565_panel_line_completion.sql', 'utf8');
  const down = fs.readFileSync('supabase/rollbacks/20261027150000_r565_panel_line_completion.down.sql', 'utf8');
  assert.match(up, /pdc_ops\.fault_regression_check\(\)/);
  assert.match(up, /'panel_line_completion_565', 'F179'/);
  assert.match(up, /true, 337, 'r565'/);
  assert.match(up, /AS ok/);
  assert.match(up, /AS detail/);
  assert.match(up, /controller_required/);
  assert.match(up, /sort_order=336 AND added_in='r563'/, 'arrival age r563 stays the predecessor');
  assert.doesNotMatch(up, /true, 336,/);
  const body = up.split('$set565$')[1].split('$set565$')[0];
  assert.match(body, /'operator', 'administrator'/);
  assert.equal(body.includes('workshop_bookings'), false);
  assert.equal(body.includes('user_metadata'), false);
  assert.equal(body.includes('UPDATE public.vehicles'), false);
  assert.match(down, /sort_order=337/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks\s+WHERE/);
  assert.doesNotMatch(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /\bfetch\s*\(|\.rpc\s*\(/);
});

test('r694: a tick saved earlier shows as soon as the panel opens (the late completion read repaints the lines)', async () => {
  const b = board();
  b.server.ticks.push({ vehicle_id: b.rows[0].id, line_identity: `source:${U(1, 2)}`, completed: true, actor_email: 'controller@example.test', actor_role: 'administrator', acted_at: '2026-10-29T00:20:00.000Z', version: 1 });
  b.openPanel();
  await b.settle();
  const line = b.panel().querySelector(`li[data-operation-source-id="${U(1, 2)}"]`);
  assert.equal(line.classList.contains('is-complete'), true);
  assert.equal(line.querySelector('[data-vso-tick]').getAttribute('aria-checked'), 'true');
  assert.equal(line.querySelector('.vso-tick span').textContent, 'Complete');
});
