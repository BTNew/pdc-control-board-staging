/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r496 (F109, Craig 22 Oct 19:16): edit hours and move lines between jobs inside the Vehicle Locations slide-out panel.
// Real app.js (Work & bookings rows, Save all hours, set_vehicle_work_category, the one-vehicle detail read), the real
// pdc-email-vehicle-location-service.js, the real panel, a small in-memory DOM (qa/mini-dom-496.cjs) and a stubbed fetch:
// nothing leaves the process and nothing is written anywhere. Synthetic vehicles only (SYN-04xx, Sample customer).
//  1. "Edit jobs & hours" becomes "Edit" + "Open full editor"; the old window and its code are unchanged.
//  2. Edit draws app.js's own hours inputs and Work category selectors (no buttons) in place of the read-only list.
//  3. Save runs the window's own save paths: Save all hours (save_vehicle_workshop_line_hours_batch_768), then
//     set_vehicle_work_category for each moved line, with the window's own arguments; Cancel sends nothing.
//  4. Speed guard: drawing the board / opening the panel reads nothing per vehicle; the one extra read happens only on
//     Edit, for that vehicle; after a save only the panel is drawn again (never the table, never the board).
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
    if (name === 'set_vehicle_work_category') {
      const detail = server.details.get(body.p_vehicle_id);
      const line = detail.job_card_lines.find(l => l.line_identity === body.p_line_identity);
      if (line && body.p_vehicle_expected_version === detail.vehicle_version && body.p_category_expected_version === line.category_version) {
        line.work_category = body.p_category; line.category_version += 1; detail.vehicle_version += 1; reply = { ok: true };
      } else reply = { ok: false, error: 'version_conflict', message: 'Synthetic version conflict' };
    }
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
  const writes = () => server.calls.filter(call => call.name !== 'get_vehicle_workshop_detail_scoped');
  return { c, doc, rows, server, spies, vlt, panel, openPanel, settle, reads, writes, realOpen };
}
const click = el => { assert.ok(el, 'element to click'); return el.dispatch('click'); };
const type = (input, value) => { input.value = value; input.dispatch('input'); };
const choose = (select, value) => { select.value = value; select.dispatch('change'); };

test('1. the heading shows Edit and Open full editor instead of Edit jobs & hours; the old window still opens from the link', async () => {
  const b = board();
  const panel = b.openPanel(b.rows[0]);
  const heading = panel.querySelector('.authenticated-email-operations-heading');
  assert.ok(heading, 'operations block drawn');
  assert.equal(heading.querySelector('[data-auth-operation-work]'), null, 'the old button is replaced');
  assert.equal(heading.querySelector('[data-vso-edit-toggle]').textContent, 'Edit');
  assert.equal(heading.querySelector('[data-vso-full-editor]').textContent, 'Open full editor');
  click(heading.querySelector('[data-vso-full-editor]'));
  assert.deepEqual(b.spies.opened, [b.c.vehicleKey(b.rows[0])], 'Open full editor -> app.js openAuthenticatedOperationWorkshop (the old window)');
  // The old window and its code are kept: app.js still has the window opener, Save all hours and the button text.
  const APP = fs.readFileSync('app.js', 'utf8');
  assert.match(APP, /function openAuthenticatedOperationWorkshop\(stock\)/);
  assert.match(APP, /data-auth-operation-work="\$\{escapeHtml\(vehicleIdentity\)\}">Edit jobs &amp; hours<\/button>/);
  assert.match(APP, />Save all hours<\/button>/);
  assert.equal(typeof b.realOpen, 'function');
});

test('1b. same role gate as the window: viewers and fitters get neither Edit nor the link', () => {
  for (const role of ['viewer', 'workshop', 'importer', '']) {
    const b = board({ role });
    const panel = b.openPanel(b.rows[0]);
    assert.equal(panel.querySelector('[data-vso-edit-toggle]'), null, `${role || 'no role'}: no Edit`);
    assert.equal(panel.querySelector('[data-vso-full-editor]'), null, `${role || 'no role'}: no Open full editor`);
    assert.equal(panel.querySelector('.vso-edit'), null);
    assert.equal(b.reads().length, 0);
  }
});

