/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r685 (F295, Craig 29 Oct 2026): click a station heading on Vehicle Locations to show only vehicles that need it.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');

const defs = [{ key: 'tint', label: 'Tint' }, { key: 'electrical', label: 'Electrical' }];
const deps = {
  pdcJobDefsPartsFirst: () => defs,
  pdcGridJobLabel: def => ({ electrical: 'Elec' }[def.key] || def.label),
  pdcJobRequired: (v, def) => (v.req || []).includes(def.key),
  pdcJobComplete: (v, def) => (v.done || []).includes(def.key),
};

test('r685: needs = required and not complete', () => {
  assert.equal(table.stationNeeds({ req: ['electrical'] }, 'electrical', deps), true);
  assert.equal(table.stationNeeds({ req: ['electrical'], done: ['electrical'] }, 'electrical', deps), false);
  assert.equal(table.stationNeeds({ req: [] }, 'electrical', deps), false);
  assert.equal(table.stationNeeds({ req: [] }, '', deps), true);
  assert.equal(table.stationNeeds({ req: [] }, 'unknown', deps), true);
});

test('r685: wired into tiles, headings, clear button and cache-bust', () => {
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(src, /const stationRows = stationOn \? filteredRows\.filter/); // r792: red/green/off per heading
  assert.match(src, /const entries = stationRows\.flatMap/);
  assert.match(src, /data-vlt-station-clear/);
  assert.match(src, /heading\.dataset\.vltStation = key/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /r685=2026\.10\.29\.r685/);
  assert.match(fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8'), /vlt-station-active/);
});
