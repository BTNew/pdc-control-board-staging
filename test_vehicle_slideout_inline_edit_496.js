/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r496 (F109, Craig 22 Oct 19:16): edit hours and move lines between jobs inside the Vehicle Locations slide-out panel.
// Real app.js (Work & bookings rows, Save all hours, set_vehicle_work_category, the one-vehicle detail read), the real
// pdc-email-vehicle-location-service.js, the real panel, a small in-memory DOM (qa/mini-dom-496.cjs) and a stubbed fetch:
// nothing leaves the process and nothing is written anywhere. Synthetic vehicles only (SYN-04xx, Sample customer).
//  1. "Edit jobs & hours" becomes "Edit" + "Open full editor"; the old window and its code are unchanged.
//  2. Edit keeps the same chip list and draws app.js's own hours inputs on those chips. r565 (F179) no longer
//     swaps in the Work & bookings page or its category selectors.
//  3. Save runs Save all hours (save_vehicle_workshop_line_hours_batch_768) only. A station drop runs
//     set_vehicle_work_category for that line. Cancel sends nothing.
//  4. Speed guard: drawing the board reads nothing. Opening the panel may read the completion list once per vehicle.
//     The workshop detail read happens only on Edit, for that vehicle. A save redraws only the panel.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const nodeCrypto = require('node:crypto');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { createDocument } = require('./qa/mini-dom-496.cjs');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service.js');
const slideout = require('./pdc-vehicle-slideout.js');

const SRC = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
const CODE = SRC.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
const CSS = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');
const STAGING_URL = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
const U = (v, n) => `00000000-0000-4000-8000-000000000${v}0${n}`;
const OPS = [[1, 'SIDE STEPS (SAMPLE)', 'BUS_MECHANICAL', 0.75], [2, 'BULL BAR (SAMPLE)', 'BUS_MECHANICAL', 5.18],
  [3, 'FIRE EXTINGUISHER (SAMPLE)', 'BUS_ACCESSORIES', 0.5], [4, 'LED LIGHT BAR (SAMPLE)', 'BUS_ELECTRICAL', 1.33]];

function syntheticVehicle(n) {
  const id = `00000000-0000-4000-8000-0000000004${String(n).padStart(2, '0')}`;
  return { id, __emailVehicleId: id, permanentVehicleId: id, __emailVehicleServerAuthoritative: true, __emailVehicleVersion: 7,
    stock: `SYN-04${String(n).padStart(2, '0')}`, keyNumber: String(40 + n), jobcard: `JSYN04${n}`, client: 'Sample customer', vehicle: 'HiLux (sample)',
    dealerCode: '37047', pdcDepartmentCodes: ['138'], pdcJobCardNumbers: [`JSYN04${n}`], pdcLocation: 'PMB', source: 'Manual', pdcSheetVisible: true,
    pdcEmailOperationLines: OPS.map(([op, d, , h]) => ({ operation_no: `OP${op}`, description: d, work_key: 'bus4x4', stage_code: 'BUS_4X4', department: '138', operation_line_id: U(n, op), estimated_hours: h })) };
}
function detailFor(vehicle, n, version = 7, categories = {}) {
  return { vehicle_id: vehicle.id, vehicle_version: version, bookings: [], line_adjustments: [], work_categories: [],
    requirements: [{ stage_code: 'BUS_4X4', work_key: 'bus4x4', required: true, completed: false }],
    job_card_lines: OPS.map(([op, d, cat, h]) => ({ line_identity: `source:${U(n, op)}`, source_line_id: U(n, op), operation_no: String(op), description: d,
      work_category: categories[op] || cat, category_version: 0, stage_code: 'BUS_4X4', department: '138', estimated_hours: h, hours_provenance: 'job_card',
      category_rule: 'craig_jobcard_categories_20261015', source_kind: 'authenticated', active: true })) };
}