test('2. Edit loads this one vehicle, then shows app.js\'s own hours inputs and Work category selectors with no buttons', async () => {
  const b = board();
  let panel = b.openPanel(b.rows[1]);
  assert.equal(b.reads().length, 0, 'opening the panel reads nothing');
  click(panel.querySelector('[data-vso-edit-toggle]'));
  panel = b.panel();
  assert.match(panel.querySelector('.vso-edit').textContent, /Loading this vehicle's jobs and hours/);
  await b.settle();
  assert.deepEqual(b.reads().map(r => r.body.p_vehicle_id), [b.rows[1].id], 'one read, for this vehicle only');
  panel = b.panel();
  const page = panel.querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  assert.ok(page, 'editor drawn');
  assert.equal(panel.querySelector('.authenticated-operation-station-grid').hidden, true, 'read-only list hidden while editing');
  const inputs = page.querySelectorAll('[data-vehicle-workshop-hours-batch-input]');
  const selects = page.querySelectorAll('[data-vehicle-workshop-line-category]');
  assert.equal(inputs.length, 4); assert.equal(selects.length, 4);
  assert.deepEqual(inputs.map(i => i.value), ['0.75', '5.18', '0.5', '1.33']);
  assert.deepEqual(selects.map(s => s.value), ['BUS_MECHANICAL', 'BUS_MECHANICAL', 'BUS_ACCESSORIES', 'BUS_ELECTRICAL']);
  // Same markup as the window: the slim copy only drops buttons.
  const windowHtml = b.c.renderVehicleWorkshopWorkPage(b.c.selectedVehicle(b.c.vehicleKey(b.rows[1])));
  for (const tag of windowHtml.match(/<input\b[^>]*data-vehicle-workshop-hours-batch-input[^>]*>/g)) assert.ok(slideout.slimWorkPage(windowHtml).includes(tag), 'input tag unchanged');
  assert.match(windowHtml, /Best slot|Edit line|Save all hours/);
  const buttons = panel.querySelector('.vso-edit').querySelectorAll('button').map(btn => btn.dataset.vsoEditAct);
  assert.deepEqual(buttons.sort(), ['cancel', 'full', 'save'], 'only Save, Cancel and Open full editor');
  assert.equal(panel.querySelector('[data-vso-edit-act="save"]').disabled, true, 'Save waits for a change');
  assert.equal(b.writes().length, 0);
});

test('3. Save runs Save all hours, then set_vehicle_work_category for the moved line, with the window\'s arguments', async () => {
  const b = board();
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-edit-toggle]'));
  await b.settle();
  let page = b.panel().querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  type(page.querySelectorAll('[data-vehicle-workshop-hours-batch-input]')[1], '4.5');
  choose(page.querySelectorAll('[data-vehicle-workshop-line-category]')[0], 'BUS_ACCESSORIES');
  assert.equal(b.writes().length, 0, 'nothing is sent while typing or choosing');
  const save = b.panel().querySelector('[data-vso-edit-act="save"]');
  assert.equal(save.disabled, false);
  const before = { table: b.spies.tableRenders, board: b.spies.boardRenders };
  await click(save)[0];
  await b.settle();
  const writes = b.writes();
  assert.deepEqual(writes.map(w => w.name), ['save_vehicle_workshop_line_hours_batch_768', 'set_vehicle_work_category']);
  assert.equal(writes[0].body.p_vehicle_id, b.rows[0].id);
  assert.equal(writes[0].body.p_expected_vehicle_version, 7);
  assert.deepEqual(writes[0].body.p_estimated_rows.map(r => [r.line_key, r.estimated_hours]), [[`source:${U(1, 2)}`, 4.5]], 'only the changed row');
  assert.deepEqual(writes[1].body, { p_vehicle_id: b.rows[0].id, p_vehicle_expected_version: 8, p_line_identity: `source:${U(1, 1)}`, p_category: 'BUS_ACCESSORIES', p_category_expected_version: 0 },
    'reloaded vehicle version after the hours save, the line\'s own category version');
  assert.equal(b.spies.tableRenders, before.table, 'the table is not drawn again');
  assert.equal(b.spies.boardRenders, before.board, 'the board is not drawn again');
  assert.equal(b.reads().every(r => r.body.p_vehicle_id === b.rows[0].id), true, 'every read is this vehicle');
  const panel = b.panel();
  assert.equal(panel.querySelector('.vso-edit'), null, 'editor closes after a good save');
  assert.match(panel.querySelector('.vso-edit-msg').textContent, /^Saved\./);
  assert.equal(panel.querySelector('.vso-edit-msg').textContent, 'Saved. 1 hour change. 1 line moved.');
  // The read-only list now shows the saved values (from the reloaded detail).
  const text = panel.querySelector('.authenticated-operation-station-grid').textContent;
  assert.match(text, /4\.50 h/);
  assert.equal(b.server.details.get(b.rows[0].id).job_card_lines[0].work_category, 'BUS_ACCESSORIES');
  assert.deepEqual(b.spies.notices, []);
});

