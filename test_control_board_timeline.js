'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { performance } = require('node:perf_hooks');
const overview = require('./control-board-overview.js');
const fixture = require('./qa/control-board-fixtures.js');

const calendar = overrides => ({
  day_start_time: '07:00', day_end_time: '17:00',
  working_week: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'],
  closures: [], overtime_windows: [],
  break_windows: [
    { scope: 'saturday', start: '07:00', end: '08:00' },
    { scope: 'saturday', start: '12:00', end: '17:00' },
  ],
  ...overrides,
});
const stamp = (date, clock) => `${date}T${clock}:00+08:00`;
function snapshot(overrides = {}) {
  const value = fixture.emptySnapshot();
  value.board.calendar = calendar(overrides);
  return value;
}
function addBooking(value, id, start, end, overrides = {}) {
  const bay = value.board.bays[0];
  const row = fixture.booking(id, bay, undefined, { scheduled_start_at: start, scheduled_end_at: end, ...overrides });
  value.board.bookings.push(row);
  return row;
}
function timeline(value, options = {}) {
  return overview.buildTimeline(overview.buildModel(value), { startDate: '2026-09-18', dayCount: 4, now: stamp('2026-09-18', '07:00'), ...options });
}
const segments = result => result.rows.flatMap(row => row.segments);
const forBooking = (result, id) => segments(result).filter(segment => segment.item.id === id);
const windows = day => day.windows.map(window => [window.start, window.end]);
const shape = value => value.map(segment => {
  const midnight = Date.parse(stamp(segment.date, '00:00'));
  return [segment.date, (segment.start - midnight) / 60000, (segment.end - midnight) / 60000];
});
const duration = value => value.reduce((minutes, segment) => minutes + (segment.end - segment.start) / 60000, 0);
const itemId = entry => (entry.item || entry).id;

test('timeline keeps all 43 physical bays in department order, including empty and inactive bays', () => {
  const value = snapshot();
  value.board.bays[12].is_active = false;
  const model = overview.buildModel(value);
  const result = timeline(value);
  assert.equal(result.rows.length, 43);
  assert.deepEqual(result.rows.map(row => row.bay.bay_id), model.columns.map(column => column.bay.bay_id));
  assert.equal(result.rows[12].bay.is_active, false);
  assert.equal(segments(result).length, 0);
});

test('calendar renders weekday hours, Saturday 08–12 and a closed Sunday on successive dates', () => {
  const result = timeline(snapshot());
  assert.deepEqual(result.days.map(day => day.date), ['2026-09-18', '2026-09-19', '2026-09-20', '2026-09-21']);
  assert.deepEqual(result.days.map(windows), [[[420, 1020]], [[480, 720]], [], [[420, 1020]]]);
  assert.equal(result.days[0].startMs, Date.parse(stamp('2026-09-18', '00:00')));
});

test('six-hour Friday booking continues through Saturday and Monday without claiming Sunday work', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, stamp('2026-09-18', '16:00'), stamp('2026-09-21', '08:00'));
  const parts = forBooking(timeline(value), booking.booking_id);
  assert.deepEqual(shape(parts), [['2026-09-18', 960, 1020], ['2026-09-19', 480, 720], ['2026-09-21', 420, 480]]);
  assert.equal(duration(parts), 360);
  assert.ok(parts.every(part => part.item.source === booking));
});

test('Saturday exact closing boundary has no Monday continuation and no artificial padding', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, stamp('2026-09-19', '08:00'), stamp('2026-09-19', '12:00'));
  assert.deepEqual(shape(forBooking(timeline(value), booking.booking_id)), [['2026-09-19', 480, 720]]);
});

test('Saturday chip geometry uses the same hour scale as weekdays and stays within its day', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, stamp('2026-09-19', '08:00'), stamp('2026-09-19', '12:00'));
  const result = timeline(value);
  const part = forBooking(result, booking.booking_id)[0];
  const pixelsPerMinute = result.dayWidth / (result.axisEnd - result.axisStart);
  assert.equal(part.left, result.dayWidth + (480 - result.axisStart) * pixelsPerMinute);
  assert.equal(part.width, 240 * pixelsPerMinute);
  assert.ok(part.left + part.width <= 2 * result.dayWidth);
});

