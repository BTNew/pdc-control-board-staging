'use strict';

const assert = require('assert');
global.normalizePmbStage = value => String(value || '').toUpperCase();
global.escapeHtml = value => String(value == null ? '' : value);
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.pmbStageLabel = value => String(value || '');
const planner = require('./workshop-planner.js');

function rows(overrides = {}) {
  return {
    day_start_time: { value: '08:00' },
    day_end_time: { value: '16:00' },
    scheduling_increment_minutes: { value: 15 },
    default_booking_duration_minutes: { value: 180 },
    working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'] },
    closures: { value: [] },
    break_windows: { value: [] },
    overtime_windows: { value: [] },
    technician_leave: { value: [] },
    ...overrides,
  };
}

function apply(configuration) {
  global.window = {
    __workshopReferenceDataService: {
      getCachedWorkshopConfiguration: () => ({ state: 'connected_editable', rows: configuration }),
      getCachedTechnicians: () => ({ state: 'connected_editable', rows: [] }),
    },
  };
  assert.strictEqual(planner.workshopSyncConfigFromSharedSettings(), true);
  assert.strictEqual(planner.WORKSHOP_CONFIG_AUTHORITY, 'shared_valid');
}

function localDate(year, month, day, hour, minute) {
  return new Date(year, month - 1, day, hour, minute, 0, 0);
}

// 1. Integer-minute 07:30–15:30 boundaries and exact zero offset.
apply(rows({ day_start_time: { value: '07:30' }, day_end_time: { value: '15:30' } }));
assert.strictEqual(planner.WORKSHOP_CONFIG.dayStartMinutes, 450);
assert.strictEqual(planner.WORKSHOP_CONFIG.dayEndMinutes, 930);
const sevenThirty = planner.workshopDateFromKey('2026-07-20');
assert.strictEqual(sevenThirty.getHours(), 7);
assert.strictEqual(sevenThirty.getMinutes(), 30);
assert.strictEqual(planner.workshopMinuteOffset(sevenThirty), 0);
const threeThirty = planner.workshopSetClock(sevenThirty, planner.WORKSHOP_CONFIG.dayEndMinutes);
assert.strictEqual(threeThirty.getHours(), 15);
assert.strictEqual(threeThirty.getMinutes(), 30);
console.log('PASS CONFIG 1: 07:30–15:30 uses exact integer-minute boundaries and zero start offset');

// 2. 08:15–16:45 through normalization, drag offset, work addition,
// break-aware segment rendering, and exact day end.
apply(rows({
  day_start_time: { value: '08:15' },
  day_end_time: { value: '16:45' },
  break_windows: { value: [{ start: '12:00', end: '12:30', scope: 'global' }] },
}));
const normalized = planner.workshopNormalizeStartDate(localDate(2026, 7, 20, 8, 7));
assert.deepStrictEqual([normalized.getHours(), normalized.getMinutes()], [8, 15]);
const drag = planner.workshopDateAtOffset('2026-07-20', 75);
assert.deepStrictEqual([drag.getHours(), drag.getMinutes()], [9, 30]);
const addAcrossBreak = planner.workshopAddWorkMinutes(localDate(2026, 7, 20, 11, 30), 120);
assert.deepStrictEqual([addAcrossBreak.getHours(), addAcrossBreak.getMinutes()], [14, 0]);
const fullDay = { startAt: localDate(2026, 7, 20, 8, 15).toISOString(), hours: 8, status: 'planned' };
const segment = planner.workshopEntrySegmentForDate(fullDay, '2026-07-20');
assert.strictEqual(segment.start, 0);
assert.strictEqual(planner.WORKSHOP_CONFIG.dayLengthMinutes, 510);
assert.deepStrictEqual([planner.workshopSetClock(drag, planner.WORKSHOP_CONFIG.dayEndMinutes).getHours(), planner.workshopSetClock(drag, planner.WORKSHOP_CONFIG.dayEndMinutes).getMinutes()], [16, 45]);
console.log('PASS CONFIG 2: 08:15–16:45 survives normalization, drag/drop, work addition, segment rendering, and day-end calculation');

// 2b. A booking that consumes the final minute of a workday continues at the
// next configured work start instead of being rejected at the exact day-end
// boundary.
apply(rows());
const nextDayCandidate = { startAt: localDate(2026, 7, 20, 13, 30).toISOString(), hours: 3, status: 'planned' };
assert.deepStrictEqual(planner.workshopNewBookingValidation(nextDayCandidate), { ok: true, usesOvertime: false });
const nextDayEnd = planner.workshopEntryEnd(nextDayCandidate);
assert.deepStrictEqual(
  [planner.workshopDateKey(nextDayEnd), nextDayEnd.getHours(), nextDayEnd.getMinutes()],
  ['2026-07-21', 8, 30],
  'A 1:30pm three-hour card must carry its final 30 minutes into the next working day',
);
console.log('PASS CONFIG 2b: end-of-day cards carry into the next working day');
const fridayCandidate = { startAt: localDate(2026, 7, 24, 15, 30).toISOString(), hours: 2, status: 'planned' };
assert.deepStrictEqual(planner.workshopNewBookingValidation(fridayCandidate), { ok: true, usesOvertime: false });
const mondayEnd = planner.workshopEntryEnd(fridayCandidate);
assert.deepStrictEqual(
  [planner.workshopDateKey(mondayEnd), mondayEnd.getHours(), mondayEnd.getMinutes()],
  ['2026-07-27', 9, 30],
  'Friday overflow must skip the weekend and continue on Monday',
);

