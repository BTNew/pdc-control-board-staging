'use strict';
// r632 (F247): Welshpool is a pit place and pit times step by 15 minutes.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const pit = require('./pdc-pit-bookings.js');

test('Welshpool is the 4th place, in the box and the legend', () => {
  assert.deepEqual([...pit.PLACES], ['PMB', 'Wangara', 'Wades', 'Welshpool']);
  const html = pit.dialogHtml({ entry: { stock_number: '1' }, date: '2026-10-30', time: '09:15', place: 'Welshpool' });
  assert.match(html, /data-pit-dlg-place="Welshpool" aria-checked="true"/);
  assert.match(html, /data-pit-time="09:15" aria-selected="true">9:15am/);
  assert.match(html, /1 2 3 4 for the place/);
});

test('quarter-hour times and labels', () => {
  assert.ok(pit.TIME_SLOTS.includes('09:45'));
  assert.equal(pit.timeLabel('09:45'), '9:45am');
});

test('SQL: staging only, guarded on r630 bodies, widens checks, pins 241, undo exists', () => {
  const sql = fs.readFileSync('supabase/migrations/20261028230000_r632_pit_welshpool_quarter.sql', 'utf8');
  assert.match(sql, /r632: staging only/);
  assert.match(sql, /r632: pit objects changed since r630/);
  assert.match(sql, /'Wades'::text, 'Welshpool'::text/);
  assert.match(sql, /IN \(0, 15, 30, 45\)/);
  assert.match(sql, /true, 385, 'r632'\)/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-pit-bookings\.js\?[^']*&r632=2026\.10\.28\.r632(?:&r753=2026\.10\.30\.r753)?'/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261028230000_r632_pit_welshpool_quarter.down.sql'));
});
