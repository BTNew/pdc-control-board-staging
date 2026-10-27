/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r483 (F96): Department 139 (PMB) bays carry Craig's names and numbers (22 Oct 2026):
// Hoist 01-03 = Express / Pits Hoist, Express, Hoist (Bays 01-03); Fitting 01-05 = Bays 06-10; Fab 01 / 02 = Internal /
// External Fabrication (Bays 11 / 12); Elec 01-10 = Bays 13-22. r509: the Fab planner shows 14 bays (03-14 use Bay NN).
// Dept 138 Bus 4x4 and the shared Tint / Tyre bays keep their labels. Bookings keep bay_id / bay_number (labels only).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const layout = require('./pdc-workshop-departments.js');
const overview = require('./control-board-overview.js');
const fixture = require('./qa/control-board-fixtures.js');
const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');

const CRAIG = [
  ['HOIST', 1, 'Express / Pits Hoist · Bay 01'], ['HOIST', 2, 'Express · Bay 02'], ['HOIST', 3, 'Hoist · Bay 03'],
  ['FITTING', 1, 'Fitting · Bay 06'], ['FITTING', 2, 'Fitting · Bay 07'], ['FITTING', 3, 'Fitting · Bay 08'], ['FITTING', 4, 'Fitting · Bay 09'], ['FITTING', 5, 'Fitting · Bay 10'],
  ['FABRICATION', 1, 'Internal Fabrication · Bay 11'], ['FABRICATION', 2, 'External Fabrication · Bay 12'],
  ...Array.from({ length: 10 }, (_, i) => ['ELECTRICAL', i + 1, `Electrical · Bay ${13 + i}`]),
];

test('r483: every Dept 139 bay label carries Craig\'s name and number', () => {
  assert.equal(layout.PMB_BAYS_VERSION, 'r566');
  assert.equal(CRAIG.length, 20);
  for (const [stage, bay, label] of CRAIG) {
    assert.equal(layout.pmbBayLabel(stage, bay), label, `${stage} ${bay}`);
    assert.equal(layout.bayLabel(stage, bay), label, `${stage} ${bay}`);
  }
  assert.deepEqual({ ...layout.PMB_BAY_COUNTS }, { HOIST: 3, FITTING: 5, FABRICATION: 14, ELECTRICAL: 7 });
  const numbers = CRAIG.map(([stage, bay]) => layout.pmbBay(stage, bay).number);
  assert.deepEqual(numbers, [1, 2, 3, ...Array.from({ length: 17 }, (_, i) => i + 6)]);
});

test('r483: Fab bays 03-14 and Dept 138 / shared bays keep their plain labels', () => {
  for (let bay = 3; bay <= 14; bay++) { assert.equal(layout.pmbBayLabel('FABRICATION', bay), ''); assert.equal(layout.bayLabel('FABRICATION', bay), `Bay ${String(bay).padStart(2, '0')}`); }
  for (const stage of ['TINT', 'TYRE']) for (const bay of [1, 2]) { assert.equal(layout.pmbBayLabel(stage, bay), ''); assert.equal(layout.bayLabel(stage, bay), `Bay 0${bay}`); }
  for (let bay = 1; bay <= 10; bay++) { assert.equal(layout.pmbBayLabel('BUS_4X4', bay), ''); assert.equal(layout.bayLabel('BUS_4X4', bay), `${layout.groupForBay(bay).label} · Bay ${String(bay).padStart(2, '0')}`); }
  assert.equal(layout.bayLabel('BUS_4X4', 3), 'Mechanical · Bay 03');
});

