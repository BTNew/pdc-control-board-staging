/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r485 (F98): Vehicle Locations is Table view only (Craig, 22 Oct 2026: "remove the dropdown view and only keep the table
// view"). The "Drop-down view | Table view" switch is gone, everyone gets Table view whatever they saved, and the
// drop-down code stays in place behind one flag (DROPDOWN_VIEW_ENABLED) for an easy undo. Synthetic data only.
// On main 1343900 tests 1-6 and 8 fail (the switch is drawn, a saved or missing choice gives the Drop-down view); test 7
// (undo by flag = r481 behaviour) passes on both by design.
// Tests 9-13 (Craig's go-live condition: Clear stoppage / Return to QC in the slide-out panel) also fail on main 1343900,
// where the panel has no stoppage box.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const FILE = 'pdc-vehicle-locations-table.js';
const SOURCE = fs.readFileSync(FILE, 'utf8');
const table = require('./' + FILE);
const VIEW_KEY = 'pdc.vehicle-locations-view.v1:user-a';

// A small inert page: the search panel, the drop-down board, an old switch left from r481, and localStorage.
function page({ saved, flag } = {}) {
  const classes = () => { const set = new Set(); return { set, add: (...n) => n.forEach(x => set.add(x)), remove: (...n) => n.forEach(x => set.delete(x)), toggle: (n, on) => { if (on === undefined ? !set.has(n) : on) set.add(n); else set.delete(n); return set.has(n); }, contains: n => set.has(n) }; };
  const el = id => ({ id, innerHTML: '', hidden: false, dataset: {}, classList: classes(), attrs: {}, removed: false, children: [],
    setAttribute(k, v) { this.attrs[k] = v; }, addEventListener() {}, remove() { this.removed = true; ids.delete(this.id); },
    after(node) { if (node.id) ids.set(node.id, node); }, appendChild(node) { if (node.id) ids.set(node.id, node); this.children.push(node); }, querySelector: () => null });
  const ids = new Map();
  const board = el('incoming-main-board'); board.innerHTML = '<details class="incoming-bucket"></details>';
  const oldSwitch = el('vlt-view-switch'); oldSwitch.innerHTML = '<button data-vlt-view="dropdown">Drop-down view</button>';
  ids.set(board.id, board); ids.set(oldSwitch.id, oldSwitch);
  const panel = el(''); panel.querySelector = () => null;
  const body = el('');
  const store = new Map(saved ? [[VIEW_KEY, saved]] : []);
  const writes = [];
  const listeners = {};
  const doc = { body, head: el(''), getElementById: id => ids.get(id) || null, createElement: () => el(''),
    querySelector: sel => (sel === '#dashboard .incoming-search-panel' ? panel : null), querySelectorAll: () => [], addEventListener() {} };
  const renders = [];
  const context = { console, document: doc, app: { currentView: 'workshop' }, PDC_AUTH_CONTEXT: { userId: 'user-a' },
    localStorage: { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => { writes.push([k, v]); store.set(k, String(v)); }, removeItem: k => store.delete(k) },
    addEventListener: (type, fn) => { listeners[type] = fn; }, renderIncomingDashboardBoard() { renders.push('app.js drop-down render'); } };
  context.window = context; context.globalThis = context;
  vm.createContext(context);
  const code = flag === undefined ? SOURCE : SOURCE.replace('const DROPDOWN_VIEW_ENABLED = false;', `const DROPDOWN_VIEW_ENABLED = ${flag};`);
  vm.runInContext(code, context, { filename: FILE });
  const api = context.PDC_VEHICLE_LOCATIONS_TABLE;
  // Later board renders (setView, refreshes) go to a spy, so this inert page never has to draw the table itself.
  context.renderIncomingDashboardBoard = () => { renders.push('render'); };
  return { api, context, ids, board, oldSwitch, body, panel, store, writes, listeners, renders };
}

test('one flag, off: the Drop-down view is hidden (DROPDOWN_VIEW_ENABLED = false, declared once)', () => {
  assert.equal(table.DROPDOWN_VIEW_ENABLED, false, 'main has no such flag');
  assert.equal((SOURCE.match(/const DROPDOWN_VIEW_ENABLED = /g) || []).length, 1, 'a single flag');
  assert.match(table.VERSION, /^2026\.10\.27\.r566$/); // r566 planner search bumps this module; r567 stays on the loader
});

test('everyone reads Table view: nothing saved, a saved "dropdown", blocked storage or no storage', () => {
  const store = new Map();
  const storage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
  assert.equal(table.readView(storage, 'user-a'), 'table', 'nothing saved: Table view (main: Drop-down view)');
  store.set(VIEW_KEY, 'dropdown');
  assert.equal(table.readView(storage, 'user-a'), 'table', 'a saved Drop-down choice is ignored, so nobody is stuck in it');
  assert.equal(table.readView({ getItem() { throw new Error('blocked'); } }, 'user-a'), 'table');
  assert.equal(table.readView(null, ''), 'table');
});

test('a saved "dropdown" is ignored, never rewritten: the value stays on the device for an undo', () => {
  const store = new Map([[VIEW_KEY, 'dropdown']]);
  const storage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
  assert.equal(table.writeView(storage, 'user-a', 'dropdown'), false, 'nothing is saved while the flag is off');
  assert.equal(table.writeView(storage, 'user-a', 'table'), false);
  assert.equal(store.get(VIEW_KEY), 'dropdown');
});

test('on the page: Table view on load, no View switch (the old one is removed), board hidden, nothing written', () => {
  const p = page({ saved: 'dropdown' });
  assert.equal(p.api.state.view, 'table', 'a person who had picked Drop-down view gets Table view');
  assert.equal(p.ids.has('vlt-view-switch'), false, 'no "Drop-down view | Table view" switch');
  assert.equal(p.oldSwitch.removed, true);
  assert.equal(p.body.classList.contains('vlt-table-on'), true);
  assert.equal(p.board.hidden, true);
  assert.equal(p.board.innerHTML, '', 'the drop-down board is not drawn');
  assert.ok(p.panel.classList.contains('vlt-slim-bar'));
  assert.deepEqual(p.writes, [], 'nothing written to localStorage');
  assert.equal(p.store.get(VIEW_KEY), 'dropdown', 'saved value left as it was');
});

test('nothing reaches the Drop-down view: setView("dropdown"), sign-in (pdc-auth-ready) and a storage event keep Table view', () => {
  const p = page({});
  p.api.setView('dropdown');
  assert.equal(p.api.state.view, 'table');
  p.store.set(VIEW_KEY, 'dropdown');
  p.listeners['pdc-auth-ready']?.();
  assert.equal(p.api.state.view, 'table');
  p.listeners.storage?.({ key: VIEW_KEY });
  assert.equal(p.api.state.view, 'table');
  assert.equal(p.ids.has('vlt-view-switch'), false);
  assert.deepEqual(p.writes, []);
});

test('hidden, not deleted: the drop-down paths are still in the module, and only parity() may draw it (internal, unsaved)', () => {
  for (const kept of ["button(VIEWS.dropdown, 'Drop-down view')", 'function dropdownSearchElsewhere()', 'const result = originalRender.apply(this, args);']) {
    assert.ok(SOURCE.includes(kept), `${kept} kept`);
  }
  assert.match(SOURCE, /setView\(VIEWS\.dropdown, \{ save: false, internal: true \}\)/, 'parity() still compares against the drop-down board');
  assert.match(SOURCE, /setView\(before\.view, \{ save: false, internal: true \}\)/, 'and puts Table view back');
  assert.equal((SOURCE.match(/\{ save: false, internal: true \}/g) || []).length, 3, 'parity() is the only internal caller');
});

test('undo by flag: DROPDOWN_VIEW_ENABLED = true brings back r481 exactly (switch drawn, drop-down default, saved choice)', () => {
  const p = page({ flag: true });
  assert.equal(p.api.state.view, 'dropdown');
  assert.match(p.ids.get('vlt-view-switch').innerHTML, /Drop-down view[\s\S]*Table view/);
  p.api.setView('table');
  assert.equal(p.api.state.view, 'table');
  assert.deepEqual(p.writes, [[VIEW_KEY, 'table']]);
});

test('loader: r485 cache-bust on the table module and on canonical-entry.js; FAULT_LOG F98', () => {
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-locations-table\.js\?[^']*&r485=2026\.10\.22\.r485(?:&[^']*)?'/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r485=2026\.10\.22\.r485/);
  const row = fs.readFileSync('docs/FAULT_LOG.md', 'utf8').split('\n').find(line => line.startsWith('| F98 |'));
  assert.ok(row, 'F98 row');
  assert.match(row, /r485/);
  assert.doesNotMatch(fs.readFileSync(__filename, 'utf8'), /\b1[23]\d{6}\b|\bJ13[89]\d{6}\b/, 'no real stock or job numbers');
});

