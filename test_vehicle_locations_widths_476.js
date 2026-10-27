'use strict';
// r476 (F89): Vehicle Locations Table view columns bunched up (display only). No stock numbers or customer data here.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const table = require('./pdc-vehicle-locations-table.js');
const C = table.COLUMNS;
const FIXED = ['key', 'stock', 'job', 'ploc', 'work', 'age'];
const FLEX = ['cust', 'unit', 'status', 'action'];
const memoryStorage = () => { const store = new Map(); return { store, getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) }; };

test('tight fixed defaults for the columns whose content never grows; only Customer, Vehicle, Status, Booking flex', () => {
  assert.deepEqual(Object.fromEntries(FIXED.map(k => [k, C[k].width])), { key: 42, stock: 82, job: 78, ploc: 60, work: 276, age: 72 });
  for (const k of FIXED) assert.equal(C[k].flex, undefined, `${k} does not flex`);
  for (const k of FLEX) assert.ok(C[k].flex > 0, `${k} flexes`);
  assert.equal(C.work.width, 9 * 27 + 8 * 3 + 9, 'stations: 9 x 27 px cells, 8 x 3 px gaps and the cell padding');
  assert.equal(C.work.min, C.work.width, 'the station strip is never squeezed');
  assert.equal(table.VERSION, '2026.10.27.r560'); // r475 (F88) Parts ETA column, r481 (F94) search across tiles, r485 (F98) Table view only, r557 (F171) New to PMB, r560 (F174) key gate
});

test('spare width goes only to the flex columns; fixed columns keep their px at any screen width', () => {
  for (const available of [900, 1098, 1366, 1652, 2400]) {
    const lay = table.layoutWidths({}, { available });
    for (const k of FIXED) assert.equal(lay.cols[k], C[k].width, `${available}: ${k} stays ${C[k].width}`);
    for (const k of FLEX) assert.ok(lay.cols[k] >= C[k].width, `${available}: ${k} never below its base`);
    assert.equal(lay.total, Math.max(available, lay.min), `${available}: columns add up to the table area exactly`);
  }
  const wide = table.layoutWidths({}, { available: 1652 });
  assert.ok(wide.cols.status > wide.cols.action, 'Status (long Navision text) gets more of the spare than Booking');
});

test('the left gap: select column is 0 px unless a row on screen has a checkbox; pinned Key / Stock follow it', () => {
  const none = table.widthStyle({}, { available: 1200 });
  assert.match(none, /--vlt-w-sel:0px/); assert.match(none, /--vlt-left-key:0px/); assert.match(none, new RegExp(`--vlt-left-stock:${C.key.width}px`));
  const sel = table.widthStyle({}, { available: 1200, select: true });
  assert.match(sel, new RegExp(`--vlt-w-sel:${table.SEL_WIDTH}px`)); assert.match(sel, new RegExp(`--vlt-left-stock:${table.SEL_WIDTH + C.key.width}px`));
  assert.ok(table.SEL_WIDTH <= 22, 'tiny when it is needed');
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(src, /\/data-select-stock\/\.test\(bodyHtml\) \? ' has-select' : ''/, 'has-select only when a rendered row has a checkbox');
  const row = table.tableRowHtml('<details class="incoming-vehicle-card" data-incoming-row="K1"><summary><span class="incoming-card-select" aria-hidden="true"></span><span class="incoming-card-stock"><div class="vehicle-identity-stack"><span class="vehicle-identity-cell identity-key">1</span><span class="vehicle-identity-cell identity-stock">2</span></div></span></summary></details>', 'pmb');
  assert.match(row, /^<tr[^>]*><td class="c-sel">/, 'markup unchanged: the select cell is still there (parity), only its width changes');
});

test('a saved width fixes that column; hidden Status takes no width; minimum keeps everything readable', () => {
  const lay = table.layoutWidths({ cust: 300 }, { available: 1652 });
  assert.equal(lay.cols.cust, 300);
  assert.equal(lay.flex.cust, undefined, 'a dragged flex column no longer flexes');
  assert.equal(lay.total, 1652);
  const ipad = table.layoutWidths({}, { available: 1000, hidden: ['status'] });
  assert.equal(ipad.cols.status, 0);
  assert.equal(table.layoutWidths({}, { available: 500 }).total, table.layoutWidths({}).min, 'too narrow: base widths, the table scrolls');
});

test('storage key v2: r462-era (v1) saved widths do not hide the new defaults; v2 widths apply; Reset clears them', () => {
  const s = memoryStorage();
  s.setItem('pdc.vehicle-locations-columns.v1:user-a', JSON.stringify({ key: 52, stock: 127, cust: 144 }));
  assert.deepEqual(table.readWidths(s, 'user-a'), {}, 'v1 widths are ignored');
  assert.equal(table.writeWidths(s, 'user-a', { ploc: 90 }), true);
  assert.deepEqual(table.readWidths(s, 'user-a'), { ploc: 90 });
  assert.equal(table.resetWidths(s, 'user-a'), true);
  assert.deepEqual(table.readWidths(s, 'user-a'), {});
  assert.equal(s.store.has('pdc.vehicle-locations-columns.v1:user-a'), true, 'v1 left untouched, so an undo brings it back');
});

test('CSS: defaults, flex fallbacks, station label size, wrapping narrow headings; nothing hides a column or recolours a cell', () => {
  const sheet = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  for (const k of FIXED) assert.match(sheet, new RegExp(`col\\.c-${k} \\{ width: var\\(--vlt-w-${k}, ${C[k].width}px\\); \\}`));
  for (const k of FLEX) assert.match(sheet, new RegExp(`col\\.c-${k} \\{ width: var\\(--vlt-w-${k}, var\\(--vlt-flex-${k}, ${C[k].width}px\\)\\); \\}`));
  assert.match(sheet, /col\.c-sel \{ width: var\(--vlt-w-sel, 0px\); \}/);
  assert.match(sheet, /pdc-grid-stations-heading > \* > span \{ font-size: 7\.5px !important;/);
  assert.match(sheet, /pdc-grid-station-parts > span::after \{ display: inline !important;/);
  assert.match(sheet, /th\.c-ploc \.incoming-sort-heading, \.vlt-table th\.c-age \.incoming-sort-heading, \.vlt-table th\.c-job \.incoming-sort-heading \{ white-space: normal;/);
  const rules = [...sheet.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => [m[1].trim(), m[2]]);
  const r476 = rules.filter(([sel]) => /col\.c-|has-select|pdc-grid-station|th\.c-ploc/.test(sel));
  assert.ok(r476.length >= 10);
  for (const [sel, body] of r476) assert.doesNotMatch(body, /(^|[;\s])(color|background(-color)?|border-color|content)\s*:/, `${sel}: r476 rules change size and spacing only`);
});

test('loader, docs: cache-bust r476 on the table module and on canonical-entry.js; FAULT_LOG F89', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-vehicle-locations-table\.js\?vehicle-locations-table=2026\.10\.22\.r461&r462=2026\.10\.22\.r462&r463=2026\.10\.22\.r463&r476=2026\.10\.22\.r476/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r476=2026\.10\.22\.r476/);
  const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  assert.match(log, /^\| F89 \|.*r476.*pdc\.vehicle-locations-columns\.v2/m);
  assert.match(fs.readFileSync('docs/vehicle-locations-table-view.md', 'utf8'), /r476 \(F89\)/);
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.doesNotMatch(src.slice(src.indexOf('r476 (F89)')), /\b1[0-9]{7}\b/, 'no stock numbers');
});
