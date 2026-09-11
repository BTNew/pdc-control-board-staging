'use strict';

const assert = require('node:assert/strict');

global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value ?? '').trim();
const planner = require('./workshop-planner.js');

assert.equal(planner.WORKSHOP_CONFIG.dayStartMinutes, 420);
assert.equal(planner.WORKSHOP_CONFIG.dayEndMinutes, 1020);
assert.equal(planner.WORKSHOP_CONFIG.dayLengthMinutes, 600);
assert.deepEqual(planner.WORKSHOP_CONFIG.workingDayIndexes, [1, 2, 3, 4, 5]);

// Match the authoritative get_workshop_configuration response shape so the
// shared calendar and the bootstrap fallback enforce the same workshop hours.
const row = value => ({ value, version: 1 });
const rows = {
  day_start_time: row('07:00'),
  day_end_time: row('17:00'),
  scheduling_increment_minutes: row(15),
  default_booking_duration_minutes: row(60),
  working_week: row(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']),
  closures: row([]),
  break_windows: row([]),
  overtime_windows: row([]),
  technician_leave: row([]),
};
global.window = {
  __workshopReferenceDataService: {
    getCachedWorkshopConfiguration: () => ({ state: 'connected_read_only', rows }),
  },
};
planner.workshopSyncConfigFromSharedSettings();
assert.equal(planner.WORKSHOP_CONFIG_AUTHORITY, 'shared_valid');
const date = (day, hour, minute = 0) => new Date(2026, 8, day, hour, minute);
const booking = (start, hours = 1) => ({ startAt: start.toISOString(), hours, status: 'planned' });

for (const day of [12, 13]) {
  assert.deepEqual(planner.workshopAvailabilityWindowsForDate(date(day, 7)), []);
  assert.equal(planner.workshopNewBookingValidation(booking(date(day, 7))).error, 'non_working_day');
  assert.equal(planner.workshopDateKey(planner.workshopNormalizeStartDate(date(day, 7))), '2026-09-14');
}
for (const start of [date(14, 6, 59), date(14, 17), date(14, 20)]) {
  assert.equal(planner.workshopNewBookingValidation(booking(start)).error, 'outside_work_window');
}
assert.equal(planner.workshopNewBookingValidation(booking(date(14, 7), 10)).ok, true);
assert.deepEqual(planner.workshopWeekDates(date(11, 7)).map(day => day.getDay()), [1, 2, 3, 4, 5]);

const start = date(11, 15, 45);
const end = planner.workshopAddWorkMinutes(start, 56.3 * 60);
assert.deepEqual([planner.workshopDateKey(end), end.getHours(), end.getMinutes()], ['2026-09-21', 12, 3]);
assert.equal(planner.workshopWorkMinutesBetween(start, end), 3378);
assert.equal(planner.workshopNewBookingValidation(booking(start, 56.3)).ok, true);
const longJob = { ...booking(start, 56.3), endAt: end.toISOString() };
assert.equal(planner.workshopEntrySegmentForDate(longJob, '2026-09-12'), null);
assert.equal(planner.workshopEntrySegmentForDate(longJob, '2026-09-13'), null);
assert.ok(planner.workshopEntrySegmentForDate(longJob, '2026-09-14'));
assert.ok(planner.workshopEntrySegmentForDate(longJob, '2026-09-21'));

console.log('Workshop weekday hours and weekend continuation checks passed.');
