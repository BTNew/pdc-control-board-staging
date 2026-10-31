/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r481 (F94): Vehicle Locations search shows where the vehicle is (Craig, 22 Oct 2026; synthetic data only).
// Before: with the QC tile selected, searching a stock number that is in PMB showed "0 of N vehicles shown … QC tile"
// and "No vehicles match this tile and the search filters". A vehicle in the other department showed nothing at all.
// After: while the search box has text the tile does not hide matches (the matching tile is selected, or All vehicles
// when the matches span tiles); the earlier tile comes back when the search is cleared; a match in another department
// is named with a switch button. Display only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { syntheticVehicles } = require('./qa/vehicle-locations-table-461-fixture.cjs');

const SOURCE = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
const body = name => { const start = SOURCE.indexOf(`function ${name}(`); assert.ok(start > 0, `${name} exists`); return SOURCE.slice(start, SOURCE.indexOf('\n  }\n', start)); };

function board(departments = {}) {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  fixture.loadHelper('pdc-department-filter.js');
  const c = fixture.context;
  c.app.data = syntheticVehicles().map(v => (departments[v.stock] !== undefined ? { ...v, department_codes: departments[v.stock] } : { ...v, department_codes: ['139'] }));
  c.__defs = fixture.evaluate('VEHICLE_LOCATION_BUCKET_DEFS'); // app.js script-level const
  return c;
}
const stockIn = (c, bucket, n = 0) => c.vehicleLocationsScreenRows().filter(v => c.incomingBucketForVehicle(v) === bucket)[n].stock;
// The table's own steps: rows matching every filter (search + department), with their bucket and journey position.
function entriesFor(c, filters) {
  const order = table.journeyOrder(c.__defs);
  const full = { search: '', department: '', status: '', bucket: '', rep: '', work: [], ...filters };
  const entries = c.vehicleLocationsScreenRows().filter(v => c.incomingVehicleMatchesFilters(v, full))
    .map(vehicle => ({ vehicle, bucket: c.incomingBucketForVehicle(vehicle), key: c.vehicleKey(vehicle) })).filter(e => order.includes(e.bucket));
  return { entries, order };
}
const shownFor = (entries, scope) => entries.filter(e => (!scope.bucket || e.bucket === scope.bucket) && !scope.stoppages);

test('Craig\'s case: QC tile selected, search for a vehicle that is in PMB -> the vehicle shows and PMB is selected for the search', () => {
  assert.equal(typeof table.searchScope, 'function', 'r481 adds searchScope (main has none: the QC tile hid the match)');
  const c = board();
  const pmbStock = stockIn(c, 'pmb');
  const { entries, order } = entriesFor(c, { search: pmbStock.toLowerCase(), department: '139' });
  assert.equal(entries.length, 1);
  assert.equal(shownFor(entries, { bucket: 'qc' }).length, 0, 'main\'s rule (the QC tile filters the search) shows nothing');
  const scope = table.searchScope({ entries, bucket: 'qc', stoppages: false, needle: pmbStock, pick: null, order });
  assert.deepEqual({ bucket: scope.bucket, stoppages: scope.stoppages, found: [...scope.found], held: scope.held, searching: scope.searching }, { bucket: 'pmb', stoppages: false, found: ['pmb'], held: 'qc', searching: true });
  assert.deepEqual([...shownFor(entries, scope).map(e => e.vehicle.stock)], [pmbStock]);
});

test('matches in several tiles -> All vehicles, every tile holding a match is listed in journey order', () => {
  const c = board();
  const { entries, order } = entriesFor(c, { search: 'syn-00', department: '139' });
  const buckets = new Set(entries.map(e => e.bucket));
  assert.ok(buckets.size >= 3, 'fixture: the search spans several tiles');
  const scope = table.searchScope({ entries, bucket: 'qc', needle: 'syn-00', order });
  assert.equal(scope.bucket, '');
  assert.equal(scope.stoppages, false);
  assert.deepEqual([...scope.found], [...order.filter(key => buckets.has(key))]);
  assert.equal(shownFor(entries, scope).length, entries.length, 'nothing hidden by the QC tile');
});

