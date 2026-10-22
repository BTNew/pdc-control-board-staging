'use strict';
// r462 (F75): Vehicle Locations Table view: slide-out panel with drag between bays through the planner's own
// moveWorkshopDroppedPlan (Option A, fallback to the planner = Option B), the Parts loc column, resizable columns,
// and the panel's operations layout. Synthetic data only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { syntheticVehicles, syntheticPlans } = require('./qa/vehicle-locations-table-461-fixture.cjs');

const memoryStorage = () => {
  const store = new Map();
  return { store, getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
};

// ---------------- Parts loc column ----------------
test('Parts loc: the card\'s own parts-location span moves to its own cell; "—" when there is none', () => {
  const span = '<span class="tune-parts-location" title="Parts location: 05E2A" aria-label="Parts location: 05E2A">05E2A</span>';
  const unit = `<span class="incoming-card-main"><strong>Coaster</strong>${span}</span>`;
  const card = `<details class="incoming-vehicle-card" data-incoming-row="SYN-0001"><summary><span class="incoming-card-select"></span>${unit}<span class="incoming-card-work-wrap"><div class="pdc-station-strip"></div></span></summary></details>`;
  const split = table.extractPartsLocation(unit);
  assert.equal(split.span, span, 'verbatim span (same title, aria-label and text the card shows)');
  assert.equal(split.text, '05E2A');
  assert.equal(split.unit, '<span class="incoming-card-main"><strong>Coaster</strong></span>');
  const row = table.tableRowHtml(card, 'pmb', { key: 'SYN-0001' });
  assert.match(row, new RegExp(`<td class="c-ploc">${span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}</td>`));
  assert.match(row, /<td class="c-unit"><span class="incoming-card-main"><strong>Coaster<\/strong><\/span><\/td>/, 'not shown twice');
  assert.match(row, /data-vlt-parts-loc="05E2A"/);
  assert.doesNotMatch(row, /c-loc|vlt-pill/, 'the old Loc column is gone');
  const none = table.tableRowHtml(card.replace(span, ''), 'pmb', { key: 'SYN-0001' });
  assert.match(none, /<td class="c-ploc"><span class="vlt-subtle-dash" title="No parts location">—<\/span><\/td>/);
  assert.equal(table.extractPartsLocation('<span class="tune-parts-location" title="x">A &amp; B</span>').text, 'A & B');
});

test('Parts loc sorts naturally with missing values last in both directions', () => {
  const values = ['12B1', '', '05E2A', '5A', '05E10', ''];
  const asc = [...values].sort((a, b) => table.comparePartsLocation(a, b, 'asc'));
  const desc = [...values].sort((a, b) => table.comparePartsLocation(a, b, 'desc'));
  assert.deepEqual(asc, ['5A', '05E2A', '05E10', '12B1', '', ''], 'numbers compare as numbers (05E2A before 05E10)');
  assert.deepEqual(desc, ['12B1', '05E10', '05E2A', '5A', '', '']);
});

test('Parts loc uses the card\'s data source: real pdc-service-locations.js output on a PMB vehicle, parity unchanged', () => {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  const c = fixture.context;
  c.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd' };
  c.app.data = syntheticVehicles();
  const plans = syntheticPlans(c, c.app.data);
  c.workshopLoadPlans = () => plans;
  c.ensureDashboardWorkshopProjectionReady = () => true;
  const pmb = c.app.data.find(v => v.pdcLocation === 'PMB');
  const yard = c.app.data.find(v => v.pdcLocation === 'YH');
  pmb.tuneServiceLocations = { jobs: [{ ro_number: 'SYN-RO-1', parts_location: '05E2A', vehicle_key_number: '516' }] };
  yard.tuneServiceLocations = { jobs: [{ ro_number: 'SYN-RO-2', parts_location: '09Z9', vehicle_key_number: '17' }] };
  fixture.loadHelper('pdc-service-locations.js');
  const row = vehicle => {
    const bucket = c.incomingBucketForVehicle(vehicle);
    const card = c.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans: plans, workshopProjectionAvailable: true, subletNavigation: true });
    return { card, row: table.tableRowHtml(card, bucket, { key: c.vehicleKey(vehicle) }) };
  };
  const a = row(pmb);
  assert.match(a.card, /Parts location: 05E2A/, 'the card shows it');
  assert.match(a.row, /<td class="c-ploc"><span class="tune-parts-location"[^>]*>05E2A<\/span><\/td>/, 'the table shows the same value in Parts loc');
  const b = row(yard);
  assert.doesNotMatch(b.card, /tune-parts-location/, 'off-site vehicles: the card shows none');
  assert.match(b.row, /<td class="c-ploc"><span class="vlt-subtle-dash"/, 'and the table shows —');
  const cells = html => (html.match(/class="incoming-work-check[^"]*"[^>]*>/g) || []).join('\n');
  assert.equal(cells(a.row), cells(a.card), 'station cells unchanged by the Parts loc move');
});

