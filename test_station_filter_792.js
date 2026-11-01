/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r792 (Craig 1 Nov 2026): station headings cycle red (needs) -> green (complete) -> off, and several combine.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');

const defs = [{ key: 'fab', label: 'Fab' }, { key: 'electrical', label: 'Electrical' }, { key: 'tint', label: 'Tint' }];
const deps = {
  pdcJobDefsPartsFirst: () => defs,
  pdcJobRequired: (v, def) => (v.req || []).includes(def.key),
  pdcJobComplete: (v, def) => (v.done || []).includes(def.key),
};

test('r792: click cycle is red, green, off', () => {
  assert.equal(table.nextStationMode(''), 'need');
  assert.equal(table.nextStationMode(undefined), 'need');
  assert.equal(table.nextStationMode('need'), 'done');
  assert.equal(table.nextStationMode('done'), '');
});

test('r792/r795: green = shows a green tick; grey (not required, not done) is not green', () => {
  assert.equal(table.stationDone({ req: ['fab'], done: ['fab'] }, 'fab', deps), true);
  assert.equal(table.stationDone({ req: ['fab'] }, 'fab', deps), false);
  assert.equal(table.stationDone({ req: [] }, 'fab', deps), false);
});

test('r795: every line ticked counts as complete for red and green, like the tick', () => {
  const d = { ...deps, pdcStationLinesMakeComplete: (v, def) => (v.lines || []).includes(def.key) };
  const car = { req: ['electrical'], lines: ['electrical'] };
  assert.equal(table.stationNeeds(car, 'electrical', d), false);
  assert.equal(table.stationDone(car, 'electrical', d), true);
  assert.equal(table.stationNeeds({ req: ['electrical'] }, 'electrical', d), true);
});

test('r792: headings combine: done everywhere except Fab', () => {
  const f = { electrical: 'done', tint: 'done', fab: 'need' };
  const onlyFab = { req: ['fab', 'electrical', 'tint'], done: ['electrical', 'tint'] };
  const elecToo = { req: ['fab', 'electrical', 'tint'], done: ['tint'] };
  const fabDone = { req: ['fab', 'electrical', 'tint'], done: ['fab', 'electrical', 'tint'] };
  assert.equal(table.stationFilterMatch(onlyFab, f, deps), true);
  assert.equal(table.stationFilterMatch(elecToo, f, deps), false);
  assert.equal(table.stationFilterMatch(fabDone, f, deps), false);
  assert.equal(table.stationFilterMatch(elecToo, {}, deps), true);
});

test('r792: wired into headings, note, clear and cache-bust', () => {
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(src, /stationFilterMatch\(vehicle, state\.stations\)/);
  assert.match(src, /classList\.toggle\('vlt-station-done', mode === 'done'\)/);
  assert.match(src, /state\.stations = \{\}; renderTable\(\)/);
  assert.match(src, /r792=2026\.11\.01\.r792(&r795=2026\.11\.01\.r795)?(&r799=2026\.11\.01\.r799)?`/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /r792=2026\.11\.01\.r792(&r795=2026\.11\.01\.r795)?(&r799=2026\.11\.01\.r799)?'/);
  assert.match(fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8'), /vlt-station-done/);
});
