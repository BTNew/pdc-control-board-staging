/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r461 (F74): Vehicle Locations "Table view". Parity gate: every station cell of every vehicle in the table view must
// match the drop-down view exactly (state classes, symbol, colour classes, tooltip). Synthetic fixture only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { syntheticVehicles, syntheticPlans, BUCKETS } = require('./qa/vehicle-locations-table-461-fixture.cjs');

const VERSION = '2026.10.27.r566'; // r462 (F75) / r463 (F76) / r476 (F89) / r475 (F88) / r481 (F94) / r485 (F98) / r557 (F171) / r562 (F176) / r563 (F177) / r566 (F180) bumped the module version; the r461 cache-bust tag stays
// r485 (F98): the Drop-down view is hidden behind DROPDOWN_VIEW_ENABLED (false). The r461 drop-down checks below run the
// module with that one flag set to true, which is exactly the undo-by-flag path (switch, drop-down default, saved choice).
const loadWithDropdownFlag = fixture => fixture.evaluate(fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8')
  .replace('const DROPDOWN_VIEW_ENABLED = false;', 'const DROPDOWN_VIEW_ENABLED = true;'));

// Independent of the module's own parser: find each element that starts with `<tag class="...needle` and return its
// exact outer HTML by counting that tag's nesting.
function elements(html, tag, needle) {
  const out = [];
  const open = new RegExp(`<(${tag === '*' ? '[a-z]+' : tag})\\b[^>]*class="(?:[^"]*\\s)?${needle}(?=[\\s"])`, 'g');
  let match;
  while ((match = open.exec(html))) {
    const name = match[1];
    const re = new RegExp(`<${name}\\b|</${name}>`, 'g');
    re.lastIndex = match.index + 1;
    let depth = 1; let m;
    while (depth && (m = re.exec(html))) depth += m[0][1] === '/' ? -1 : 1;
    out.push(html.slice(match.index, m ? m.index + `</${name}>`.length : html.length));
    open.lastIndex = match.index + 1;
  }
  return out;
}
const cellFields = cell => {
  const openTag = cell.slice(0, cell.indexOf('>') + 1);
  const attr = name => (new RegExp(`\\s${name}="([^"]*)"`).exec(openTag) || [])[1] || '';
  const markers = [...cell.matchAll(/<span class="(incoming-work-box[^"]*|parts-jita-marker)"[^>]*>([^<]*)<\/span>/g)].map(m => m[2].trim());
  return { classes: attr('class').split(/\s+/).filter(Boolean).sort().join(' '), symbol: markers.join('|'), title: attr('title'), aria: attr('aria-label'), html: cell };
};
const stateOf = classes => /is-blocked/.test(classes) ? 'stoppage' : /is-complete/.test(classes) ? 'complete' : /is-booked/.test(classes) ? 'booked'
  : /imported-parts-/.test(classes) ? `parts ${(classes.match(/imported-parts-(\w+)/) || [])[1]}` : /is-not-required/.test(classes) ? 'not required'
    : /is-required/.test(classes) ? 'required' : 'other';

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