test('Parts loc: search includes it (table only), sorting is table-only and never changes the drop-down sort', () => {
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /partsLocationValues\(vehicle\)\.some\(value => value\.toLowerCase\(\)\.includes\(needle\)\) && root\.incomingVehicleMatchesFilters\(vehicle, searchless\)/,
    'a search that matches the parts location shows the vehicle; every other filter still applies');
  assert.match(source, /vehiclePdcLocation\(vehicle\) !== 'PMB'\) return \[\]/, 'same on-site rule as the card');
  assert.match(source, /state\.partsSort \? comparePartsLocation\(a\.partsLoc, b\.partsLoc, state\.partsSort\) : 0/);
  assert.doesNotMatch(source, /incomingDashboardSort = \{ key: 'parts/, 'the shared drop-down sort is never set to the table-only column');
});

// ---------------- Resizable columns ----------------
test('column widths: saved per signed-in user on this device, like the view switch', () => {
  const storage = memoryStorage();
  assert.deepEqual(table.readWidths(storage, 'user-a'), {}, 'nothing saved: default widths');
  assert.equal(table.writeWidths(storage, 'user-a', { cust: 180, unit: 210 }), true);
  assert.deepEqual(table.readWidths(storage, 'user-a'), { cust: 180, unit: 210 });
  assert.deepEqual(table.readWidths(storage, 'user-b'), {}, 'another person on this device keeps their own widths');
  // r476 (F89): the key moved to v2 so r462-era saved widths do not hide the new defaults.
  assert.equal(storage.store.get('pdc.vehicle-locations-columns.v2:user-a'), '{"cust":180,"unit":210}');
  assert.equal(table.columnStorageKey(''), 'pdc.vehicle-locations-columns.v2:signed-out');
  storage.setItem('pdc.vehicle-locations-columns.v2:user-c', '{not json');
  assert.deepEqual(table.readWidths(storage, 'user-c'), {}, 'broken value: defaults');
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }, removeItem() { throw new Error('blocked'); } };
  assert.deepEqual(table.readWidths(broken, 'user-a'), {});
  assert.equal(table.writeWidths(broken, 'user-a', { cust: 120 }), false);
});

test('column widths: sensible minimums, a maximum, unknown columns dropped; the station column never shrinks', () => {
  const clean = table.sanitizeWidths({ key: 1, stock: 10, cust: 9999, unit: 'abc', ploc: 50.6, work: 100, status: -5, nope: 300, action: Infinity });
  assert.deepEqual(clean, { key: 30, stock: 56, cust: 520, ploc: 51, work: table.COLUMNS.work.min }); // r476: station minimum 276
  for (const [key, col] of Object.entries(table.COLUMNS)) {
    assert.ok(col.min >= 30 && col.min <= col.width, `${key}: minimum ${col.min} is at most its default ${col.width}`);
  }
  assert.equal(table.COLUMNS.work.min, table.COLUMNS.work.width, 'station strip keeps its 9 x 27 px cells at any width');
  assert.ok(table.COLUMNS.work.min >= 9 * 27 + 8 * 3 + 8, 'room for 9 cells, 8 gaps and the cell padding');
});