test('one minute beyond the Saturday allocation ends at Monday 07:01 exactly', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, stamp('2026-09-19', '08:00'), stamp('2026-09-21', '07:01'));
  const parts = forBooking(timeline(value), booking.booking_id);
  assert.deepEqual(shape(parts), [['2026-09-19', 480, 720], ['2026-09-21', 420, 421]]);
  assert.equal(duration(parts), 241);
});

test('intraday breaks split continuation and do not contribute working minutes', () => {
  const value = snapshot({ break_windows: [{ scope: 'friday', start: '12:00', end: '12:30' }] });
  const booking = addBooking(value, 1, stamp('2026-09-18', '11:30'), stamp('2026-09-18', '13:00'));
  const parts = forBooking(timeline(value), booking.booking_id);
  assert.deepEqual(shape(parts), [['2026-09-18', 690, 720], ['2026-09-18', 750, 780]]);
  assert.equal(duration(parts), 60);
});

test('date-specific breaks apply by date even when a different day scope is supplied', () => {
  const value = snapshot({ break_windows: [{ date: '2026-09-18', scope: 'monday', start: '09:10', end: '09:25' }] });
  const result = timeline(value);
  assert.deepEqual(windows(result.days[0]), [[420, 550], [565, 1020]]);
  assert.deepEqual(windows(result.days[3]), [[420, 1020]]);
});

test('overlapping regular and overtime windows are unioned before breaks are subtracted', () => {
  const value = snapshot({
    overtime_windows: [{ scope: 'friday', start: '06:00', end: '09:00' }, { scope: 'friday', start: '16:00', end: '18:00' }, { scope: 'friday', start: '08:00', end: '10:00' }],
    break_windows: [{ scope: 'friday', start: '08:30', end: '08:45' }],
  });
  const booking = addBooking(value, 1, stamp('2026-09-18', '06:00'), stamp('2026-09-18', '18:00'));
  const result = timeline(value);
  assert.deepEqual(windows(result.days[0]), [[360, 510], [525, 1080]]);
  assert.equal(duration(forBooking(result, booking.booking_id)), 705);
});

test('closures and nonworking days stay closed even with matching overtime windows', () => {
  const value = snapshot({ closures: [{ date: '2026-09-18', label: 'Closure' }], overtime_windows: [{ scope: 'global', start: '06:00', end: '19:00' }] });
  const result = timeline(value);
  assert.deepEqual(windows(result.days[0]), []);
  assert.deepEqual(windows(result.days[2]), []);
});

test('UTC timestamps are plotted on the Perth calendar date rather than the UTC date', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, '2026-09-20T23:00:00Z', '2026-09-21T00:00:00Z');
  assert.deepEqual(shape(forBooking(timeline(value), booking.booking_id)), [['2026-09-21', 420, 480]]);
});

test('date stepping remains correct across month and leap-year boundaries', () => {
  const result = timeline(snapshot(), { startDate: '2028-02-28', dayCount: 4 });
  assert.deepEqual(result.days.map(day => day.date), ['2028-02-28', '2028-02-29', '2028-03-01', '2028-03-02']);
  result.days.slice(1).forEach((day, index) => assert.equal(day.startMs - result.days[index].startMs, 86400000));
});

test('a booking spanning both edges of the visible window is clipped without duplication', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, stamp('2026-09-17', '15:00'), stamp('2026-09-22', '09:00'));
  const result = timeline(value);
  assert.deepEqual(shape(forBooking(result, booking.booking_id)), [['2026-09-18', 420, 1020], ['2026-09-19', 480, 720], ['2026-09-21', 420, 1020]]);
  assert.equal(result.outside.filter(item => itemId(item) === booking.booking_id).length, 0);
});