// ---------------------------------------------------------------------------------------------------------------------
// r485 condition (Craig, 22 Oct 2026: "first add Clear stoppage to the Table view so nothing is lost when the drop-down
// is hidden"). The slide-out panel shows the vehicle's STOPPAGES rows with the drop-down list's own action buttons,
// bound through app.js bindFixFirstRows() -> clearPriorityStoppage() -> service.clearVehicleStoppage() ->
// clear_vehicle_stoppage_422. Real app.js, real pdc-qc-rework.js, real service with a stubbed fetch: no network, no
// writes. Synthetic vehicles only (SYN-00xx).
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { syntheticVehicles } = require('./qa/vehicle-locations-table-461-fixture.cjs');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service.js');
const APP = fs.readFileSync('app.js', 'utf8');
const SLIDEOUT = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');

// A tiny DOM, just enough for the panel: innerHTML is kept as text; the panel's buttons are read back from it.
function fakeDom() {
  const ids = new Map();
  const docListeners = {};
  const classList = () => { const set = new Set(); return { add: (...n) => n.forEach(x => set.add(x)), remove: (...n) => n.forEach(x => set.delete(x)), contains: n => set.has(n), toggle() {} }; };
  const camel = name => name.replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
  const unescape = text => text.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  function buttonsIn(html, attr) {
    return [...html.matchAll(/<button\b([^>]*)>([^<]*)<\/button>/g)].filter(m => m[1].includes(attr)).map(m => {
      const b = el('button');
      for (const [, name, value] of m[1].matchAll(/\sdata-([\w-]+)="([^"]*)"/g)) b.dataset[camel(name)] = unescape(value);
      b.outerHTML = m[0]; b.textContent = m[2];
      b.closest = sel => (sel === '[data-qc-rework-return]' && 'qcReworkReturn' in b.dataset ? b : null);
      return b;
    });
  }
  function el(tag) {
    const node = { tagName: tag, id: '', dataset: {}, style: {}, hidden: false, listeners: {}, kids: {}, _html: '', classList: classList(),
      get innerHTML() { return this._html; }, set innerHTML(html) { this._html = String(html); this.kids = {}; },
      addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }, appendChild(child) { if (child.id) ids.set(child.id, child); return child; },
      focus() {}, replaceWith() {}, replaceChildren() {}, closest: () => null,
      querySelector(sel) {
        if (sel in this.kids) return this.kids[sel];
        const has = text => this._html.includes(text);
        let found = null;
        if (sel === '.vso-panel' && has('class="vso-panel"')) found = el('aside');
        else if (sel === '.vso-parity' && has('class="vso-parity"')) found = el('div');
        else if (sel === 'details.vso-card' && has('vso-card')) found = el('details');
        else if ((sel === '.vso-open-row' || sel === '.vso-body') && has(sel.slice(1))) found = el('div');
        else if (sel === '.vso-stoppages' && has('<section class="vso-stoppages"')) {
          found = el('section');
          found._html = this._html.slice(this._html.indexOf('<section class="vso-stoppages"'), this._html.indexOf('</section>') + 10);
        }
        this.kids[sel] = found;
        return found;
      },
      querySelectorAll(sel) {
        if (sel === '[data-clear-priority-stoppage]') return (this.kids[sel] ||= buttonsIn(this._html, 'data-clear-priority-stoppage='));
        if (sel === '[data-qc-rework-return]') return (this.kids[sel] ||= buttonsIn(this._html, 'data-qc-rework-return='));
        return [];
      } };
    return node;
  }
  const body = el('body');
  const doc = { body, head: el('head'), documentElement: el('html'), readyState: 'complete', getElementById: id => ids.get(id) || null,
    createElement: tag => el(tag), querySelector: () => null, querySelectorAll: () => [],
    addEventListener: (type, fn) => { (docListeners[type] ||= []).push(fn); } };
  return { doc, el, docListeners };
}

