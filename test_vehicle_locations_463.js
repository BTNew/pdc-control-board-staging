/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r463 (F76): Vehicle Locations Table view follow-ups after the r462 live check (22 Oct 2026, synthetic data only).
//  1. Job Card column: r461/r462 never had one; the job card sat as a small sub-line under Stock.
//  2. First load after a hard reload: the table must fill in when the board data arrives after the module loaded.
//  3. DevTools "Interactive element inside of a <summary>": the table rows carry no <summary>.
//  4. Craig 09:03: the slide-out panel's "Jobs & bookings" list and drag-to-bay are withdrawn.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');
const slideout = require('./pdc-vehicle-slideout.js');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { syntheticVehicles, syntheticPlans } = require('./qa/vehicle-locations-table-461-fixture.cjs');

const memoryStorage = () => {
  const store = new Map();
  return { store, getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
};
function board() {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  const c = fixture.context;
  c.app.data = syntheticVehicles();
  const plans = syntheticPlans(c, c.app.data);
  c.workshopLoadPlans = () => plans;
  c.ensureDashboardWorkshopProjectionReady = () => true;
  return { fixture, c, plans };
}
const cellOf = (row, cls) => { const m = new RegExp(`<td class="${cls}"[^>]*>([\\s\\S]*?)</td>(?=<td|</tr>)`).exec(row); return m ? m[1] : null; };
const rowsOf = c => c.vehicleLocationsScreenRows().map(vehicle => {
  const bucket = c.incomingBucketForVehicle(vehicle);
  const card = c.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans: c.workshopLoadPlans(), workshopProjectionAvailable: true, subletNavigation: true });
  return { vehicle, bucket, card, row: table.tableRowHtml(card, bucket, { key: c.vehicleKey(vehicle) }) };
});