function board({ role = 'administrator', vehicles = 3 } = {}) {
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
  const rows = Array.from({ length: vehicles }, (_, i) => syntheticVehicle(i + 1));
  c.app.data = rows;
  const server = { details: new Map(rows.map((v, i) => [v.id, detailFor(v, i + 1)])), calls: [] };
  // Every request is answered here, in the process. Writes only change this in-memory copy.
  c.fetch = async (url, init = {}) => {
    const name = String(url).split('/rpc/')[1] || String(url);
    const body = init.body ? JSON.parse(init.body) : {};
    server.calls.push({ name, body });
    let reply = { ok: false, code: 'not_in_test' };
    if (name === 'get_vehicle_workshop_detail_scoped') reply = server.details.get(body.p_vehicle_id);
    if (name === 'set_vehicle_work_category' && c.releaseMode && body.p_release_unstarted !== true) {
      reply = { ok: false, error: 'confirm_release', message: c.releaseMode };
    } else if (name === 'set_vehicle_work_category') {
      const detail = server.details.get(body.p_vehicle_id);
      const line = detail.job_card_lines.find(l => l.line_identity === body.p_line_identity);
      if (line && body.p_vehicle_expected_version === detail.vehicle_version && body.p_category_expected_version === line.category_version) {
        line.work_category = body.p_category; line.category_version += 1; detail.vehicle_version += 1; reply = { ok: true };
      } else reply = { ok: false, error: 'version_conflict', message: 'Synthetic version conflict' };
    }
    if (name === 'get_panel_line_completions_565' && server.completionLines) reply = { ok: true, lines: server.completionLines };
    if (name === 'save_vehicle_workshop_line_hours_batch_768') {
      const detail = server.details.get(body.p_vehicle_id);
      for (const row of body.p_estimated_rows) { const line = detail.job_card_lines.find(l => l.line_identity === row.line_key); if (line) line.estimated_hours = row.estimated_hours; }
      detail.vehicle_version += 1;
      reply = { ok: true, data: { receipt_id: 'syn-receipt', vehicle_id: body.p_vehicle_id, request_sha256: 'a'.repeat(64), changed_count: body.p_estimated_rows.length } };
    }
    return { ok: true, status: 200, json: async () => JSON.parse(JSON.stringify(reply)) };
  };
  c.app.emailVehicleLocationService = createPdcEmailVehicleLocationService({ config: { url: STAGING_URL, publishableKey: 'test-only-not-a-key' }, getAccessToken: () => 'test-only-token', fetchImpl: (...a) => c.fetch(...a) });
  const spies = { notices: [], confirms: [], boardRenders: 0, tableRenders: 0, panelDraws: 0, cardsDrawn: 0, opened: [] };
  c.pdcNotify = message => spies.notices.push(message);
  c.confirm = message => { spies.confirms.push(message); return spies.confirmAnswer ?? true; };
  c.renderAll = () => { spies.boardRenders += 1; };
  c.vehicleLocationsScreenRows = () => rows;
  c.openVehicleCardFromVisibleBoard = () => true;
  // The real ops block (authenticatedEmailOperationLinesHtml) inside a card shell, as incomingVehicleDetailRow draws it.
  c.incomingVehicleDetailRow = vehicle => { spies.cardsDrawn += 1; return `<details class="incoming-vehicle-card"><summary>row</summary><div class="incoming-vehicle-detail-grid">${c.authenticatedEmailOperationLinesHtml(vehicle)}</div></details>`; };
  const realOpen = c.openAuthenticatedOperationWorkshop;
  c.openAuthenticatedOperationWorkshop = stock => { spies.opened.push(stock); return true; };
  // A stand-in for the r461 table module: the panel only needs these hooks from it.
  const vlt = { TILE: {}, state: { view: 'table' }, splitCard: () => ({ key: null }), bindBoardHandlers() {}, drawerClosed() {}, render() { spies.tableRenders += 1; }, setDrawerOpener(o) { this.opener = o; } };
  c.PDC_VEHICLE_LOCATIONS_TABLE = vlt;
  fixture.loadHelper('pdc-vehicle-slideout.js');
  const panel = () => doc.getElementById('vso-shell').querySelector('.vso-panel');
  const openPanel = vehicle => { vlt.opener.open(c.vehicleKey(vehicle), 'pmb'); return panel(); };
  const settle = async () => { for (let i = 0; i < 8; i += 1) await new Promise(r => setImmediate(r)); };
  const reads = () => server.calls.filter(call => call.name === 'get_vehicle_workshop_detail_scoped');
  const writes = () => server.calls.filter(call => !['get_vehicle_workshop_detail_scoped', 'get_panel_line_completions_565', 'list_station_icon_completion_578'].includes(call.name));
  return { c, doc, rows, server, spies, vlt, panel, openPanel, settle, reads, writes, realOpen };
}
const click = el => { assert.ok(el, 'element to click'); return el.dispatch('click'); };
const type = (input, value) => { input.value = value; input.dispatch('input'); };

