'use strict';
// r618 (F233): the pit list and calendar show on the PIT tile only, and the Vehicle Locations search boxes search them.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const pit = require('./pdc-pit-bookings.js');

const board = pit.indexBoard({ today: '2026-10-28', can_edit: true, vehicles: [
  { vehicle_id: 'a1', stock_number: '13000608', key_number: 329, job_card_number: 'J139125361', vehicle: 'HiLux WorkMate', location: 'PMB', pit_lines: ['PIT AND WEIGH'], needs_pit: true },
  { vehicle_id: 'b2', stock_number: '12328823', key_number: 504, job_card_number: 'J138000795', vehicle: 'Coaster Deluxe', location: 'PMB', pit_lines: ['PIT AND WEIGH'], needs_pit: true, pit_date: '2026-10-30', pit_location: 'Wades' },
  { vehicle_id: 'c3', stock_number: '13001553', key_number: '0430', vehicle: 'HiLux SR', location: 'QC', pit_lines: ['PIT AND WEIGH'], needs_pit: true },
] });
const ids = list => list.map(v => v.vehicle_id);

test('key number is exact, leading zeros ignored', () => {
  assert.deepEqual(ids(pit.filterVehicles(board.vehicles, 'all', { key: '329', text: '' })), ['a1']);
  assert.deepEqual(ids(pit.filterVehicles(board.vehicles, 'all', { key: '430', text: '' })), ['c3']);
  assert.deepEqual(ids(pit.filterVehicles(board.vehicles, 'all', { key: '32', text: '' })), []);
});

test('stock, job card and vehicle text search', () => {
  assert.deepEqual(ids(pit.filterVehicles(board.vehicles, 'all', { key: '', text: '12328823' })), ['b2']);
  assert.deepEqual(ids(pit.filterVehicles(board.vehicles, 'all', { key: '', text: 'j139125361' })), ['a1']);
  assert.deepEqual(ids(pit.filterVehicles(board.vehicles, 'all', { key: '', text: 'coaster' })), ['b2']);
  assert.equal(pit.filterVehicles(board.vehicles, 'all', { key: '', text: 'h' }).length, 3, 'one letter does not search');
});

test('panel: counts, rows and calendar follow the search', () => {
  const html = pit.panelHtml(board, { filter: 'all', search: { key: '504', text: '' } });
  assert.match(html, /Search: key 504 · 1 match/);
  assert.match(html, /All <b>1<\/b>/);
  assert.doesNotMatch(html, /13000608|13001553/);
  assert.match(html, /K504 · Wades/);
  const none = pit.panelHtml(board, { filter: 'open', search: { key: '504', text: '' } });
  assert.match(none, /No pit vehicle matches your search under Not booked. Try All/);
  assert.doesNotMatch(pit.panelHtml(board, { filter: 'all' }), /pdc-pit-search/);
});

test('table: the panel is asked for only on the PIT tile, and PIT stays the tile while searching from it', () => {
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(src, /afterRender\?\.\(host, \{ bucket: !scope\.stoppages && scope\.bucket === 'pit' \? 'pit' : '', search: scope\.searching \? searchCriteria : null \}\)/);
  assert.match(src, /if \(held === 'pit'\) return \{ searching: true, bucket: 'pit'/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-pit-bookings\.js\?[^']*&r618=2026\.10\.28\.r618(?:&r622=2026\.10\.28\.r622)?(?:&r630=2026\.10\.28\.r630)?(?:&r632=2026\.10\.28\.r632)?'/);
  assert.match(fs.readFileSync('pdc-pit-bookings.js', 'utf8'), /if \(bucket !== 'pit'\) return;/);
});
