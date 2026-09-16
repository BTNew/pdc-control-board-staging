'use strict';

process.env.TZ = 'Australia/Perth';
const test = require('node:test');
const assert = require('node:assert/strict');
const overview = require('./control-board-overview.js');
const timing = require('./workshop-booking-timing.js');
const displayIdentity = require('./workshop-display-identity.js');
const fixture = require('./qa/control-board-fixtures.js');
const { createSlotRuntime } = require('./tests/helpers/workshop-slot-runtime.cjs');
const stamp = (date, clock) => `${date}T${clock}:00+08:00`;
const calendar = overrides => ({
  day_start_time: '06:00', day_end_time: '16:30', scheduling_increment_minutes: 15,
  working_week: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
  closures: [], break_windows: [], overtime_windows: [], ...overrides,
});

function pair(fields, options = {}) {
  const config = calendar(options.calendar), runtime = createSlotRuntime();
  Object.entries(config).forEach(([key, value]) => { runtime.config[key] = { value, version: 2 }; });
  runtime.planner.workshopSyncConfigFromSharedSettings();
  const value = fixture.emptySnapshot();
  value.board.calendar = config;
  const source = fixture.booking(1, value.board.bays[0], undefined, fields);
  value.board.bookings = [source];
  const before = JSON.stringify(value), now = new Date(options.now || stamp('2026-09-16', '14:26'));
  const model = overview.buildModel(value);
  const result = overview.buildTimeline(model, { startDate: '2026-09-16', dayCount: 7, now, ...options });
  const entry = { status: source.status, startAt: source.scheduled_start_at, endAt: source.scheduled_end_at,
    actualStartAt: source.actual_start_at, actualEndAt: source.actual_end_at, stoppageAt: source.stoppage_started_at, hours: 1 };
  for (const day of result.days) {
    const station = runtime.planner.workshopEntrySegmentForDate(entry, day.date, now);
    const pieces = result.rows.flatMap(row => row.segments).filter(piece => piece.date === day.date);
    assert.equal(!!pieces.length, !!station, `${day.date}: both views show the same booking`);
    if (!station) continue;
    const base = Date.parse(stamp(day.date, config.day_start_time));
    assert.equal(Math.min(...pieces.map(piece => piece.start)), base + station.start * 60000, `${day.date}: same start`);
    assert.equal(Math.max(...pieces.map(piece => piece.end)), base + station.end * 60000, `${day.date}: same end`);
  }
  assert.equal(JSON.stringify(value), before, 'display projection must not alter canonical records');
  return { result, model, source, runtime, entry, now };
}
const running = overrides => ({ status: 'started', scheduled_start_at: stamp('2026-09-16', '07:19'),
  scheduled_end_at: stamp('2026-09-16', '08:19'), actual_start_at: stamp('2026-09-16', '07:19'), ...overrides });
const parts = value => value.result.rows.flatMap(row => row.segments);

test('both views extend the reported 07:19–08:19 live job through 14:26', () => {
  const value = pair(running());
  assert.equal(parts(value)[0].end, Date.parse(stamp('2026-09-16', '14:26')));
  assert.ok(Math.abs(parts(value)[0].width - 427 / 60 * 64) < 1e-9);
});

test('started job whose estimate ended yesterday remains visible today and retains fitter progress', () => {
  const progress = { percent: 30, completed_hours: 3, total_hours: 10 };
  const value = pair(running({ scheduled_start_at: stamp('2026-09-15', '14:00'), scheduled_end_at: stamp('2026-09-15', '16:00'), fitter_progress: progress }));
  assert.equal(parts(value)[0].start, Date.parse(stamp('2026-09-16', '06:00')));
  assert.equal(parts(value)[0].item.source.fitter_progress, progress);
  assert.equal(parts(value)[0].continuesFromPrevious, true);
  assert.equal(value.result.outside.length, 0);
});

test('overdue live work carries across a weekend without Saturday or Sunday work', () => {
  const value = pair(running({ scheduled_start_at: stamp('2026-09-18', '15:00'), scheduled_end_at: stamp('2026-09-18', '16:00') }), {
    startDate: '2026-09-18', dayCount: 4, now: stamp('2026-09-21', '09:00'),
  });
  assert.deepEqual(parts(value).map(part => part.date), ['2026-09-18', '2026-09-21']);
});

test('live projection during a break stops at the previous operational minute', () => {
  const value = pair(running(), { now: stamp('2026-09-16', '12:15'), calendar: { break_windows: [{ scope: 'global', start: '12:00', end: '12:30' }] } });
  assert.equal(parts(value)[0].end, Date.parse(stamp('2026-09-16', '12:00')));
});

test('after a break both views have the same envelope and overview excludes break work', () => {
  const value = pair(running(), { calendar: { break_windows: [{ scope: 'global', start: '12:00', end: '12:30' }] } });
  assert.equal(parts(value).length, 2);
  assert.equal(parts(value)[0].end, Date.parse(stamp('2026-09-16', '12:00')));
  assert.equal(parts(value)[1].start, Date.parse(stamp('2026-09-16', '12:30')));
});

test('stoppage past the estimate freezes at its recorded stop plus the configured increment', () => {
  const value = pair(running({ status: 'stoppage', stoppage_started_at: stamp('2026-09-16', '09:10') }), { calendar: { scheduling_increment_minutes: 10 } });
  assert.equal(parts(value)[0].end, Date.parse(stamp('2026-09-16', '09:20')));
});

test('stoppage carry-over spans the next working morning at a closing boundary', () => {
  const value = pair(running({ status: 'stoppage', scheduled_start_at: stamp('2026-09-15', '14:00'), scheduled_end_at: stamp('2026-09-15', '15:00'), stoppage_started_at: stamp('2026-09-15', '16:30') }));
  assert.equal(parts(value)[0].end, Date.parse(stamp('2026-09-16', '06:15')));
});