// 3. Closure dates are blocked and skipped by next/previous workday math.
apply(rows({ closures: { value: [{ date: '2026-07-20', label: 'Synthetic closure' }] } }));
assert.strictEqual(planner.workshopIsWorkday(localDate(2026, 7, 20, 10, 0)), false);
assert.strictEqual(planner.workshopDateKey(planner.workshopShiftWorkday(localDate(2026, 7, 17, 8, 0), 1)), '2026-07-21');
assert.strictEqual(planner.workshopDateKey(planner.workshopShiftWorkday(localDate(2026, 7, 21, 8, 0), -1)), '2026-07-17');
assert.strictEqual(planner.workshopNewBookingValidation({ startAt: localDate(2026, 7, 20, 9, 0).toISOString(), hours: 1 }).error, 'closure_date');
console.log('PASS CONFIG 3: closures block scheduling and are skipped in both workday directions');

// 4. Break windows split work duration and reject starts inside the break.
apply(rows({ break_windows: { value: [{ start: '12:00', end: '12:30' }] } }));
assert.strictEqual(planner.workshopWorkMinutesBetween(localDate(2026, 7, 20, 11, 30), localDate(2026, 7, 20, 13, 30)), 90);
assert.strictEqual(planner.workshopNewBookingValidation({ startAt: localDate(2026, 7, 20, 12, 15).toISOString(), hours: 1 }).error, 'break_window');
console.log('PASS CONFIG 4: breaks split work duration and cannot receive new bookings');

// 5. Overtime is accepted only inside an explicit configured window.
apply(rows({
  day_start_time: { value: '08:15' },
  day_end_time: { value: '16:45' },
  overtime_windows: { value: [{ start: '17:00', end: '18:00', date: '2026-07-20' }] },
}));
assert.strictEqual(planner.workshopNewBookingValidation({ startAt: localDate(2026, 7, 20, 16, 50).toISOString(), hours: 1 }).error, 'outside_work_window');
const overtimeCandidate = { startAt: localDate(2026, 7, 20, 17, 0).toISOString(), hours: 1, status: 'planned' };
assert.deepStrictEqual(planner.workshopNewBookingValidation(overtimeCandidate), { ok: true, usesOvertime: true });
assert.strictEqual(planner.workshopEntryUsesConfiguredOvertime(overtimeCandidate), true);
console.log('PASS CONFIG 5: overtime outside configured windows is rejected and configured overtime is accepted/identified');

// 6. Technician leave blocks a newly assigned technician.
apply(rows({ technician_leave: { value: [{ technician_id: '00000000-0000-4000-8000-000000000001', date: '2026-07-20' }] } }));
const leaveResult = planner.workshopNewBookingValidation({
  startAt: localDate(2026, 7, 20, 9, 0).toISOString(),
  hours: 1,
  technicianId: '00000000-0000-4000-8000-000000000001',
});
assert.strictEqual(leaveResult.error, 'technician_on_leave');
console.log('PASS CONFIG 6: technician leave rejects a new assignment in the planner adapter');

// 7. Existing historical bookings remain renderable after closure changes.
apply(rows({ closures: { value: [{ date: '2026-07-20', label: 'Later closure' }] } }));
const historical = { startAt: localDate(2026, 7, 20, 9, 0).toISOString(), hours: 2, status: 'completed' };
const historicalSegment = planner.workshopEntrySegmentForDate(historical, '2026-07-20');
assert.ok(historicalSegment);
assert.strictEqual(historicalSegment.historicalOnClosure, true);
console.log('PASS CONFIG 7: historical bookings remain renderable after a closure is introduced');

// 8. Planner week columns follow three-day and six-day configurations.
apply(rows({ working_week: { value: ['Monday', 'Wednesday', 'Friday'] } }));
assert.strictEqual(planner.workshopWeekDates('2026-07-20').length, 3);
assert.deepStrictEqual(planner.workshopWeekDates('2026-07-20').map(date => date.getDay()), [1, 3, 5]);
apply(rows({ working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] } }));
assert.strictEqual(planner.workshopWeekDates('2026-07-20').length, 6);
assert.deepStrictEqual(planner.workshopWeekDates('2026-07-20').map(date => date.getDay()), [1, 2, 3, 4, 5, 6]);
console.log('PASS CONFIG 8: three-day and six-day configurations produce exactly three and six planner columns');

// 9. Once shared configuration has been valid, loading/missing state retains
// the last values for display but fails closed for every new scheduling write.
global.window.__workshopReferenceDataService.getCachedWorkshopConfiguration = () => ({ state: 'loading', rows: null });
assert.strictEqual(planner.workshopSyncConfigFromSharedSettings(), false);
assert.strictEqual(planner.WORKSHOP_CONFIG_AUTHORITY, 'shared_stale');
assert.strictEqual(planner.workshopConfigurationAllowsNewScheduling(), false);
console.log('PASS CONFIG 9: stale/loading shared configuration never reverts to boot defaults and fails closed for new scheduling');

console.log('Workshop planner integer-minute configuration checks passed');