const STAGING_URL = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
function stoppageBoard({ role = 'administrator', qcRework = false } = {}) {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  const c = fixture.context;
  const dom = fakeDom();
  c.document = dom.doc;
  c.CSS = { escape: value => String(value) };
  c.app.data = syntheticVehicles();
  const byKey = key => c.app.data.find(v => c.vehicleKey(v) === key);
  // Synthetic stopped PMB vehicle, bound to (fake) server authority like a live vehicle.
  const stopped = byKey('SYN-0025');
  Object.assign(stopped, { pdcBlocked: true, pdcBlockReason: 'Synthetic PMB hold', __emailVehicleServerAuthoritative: true, __emailVehicleId: 'syn-vehicle-25', __emailVehicleVersion: 4 });
  const qc = byKey('SYN-0026');
  if (qcRework) {
    Object.assign(qc, { pdcBlocked: true, pdcBlockReason: 'Synthetic QC fix hold', __emailVehicleServerAuthoritative: true, __emailVehicleId: 'syn-vehicle-26', __emailVehicleVersion: 2,
      pdcQcRework: { active: true, contract: 'pdc-qc-rework-v1', vehicle_id: 'syn-vehicle-26', vehicle_version: 2, lines: [], stages: [], ready_for_qc: true, repairs_complete: true, issues: [] } });
  }
  // The real service, with fetch stubbed: every request is recorded and answered "ok"; nothing leaves the process.
  const calls = [];
  const fetchImpl = async (url, init) => { const payload = JSON.parse(init.body); calls.push({ url, payload }); return { ok: true, json: async () => ({ ok: true, data: { receipt_id: 'syn-receipt', vehicle_id: payload.p_vehicle_id } }) }; };
  c.app.emailVehicleLocationService = createPdcEmailVehicleLocationService({ config: { url: STAGING_URL, publishableKey: 'test-only-not-a-key' }, getAccessToken: () => 'test-only-token', fetchImpl });
  const spies = { prompts: [], notices: [], renders: 0, refreshes: 0, qc: [] };
  c.prompt = (message, value) => { spies.prompts.push([message, value]); return 'Synthetic note'; };
  c.pdcNotify = message => spies.notices.push(message);
  c.renderAll = () => { spies.renders += 1; };
  c.refreshEmailVehicleLocations = async () => { spies.refreshes += 1; };
  c.salespersonAssignmentIdempotencyKey = () => 'syn-idempotency-key';
  c.PDC_AUTH_CONTEXT = role ? { userId: 'user-a', role } : { userId: 'user-a' };
  // The fixture stubs bindFixFirstRows(); put app.js's own one back.
  const bind = /\nfunction bindFixFirstRows\(root = document\) \{[\s\S]*?\n\}\n/.exec(APP)[0];
  fixture.evaluate(`bindFixFirstRows = ${bind.trim().replace(/^function bindFixFirstRows/, 'function')};`);
  if (qcRework) {
    c.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd' };
    c.mapServerVehicle = raw => ({ ...raw });
    fixture.loadHelper('pdc-qc-rework.js');
    c.markVehicleReadyForQualityControl = async key => { spies.qc.push(key); return true; };
  }
  // A stand-in for the r461 table module: the panel only needs these hooks from it.
  const vlt = { TILE: {}, state: { view: 'table' }, splitCard: () => ({ key: null }), bindBoardHandlers() {}, drawerClosed() {}, setDrawerOpener(o) { this.opener = o; } };
  c.PDC_VEHICLE_LOCATIONS_TABLE = vlt;
  fixture.loadHelper('pdc-vehicle-slideout.js');
  const openPanel = key => {
    vlt.opener.open(key, c.incomingBucketForVehicle(byKey(key)));
    return dom.doc.getElementById('vso-shell').querySelector('.vso-panel');
  };
  return { c, dom, vlt, byKey, calls, spies, openPanel };
}
const click = async button => { for (const fn of button.listeners.click || []) await fn({ stopPropagation() {}, preventDefault() {} }); await new Promise(r => setImmediate(r)); };

