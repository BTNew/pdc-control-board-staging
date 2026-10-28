'use strict';
// r612 (F226): Completed Vehicles shows every vehicle that has been at PMB, including vehicles taken off the
// board because they dropped off an upload. Pure rendering only; no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vh = require('./pdc-vehicle-history.js');

const list = { vehicles: [
  { id: 'a', stock: '13073300', key: '307', job_card: 'J138000001', customer: 'Fleet A', vehicle: 'HiLux', status: 'removed', removed_at: '2026-10-20T02:00:00Z', removed_reason: 'r569: absent from the latest as-a-Whole sheet', imported_at: '2026-10-01T02:00:00Z', to_pmb: '2026-10-02', lines: 10, lines_done: 7, actual_hours: 5.5, booked_hours: 6, stations: ['Hoist', 'Elec'], pit_date: '2026-10-15', pit_location: 'Wangara', pit_back: true },
  { id: 'b', stock: '13094080', status: 'completed', collected_at: '2026-10-25T02:00:00Z', lines: 4, lines_done: 4, stations: [] },
  { id: 'c', stock: 'S-DEL', status: 'deleted', removed_reason: 'Old Jobcard', lines: 0, stations: [] },
  { id: 'd', stock: 'S-NOW', status: 'on_board', lines: 3, lines_done: 0, stations: [] },
  { id: 'e', stock: 'S-RFT', status: 'rft', lines: 2, lines_done: 2, stations: [] },
] };

test('tabs: Left the board (default) holds completed, RFT, off-upload and deleted; on-board is separate', () => {
  assert.deepEqual(vh.filterRows(list.vehicles, { tab: 'left' }).map(v => v.id), ['a', 'b', 'c', 'e']);
  assert.deepEqual(vh.filterRows(list.vehicles, { tab: 'removed' }).map(v => v.id), ['a']);
  assert.deepEqual(vh.filterRows(list.vehicles, { tab: 'on_board' }).map(v => v.id), ['d']);
  assert.equal(vh.filterRows(list.vehicles, { tab: 'all' }).length, 5);
  assert.deepEqual(vh.tabCounts(list.vehicles), { left: 4, completed: 2, removed: 1, deleted: 1, on_board: 1, all: 5 });
});

test('search covers stock, key, customer, stations and status', () => {
  assert.deepEqual(vh.filterRows(list.vehicles, { tab: 'all', search: 'wangara' }).map(v => v.id), ['a']);
  assert.deepEqual(vh.filterRows(list.vehicles, { tab: 'all', search: 'elec' }).map(v => v.id), ['a']);
  assert.deepEqual(vh.filterRows(list.vehicles, { tab: 'all', search: 'off upload' }).map(v => v.id), ['a']);
});

test('row: removed vehicle shows why it left, lines done, bay time and a green pit tick', () => {
  const html = vh.tableHtml(list, { tab: 'removed' });
  assert.match(html, /vh-status is-removed" title="r569: absent/);
  assert.match(html, /7\/10/);
  assert.match(html, /5\.5 h <small>of 6\.0 h<\/small>/);
  assert.match(html, /vh-pit is-back">15\/10\/26 Wangara ✓/);
  assert.match(html, /Hoist, Elec/);
  assert.match(html, /Off upload <b>1<\/b>/);
});

test('detail: milestones, every line with who ticked it, bay bookings with worked time, pit and board history', () => {
  const html = vh.detailHtml({
    stock: '13073300', vehicle: 'HiLux', vin: 'VIN1', imported_at: '2026-10-01T02:00:00Z', qc_done_at: '2026-10-10T02:00:00Z', removed_at: '2026-10-20T02:00:00Z', removed_reason: 'r569: absent',
    lines: [{ ro: 'J138000001', line: 1, description: 'PIT AND WEIGH', station: 'FITTING', hours: 1, done: true, done_at: '2026-10-09T02:00:00Z', done_by: 'qc@x', pit: true },
            { ro: 'J138000001', line: 2, description: 'Fit bullbar', station: 'FITTING', hours: 3, done: false }],
    bookings: [{ station: 'Fitting', bay: 'Fitting Bay 1', technician: 'Ben', status: 'completed', start: '2026-10-05T00:00:00Z', end: '2026-10-05T04:00:00Z', actual_start: '2026-10-05T00:10:00Z', actual_end: '2026-10-05T03:40:00Z', actual_minutes: 210, line_timings: [{ technician: 'Ben', minutes: 95 }] }],
    pit: { date: '2026-10-15', location: 'Wangara', back: true, back_at: '2026-10-16T02:00:00Z', back_by: 'craig@x' },
    events: [{ at: '2026-10-20T02:00:00Z', what: 'Removed from board: no longer on the Service as a Whole upload', by: 'x' }],
  });
  assert.match(html, /Left the board: r569: absent/);
  assert.match(html, /<dt>QC done<\/dt>/);
  assert.match(html, /1 of 2 lines ticked/);
  assert.match(html, /is-done is-pit[\s\S]*PIT AND WEIGH[\s\S]*qc@x/);
  assert.match(html, /Fitting Bay 1[\s\S]*3h 30m[\s\S]*Ben 1h 35m/);
  assert.match(html, /Pit booked<\/strong> 15\/10\/26 at Wangara[\s\S]*✓ Back/);
  assert.match(html, /Removed from board: no longer on the Service as a Whole upload/);
  assert.match(vh.detailHtml({ lines: [], bookings: [], events: [] }), /Never booked into a bay/);
});

test('wiring: loads after app.js, Pages ships it, reads only, staging only', () => {
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-history\.js\?r612=2026\.10\.28\.r612/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r612=2026\.10\.28\.r612/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-vehicle-history\.js'/);
  const js = fs.readFileSync('pdc-vehicle-history.js', 'utf8');
  assert.deepEqual([...new Set([...js.matchAll(/rpc\('([a-z0-9_]+)'/g)].map(m => m[1]))], ['get_pdc_vehicle_history_612', 'get_pdc_vehicle_history_detail_612']);
  const sql = fs.readFileSync('supabase/migrations/20261028160000_r612_vehicle_history.sql', 'utf8');
  assert.equal((sql.match(/STABLE SECURITY DEFINER/g) || []).length, 2);
  assert.doesNotMatch(sql, /\b(INSERT INTO public|UPDATE public|DELETE FROM public)\b/);
  assert.match(sql, /expected_function_md5\) <> 241/);
});
