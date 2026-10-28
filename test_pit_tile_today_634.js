'use strict';
// r634 (F249): the PIT tile number is the pits booked for today and not ticked Done.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const pit = require('./pdc-pit-bookings.js');

test('counts today only, not Done, keyed vehicles only', () => {
  const v = [
    { vehicle_id: 'a', key_number: 1, pit_date: '2026-10-30' },
    { vehicle_id: 'b', key_number: 2, pit_date: '2026-10-30' },
    { vehicle_id: 'c', key_number: 3, pit_date: '2026-10-30', back: true },
    { vehicle_id: 'd', key_number: null, pit_date: '2026-10-30' },
    { vehicle_id: 'e', key_number: 5, pit_date: '2026-10-31' },
    { vehicle_id: 'f', key_number: 6 },
  ];
  assert.equal(pit.todayCount(v, '2026-10-30'), 2);
  assert.equal(pit.todayCount(v, '2026-10-28'), 0);
  assert.equal(pit.todayCount(v, ''), 0);
});

test('table: PIT tile uses the pit count; caption says pits booked today', () => {
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(src, /key === 'pit' \? pitTodayCount\(\) : counts\.get\(key\) \|\| 0/);
  assert.match(src, /pit: \['PIT', 'Pits booked today', 'production', 'PIT'\]/);
  assert.match(fs.readFileSync('pdc-pit-bookings.js', 'utf8'), /todayCount: \(\) => todayCount\(board\.vehicles, board\.today\)/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-pit-bookings\.js\?[^']*&r634=2026\.10\.28\.r634'/);
  assert.match(entry, /pdc-vehicle-locations-table\.js\?[^']*&r634=2026\.10\.28\.r634'/);
});