test('r485 panel: a stopped vehicle shows its stoppage reason and the drop-down list\'s own Clear stoppage button', () => {
  const { c, openPanel } = stoppageBoard();
  const panel = openPanel('SYN-0025');
  assert.match(panel.innerHTML, /<section class="vso-stoppages" aria-label="Stoppage"><h4>STOPPAGE<\/h4>/);
  assert.match(panel.innerHTML, /<strong>PMB STOPPAGE<\/strong><span>Synthetic PMB hold<\/span>/, 'the reason, as the STOPPAGES list shows it');
  const own = /<button\b[^>]*data-clear-priority-stoppage="SYN-0025"[^>]*>Clear stoppage<\/button>/.exec(c.fixFirstRowsHtml(c.workflowPriorityRows().filter(r => c.vehicleKey(r.vehicle) === 'SYN-0025')))[0];
  assert.ok(panel.innerHTML.includes(own), 'the very same button markup as the drop-down list');
  assert.ok(panel.innerHTML.indexOf('vso-stoppages') < panel.innerHTML.indexOf('<div class="vso-body">'), 'above the card, outside .vso-body');
  const parts = openPanel('SYN-0003');
  assert.match(parts.innerHTML, /<strong>Parts STOPPAGE<\/strong>[\s\S]*data-stoppage-kind="parts"[^>]*>Clear stoppage</, 'Parts stoppages too');
});