test('r509: the Fab planner and WIP count is 14; other station counts stay on the r483 numbers', () => {
  const app = read('app.js');
  for (const name of ['PMB_WIP_LIMITS', 'PMB_STAGE_BAY_COUNTS']) {
    const block = app.match(new RegExp(`const ${name} = \\{([\\s\\S]*?)\\n\\};`))[1];
    assert.match(block, /FABRICATION: 14,/, name);
    assert.doesNotMatch(block, /FABRICATION: 2,/, name);
    assert.match(block, /HOIST: 3,/, name);
    assert.match(block, /FITTING: 5,/, name);
    assert.match(block, /ELECTRICAL: 7,/, name);
  }
  assert.match(app, /FABRICATION: '14 bays · Internal and External Fabrication, Fab 03-14'/);
  assert.match(app, /const PMB_BAY_MAX_COUNT = 13;/);
});

test('r483: app.js and the planner turn Dept 139 bay numbers into Craig\'s names', () => {
  for (const [file, fn] of [['app.js', 'pdcBayText'], ['workshop-planner.js', 'workshopBayText']]) {
    const src = read(file);
    const body = src.match(new RegExp(`function ${fn}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`))[0];
    const ctx = { window: { PDC_WORKSHOP_DEPARTMENTS: layout }, workshopDepartmentLayout: () => layout, workshopPad: v => String(v).padStart(2, '0'),
      normalizePmbStage: v => ({ Fab: 'FABRICATION', Elec: 'ELECTRICAL' }[v] || String(v).toUpperCase()) };
    vm.runInNewContext(`${body}; this.fn = ${fn};`, ctx);
    assert.equal(ctx.fn('FITTING', 1), 'Fitting · Bay 06', file);
    assert.equal(ctx.fn('Fab', 2), 'External Fabrication · Bay 12', file);
    assert.equal(ctx.fn('BUS_4X4', 4, true), 'Bay 04', file);
    assert.equal(ctx.fn('TINT', 1), 'Bay 1', file);
  }
  const planner = read('workshop-planner.js');
  assert.match(planner, /bay: entry\.bay \? workshopBayText\(entry\.stage, entry\.bay\) : 'Bay —'/, 'booking search meta');
  assert.match(planner, /<option value="\$\{index \+ 1\}">\$\{escapeHtml\(workshopBayText\(stage, index \+ 1, true\)\)\}<\/option>/, 'admin block bay picker');
});

test('r509: control board shows Craig\'s names and draws all 14 fabrication bays', () => {
  const snapshot = fixture.emptySnapshot();
  const fab = snapshot.board.bays.filter(bay => bay.stage_code === 'FABRICATION');
  const within = fab.filter(bay => bay.bay_number >= 3);
  assert.ok(within.length >= 1, 'fixture has Fab bays above 2');
  within.forEach(bay => { bay.is_active = false; });
  const all = overview.buildModel(fixture.emptySnapshot()).totalBays;
  // Fab 03-13 are inside the 14, so an inactive empty row still stays on the board.
  const model = overview.buildModel(snapshot);
  assert.equal(model.totalBays, all);
  const html = overview.render(model);
  assert.match(html, /<strong>FABRICATION Bay 1<\/strong>/);
  const fallback = fixture.emptySnapshot();
  fallback.board.bays.forEach(bay => { bay.display_name = ''; });
  assert.match(overview.render(overview.buildModel(fallback)), /<strong>Internal Fabrication · Bay 11<\/strong>/);
  for (const bay of within) assert.match(html, new RegExp(`data-control-board-bay="${bay.bay_id}"`));
  const extra = { ...within[0], bay_id: '0000000f-0000-4000-8000-00000000000f', bay_number: 15, is_active: false, display_name: 'Fab Bay 15' };
  snapshot.board.bays.push(extra);
  const omitted = overview.buildModel(snapshot);
  assert.equal(omitted.totalBays, all);
  assert.doesNotMatch(overview.render(omitted), new RegExp(`data-control-board-bay="${extra.bay_id}"`));
  // A bay above the count that still holds a booking stays visible, as before.
  snapshot.board.bookings.push(fixture.booking(1, extra));
  const kept = overview.buildModel(snapshot);
  assert.equal(kept.totalBays, all + 1);
  assert.match(overview.render(kept), /Inactive · existing bookings only/);
  // Any other inactive empty bay within its station count still shows.
  const other = fixture.emptySnapshot();
  other.board.bays.filter(bay => (bay.stage_code === 'BUS_4X4' && bay.bay_number === 2) || (bay.stage_code === 'HOIST' && bay.bay_number === 1)).forEach(bay => { bay.is_active = false; });
  assert.equal(overview.buildModel(other).totalBays, all);
  const fit = snapshot.board.bays.find(bay => bay.stage_code === 'FITTING' && bay.bay_number === 1);
  if (fit) assert.match(html, /aria-label="Fitting FITTING Bay 1"/);
});