test('clearing the search returns the tile picked before; STOPPAGES does not hide a search either', () => {
  const entries = [{ bucket: 'pmb', key: 'a' }];
  const order = [...table.JOURNEY];
  assert.deepEqual(table.searchScope({ entries, bucket: 'qc', stoppages: false, needle: '', order }), { searching: false, bucket: 'qc', stoppages: false, found: [], picked: false, held: '' });
  assert.deepEqual(table.searchScope({ entries, bucket: '', stoppages: true, needle: '  ', order }).stoppages, true, 'no search text: STOPPAGES applies as before');
  const s = table.searchScope({ entries, bucket: '', stoppages: true, needle: 'x', order });
  assert.equal(s.stoppages, false); assert.equal(s.bucket, 'pmb'); assert.equal(s.held, table.STOPPAGES);
});

test('a tile clicked during the search narrows the results only; the earlier tile is kept', () => {
  const entries = [{ bucket: 'pmb' }, { bucket: 'rft' }];
  const order = [...table.JOURNEY];
  const pick = p => table.searchScope({ entries, bucket: 'qc', needle: 'x', pick: p, order });
  assert.deepEqual([pick('rft').bucket, pick('rft').picked, pick('rft').held], ['rft', true, 'qc']);
  assert.deepEqual([pick('').bucket, pick('').stoppages], ['', false]);
  assert.deepEqual([pick(table.STOPPAGES).bucket, pick(table.STOPPAGES).stoppages], ['', true]);
  assert.deepEqual(pick(null).found, ['pmb', 'rft']);
  const click = body('bindTableEvents');
  assert.match(click, /if \(state\.search\.needle\) \{[^}]*state\.search\.pick = active && key !== '' \? '' : key;\s*\} else if \(key === STOPPAGES\)/, 'while searching a click sets the search pick, never state.bucket');
  assert.match(body('renderTable'), /if \(needle !== state\.search\.needle\) state\.search = \{ needle, pick: null \};/, 'a new or cleared search drops the pick');
});

test('department still applies; a match in another department is named with a switch button', () => {
  const c = board();
  const pmbStock = stockIn(c, 'pmb', 1);
  const c2 = board({ [pmbStock]: ['138'] });
  const filters = { search: pmbStock.toLowerCase(), department: '139' };
  assert.equal(entriesFor(c2, filters).entries.length, 0, 'not in 139');
  const other = c2.vehicleLocationsScreenRows().filter(v => c2.incomingVehicleMatchesFilters(v, { ...filters, department: '', status: '', bucket: '', rep: '', work: [] }));
  const groups = table.departmentElsewhere(other, '139', v => c2.PDC_DEPARTMENT_FILTER.departmentCodes(v));
  assert.deepEqual(groups.map(g => [g.code, g.vehicles.map(v => v.stock)]), [['138', [pmbStock]]]);
  assert.deepEqual(table.departmentElsewhere([{ id: 'n' }], '139', () => []).map(g => g.code), [''], 'no department: offers All departments');
  assert.deepEqual(table.departmentElsewhere([{ id: 'm' }], '138', () => ['138', '139']).map(g => g.code), ['139']);
  const html = body('elsewhereHtml');
  assert.match(html, /Found in \$\{esc\(departmentName\(group\.code\)\)\}/);
  assert.match(html, /data-vlt-switch-dept="\$\{esc\(target\)\}"/);
  assert.match(body('bindElsewhere'), /root\.PDC_DEPARTMENT_FILTER\?\.setSelection\(button\.dataset\.vltSwitchDept \|\| ''\)/, 'the button does what choosing it in the Department box does');
});