test('r485 panel: Clear stoppage calls clearPriorityStoppage -> clear_vehicle_stoppage_422 with the same args as the drop-down (stubbed fetch)', async () => {
  // Drop-down path: the STOPPAGES list host as renderFixFirstGrid() fills it.
  const a = stoppageBoard();
  const host = a.dom.el('div');
  host.innerHTML = a.c.fixFirstRowsHtml(a.c.workflowPriorityRows());
  a.c.bindFixFirstRows(host);
  await click(host.querySelectorAll('[data-clear-priority-stoppage]').find(b => b.dataset.clearPriorityStoppage === 'SYN-0025'));
  // Panel path.
  const b = stoppageBoard();
  const section = b.openPanel('SYN-0025').querySelector('.vso-stoppages');
  const buttons = section.querySelectorAll('[data-clear-priority-stoppage]');
  assert.equal(buttons.length, 1);
  assert.equal(buttons[0].dataset.clearStoppageBound, 'true', 'bound by app.js bindFixFirstRows()');
  await click(buttons[0]);
  assert.equal(b.calls.length, 1, 'one request');
  assert.equal(b.calls[0].url, `${STAGING_URL}/rest/v1/rpc/clear_vehicle_stoppage_422`);
  assert.deepEqual(b.calls[0].payload, { p_vehicle_id: 'syn-vehicle-25', p_expected_vehicle_version: 4, p_stoppage_kind: 'pmb', p_booking_id: null, p_expected_booking_version: 0, p_resolution_note: 'Synthetic note', p_idempotency_key: 'syn-idempotency-key' });
  assert.deepEqual(b.calls, a.calls, 'identical to the drop-down list');
  assert.deepEqual(b.spies.prompts, a.spies.prompts, 'same note prompt');
  assert.equal(b.spies.prompts[0][0], 'Why is this stoppage being cleared? This note is kept in the vehicle history.');
  assert.deepEqual([b.spies.renders, b.spies.refreshes], [1, 1], 'same refresh + renderAll afterwards');
  // A cancelled prompt sends nothing; a refused clear shows the same message as the drop-down.
  const cancel = stoppageBoard();
  cancel.c.prompt = () => null;
  await click(cancel.openPanel('SYN-0025').querySelector('.vso-stoppages').querySelectorAll('[data-clear-priority-stoppage]')[0]);
  assert.deepEqual(cancel.calls, []);
  const refused = stoppageBoard();
  refused.c.app.emailVehicleLocationService = createPdcEmailVehicleLocationService({ config: { url: STAGING_URL, publishableKey: 'test-only-not-a-key' }, getAccessToken: () => 'test-only-token',
    fetchImpl: async () => ({ ok: false, json: async () => ({ ok: false, code: 'no_active_pmb_stoppage' }) }) });
  await click(refused.openPanel('SYN-0025').querySelector('.vso-stoppages').querySelectorAll('[data-clear-priority-stoppage]')[0]);
  assert.deepEqual(refused.spies.notices, ['This PMB stoppage is no longer active.']);
  // A vehicle not bound to server authority is refused by clearPriorityStoppage() itself, exactly as on the list.
  const unbound = stoppageBoard();
  delete unbound.byKey('SYN-0003').__emailVehicleServerAuthoritative;
  await click(unbound.openPanel('SYN-0003').querySelector('.vso-stoppages').querySelectorAll('[data-clear-priority-stoppage]')[0]);
  assert.deepEqual(unbound.calls, []);
  assert.deepEqual(unbound.spies.notices, ['This stoppage is not bound to current server authority. Nothing was changed.']);
});