test('1. the heading shows Edit only (r695, F305: Open full editor removed from the panel); the old window code stays in app.js', async () => {
  const b = board();
  const panel = b.openPanel(b.rows[0]);
  const heading = panel.querySelector('.authenticated-email-operations-heading');
  assert.ok(heading, 'operations block drawn');
  assert.equal(heading.querySelector('[data-auth-operation-work]'), null, 'the old button is replaced');
  assert.equal(heading.querySelector('[data-vso-top-edit]'), null, 'r699: Edit moved to the top row');
  assert.equal(panel.querySelector('.vso-open-row [data-vso-top-edit]').textContent, 'Edit');
  assert.equal(panel.querySelector('[data-vso-full-editor]'), null, 'r695: no Open full editor button');
  assert.doesNotMatch(panel.textContent, /Open full editor/, 'r695: no Open full editor anywhere in the panel');
  assert.deepEqual(b.spies.opened, [], 'the old window is not opened from the panel');
  const APP = fs.readFileSync('app.js', 'utf8');
  assert.match(APP, /function openAuthenticatedOperationWorkshop\(stock\)/);
  assert.match(APP, />Save all hours<\/button>/);
  assert.equal(typeof b.realOpen, 'function');
});

test('1b. same role gate as the window: viewers and fitters get neither Edit nor the link', () => {
  for (const role of ['viewer', 'workshop', 'importer', '']) {
    const b = board({ role });
    const panel = b.openPanel(b.rows[0]);
    assert.equal(panel.querySelector('[data-vso-top-edit]'), null, `${role || 'no role'}: no Edit`);
    assert.equal(panel.querySelector('[data-vso-full-editor]'), null, `${role || 'no role'}: no Open full editor`);
    assert.equal(panel.querySelector('.vso-edit'), null);
    assert.equal(b.reads().length, 0);
  }
});

