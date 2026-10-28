'use strict';
// r604 (F218): pit bookings list, calendar and Pit column. Pure helpers only; no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const pit = require('./pdc-pit-bookings.js');

const board = pit.indexBoard({
  today: '2026-10-28', can_edit: true,
  vehicles: [
    { vehicle_id: 'a1', stock_number: '13073300', key_number: 307, vehicle: 'HiLux', location: 'PMB', pit_lines: ['PIT AND WEIGH'], needs_pit: true, pit_date: null, pit_location: null, back: false, booking_version: 0 },
    { vehicle_id: 'b2', stock_number: 's-200', key_number: 360, vehicle: 'Coaster', location: 'YH', pit_lines: ['Pit Inspection'], needs_pit: true, pit_date: '2026-10-31', pit_location: 'Wangara', back: false, booking_version: 1 },
    { vehicle_id: 'c3', stock_number: '300', key_number: 361, vehicle: 'LC79', location: 'PIT', pit_lines: ['PIT & WEIGH'], needs_pit: true, pit_date: '2026-10-26', pit_location: 'Wades', back: false, booking_version: 2 },
    { vehicle_id: 'd4', stock_number: '400', key_number: 362, vehicle: 'Prado', location: 'PMB', pit_lines: ['PIT AND WEIGH'], needs_pit: true, pit_date: '2026-10-20', pit_location: 'PMB', back: true, back_at: '2026-10-22T03:00:00Z', booking_version: 3 },
  ],
});

test('day counter: days to go, today, and days past', () => {
  assert.equal(pit.daysUntil('2026-10-31', '2026-10-28'), 3);
  assert.equal(pit.daysUntil('2026-10-28', '2026-10-28'), 0);
  assert.equal(pit.daysUntil('2026-10-26', '2026-10-28'), -2);
  assert.equal(pit.counterText(3), 'in 3d');
  assert.equal(pit.counterText(0), 'today');
  assert.equal(pit.counterText(-2), '+2d');
  assert.equal(pit.daysUntil('', '2026-10-28'), null);
});

test('index by vehicle id and stock (case-insensitive), as the table row key is the stock number', () => {
  assert.equal(board.byKey.get('a1').stock_number, '13073300');
  assert.equal(board.byKey.get('S-200').vehicle_id, 'b2');
  assert.equal(board.canEdit, true);
});

test('Pit cell: dash when not booked, date + place + counter when booked, green tick when back', () => {
  assert.match(pit.cellHtml(board.byKey.get('a1'), board.today), /vlt-subtle-dash[^>]*Needs pitting/);
  const booked = pit.cellHtml(board.byKey.get('b2'), board.today);
  assert.match(booked, /Sat 31 Oct · Wangara/);
  assert.match(booked, /<b class="pdc-pit-count">in 3d<\/b>/);
  assert.doesNotMatch(booked, /is-back/);
  assert.match(pit.cellHtml(board.byKey.get('c3'), board.today), /is-over[\s\S]*\+2d/);
  const back = pit.cellHtml(board.byKey.get('d4'), board.today);
  assert.match(back, /pdc-pit-chip is-back/);
  assert.match(back, /✓/);
  assert.doesNotMatch(back, /pdc-pit-count/, 'no counter once it is back');
  assert.match(pit.cellHtml(undefined, board.today), /No pit booked/);
});

test('filters: not booked, booked, back, all', () => {
  assert.deepEqual(pit.filterVehicles(board.vehicles, 'open').map(v => v.vehicle_id), ['a1']);
  assert.deepEqual(pit.filterVehicles(board.vehicles, 'booked').map(v => v.vehicle_id), ['b2', 'c3']);
  assert.deepEqual(pit.filterVehicles(board.vehicles, 'back').map(v => v.vehicle_id), ['d4']);
  assert.equal(pit.filterVehicles(board.vehicles, 'all').length, 4);
});