// ---------------- 1. Job Card column ----------------
test('bug 1 reproduced and fixed: every row has its own Job Card cell; Stock shows only the stock number', () => {
  const { c } = board();
  let withJob = 0;
  for (const { card, row, vehicle } of rowsOf(c)) {
    const jc = /<span class="vehicle-identity-cell identity-jc[\s\S]*?<\/span><\/span>/.exec(card.slice(0, card.indexOf('</summary>')))?.[0];
    const job = cellOf(row, 'c-job');
    assert.notEqual(job, null, `${c.vehicleKey(vehicle)}: Job Card cell exists (r462 had none)`);
    assert.doesNotMatch(cellOf(row, 'c-stock'), /identity-jc|vlt-subtle"/, 'the job card is no longer a sub-line under Stock');
    if (jc) { assert.ok(job.includes(jc), 'the card\'s own job-card markup moves verbatim'); withJob += 1; }
    else assert.match(job, /vlt-subtle-dash/, 'no job card: a grey dash');
    // order: select, key, stock, job, customer, vehicle, parts loc, stations
    assert.deepEqual([...row.matchAll(/<td class="(c-[a-z]+)/g)].map(m => m[1]).slice(0, 9), ['c-sel', 'c-key', 'c-stock', 'c-job', 'c-cust', 'c-unit', 'c-ploc', 'c-eta', 'c-work']); // r475 adds Parts ETA
  }
  assert.ok(withJob >= 20, `fixture has job cards (${withJob})`);
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /<col class="c-stock"><col class="c-job"><col class="c-cust">/);
  assert.match(source, /<th class="c-job">\$\{heading\('Job Card', 'jobcard'\)\}\$\{grip\('job'\)\}<\/th>/, 'header uses the board\'s own job-card sort');
  assert.match(source, /colspan="12" class="vlt-empty"/); // r475: + Parts ETA
  assert.equal(table.COLUMNS.job.label, 'Job Card');
  assert.deepEqual(Object.keys(table.COLUMNS), ['key', 'stock', 'job', 'cust', 'unit', 'ploc', 'eta', 'work', 'age', 'status', 'action']); // r475 adds eta
});

test('Job Card shows for people who already saved r461 / r462 settings (view, widths) and can never be 0 wide or hidden', () => {
  const storage = memoryStorage();
  table.writeView(storage, 'user-a', 'table'); // r461 view switch key
  storage.setItem('pdc.vehicle-locations-columns.v2:user-a', JSON.stringify({ key: 50, stock: 120, cust: 150, ploc: 70 })); // saved widths with no "job" (r476: v2 key)
  assert.equal(table.readView(storage, 'user-a'), 'table');
  const widths = table.readWidths(storage, 'user-a');
  assert.equal(widths.job, undefined, 'no saved width: the default applies');
  const css = table.widthStyle(widths);
  assert.doesNotMatch(css, /--vlt-w-job/);
  const C = table.COLUMNS; // r476 (F89): new defaults, no select column when no row has a checkbox; r475 adds Parts ETA
  assert.match(css, new RegExp(`--vlt-table-min:${50 + 120 + C.job.width + 150 + C.unit.width + 70 + C.eta.width + C.work.width + C.age.width + C.status.width + C.action.width}px`), 'table minimum includes the Job Card default width');
  assert.deepEqual(table.sanitizeWidths({ job: 0 }), {}, 'a 0 width is ignored');
  assert.deepEqual(table.sanitizeWidths({ job: 5 }), { job: 64 }, 'below the minimum: the minimum');
  const sheet = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  assert.match(sheet, new RegExp(`col\\.c-job \\{ width: var\\(--vlt-w-job, ${C.job.width}px\\); \\}`));
  const rules = [...sheet.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => [m[1].trim(), m[2]]);
  for (const [selector, body] of rules.filter(([selector]) => /\.c-job(\s*[,{]|$)|col\.c-job|th\.c-job|td\.c-job$/.test(selector))) {
    assert.doesNotMatch(body, /display:\s*none|(^|;|\s)width:\s*0|visibility:\s*hidden/, `${selector}: no rule (any screen width) hides the Job Card column`);
  }
  assert.match(sheet, /td\.c-stock \.vehicle-identity-value \{ font-size: 13px !important; font-weight: 700 !important; \}/, 'stock number is larger');
});

// ---------------- 2. Hard reload: data arriving after the module loaded ----------------
test('bug 2 check: the table reads the vehicles fresh on every board render, so data arriving after a hard reload fills it in', () => {
  // app.js calls renderIncomingDashboardBoard() whenever board data arrives; the table replaces that function and never
  // keeps a copy of the vehicles from load time. (Browser check: release_log/r463/probe_zero.js, slow auth / data / failed first call.)
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /root\.renderIncomingDashboardBoard = function renderIncomingDashboardBoardWithViewSwitch/);
  // r481 (F94): the drop-down branch still draws with app.js's own render first, then adds the other-department search note.
  assert.match(source, /if \(!tableOn\(\)\) \{\s*const result = originalRender\.apply\(this, args\);[\s\S]{0,300}return result;\s*\}\s*return renderWithCache\(\);/);
  assert.match(source, /function renderTable\(\) \{[\s\S]{0,400}const rows = root\.vehicleLocationsScreenRows\(\);/);
  const { c } = board();
  const data = c.app.data;
  c.app.data = [];
  assert.equal(c.vehicleLocationsScreenRows().length, 0, 'first paint: no vehicles yet');
  c.app.data = data;
  assert.ok(c.vehicleLocationsScreenRows().length > 0, 'next render sees them');
});

// ---------------- 3. <summary> warnings ----------------
test('table rows carry no <summary> (DevTools "interactive element inside <summary>" is the drop-down board in app.js)', () => {
  const { c } = board();
  let buttons = 0;
  for (const { row } of rowsOf(c)) {
    assert.doesNotMatch(row, /<summary|<details/, 'no summary / details in a table row');
    buttons += (row.match(/<button/g) || []).length;
  }
  assert.ok(buttons > 0, 'the rows do carry buttons, outside any summary');
  c.renderIncomingDashboardBoard();
});

// ---------------- 4. Panel: drag-to-bay withdrawn (Craig 09:03) ----------------
test('panel has no Jobs & bookings list, no drag handles, no bay targets and never calls the planner', () => {
  assert.deepEqual(Object.keys(slideout), ['VERSION'], 'no drag / drop / bookings helpers are exported any more');
  const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  for (const gone of [/data-vso-drag/, /data-vso-drop-bay/, /vso-jobs/, /vso-bay/, /pointerdown|pointermove|pointerup/, /moveWorkshopDroppedPlan/, /renderWorkshopPlannerWhenReady/,
    /initWorkshopSharedServicesIfEnabled/, /openVehicleWorkshopBooking/, /setScope/, /workshopLoadPlans\(\)\.find/, /performDrop|stationEntry|openInPlanner/]) {
    assert.doesNotMatch(js, gone, `${gone} is gone from the panel`);
  }
  assert.match(js, /VLT\.bindBoardHandlers\(panel\)/, 'the card\'s own buttons are bound as before');
  assert.match(js, /incomingVehicleDetailRow\(vehicle, bucket/, 'the panel shows the board\'s own card (stations, details, operations)');
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');
  assert.doesNotMatch(css, /vso-(jobs|booking|grip|bay|ghost|toast|dialog)|vso-target-bay/, 'drag styles removed');
});

test('panel in the VM: opening and refreshing never touches the planner or the drag path', () => {
  const { fixture, c } = board();
  const spies = { move: 0, planner: 0, init: 0 };
  c.moveWorkshopDroppedPlan = () => { spies.move += 1; return true; };
  c.renderWorkshopPlannerWhenReady = () => { spies.planner += 1; };
  c.initWorkshopSharedServicesIfEnabled = () => { spies.init += 1; };
  // r485 (F98): Table view is now the only view, so loading on the dashboard would draw the table, which this inert
  // fixture DOM cannot do. Load with another page current (the table draws when the dashboard is shown).
  c.app.currentView = 'workshop';
  fixture.loadHelper('pdc-vehicle-locations-table.js');
  fixture.loadHelper('pdc-vehicle-slideout.js');
  assert.deepEqual(Object.keys(c.PDC_VEHICLE_SLIDEOUT).sort(), ['VERSION', 'close', 'open', 'parityStrip', 'refresh', 'state'].sort());
  assert.deepEqual(spies, { move: 0, planner: 0, init: 0 });
});

test('docs: FAULT_LOG F76 records the withdrawn F75 drag, the Job Card column and the checks', () => {
  const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  const row = log.split('\n').find(line => line.startsWith('| F76 |'));
  assert.ok(row, 'F76 row');
  assert.match(row, /withdrawn/i);
  assert.match(row, /Job Card/);
  assert.match(fs.readFileSync('docs/vehicle-slideout-panel.md', 'utf8'), /r463 \(F76\)[\s\S]*withdrawn/);
});

test('loader: r463 cache-bust tags; pdc-auto-reload.js stays first; no real stock numbers here', () => {
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /r462=2026\.10\.22\.r462&r463=2026\.10\.22\.r463/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.22\.r4(?:[67]3|85)/ /* r485 (F98) bumped the panel */);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /r463=2026\.10\.22\.r463/);
  assert.match([...html.matchAll(/<script[^>]*src="([^"]+)"/g)][0][1], /^pdc-auto-reload\.js/);
  assert.equal(table.VERSION, '2026.10.22.r485'); // r475 (F88), r481 (F94), then r485 (F98) bumped the table module (on top of r476)
  assert.match(slideout.VERSION, /^2026\.10\.22\.r4(?:[67]3|85)$/); // r485 (F98): stoppage box
  const text = fs.readFileSync(__filename, 'utf8');
  assert.doesNotMatch(text, /\b1[23]\d{6}\b|\bJ13[89]\d{6}\b/);
});