test('2. Edit loads this one vehicle and keeps the same chip list, with hours inputs on the chips', async () => {
  const b = board();
  let panel = b.openPanel(b.rows[1]);
  assert.equal(b.reads().length, 0, 'opening the panel does not read workshop detail');
  click(panel.querySelector('[data-vso-top-edit]'));
  panel = b.panel();
  assert.match(panel.querySelector('.vso-edit').textContent, /Loading this vehicle's jobs and hours/);
  assert.equal(panel.querySelector('.vehicle-workshop-page'), null, 'Edit does not open the Work & bookings layout');
  await b.settle();
  assert.deepEqual(b.reads().map(r => r.body.p_vehicle_id), [b.rows[1].id], 'one detail read, for this vehicle only');
  panel = b.panel();
  const page = panel.querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  const grid = panel.querySelector('.authenticated-operation-station-grid');
  assert.ok(page, 'editor drawn');
  assert.equal(grid.hidden, false, 'the chip list stays visible');
  assert.equal(grid.closest('[data-vehicle-workshop-hours-batch-page]'), page, 'the same grid is edited in place');
  assert.equal(panel.querySelector('.vehicle-workshop-page'), null);
  assert.equal(panel.querySelector('[data-vehicle-workshop-line-category]'), null, 'no Work category selector');
  const inputs = page.querySelectorAll('[data-vehicle-workshop-hours-batch-input]');
  assert.equal(inputs.length, 4);
  assert.deepEqual(inputs.map(i => i.value), ['0.75', '5.18', '0.5', '1.33']);
  const windowHtml = b.c.renderVehicleWorkshopWorkPage(b.c.selectedVehicle(b.c.vehicleKey(b.rows[1])));
  for (const tag of windowHtml.match(/<input\b[^>]*data-vehicle-workshop-hours-batch-input[^>]*>/g) || []) assert.ok(slideout.slimWorkPage(windowHtml).includes(tag), 'input tag unchanged');
  assert.match(windowHtml, /Best slot|Edit line|Save all hours/);
  const buttons = [...panel.querySelector('.vso-edit').querySelectorAll('button')].map(btn => btn.dataset.vsoEditAct).filter(Boolean);
  assert.deepEqual(buttons.sort(), ['cancel', 'save'], 'only Save and Cancel (r695: no Open full editor)');
  assert.equal(panel.querySelector('[data-vso-edit-act="save"]').disabled, true, 'Save waits for a change');
  assert.equal(b.writes().length, 0);
});

test('3. Save runs Save all hours for the changed chip and leaves the line in its job', async () => {
  const b = board();
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  const page = b.panel().querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  type(page.querySelectorAll('[data-vehicle-workshop-hours-batch-input]')[1], '4.5');
  assert.equal(b.writes().length, 0, 'nothing is sent while typing');
  const save = b.panel().querySelector('[data-vso-edit-act="save"]');
  assert.equal(save.disabled, false);
  const before = { table: b.spies.tableRenders, board: b.spies.boardRenders };
  await click(save)[0];
  await b.settle();
  const writes = b.writes();
  assert.deepEqual(writes.map(w => w.name), ['save_vehicle_workshop_line_hours_batch_768']);
  assert.equal(writes[0].body.p_vehicle_id, b.rows[0].id);
  assert.equal(writes[0].body.p_expected_vehicle_version, 7);
  assert.deepEqual(writes[0].body.p_estimated_rows.map(r => [r.line_key, r.estimated_hours]), [[`source:${U(1, 2)}`, 4.5]], 'only the changed row');
  assert.equal(b.spies.tableRenders, before.table, 'the table is not drawn again');
  assert.equal(b.spies.boardRenders, before.board, 'the board is not drawn again');
  assert.equal(b.reads().every(r => r.body.p_vehicle_id === b.rows[0].id), true, 'every detail read is this vehicle');
  const panel = b.panel();
  assert.equal(panel.querySelector('.vso-edit'), null, 'editor closes after a good save');
  assert.equal(panel.querySelector('.vso-edit-msg').textContent, 'Saved. 1 hour change.');
  assert.match(panel.querySelector('.authenticated-operation-station-grid').textContent, /4\.50 h/);
  assert.equal(b.server.details.get(b.rows[0].id).job_card_lines[0].work_category, 'BUS_MECHANICAL');
  assert.deepEqual(b.spies.notices, []);
  assert.deepEqual(b.spies.confirms, []);
});

test('3a. dragging a chip onto another station asks confirm_release, then saves that line with the release flag', async () => {
  const b = board();
  const sentence = 'The running Fitting job (Fitting - PMB Bay 06, Mon 26 Oct) stays on the bay. These 7.25 h move onto that job.';
  b.c.releaseMode = sentence;
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  const chip = b.panel().querySelector(`li[data-operation-source-id="${U(1, 1)}"]`);
  const target = b.panel().querySelector('[data-operation-category="bus_accessories"]');
  b.spies.confirmAnswer = true;
  chip.dispatch('dragstart');
  target.dispatch('dragover');
  target.dispatch('drop');
  await b.settle();
  const categoryWrites = b.writes().filter(w => w.name === 'set_vehicle_work_category');
  assert.equal(categoryWrites.length, 2, 'the drop is previewed, then saved after the confirm');
  assert.deepEqual(b.spies.confirms, [sentence]);
  assert.equal(categoryWrites[0].body.p_release_unstarted, undefined);
  assert.equal(categoryWrites[1].body.p_release_unstarted, true);
  assert.equal(categoryWrites[1].body.p_line_identity, `source:${U(1, 1)}`);
  assert.equal(categoryWrites[1].body.p_category, 'BUS_ACCESSORIES');
  assert.deepEqual(categoryWrites[1].body.p_batch, [{ line_identity: `source:${U(1, 1)}`, category: 'BUS_ACCESSORIES' }]);
  assert.equal(b.spies.notices.length, 0);
  assert.equal(b.server.details.get(b.rows[0].id).job_card_lines[0].work_category, 'BUS_ACCESSORIES');
  assert.equal(b.panel().querySelector(`li[data-operation-source-id="${U(1, 1)}"]`).closest('[data-operation-category]').dataset.operationCategory, 'bus_accessories');
});

test('3a2. declining the confirm leaves the chip where it is', async () => {
  const b = board();
  b.c.releaseMode = 'This will release the unstarted Electrical booking (no bay, Tue 20 Oct).';
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  const chip = b.panel().querySelector(`li[data-operation-source-id="${U(1, 1)}"]`);
  const target = b.panel().querySelector('[data-operation-category="bus_accessories"]');
  b.spies.confirmAnswer = false;
  chip.dispatch('dragstart');
  target.dispatch('drop');
  await b.settle();
  assert.deepEqual(b.writes().map(w => w.name), ['set_vehicle_work_category']);
  assert.equal(b.writes()[0].body.p_release_unstarted, undefined);
  assert.deepEqual(b.spies.notices, ['Save cancelled. Nothing was changed.']);
  assert.equal(b.server.details.get(b.rows[0].id).job_card_lines[0].work_category, 'BUS_MECHANICAL');
  assert.ok(b.panel().querySelector('.vso-edit'), 'editor stays open');
  assert.equal(b.panel().querySelector(`li[data-operation-source-id="${U(1, 1)}"]`).closest('[data-operation-category]').dataset.operationCategory, 'bus_mechanical');
});

test('3b. Cancel drops the drafts and sends nothing; a refused drop keeps the editor open', async () => {
  const b = board();
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  const page = b.panel().querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  type(page.querySelectorAll('[data-vehicle-workshop-hours-batch-input]')[0], '9');
  click(b.panel().querySelector('[data-vso-edit-act="cancel"]'));
  assert.equal(b.panel().querySelector('.vso-edit'), null);
  assert.equal(b.writes().length, 0);
  assert.equal(b.c.app.vehicleWorkshopHoursBatchDrafts.has(b.rows[0].id), false, 'draft dropped');
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  b.server.details.get(b.rows[0].id).job_card_lines[2].category_version = 5;
  const chip = b.panel().querySelector(`li[data-operation-source-id="${U(1, 3)}"]`);
  const target = b.panel().querySelector('[data-operation-category="bus_electrical"]');
  chip.dispatch('dragstart');
  target.dispatch('drop');
  await b.settle();
  assert.deepEqual(b.writes().map(w => w.name), ['set_vehicle_work_category']);
  assert.ok(b.panel().querySelector('.vso-edit'), 'editor stays open');
  assert.equal(b.panel().querySelector(`li[data-operation-source-id="${U(1, 3)}"]`).closest('[data-operation-category]').dataset.operationCategory, 'bus_accessories');
  assert.equal(b.server.details.get(b.rows[0].id).job_card_lines[2].work_category, 'BUS_ACCESSORIES');
  assert.equal(b.spies.notices.length, 1, 'app.js\'s own error message');
});

test('3c. closing the panel or opening another vehicle with unsaved changes asks first', async () => {
  const b = board();
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  type(b.panel().querySelector('[data-vehicle-workshop-hours-batch-input]'), '3');
  b.spies.confirmAnswer = false;
  b.vlt.opener.open(b.c.vehicleKey(b.rows[1]), 'pmb');
  assert.equal(b.c.PDC_VEHICLE_SLIDEOUT.state.key, b.c.vehicleKey(b.rows[0]), 'stays on the vehicle being edited');
  b.vlt.opener.close();
  assert.equal(b.c.PDC_VEHICLE_SLIDEOUT.state.key, b.c.vehicleKey(b.rows[0]), 'stays open');
  b.spies.confirmAnswer = true;
  b.vlt.opener.open(b.c.vehicleKey(b.rows[1]), 'pmb');
  assert.equal(b.c.PDC_VEHICLE_SLIDEOUT.state.key, b.c.vehicleKey(b.rows[1]));
  assert.equal(b.panel().querySelector('.vso-edit'), null);
  assert.equal(b.spies.confirms.length, 3);
  assert.equal(b.writes().length, 0);
});

test('4. speed guard: the board reads nothing; a panel open reads the completion list once; Edit reads one vehicle', async () => {
  const b = board({ vehicles: 40 });
  b.c.app.data = b.rows;
  b.server.completionLines = [{ line_identity: 'source:line', completed: false, actor_email: '', acted_at: '' }];
  for (const vehicle of b.rows) b.c.incomingVehicleDetailRow(vehicle);
  assert.equal(b.server.calls.length, 0, 'drawing the board reads nothing');
  for (const vehicle of b.rows) b.openPanel(vehicle);
  await b.settle();
  assert.equal(b.spies.cardsDrawn, 80, '40 board rows plus one card per open; the completion list does not draw the card again');
  assert.equal(b.c.PDC_VEHICLE_SLIDEOUT.state.key, b.c.vehicleKey(b.rows[39]));
  b.vlt.opener.refresh(b.c.vehicleKey(b.rows[39]), 'pmb');
  assert.equal(b.spies.cardsDrawn, 80, 'a table refresh of the same vehicle does not rebuild the panel');
  const completions = b.server.calls.filter(call => call.name === 'get_panel_line_completions_565');
  assert.equal(completions.length, 40, 'one completion read per opened vehicle');
  assert.deepEqual([...new Set(completions.map(call => call.body.p_vehicle_id))].sort(), b.rows.map(row => row.id).sort());
  assert.equal(b.reads().length, 0, 'workshop detail is not read on open');
  assert.equal(b.c.PDC_VEHICLE_SLIDEOUT.edit.loads, 0);
  b.openPanel(b.rows[7]);
  click(b.panel().querySelector('[data-vso-top-edit]'));
  await b.settle();
  assert.equal(b.reads().length, 1);
  assert.equal(b.reads()[0].body.p_vehicle_id, b.rows[7].id);
  assert.equal(b.spies.tableRenders + b.spies.boardRenders, 0, 'Edit draws the panel only');
  assert.equal((CODE.match(/loadVehicleWorkshopDetail\(/g) || []).length, 2, 'Edit, and r699 (F309) Move to when a station is picked');
  assert.match(CODE, /const readDetail = vehicle => Promise\.resolve\(root\.loadVehicleWorkshopDetail\(vehicle, \{ force: true \}\)\);/);
  assert.match(/function startEdit\(key\) \{[\s\S]*?\n {2}\}/.exec(CODE)[0], /root\.loadVehicleWorkshopDetail\(vehicle, \{ force: true \}\)/);
  const r496 = CODE.slice(CODE.indexOf('const EDIT_NEEDS'), CODE.indexOf('function loadStyles'));
  assert.doesNotMatch(r496, /VLT\.render|renderAll|renderIncomingDashboardBoard|refreshEmailVehicleLocations|renderDetail\(/);
  assert.doesNotMatch(/function render\(key, bucket[\s\S]*?\n {2}\}/.exec(CODE)[0], /workshopLoadPlans|loadVehicleWorkshopDetail|startEdit/);
  assert.doesNotMatch(/function startEdit\(key\) \{[\s\S]*?\n {2}\}/.exec(CODE)[0], /workshopLoadPlans/);
  assert.match(r496, /const redraw = key => \{ if \(state\.key === key\) render\(key, state\.bucket, \{ keepScroll: true \}\); \};/);
  assert.match(/function decorateOperations\([\s\S]*?\n {2}\}/.exec(CODE)[0], /startEdit\(key\)/);
  assert.doesNotMatch(CODE, /\bfetch\s*\(|\.rpc\s*\(|localStorage|sessionStorage|XMLHttpRequest/);
});

test('5. slimWorkPage keeps inputs and selectors, removes every button, keeps drag-handle numbers as text', () => {
  const html = '<div data-vehicle-workshop-hours-batch-page><button type="button" class="vehicle-workshop-line-number" draggable="true" data-vehicle-workshop-line-handle>3</button><input data-vehicle-workshop-hours-batch-input value="1"><select data-vehicle-workshop-line-category><option value="A" selected>A</option></select><button type="button" data-vehicle-workshop-line-edit>Edit line</button><button type="button" data-vehicle-workshop-schedule-next>Best slot</button><p><button data-vehicle-workshop-offboard-done>Mark <b>done</b></button></p></div>';
  const out = slideout.slimWorkPage(html);
  assert.doesNotMatch(out, /<button|draggable|Best slot|Edit line|Mark/);
  assert.match(out, /<span class="vehicle-workshop-line-number">3<\/span>/);
  assert.match(out, /<input data-vehicle-workshop-hours-batch-input value="1">/);
  assert.match(out, /<select data-vehicle-workshop-line-category><option value="A" selected>A<\/option><\/select>/);
});

test('6. loader, styles and docs: r565 cache-bust tags, FAULT_LOG F109 and F179, panel doc; no real stock numbers here', () => {
  assert.equal(slideout.VERSION, '2026.10.28.r588');
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.28\.r588&r595=2026\.10\.28\.r595(&r681=2026\.10\.29\.r681)?(&r695=2026\.10\.29\.r695)?(&r696=2026\.10\.29\.r696)?(&r699=2026\.10\.29\.r699)?(&r705=2026\.10\.29\.r705)?(&r721=2026\.10\.29\.r721)?(&r738=2026\.10\.30\.r738)?'/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*&amp;r496=2026\.10\.22\.r496&amp;/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /&amp;r563=2026\.10\.27\.r563&amp;/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /&amp;r565=2026\.10\.27\.r565&amp;/);
  assert.match(CSS, /#vso-shell \.vso-edit \.vehicle-workshop-line-booking,/);
  assert.match(CSS, /#vso-shell \.vso-edit-save \{/);
  assert.doesNotMatch(CSS, /#f59e0b|#f97316|#ffedd5|#fffbeb/);
  const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  const row = log.split('\n').find(line => line.startsWith('| F109 |'));
  assert.ok(row && /Open full editor/.test(row) && /set_vehicle_work_category/.test(row));
  assert.ok(log.split('\n').some(line => line.startsWith('| F179 |') && /set_panel_line_completion_565/.test(line)));
  assert.match(fs.readFileSync('docs/vehicle-slideout-panel.md', 'utf8'), /r496 \(F109\)[\s\S]*Open full editor/);
  assert.match(fs.readFileSync('docs/vehicle-slideout-panel.md', 'utf8'), /r565 \(F179\)[\s\S]*same chip list/);
  for (const locked of ['styles.css', 'pdc-vehicle-locations-table.js', 'pdc-operation-panels.js']) assert.doesNotMatch(fs.readFileSync(locked, 'utf8'), /r496|vso-edit/, `${locked} untouched`);
  assert.doesNotMatch(fs.readFileSync('app.js', 'utf8'), /vso-edit/);
  assert.doesNotMatch(fs.readFileSync(__filename, 'utf8'), /\b1[23]\d{6}\b|\bJ13[89]\d{6}\b/);
});