test('bookings entirely before or after the visible date range remain in the outside list', () => {
  const value = snapshot();
  const earlier = addBooking(value, 1, stamp('2026-09-17', '07:00'), stamp('2026-09-17', '08:00'));
  const later = addBooking(value, 2, stamp('2026-09-22', '07:00'), stamp('2026-09-22', '08:00'));
  const result = timeline(value);
  assert.equal(segments(result).length, 0);
  assert.deepEqual(result.outside.map(itemId).sort(), [earlier.booking_id, later.booking_id].sort());
});

test('a recorded booking on a new closure keeps its position, matching the station planner history', () => {
  const value = snapshot({ closures: [{ date: '2026-09-18' }] });
  const booking = addBooking(value, 1, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '08:00'));
  const result = timeline(value);
  assert.deepEqual(shape(forBooking(result, booking.booking_id)), [['2026-09-18', 420, 480]]);
  assert.equal(forBooking(result, booking.booking_id)[0].historicalOnClosure, true);
  assert.deepEqual(result.days[0].windows, []);
});

test('missing or malformed calendar cannot silently render using hardcoded weekday defaults', () => {
  for (const invalid of [undefined, null, {}, { ...calendar(), day_start_time: 'bad' }, { ...calendar(), day_end_time: '06:00' }, { ...calendar(), working_week: [] }, { ...calendar(), break_windows: [{ start: '12:30', end: '12:00' }] }]) {
    const value = snapshot();
    value.board.calendar = invalid;
    assert.equal(timeline(value), null);
  }
});

test('malformed calendar collection entries fail closed without throwing', () => {
  for (const malformed of [
    { closures: [null] }, { closures: [{ date: '2026-13-01' }] },
    { break_windows: [null] }, { break_windows: ['12:00'] },
    { overtime_windows: [null] }, { overtime_windows: [{ date: '2026-99-99', start: '06:00', end: '07:00' }] },
    { working_week: [null] },
  ]) {
    assert.equal(timeline(snapshot(malformed)), null);
  }
});

test('invalid date input is rejected or falls back safely without a RangeError', () => {
  for (const invalid of ['2026-13-01', '2026-99-99', '2026-02-30', 'not-a-date']) {
    assert.equal(overview.shiftDate(invalid, 1), '');
    const result = timeline(snapshot(), { startDate: invalid });
    assert.equal(result.days[0].date, '2026-09-15');
  }
  assert.equal(overview.dateKey(new Date('invalid')), '');
});

test('assigned bookings with missing, invalid or reversed timestamps stay in unscheduled work', () => {
  const value = snapshot();
  const rows = [
    addBooking(value, 1, null, null),
    addBooking(value, 2, 'invalid', stamp('2026-09-18', '09:00')),
    addBooking(value, 3, stamp('2026-09-18', '10:00'), stamp('2026-09-18', '09:00')),
  ];
  const result = timeline(value);
  assert.equal(segments(result).length, 0);
  assert.deepEqual(result.unscheduled.map(itemId).sort(), rows.map(row => row.booking_id).sort());
});

test('queued jobs without a canonical bay never enter a physical bay timeline', () => {
  const value = snapshot();
  addBooking(value, 1, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '08:00'), { status: 'queued', bay_id: null, bay_number: null });
  const model = overview.buildModel(value);
  assert.equal(model.waiting.length, 1);
  const result = overview.buildTimeline(model, { startDate: '2026-09-18', dayCount: 4 });
  assert.equal(segments(result).length, 0);
});

test('admin blocks use the same canonical bay and working-window clipping as jobs', () => {
  const value = snapshot();
  const bay = value.board.bays[0];
  const block = { block_id: fixture.uuid(30000), stage_code: bay.stage_code, bay_id: bay.bay_id, label: 'Maintenance', scheduled_start_at: stamp('2026-09-18', '16:00'), scheduled_end_at: stamp('2026-09-21', '08:00') };
  value.board.admin_blocks.push(block);
  const result = timeline(value);
  assert.deepEqual(shape(forBooking(result, block.block_id)), [['2026-09-18', 960, 1020], ['2026-09-19', 480, 720], ['2026-09-21', 420, 480]]);
  assert.equal(result.rows.filter(row => row.segments.length).length, 1);
});