test('r485 panel: hidden for a vehicle with no stoppage, and the button is hidden for roles the server refuses', () => {
  const plain = stoppageBoard().openPanel('SYN-0001');
  assert.doesNotMatch(plain.innerHTML, /vso-stoppages|data-clear-priority-stoppage|Clear stoppage/);
  assert.match(plain.innerHTML, /<div class="vso-body">/, 'the panel itself is unchanged');
  for (const role of ['operator', 'administrator', 'Administrator ']) {
    assert.match(stoppageBoard({ role }).openPanel('SYN-0025').innerHTML, /data-clear-priority-stoppage="SYN-0025"/, `${role} can clear`);
  }
  for (const role of ['workshop', 'sales', 'parts', 'viewer', '']) {
    const board = stoppageBoard({ role });
    const panel = board.openPanel('SYN-0025');
    assert.match(panel.innerHTML, /PMB STOPPAGE[\s\S]*Synthetic PMB hold/, `${role || 'no role'}: the reason is still shown`);
    assert.doesNotMatch(panel.innerHTML, /data-clear-priority-stoppage|data-qc-rework-return|Clear stoppage|Return to QC/, `${role || 'no role'}: no action button`);
    assert.match(panel.innerHTML, /Only an operator or administrator can clear a stoppage\./);
  }
  assert.match(SLIDEOUT, /const STOPPAGE_ACTION_ROLES = Object\.freeze\(\['operator', 'administrator'\]\);/);
  const sql = fs.readFileSync('supabase/staging_only/20260826193000_422_targeted_stoppage_paths.sql', 'utf8');
  assert.match(sql, /r\.role IN\('operator','administrator'\)/, 'the same roles the server lets clear');
});

test('r485 panel: Return to QC (pdc-qc-rework) shows instead of Clear stoppage and runs markVehicleReadyForQualityControl', async () => {
  const board = stoppageBoard({ qcRework: true });
  const listHtml = board.c.fixFirstRowsHtml(board.c.workflowPriorityRows());
  const own = /<button class="primary fix-first-clear" type="button" data-qc-rework-return="SYN-0026">Return to QC<\/button>/.exec(listHtml)?.[0];
  assert.ok(own, 'the drop-down list shows Return to QC for this vehicle');
  const panel = board.openPanel('SYN-0026');
  assert.ok(panel.innerHTML.includes(own), 'the panel shows the same button');
  assert.doesNotMatch(panel.innerHTML, /data-clear-priority-stoppage="SYN-0026"/);
  const button = panel.querySelector('.vso-stoppages').querySelectorAll('[data-qc-rework-return]')[0];
  for (const fn of board.dom.docListeners.click || []) fn({ target: button, preventDefault() {}, stopPropagation() {} });
  await new Promise(r => setImmediate(r));
  assert.deepEqual(board.spies.qc, ['SYN-0026'], 'pdc-qc-rework.js\'s own document listener handles it');
  assert.deepEqual(board.calls, [], 'Return to QC sends no stoppage clear');
  assert.match(board.openPanel('SYN-0025').innerHTML, /data-clear-priority-stoppage="SYN-0025"[^>]*>Clear stoppage/, 'other stoppages keep Clear stoppage');
  assert.doesNotMatch(stoppageBoard({ qcRework: true, role: 'workshop' }).openPanel('SYN-0026').innerHTML, /Return to QC/, 'same role gate');
});

test('r485 panel: parity() is unaffected (the parity strip draws only the card) and the panel itself calls no RPC', () => {
  const board = stoppageBoard();
  board.openPanel('SYN-0025');
  board.vlt.opener.parityStrip('SYN-0025', board.c.incomingBucketForVehicle(board.byKey('SYN-0025')));
  const parityHost = board.dom.doc.getElementById('vso-shell').querySelector('.vso-parity');
  assert.match(parityHost.innerHTML, /^<div class="vso-panel-like"><div class="vso-body">/);
  assert.doesNotMatch(parityHost.innerHTML, /vso-stoppages/);
  assert.doesNotMatch(/function parityStrip\([\s\S]*?\n {2}\}/.exec(SLIDEOUT)[0], /stoppage/i);
  assert.doesNotMatch(SLIDEOUT, /\bfetch\s*\(|\.rpc\s*\(|clearVehicleStoppage|clear_vehicle_stoppage_422'/, 'the panel reuses app.js; it has no write path of its own');
  assert.match(SLIDEOUT, /root\.bindFixFirstRows\(stoppages\)/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.28\.r588'/); // r588 (F202); r565 chip layout stays
  assert.match(fs.readFileSync('pdc-vehicle-slideout.css', 'utf8'), /#vso-shell \.vso-stoppages \{/);
});