test('missing stoppage timestamp keeps the recorded range instead of pretending work continues', () => {
  const value = pair(running({ status: 'stoppage', stoppage_started_at: null }));
  assert.equal(parts(value)[0].end, Date.parse(stamp('2026-09-16', '08:19')));
});

test('live work before opening and after closing respects 06:00–16:30', () => {
  const fields = running({ scheduled_start_at: stamp('2026-09-15', '14:00'), scheduled_end_at: stamp('2026-09-15', '15:00') });
  assert.equal(parts(pair(fields, { now: stamp('2026-09-16', '05:59') })).length, 0);
  assert.equal(parts(pair(fields, { now: stamp('2026-09-16', '18:00') }))[0].end, Date.parse(stamp('2026-09-16', '16:30')));
});

test('planned multi-day and actual-start changes preserve canonical scheduled positions', () => {
  const value = pair(running({ status: 'planned', scheduled_start_at: stamp('2026-09-16', '15:30'), scheduled_end_at: stamp('2026-09-17', '08:00'), actual_start_at: stamp('2026-09-16', '15:45') }));
  assert.equal(parts(value)[0].start, Date.parse(stamp('2026-09-16', '15:30')));
  assert.equal(parts(value)[1].end, Date.parse(stamp('2026-09-17', '08:00')));
});

test('recorded closure history is shown consistently while the date remains closed', () => {
  const value = pair(running({ status: 'planned' }), { calendar: { closures: [{ date: '2026-09-16' }] } });
  assert.equal(parts(value)[0].historicalOnClosure, true);
  assert.equal(value.result.days[0].windows.length, 0);
});

test('overview uses exact closing axis and includes 4:30 pm header and continuation tooltip', () => {
  const value = pair(running({ scheduled_start_at: stamp('2026-09-15', '14:00'), scheduled_end_at: stamp('2026-09-15', '16:00') }));
  assert.equal(value.result.axisStart, 360);
  assert.equal(value.result.axisEnd, 990);
  const html = overview.render(value.model, { startDate: '2026-09-16', dayCount: 1, now: value.now });
  assert.match(html, /left:100%">4:30 pm/);
  assert.doesNotMatch(html, /">4 pm<\/span>/, 'hourly label must not collide with the half-hour closing label');
  assert.match(html, /Continued from previous day/);
});

test('searched vehicle range includes current carried-over work instead of stopping yesterday', () => {
  const value = pair(running({ scheduled_start_at: stamp('2026-09-15', '14:00'), scheduled_end_at: stamp('2026-09-15', '16:00') }));
  assert.deepEqual(overview.searchDateRange(value.model, { now: value.now }), { startDate: '2026-09-15', dayCount: 2 });
});

test('shared projection preserves completed-history end without changing active-view status selection', () => {
  const scheduled = stamp('2026-09-16', '08:00'), actual = stamp('2026-09-16', '09:00');
  assert.equal(timing.effectiveEnd({ status: 'completed', scheduled_end_at: scheduled, actual_end_at: actual }, {}), Date.parse(actual));
  const value = fixture.emptySnapshot();
  value.board.bookings = [fixture.booking(1, value.board.bays[0], undefined, { status: 'completed' })];
  assert.equal(overview.buildModel(value).totalBookings, 0);
});

test('authenticated display identity fills missing labels and search without altering booking data', () => {
  const value = fixture.emptySnapshot();
  const vehicle = fixture.vehicle(1, { id: 'ABCDEF12-0000-4000-8000-000000000001', job_card_number: '', key_number: '' });
  const source = fixture.booking(1, value.board.bays[0], vehicle);
  value.board.bookings = [source];
  const before = JSON.stringify(value);
  const displayIdentities = displayIdentity.build([{ __emailVehicleId: vehicle.id, __emailVehicleServerAuthoritative: true,
    keyNumber: '789', pdcQcOperationLinesProjectionPresent: true,
    pdcQcOperationLines: [{ stageCode: source.stage_code, jobCardNumber: 'JC-OPERATIONS-1', active: true }],
  }]);
  const model = overview.buildModel(value, { displayIdentities, search: 'JC-OPERATIONS-1' });
  assert.equal(model.columns.length, 1);
  assert.equal(model.columns[0].items[0].source, source);
  assert.equal(model.columns[0].items[0].vehicle, vehicle);
  const html = overview.render(model, { startDate: '2026-09-15', dayCount: 1 });
  assert.match(html, /Key 789 · JC JC-OPERATIONS-1/);
  assert.equal(JSON.stringify(value), before);
});

test('display fallback cannot override raw identity or cross vehicle and station boundaries', () => {
  const value = fixture.emptySnapshot();
  const source = fixture.booking(1, value.board.bays[0]);
  value.board.bookings = [source];
  const displayIdentities = new Map([[`${source.vehicle_id}:${source.stage_code}`, { job: 'FALLBACK-JC', key: 'FALLBACK-KEY' }]]);
  assert.equal(overview.buildModel(value, { displayIdentities, search: 'FALLBACK-JC' }).columns.length, 0);
  source.vehicle.job_card_number = '';
  source.vehicle.key_number = '';
  displayIdentities.clear();
  displayIdentities.set(`${source.vehicle_id}:TINT`, { job: 'OTHER-STATION' });
  displayIdentities.set(`other-vehicle:${source.stage_code}`, { job: 'OTHER-VEHICLE' });
  assert.equal(overview.buildModel(value, { displayIdentities, search: 'OTHER-' }).columns.length, 0);
});