test('column widths: CSS variables keep pinned Key / Stock aligned; defaults equal the r476 widths; reset clears', () => {
  assert.equal(table.widthStyle({}), '', 'no saved widths and no layout: no inline style at all');
  const css = table.widthStyle({ key: 50, cust: 150 });
  assert.match(css, /--vlt-w-key:50px/);
  assert.match(css, /--vlt-w-cust:150px/);
  assert.match(css, /--vlt-left-key:0px/, 'r476: no select column when no row has a checkbox');
  assert.match(css, /--vlt-left-stock:50px/, 'Stock pins right after the wider Key column');
  const C = table.COLUMNS;
  const total = 50 + C.stock.width + C.job.width + 150 + C.unit.width + C.ploc.width + C.work.width + C.age.width + C.status.width + C.action.width;
  assert.match(css, new RegExp(`--vlt-table-min:${total}px`));
  const sheet = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  for (const [key, col] of Object.entries(table.COLUMNS)) {
    const fallback = col.flex ? `var\\(--vlt-flex-${key}, ${col.width}px\\)` : `${col.width}px`; // r476: flex columns take the spare width
    assert.match(sheet, new RegExp(`col\\.c-${key} \\{ width: var\\(--vlt-w-${key}, ${fallback}\\); \\}`), `${key} default is the r476 width`);
  }
  assert.match(sheet, /\.c-key \{ left: var\(--vlt-left-key, 0px\); \}/);
  assert.match(sheet, new RegExp(`\\.c-stock \\{ left: var\\(--vlt-left-stock, ${C.key.width}px\\);`));
  const storage = memoryStorage();
  table.writeWidths(storage, 'user-a', { cust: 200 });
  assert.equal(table.resetWidths(storage, 'user-a'), true);
  assert.equal(storage.store.has('pdc.vehicle-locations-columns.v2:user-a'), false, 'Reset columns removes the saved widths');
  assert.deepEqual(table.readWidths(storage, 'user-a'), {});
  table.writeWidths(storage, 'user-a', {});
  assert.equal(storage.store.size, 0, 'saving nothing removes the key');
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /data-vlt-reset-cols/, 'Reset columns button');
  assert.match(source, /role="separator" aria-orientation="vertical" tabindex="0"/, 'header edge grips are keyboard reachable');
  assert.match(source, /ArrowLeft[\s\S]{0,80}ArrowRight/);
});

// r463 (F76): the r462 bay-guide, drag-handle, drop, Option A/B and bookings tests are withdrawn with the feature
// (Craig, 22 Oct 09:03). test_vehicle_locations_463.js proves the panel has no drag and never calls the planner.