test('wiring: table rows, tiles and summary follow the search scope; the drop-down view gets the department note; single result still opens once', () => {
  const render = body('renderTable');
  assert.match(render, /const scope = searchScope\(\{ entries, bucket: state\.bucket, stoppages: state\.stoppages, needle, pick: state\.search\.pick, order \}\);/);
  assert.match(render, /\.filter\(entry => \(!scope\.bucket \|\| entry\.bucket === scope\.bucket\) && \(!scope\.stoppages \|\| stoppageKeys\.has\(entry\.key\)\)\)/);
  assert.doesNotMatch(render, /\.filter\(entry => \(!state\.bucket \|\| entry\.bucket === state\.bucket\)/, 'main\'s tile filter on the rows is gone');
  assert.match(render, /tile\('', 'All vehicles', new Set\(entries\.map\(entry => entry\.key\)\)\.size, 'Every active vehicle', 'all', !scope\.bucket && !scope\.stoppages/);
  assert.match(render, /found in \$\{scope\.found\.map\(tileName\)\.join\(', '\)\}/);
  assert.match(render, /host\.innerHTML = `\$\{tilesHtml\}(\$\{spareHtml\})?\$\{ageReport\}\$\{elsewhereHtml\(elsewhere\)\}/);
  assert.match(render, /revealSingleResult\(shown, filters\.search\);/, 'r470-era open-once on a single result is unchanged');
  assert.match(body('revealSingleResult'), /if \(focus\['incoming-table'\] === token\) return;/);
  assert.match(SOURCE, /const result = originalRender\.apply\(this, args\);[\s\S]{0,200}dropdownSearchElsewhere\(\);/);
  const drop = body('dropdownSearchElsewhere');
  assert.match(drop, /if \(!filters\.search \|\| !filters\.department\) return;/, 'drop-down: only a search with a department set');
  assert.doesNotMatch(render, /\brpc\(|supabase|fetch\(|localStorage|setItem/i, 'renderTable: display only');
  for (const fn of ['dropdownSearchElsewhere', 'elsewhereHtml', 'bindElsewhere', 'searchElsewhere', 'searchScope', 'departmentElsewhere']) {
    assert.doesNotMatch(body(fn), /\brpc\(|supabase|fetch\(|localStorage|setItem|delete|complete/i, `${fn}: display only (no write, no saved setting)`);
  }
});

test('loader, version, CSS and synthetic data', () => {
  assert.equal(table.VERSION, '2026.10.28.r593'); // r567 typed Parts ETA stays on the loader; r586 New to PMB view bumps this module
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-locations-table\.js\?[^']*&r481=2026\.10\.22\.r481&r485=2026\.10\.22\.r485&r557=2026\.10\.27\.r557&r562=2026\.10\.27\.r562&r563=2026\.10\.27\.r563&r567=2026\.10\.27\.r567&r566=2026\.10\.27\.r566&r593=2026\.10\.28\.r593(?:&r604=2026\.10\.28\.r604)?(?:&r613=2026\.10\.28\.r613)?(?:&r618=2026\.10\.28\.r618)?(?:&r622=2026\.10\.28\.r622)?(?:&r672=2026\.10\.28\.r672)?(?:&r685=2026\.10\.29\.r685)?(?:&r693=2026\.10\.29\.r693)?(?:&r698=2026\.10\.29\.r698)?(?:&r707=2026\.10\.29\.r707)?(?:&r745=2026\.10\.30\.r745)?(?:&r753=2026\.10\.30\.r753)?(?:&r792=2026\.11\.01\.r792)?(?:&r795=2026\.11\.01\.r795)?'/); // r604 (F218) appends the Pit column tag
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r481=2026\.10\.22\.r481/);
  const css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  assert.match(css, /\.vlt-tile\.vlt-found \{/);
  assert.match(css, /\.vlt-search-elsewhere \{/);
  const r481 = css.slice(css.indexOf('/* r481'), css.indexOf('/* r481: a longer'));
  assert.doesNotMatch(r481, /incoming-work|pdc-station|parts-jita/, 'station cells untouched');
  assert.doesNotMatch(fs.readFileSync(__filename, 'utf8'), /\b1[23]\d{6}\b|\bJ13[89]\d{6}\b|\bU1\d{5}\b/);
});