test('parity gate: every station cell of every vehicle is identical in the drop-down and table views (synthetic fixture)', () => {
  const { fixture, c, plans } = board();
  c.renderIncomingDashboardBoard();
  const dropDown = fixture.host.innerHTML;
  const rows = c.vehicleLocationsScreenRows();
  assert.equal(rows.length, 48, 'every synthetic vehicle is on the board');
  const report = { vehicles: 0, cells: 0, states: {}, mismatches: [] };
  const seenBuckets = new Set();
  for (const vehicle of rows) {
    const key = c.vehicleKey(vehicle);
    const bucket = c.incomingBucketForVehicle(vehicle);
    seenBuckets.add(bucket);
    // The table renders from the very same incomingVehicleDetailRow() call the drop-down view makes.
    const card = c.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans: plans, workshopProjectionAvailable: true, subletNavigation: true });
    const cardStart = dropDown.indexOf(`data-incoming-row="${key}"`);
    assert.ok(cardStart > 0, `${key} is drawn in the drop-down view`);
    const dropCard = elements(dropDown.slice(dropDown.lastIndexOf('<details', cardStart)), 'details', 'incoming-vehicle-card')[0];
    assert.equal(dropCard.trim(), card.trim(), `${key}: the drop-down card is the same render the table uses`);
    const row = table.tableRowHtml(card, bucket, { key, bucketLabel: c.incomingBucketLabel(bucket) });
    const before = elements(dropCard, '*', 'incoming-work-check').map(cellFields);
    const after = elements(row, '*', 'incoming-work-check').map(cellFields);
    report.vehicles += 1;
    if (before.length !== after.length) report.mismatches.push({ key, field: 'cell count', before: before.length, after: after.length });
    before.forEach((cell, index) => {
      report.cells += 1;
      const state = stateOf(cell.classes);
      report.states[state] = (report.states[state] || 0) + 1;
      for (const field of ['classes', 'symbol', 'title', 'aria', 'html']) {
        if (cell[field] !== after[index]?.[field]) report.mismatches.push({ key, index, field, before: cell[field], after: after[index]?.[field] });
      }
    });
    // Everything else in the summary row travels verbatim too: RFT controls, age, status, booking buttons, identity.
    for (const needle of ['incoming-card-select', 'rft-row-controls-slot', 'incoming-card-work-wrap', 'incoming-card-age', 'incoming-card-status', 'incoming-card-action', 'incoming-card-main', 'identity-key', 'identity-stock', 'identity-jc', 'identity-name']) {
      const part = elements(card.slice(0, card.indexOf('</summary>')), '*', needle)[0];
      // r462: the Vehicle cell travels without the parts-location span, which has its own Parts loc cell.
      const expected = needle === 'incoming-card-main' && part ? table.extractPartsLocation(part).unit : part;
      if (expected && !row.includes(expected)) report.mismatches.push({ key, field: needle, before: part.slice(0, 120) });
    }
  }
  assert.deepEqual(report.mismatches, [], `drop-down vs table mismatches: ${report.mismatches.length}`);
  const expectedCells = rows.filter(vehicle => c.incomingBucketForVehicle(vehicle) !== 'rft')
    .reduce((sum, vehicle) => sum + elements(c.incomingWorkChecklistHtml(vehicle, { bookingProjection: c.vehicleWorkshopBookingProjection(vehicle, { plans }) }), '*', 'incoming-work-check').length, 0);
  assert.equal(report.cells, expectedCells, 'every station cell of every vehicle was compared (RFT rows carry the RFT controls instead)');
  assert.ok(report.cells >= 300, `enough cells compared (${report.cells})`);
  for (const state of ['not required', 'required', 'booked', 'complete', 'stoppage', 'parts green', 'parts orange', 'parts grey', 'parts review', 'parts red']) {
    assert.ok(report.states[state] > 0, `fixture covers the ${state} state`);
  }
  assert.deepEqual([...seenBuckets].sort(), [...BUCKETS].sort(), 'fixture covers all eight location buckets');
  console.log(`r461 parity (synthetic): ${report.vehicles} vehicles, ${report.cells} station cells, 0 mismatches`, report.states);
});

test('each state keeps its symbol: required •, booked !, complete ✓, STOPPAGE !, not required –', () => {
  const { c, plans } = board();
  const symbols = {};
  for (const vehicle of c.vehicleLocationsScreenRows()) {
    const bucket = c.incomingBucketForVehicle(vehicle);
    const row = table.tableRowHtml(c.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans: plans, workshopProjectionAvailable: true, subletNavigation: true }), bucket);
    elements(row, '*', 'incoming-work-check').map(cellFields).filter(cell => !/parts-jita-split/.test(cell.classes))
      .forEach(cell => { (symbols[stateOf(cell.classes)] ||= new Set()).add(cell.symbol); });
  }
  assert.deepEqual([...symbols.required], ['•']);
  assert.deepEqual([...symbols.booked], ['!']);
  assert.deepEqual([...symbols.complete], ['✓']);
  assert.deepEqual([...symbols.stoppage], ['!']);
  assert.deepEqual([...symbols['not required']], ['–']);
});

