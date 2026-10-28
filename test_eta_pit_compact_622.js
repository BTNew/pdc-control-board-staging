'use strict';
// r622 (F237, Craig 28 Oct 2026): Parts ETA and Pit cells on Vehicle Locations show only "dd/mm · N days", same size.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs');
const eta = require('./pdc-parts-eta.js');
const table = require('./pdc-vehicle-locations-table.js');
const css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');

test('Parts ETA cell drops the part count; the hover keeps the detail', () => {
  const entry = { latest_eta: '2026-12-14', count: 3, parts: [{ part: 'Towbar', eta_date: '2026-12-14' }, { part: 'Tank', eta_date: '2026-12-10' }, { part: 'Lights', eta_date: '2026-12-01' }] };
  const chip = eta.chipHtml(eta.summarise(entry, '2026-12-05'));
  assert.match(chip, /3 parts/, 'the chip itself still carries the count elsewhere');
  const card = `<div class="incoming-vehicle-card"><span class="pdc-parts-eta-wrap">${chip}</span></div>`;
  const lifted = table.extractPartsEta(card);
  const shown = (lifted.span || '').replace(/ · \d+ parts(?=<\/span>)/, '');
  assert.match(shown, /14\/12 · 9 days<\/span>$/);
  assert.match(shown, /title="[^"]*Towbar/);
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(src, /replace\(\/ · \\d\+ parts\(\?=<\\\/span>\)\/, ''\)/, 'table strips the count');
});

test('Pit and Parts ETA columns are the same width; extras hidden in the ETA cell', () => {
  assert.equal(table.COLUMNS.pit.width, table.COLUMNS.eta.width);
  assert.match(css, /col\.c-pit \{ width: var\(--vlt-w-pit, 96px\)/);
  assert.match(css, /td\.c-eta \.pdc-parts-stoppage-note, \.vlt-table td\.c-eta \.pdc-parts-stoppage-email, \.vlt-table td\.c-eta \.pdc-parts-stoppage-placed \{ display: none; \}/);
  assert.doesNotMatch(css, /td\.c-eta:has\(\.pdc-parts-stoppage-slot\) \{ height: auto/, 'no growing ETA row');
});