// ---------------- Safety, scope, loader ----------------
test('the panel never calls an RPC or fetch itself and writes nothing to storage', () => {
  const source = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  assert.doesNotMatch(source, /\bfetch\s*\(|\.rpc\s*\(|XMLHttpRequest|sendBeacon|localStorage|sessionStorage|\beval\s*\(|new Function/);
  assert.doesNotMatch(source, /__workshopSharedActions|administratorMoveBooking|moveBooking\(|mutate\(|moveWorkshopDroppedPlan/, 'r463: the panel moves nothing');
  assert.doesNotMatch(source, /deleteIncomingVehicleFromMain\(|completeVehicle|markVehicleComplete/, 'never calls delete / complete itself');
  const tableSource = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.doesNotMatch(tableSource, /\beval\s*\(|new Function|\.rpc\(|fetch\(/);
});

test('panel CSS is scoped to the panel: the Drop-down view card and station cells are untouched', () => {
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => [m[1].trim(), m[2]]);
  assert.ok(rules.length > 20);
  for (const [selector, body] of rules) {
    for (const part of selector.split(',').map(s => s.trim())) {
      assert.match(part, /^#vso-shell\b/, `${part} is scoped to the panel`);
    }
    if (/incoming-work-check|incoming-work-box|parts-jita|pdc-station-strip|pdc-sublet-po|badge/.test(selector)) {
      assert.doesNotMatch(body, /(^|;|\s)(color|background(-color|-image)?|border(-\w+)?-color|opacity|content)\s*:/, `${selector} must not change colours or symbols`);
    }
  }
  // Craig 08:07: operations stacked full width, one row per line, ellipsis + full text on hover and focus.
  assert.match(css, /#vso-shell \.authenticated-email-operations \.pdc-op-panels \{ display: flex !important; flex-direction: column;/);
  assert.match(css, /li > span \{[^}]*white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis;/);
  assert.match(css, /li\[data-vso-full\]:hover::after,\s*#vso-shell \.authenticated-email-operations li\[data-vso-full\]:focus::after/);
  assert.match(css, /content: attr\(data-vso-full\)/);
  const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(js, /if \(!span\.title\) span\.title = full;/, 'title tooltip');
  assert.match(js, /li\.tabIndex = 0/, 'keyboard focus shows it');
  for (const locked of ['styles.css', 'app.js', 'pdc-operation-panels.js']) {
    assert.doesNotMatch(fs.readFileSync(locked, 'utf8'), /vso-|r462|r463/, `${locked} untouched`);
  }
});

test('loading both modules leaves the Drop-down view render byte-for-byte unchanged', () => {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  const c = fixture.context;
  c.app.data = syntheticVehicles();
  const plans = syntheticPlans(c, c.app.data);
  c.workshopLoadPlans = () => plans;
  c.ensureDashboardWorkshopProjectionReady = () => true;
  c.renderIncomingDashboardBoard();
  const before = fixture.host.innerHTML;
  fixture.loadHelper('pdc-vehicle-locations-table.js');
  fixture.loadHelper('pdc-vehicle-slideout.js');
  assert.equal(typeof c.PDC_VEHICLE_SLIDEOUT.open, 'function', 'panel installed');
  assert.equal(c.PDC_VEHICLE_LOCATIONS_TABLE.state.view, 'dropdown', 'default stays the Drop-down view');
  fixture.host.innerHTML = '';
  c.renderIncomingDashboardBoard();
  assert.equal(fixture.host.innerHTML, before);
  assert.doesNotMatch(before, /vso-|c-ploc|vlt-col-resize/);
});

test('loader: slide-out loads after the table module; cache-bust tags; runtime files; pdc-auto-reload.js first', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-vehicle-locations-table\.js\?vehicle-locations-table=2026\.10\.22\.r461&r462=2026\.10\.22\.r462&r463=2026\.10\.22\.r463/);
  assert.match(entry, /table\.onload = loadVehicleSlideout;/);
  assert.match(entry, /pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.22\.r4[67]3/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /pdc-vehicle-slideout\.css\?vehicle-slideout=\$\{VERSION\}/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /const VERSION = '2026\.10\.22\.r47?[36]'/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /canonical-entry\.js\?[^"]*r462=2026\.10\.22\.r462&amp;r463=2026\.10\.22\.r463/);
  const scripts = [...html.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m => m[1]);
  assert.match(scripts[0], /^pdc-auto-reload\.js/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-vehicle-slideout\.js', 'pdc-vehicle-slideout\.css'/);
});

test('this test and its fixtures carry no real stock numbers, job cards or customer names', () => {
  const text = fs.readFileSync(__filename, 'utf8');
  assert.doesNotMatch(text, /\b1[23]\d{6}\b/);
  assert.doesNotMatch(text, /\bJ13[89]\d{6}\b/);
});