test('tiles and rows follow Craig\'s journey order; a bucket added later is never dropped', () => {
  const { c } = board();
  assert.deepEqual(table.journeyOrder(c.VEHICLE_LOCATION_BUCKET_DEFS ?? c.eval?.('VEHICLE_LOCATION_BUCKET_DEFS') ?? []).length ? table.journeyOrder(c.VEHICLE_LOCATION_BUCKET_DEFS) : table.JOURNEY,
    ['overseas', 'transit', 'yardhold', 'nonnavision', 'newpmb', 'pmb', 'qc', 'pit', 'rft']);
  assert.deepEqual(table.journeyOrder([{ key: 'rft' }, { key: 'pmb' }, { key: 'future' }, { key: 'overseas' }]), ['overseas', 'pmb', 'rft', 'future']);
  assert.deepEqual(table.JOURNEY, ['overseas', 'transit', 'yardhold', 'nonnavision', 'newpmb', 'pmb', 'qc', 'pit', 'rft']);
  assert.deepEqual(table.JOURNEY.map(key => table.TILE[key][0]), ['Other', 'In transit (IT)', 'Yard Hold', 'Non-Navision', 'New to PMB', 'PMB', 'QC', 'PIT', 'RFT']);
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /tile\('', 'All vehicles'[\s\S]*order\.map[\s\S]*tile\(STOPPAGES, 'STOPPAGES', priorityRows\.length/, 'All first, STOPPAGES last, counted from the board\'s own stoppage list');
});

// r485 (F98): was "the choice is remembered per user on this device and defaults to the drop-down view". The r461 rules
// are unchanged behind the flag (checked with dropdownEnabled: true); with the flag off (live) everyone reads Table view.
test('the choice is remembered per user on this device and defaults to the drop-down view (r461 rules, behind the r485 flag)', () => {
  const store = new Map();
  const storage = { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)) };
  const on = { dropdownEnabled: true };
  assert.equal(table.readView(storage, 'user-a', on), 'dropdown', 'nobody gets the table unless they switch');
  assert.equal(table.writeView(storage, 'user-a', 'table', on), true);
  assert.equal(table.readView(storage, 'user-a', on), 'table');
  assert.equal(table.readView(storage, 'user-b', on), 'dropdown', 'another person on the same device keeps their own view');
  assert.equal(store.get('pdc.vehicle-locations-view.v1:user-a'), 'table');
  table.writeView(storage, 'user-a', 'something-else', on);
  assert.equal(table.readView(storage, 'user-a', on), 'dropdown');
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  assert.equal(table.readView(broken, 'user-a', on), 'dropdown', 'storage blocked: drop-down view');
  assert.equal(table.writeView(broken, 'user-a', 'table', on), false);
  assert.equal(table.readView(null, '', on), 'dropdown');
  // r485 live (flag off): Table view for everyone, whatever is stored; nothing is written.
  assert.equal(table.DROPDOWN_VIEW_ENABLED, false);
  assert.equal(table.readView(storage, 'user-a'), 'table');
  assert.equal(table.readView(broken, 'user-a'), 'table');
  assert.equal(table.readView(null, ''), 'table');
});

// r485 (F98): with the flag off the module switches to Table view on load (test_vehicle_locations_table_only_485.js);
// this r461 check now runs with the flag set to true, proving the hidden drop-down path is intact for an undo.
test('loading the module leaves the drop-down render untouched until someone switches (r485 flag set to true)', () => {
  const { fixture, c } = board();
  c.renderIncomingDashboardBoard();
  const before = fixture.host.innerHTML;
  loadWithDropdownFlag(fixture);
  assert.equal(typeof c.PDC_VEHICLE_LOCATIONS_TABLE.setView, 'function', 'browser part installed');
  assert.equal(c.PDC_VEHICLE_LOCATIONS_TABLE.state.view, 'dropdown');
  fixture.host.innerHTML = '';
  c.renderIncomingDashboardBoard();
  assert.equal(fixture.host.innerHTML, before, 'drop-down view renders byte-for-byte as before');
});