test('r611 (F225): vehicles without a key number are not listed', () => {
  const noKey = pit.indexBoard({ today: '2026-10-28', can_edit: true, vehicles: [...board.vehicles, { vehicle_id: 'z9', stock_number: 'NOKEY', key_number: null, needs_pit: true }, { vehicle_id: 'z8', stock_number: 'ZERO', key_number: '0', needs_pit: true }] });
  assert.equal(pit.filterVehicles(noKey.vehicles, 'all').length, 4);
  assert.doesNotMatch(pit.panelHtml(noKey, { filter: 'all' }), /NOKEY|ZERO/);
});

test('calendar: Monday-first whole weeks covering the month; month stepping wraps the year', () => {
  const days = pit.monthGrid('2026-10-01');
  assert.equal(days.length % 7, 0);
  assert.equal(days[0].iso, '2026-09-28');
  assert.equal(days.at(-1).iso, '2026-11-01');
  assert.equal(days.filter(d => d.inMonth).length, 31);
  assert.equal(pit.shiftMonth('2026-12-01', 1), '2027-01-01');
  assert.equal(pit.shiftMonth('2026-01-01', -1), '2025-12-01');
});

test('panel: list rows drag, booked chips sit on their day, places are PMB / Wangara / Wades only', () => {
  const html = pit.panelHtml(board, { filter: 'all', month: '2026-10-01', place: 'Wades' });
  assert.match(html, /data-pdc-pit-panel/);
  assert.equal((html.match(/<tr class="pdc-pit-row/g) || []).length, 4);
  assert.match(html, /data-pit-day="2026-10-31"[^>]*>[\s\S]*?K360 · Wangara/);
  assert.match(html, /data-pit-place="Wades"[^>]*>Wades|aria-checked="true" class="active" data-pit-place="Wades"/);
  assert.deepEqual([...pit.PLACES], ['PMB', 'Wangara', 'Wades']);
  assert.match(html, /data-pit-back="d4" checked/);
  assert.match(html, /data-pit-back="a1"/, 'r611 (F225): unbooked vehicles have a Done tick too');
  assert.match(html, /> Done<\/label>/);
  const readOnly = pit.panelHtml({ ...board, canEdit: false }, { filter: 'all', month: '2026-10-01' });
  assert.doesNotMatch(readOnly, /draggable="true"|data-pit-day=|data-pit-clear/);
  assert.match(readOnly, /View only/);
});

test('wiring: loader, cache bust, Pages ships the file, migration is staging-only and keeps pins at 241', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-pit-bookings\.js\?r604=2026\.10\.28\.r604&r611=2026\.10\.28\.r611&r607=2026\.10\.28\.r607/);
  assert.match(fs.readFileSync('pdc-pit-bookings.js', 'utf8'), /PDC_AUTH_CONTEXT\?\.role === 'fitter'/, 'fitters do not call the pit read');
  assert.match(entry, /pdc-vehicle-locations-table\.js\?[^']*&r604=2026\.10\.28\.r604/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r604=2026\.10\.28\.r604/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-pit-bookings\.js'/);
  const table = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(table, /td\('c-pit', pitCell\),\n\s+td\('c-eta', etaCell\)/, 'Pit sits left of Parts ETA');
  assert.match(table, /PDC_PIT_BOOKINGS\?\.afterRender\?\.\(host, \{ bucket: state\.bucket \}\)/);
  const sql = fs.readFileSync('supabase/migrations/20261028130000_r604_pit_bookings.sql', 'utf8');
  assert.match(sql, /project_ref = 'cdsmnqxtyyoeoznmbidd'/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.match(sql, /CHECK \(pit_location IN \('PMB', 'Wangara', 'Wades'\)\)/);
  assert.match(sql, /!~\* '\\mno\\s\+pit'/, '"NO PIT..." lines do not count');
  assert.doesNotMatch(sql, /vjdtsswhroyguxyfjdkt'\s*(THEN|AND|=)/, 'production is never a target');
  assert.ok(fs.existsSync('supabase/rollbacks/20261028130000_r604_pit_bookings.down.sql'));
});