test('stored allocated timestamps win over quoted hours or the current bay efficiency', () => {
  const value = snapshot();
  value.board.bays[0].efficiency_percent = 80;
  const booking = addBooking(value, 1, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '12:00'), { estimated_hours: 4, default_duration_minutes: 240 });
  assert.equal(duration(forBooking(timeline(value), booking.booking_id)), 300);
});

test('overlapping jobs get separate lanes while touching endpoints reuse a lane', () => {
  const value = snapshot();
  const a = addBooking(value, 1, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '09:00'));
  const b = addBooking(value, 2, stamp('2026-09-18', '08:00'), stamp('2026-09-18', '10:00'), { status: 'started' });
  const c = addBooking(value, 3, stamp('2026-09-18', '09:00'), stamp('2026-09-18', '10:00'));
  const result = timeline(value);
  const byId = new Map(segments(result).map(segment => [segment.item.id, segment]));
  assert.notEqual(byId.get(a.booking_id).lane, byId.get(b.booking_id).lane);
  assert.equal(byId.get(a.booking_id).lane, byId.get(c.booking_id).lane);
  assert.equal(result.rows[0].laneCount, 2);
});

test('overlap placement is deterministic when the snapshot booking order changes', () => {
  const value = snapshot();
  addBooking(value, 3, stamp('2026-09-18', '08:00'), stamp('2026-09-18', '10:00'));
  addBooking(value, 1, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '09:00'));
  addBooking(value, 2, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '08:00'));
  const positions = result => segments(result).map(segment => [segment.item.id, segment.date, segment.start, segment.end, segment.lane]).sort((a, b) => a[0].localeCompare(b[0]));
  const before = positions(timeline(value));
  value.board.bookings.reverse();
  assert.deepEqual(positions(timeline(value)), before);
});

test('a lane can be reused on the next day and empty days do not grow a bay row', () => {
  const value = snapshot();
  addBooking(value, 1, stamp('2026-09-18', '07:00'), stamp('2026-09-18', '09:00'));
  addBooking(value, 2, stamp('2026-09-19', '08:00'), stamp('2026-09-19', '10:00'));
  const result = timeline(value);
  assert.equal(result.rows[0].laneCount, 1);
});

test('building a timeline is read-only and every rendered segment keeps its original booking identity', () => {
  const value = snapshot();
  const booking = addBooking(value, 1, stamp('2026-09-18', '16:00'), stamp('2026-09-21', '08:00'));
  const original = structuredClone(value);
  const result = timeline(value);
  assert.deepEqual(value, original);
  assert.ok(segments(result).every(segment => segment.item.id === booking.booking_id && segment.item.source.booking_id === booking.booking_id));
});

test('43 bays and 1000 synthetic bookings build as one bounded in-memory timeline', context => {
  const value = snapshot();
  for (let index = 0; index < 1000; index += 1) {
    const bay = value.board.bays[index % value.board.bays.length];
    const day = 21 + Math.floor(index / 200);
    const hour = 7 + index % 9;
    value.board.bookings.push(fixture.booking(index + 1, bay, undefined, { scheduled_start_at: stamp(`2026-09-${day}`, `${String(hour).padStart(2, '0')}:00`), scheduled_end_at: stamp(`2026-09-${day}`, `${String(hour + 1).padStart(2, '0')}:00`) }));
  }
  const started = performance.now();
  const result = timeline(value, { dayCount: 14 });
  const elapsed = performance.now() - started;
  assert.equal(result.rows.length, 43);
  assert.equal(new Set(segments(result).map(segment => segment.item.id)).size, 1000);
  assert.equal(result.outside.length, 0);
  context.diagnostic(`43 bays / 1000 bookings / 14 days: ${elapsed.toFixed(2)} ms`);
});