test('HTML splitter keeps nested, void, quoted and self-closing markup intact', () => {
  const parts = table.topLevelElements('x<span title="a > b" class="one"><b>1</b><svg><path d="m1 2"/></svg></span><!-- c --><input data-x="<"><br/><i class="two">2</i>');
  assert.deepEqual(parts.map(p => p.tag), ['span', 'input', 'br', 'i']);
  assert.equal(parts[0].html, '<span title="a > b" class="one"><b>1</b><svg><path d="m1 2"/></svg></span>');
  assert.equal(parts[3].inner, '2');
  const split = table.splitCard('<details class="incoming-vehicle-card x" data-incoming-row="K1"><summary><span class="incoming-card-select"></span><span class="incoming-card-stock"><div class="vehicle-identity-stack" title="T"><span class="vehicle-identity-cell identity-key">1</span><span class="vehicle-identity-cell identity-stock">2</span></div></span><span class="incoming-card-work-wrap"><div class="pdc-station-strip"></div></span></summary><div>detail</div></details>');
  assert.equal(split.ok, true);
  assert.equal(split.rowKey, 'K1');
  assert.equal(split.key.html, '<span class="vehicle-identity-cell identity-key">1</span>');
  assert.equal(split.work.html, '<span class="incoming-card-work-wrap"><div class="pdc-station-strip"></div></span>');
  assert.match(table.tableRowHtml('<details class="incoming-vehicle-card"><summary><span class="incoming-card-stock">odd</span></summary></details>', 'pmb'), /<td class="c-stock"><span class="incoming-card-stock">odd<\/span><\/td>/, 'unexpected identity markup is shown whole, never dropped');
});

test('compact CSS never changes a station cell\'s colour (size and spacing only)', () => {
  const css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => [m[1].trim(), m[2]]);
  const station = rules.filter(([selector]) => /incoming-work-check|incoming-work-box|parts-jita|pdc-station-strip/.test(selector));
  assert.ok(station.length >= 4);
  for (const [selector, body] of station) {
    assert.doesNotMatch(body, /(^|;|\s)(color|background(-color|-image)?|border(-\w+)?-color|border\s*:|opacity|filter|content)\s*:/, `${selector} must not change colour or symbol`);
  }
  for (const [selector] of rules) {
    if (/@media/.test(selector)) continue;
    assert.match(selector, /vlt-|#vlt|body\.vlt-table-on|^\s*$|^(from|to|\d+%)$/, `${selector} is scoped to the table view or the switch`);
  }
});

test('loader: r461 cache-bust tags, runtime files, and pdc-auto-reload.js stays the first script', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-vehicle-locations-table\.js\?vehicle-locations-table=2026\.10\.22\.r461/);
  assert.ok(entry.indexOf('keyNumber.onload = loadPartsStoppage') > 0, 'the typed parts ETA loads after the key number');
  assert.ok(entry.indexOf('stoppage.onload = loadVehicleLocationsTable') > entry.indexOf('keyNumber.onload = loadPartsStoppage'), 'the table loads after the typed parts ETA');
  const module = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(module, new RegExp(`const VERSION = '${VERSION.replace(/\./g, '\\.')}'`));
  assert.match(module, /pdc-vehicle-locations-table\.css\?vehicle-locations-table=\$\{VERSION\}/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /canonical-entry\.js\?[^"]*vehicle-locations-table=2026\.10\.22\.r461/);
  const scripts = [...html.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m => m[1]);
  assert.match(scripts[0], /^pdc-auto-reload\.js/);
  const build = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(build, /'pdc-vehicle-locations-table\.js', 'pdc-vehicle-locations-table\.css'/);
  assert.doesNotMatch(module, /\beval\s*\(|new Function|\.rpc\(|fetch\(/, 'no eval, no network, no writes');
});

test('fixture is synthetic: no real stock numbers, customer names or job cards', () => {
  const text = fs.readFileSync('qa/vehicle-locations-table-461-fixture.cjs', 'utf8');
  assert.doesNotMatch(text, /\b1[23]\d{6}\b/, 'no 8-digit stock numbers');
  assert.doesNotMatch(text, /\bJ13[89]\d{6}\b/, 'no job card numbers');
  for (const vehicle of syntheticVehicles()) {
    assert.match(vehicle.stock, /^SYN-\d{4}$/);
    assert.equal(vehicle.client, '');
  }
});