test('r483: Book all stations result names the Dept 139 bay', () => {
  const src = read('pdc-book-all-stations.js').replace('window.PDC_BOOK_ALL_STATIONS = Object.freeze({ eligible, actionHtml });', '$&\n  window.__summaryHtml = summaryHtml;');
  const el = () => new Proxy({ setAttribute() {}, addEventListener() {}, appendChild() {}, querySelector: () => el(), insertAdjacentHTML() {}, showModal() {}, close() {} }, { get: (t, k) => (k in t ? t[k] : ''), set: () => true });
  const window = { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' }, PDC_WORKSHOP_DEPARTMENTS: layout, addEventListener() {} };
  const ctx = { window, document: { createElement: el, body: { appendChild() {} }, addEventListener() {} }, app: {}, console };
  vm.runInNewContext(src, ctx);
  const html = window.__summaryHtml({ ok: true, bookings: [
    { stage: 'HOIST', bay: 1, start_at: '2026-10-23T00:00:00Z', end_at: '2026-10-23T01:00:00Z' },
    { stage: 'FABRICATION', bay: 2, start_at: '2026-10-23T01:00:00Z', end_at: '2026-10-23T02:00:00Z' },
    { stage: 'TINT', bay: 1, start_at: '2026-10-23T03:00:00Z', end_at: '2026-10-23T04:00:00Z' }], skipped: [] });
  assert.match(html, /<small>Express \/ Pits Hoist · Bay 01<\/small>/);
  assert.match(html, /<small>External Fabrication · Bay 12<\/small>/);
  assert.match(html, /<small>Bay 1<\/small>/);
});

test('r483: fitter page names Dept 139 bays and keeps Bus 4x4 plain', () => {
  const src = read('pdc-fitters.js');
  const helper = src.match(/const STAGE_BY_NAME = [^\n]*\n\s*const bayText = [^\n]*\n/)[0].replace('root.', 'globalThis.');
  const ctx = { PDC_WORKSHOP_DEPARTMENTS: layout };
  vm.runInNewContext(`${helper}; this.bayText = bayText; this.byName = STAGE_BY_NAME;`, ctx);
  assert.equal(ctx.bayText('ELECTRICAL', 10), 'Electrical · Bay 22');
  assert.equal(ctx.bayText(ctx.byName.Hoist, 2), 'Express · Bay 02');
  assert.equal(ctx.bayText('BUS_4X4', 2), 'Bay 2');
  assert.doesNotMatch(src, /· Bay \$\{esc\(job\.bay_number/);
});

test('r483: cache-bust tags load the new labels', () => {
  const html = read('index.html');
  for (const file of ['pdc-workshop-departments.js', 'control-board-overview.js', 'app.js', 'pdc-fitters.js', 'canonical-entry.js']) assert.match(html, new RegExp(`src="${file.replace('.', '\\.')}\\?[^"]*r483=2026\\.10\\.22\\.r483`), file);
  assert.match(read('canonical-entry.js'), /pdc-book-all-stations\.js\?[^'"`]*r483=2026\.10\.22\.r483/);
  // r527 appends a later cache bust after r483. The r483 tag must stay on both planner loads.
  assert.equal((read('app.js').match(/workshop-planner\.js\?station-scope=[^`]*&r483=2026\.10\.22\.r483(?:&[^`]*)?`/g) || []).length, 2);
});
