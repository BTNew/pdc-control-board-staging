'use strict';
// r630 (F245): dropping on the pit calendar asks the time (07:00 to 17:00, half hours) and the place, then saves.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const pit = require('./pdc-pit-bookings.js');

const board = pit.indexBoard({ today: '2026-10-28', can_edit: true, vehicles: [
  { vehicle_id: 'a1', stock_number: '111', key_number: 504, vehicle: 'Coaster', needs_pit: true, pit_date: '2026-10-30', pit_time: '13:00', pit_location: 'Wades', booking_version: 2 },
  { vehicle_id: 'b2', stock_number: '222', key_number: 505, vehicle: 'HiLux', needs_pit: true, pit_date: '2026-10-30', pit_time: '07:30', pit_location: 'PMB', booking_version: 1 },
  { vehicle_id: 'c3', stock_number: '333', key_number: 506, vehicle: 'Prado', needs_pit: true, pit_date: '2026-10-30', pit_location: 'Wangara', booking_version: 1 },
] });

test('time slots: 07:00 to 17:00 every half hour', () => {
  assert.equal(pit.TIME_SLOTS.length, 21);
  assert.equal(pit.TIME_SLOTS[0], '07:00');
  assert.equal(pit.TIME_SLOTS[1], '07:30');
  assert.equal(pit.TIME_SLOTS.at(-1), '17:00');
  assert.equal(pit.timeLabel('07:30'), '7:30am');
  assert.equal(pit.timeLabel('13:00:00'), '1:00pm');
  assert.equal(pit.timeLabel('12:00'), '12:00pm');
});

test('box: time list and the three places, picked values selected', () => {
  const html = pit.dialogHtml({ entry: board.byKey.get('a1'), date: '2026-10-31', time: '13:00', place: 'Wades', booked: true });
  assert.match(html, /Pit booking · Sat 31 Oct/);
  assert.match(html, /Key 504 · 111 · Coaster/);
  assert.equal((html.match(/data-pit-time="/g) || []).length, 21);
  assert.match(html, /data-pit-time="13:00" aria-selected="true">1:00pm/);
  assert.match(html, /data-pit-dlg-place="Wades" aria-checked="true"/);
  assert.match(html, /data-pit-dlg-remove/);
  const fresh = pit.dialogHtml({ entry: board.byKey.get('b2'), date: '2026-11-02', time: '', place: '' });
  assert.match(fresh, /Book pit · Mon 2 Nov/);
  assert.match(fresh, /data-pit-time="07:00" aria-selected="true"/);
  assert.match(fresh, /data-pit-dlg-place="PMB" aria-checked="true"/);
  assert.doesNotMatch(fresh, /data-pit-dlg-remove/);
});

test('calendar: one calendar, chips in time order with the time shown; untimed last', () => {
  const html = pit.panelHtml(board, { filter: 'all', month: '2026-10-01' });
  const day = html.split('data-pit-day="2026-10-30"')[1].split('data-pit-day="2026-10-31"')[0];
  const order = [...day.matchAll(/K(50\d)/g)].map(m => m[1]);
  assert.deepEqual(order, ['505', '504', '506']);
  assert.match(day, /<b>07:30<\/b> K505 · PMB/);
  assert.match(day, /data-pit-edit="a1"/);
  assert.doesNotMatch(html, /Drop books at/);
});

test('Pit cell hover names the time', () => {
  assert.match(pit.cellHtml(board.byKey.get('a1'), board.today), /title="[^"]*1:00pm\. Wades\./);
});

test('wiring: writes go to set_pdc_pit_booking_630; drop and Done open the box; SQL is staging-only, pins 241, undo exists', () => {
  const src = fs.readFileSync('pdc-pit-bookings.js', 'utf8');
  assert.match(src, /rpc\('set_pdc_pit_booking_630', \{ p_vehicle_id: vehicleId, p_pit_date: next\.date, p_pit_time:/);
  assert.doesNotMatch(src, /rpc\('set_pdc_pit_booking_604'/);
  assert.match(src, /openDialog\(vid, \{ date: day\.dataset\.pitDay \}\)/);
  assert.match(src, /openDialog\(c\.dataset\.pitBack, \{ date: board\.today, back: true/);
  assert.match(src, /addEventListener\('wheel'/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-pit-bookings\.js\?[^']*&r630=2026\.10\.28\.r630'/);
  const sql = fs.readFileSync('supabase/migrations/20261028220000_r630_pit_time.sql', 'utf8');
  assert.match(sql, /r630: staging only/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.match(sql, /'pit_time_630', 'F245'/);
  assert.match(sql, /true, 383, 'r630'\)/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261028220000_r630_pit_time.down.sql'));
});