test('3b. Cancel drops the drafts and sends nothing; a failed move keeps the editor open with the change', async () => {
  const b = board();
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-edit-toggle]'));
  await b.settle();
  let page = b.panel().querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  type(page.querySelectorAll('[data-vehicle-workshop-hours-batch-input]')[0], '9');
  click(b.panel().querySelector('[data-vso-edit-act="cancel"]'));
  assert.equal(b.panel().querySelector('.vso-edit'), null);
  assert.equal(b.writes().length, 0);
  assert.equal(b.c.app.vehicleWorkshopHoursBatchDrafts.has(b.rows[0].id), false, 'draft dropped');
  // Someone else moves line 3 in the meantime: the move is refused by the (synthetic) server and nothing else changes.
  click(b.panel().querySelector('[data-vso-edit-toggle]'));
  await b.settle();
  page = b.panel().querySelector('.vso-edit [data-vehicle-workshop-hours-batch-page]');
  choose(page.querySelectorAll('[data-vehicle-workshop-line-category]')[2], 'BUS_ELECTRICAL');
  b.server.details.get(b.rows[0].id).job_card_lines[2].category_version = 5; // the selector still carries 0
  await click(b.panel().querySelector('[data-vso-edit-act="save"]'))[0];
  await b.settle();
  assert.deepEqual(b.writes().map(w => w.name), ['set_vehicle_work_category']);
  assert.ok(b.panel().querySelector('.vso-edit'), 'editor stays open');
  assert.equal(b.panel().querySelector('[data-vehicle-workshop-line-category].vso-changed')?.value, 'BUS_ELECTRICAL', 'the staged move is kept for another try');
  assert.equal(b.spies.notices.length, 1, 'app.js\'s own error message');
});

test('3c. closing the panel or opening another vehicle with unsaved changes asks first', async () => {
  const b = board();
  b.openPanel(b.rows[0]);
  click(b.panel().querySelector('[data-vso-edit-toggle]'));
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

test('4. speed guard: no per-vehicle read while drawing the board or opening panels; one read per Edit; panel-only redraws', async () => {
  const b = board({ vehicles: 40 });
  // Draw the real board HTML for every vehicle, then open the panel for each one: nothing is read.
  b.c.app.data = b.rows;
  for (const vehicle of b.rows) b.c.incomingVehicleDetailRow(vehicle);
  for (const vehicle of b.rows) b.openPanel(vehicle);
  await b.settle();
  assert.equal(b.server.calls.length, 0, 'no request at all for 40 cards and 40 panel opens');
  assert.equal(b.c.PDC_VEHICLE_SLIDEOUT.edit.loads, 0);
  b.openPanel(b.rows[7]);
  click(b.panel().querySelector('[data-vso-edit-toggle]'));
  await b.settle();
  assert.equal(b.reads().length, 1);
  assert.equal(b.reads()[0].body.p_vehicle_id, b.rows[7].id);
  assert.equal(b.spies.tableRenders + b.spies.boardRenders, 0, 'Edit draws the panel only');
  // Static: the only read call in the panel sits in startEdit; no board / table redraw anywhere in the r496 code.
  assert.equal((CODE.match(/loadVehicleWorkshopDetail\(/g) || []).length, 1);
  assert.match(/function startEdit\(key\) \{[\s\S]*?\n {2}\}/.exec(CODE)[0], /root\.loadVehicleWorkshopDetail\(vehicle, \{ force: true \}\)/);
  const r496 = CODE.slice(CODE.indexOf('const EDIT_NEEDS'), CODE.indexOf('function loadStyles'));
  assert.doesNotMatch(r496, /VLT\.render|renderAll|renderIncomingDashboardBoard|refreshEmailVehicleLocations|renderDetail\(|workshopLoadPlans/);
  assert.match(r496, /const redraw = key => \{ if \(state\.key === key\) render\(key, state\.bucket, \{ keepScroll: true \}\); \};/);
  assert.match(/function decorateOperations\([\s\S]*?\n {2}\}/.exec(CODE)[0], /startEdit\(key\)/);
  assert.doesNotMatch(/function render\(key, bucket[\s\S]*?\n {2}\}/.exec(CODE)[0], /loadVehicleWorkshopDetail|startEdit/);
  // The panel still never calls an RPC or fetch itself.
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

test('6. loader, styles and docs: r496 cache-bust tags, FAULT_LOG F109, panel doc; no real stock numbers here', () => {
  assert.equal(slideout.VERSION, '2026.10.22.r496');
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.22\.r496'/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*&amp;r496=2026\.10\.22\.r496&amp;/);
  assert.match(CSS, /#vso-shell \.vso-edit \.vehicle-workshop-line-booking,/);
  assert.match(CSS, /#vso-shell \.vso-edit-save \{/);
  const row = fs.readFileSync('docs/FAULT_LOG.md', 'utf8').split('\n').find(line => line.startsWith('| F109 |'));
  assert.ok(row && /Open full editor/.test(row) && /set_vehicle_work_category/.test(row));
  assert.match(fs.readFileSync('docs/vehicle-slideout-panel.md', 'utf8'), /r496 \(F109\)[\s\S]*Open full editor/);
  for (const locked of ['app.js', 'styles.css', 'pdc-vehicle-locations-table.js', 'pdc-operation-panels.js']) assert.doesNotMatch(fs.readFileSync(locked, 'utf8'), /r496|vso-edit/, `${locked} untouched`);
  assert.doesNotMatch(fs.readFileSync(__filename, 'utf8'), /\b1[23]\d{6}\b|\bJ13[89]\d{6}\b/);
});
