'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createSlotRuntime, at, booking } = require('./tests/helpers/workshop-slot-runtime.cjs');
const plain = value => JSON.parse(JSON.stringify(value));

test('Best slot uses a different bay when its default mechanic is on leave', () => {
  const r = createSlotRuntime();
  r.bays[0].default_technician_id = 'tech-a';
  r.bays[1].default_technician_id = 'tech-b';
  r.config.technician_leave.value = [{ technician_id: 'tech-a', date: '2026-09-14' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  assert.deepEqual(plain(r.planner.workshopBestStageSlot('FITTING', '2026-09-14', 2, [], 0, '2026-09-15')),
    { stage: 'FITTING', bay: 2, dateKey: '2026-09-14', startMinutes: 0 });
});

test('Best slot waits until the default mechanic finishes a loaded booking in another bay or station', () => {
  for (const other of [{ stage: 'FITTING', bay: 2 }, { stage: 'ELECTRICAL', bay: 1 }]) {
    const r = createSlotRuntime();
    r.bays[0].default_technician_id = 'tech-a';
    const rows = [booking(14, 7, 3, { ...other, assignee: 'Mechanic A' })];
    assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-14', 2, rows), 180);
  }
});

test('an existing assigned mechanic takes precedence over a destination bay default', () => {
  const r = createSlotRuntime();
  r.bays[0].default_technician_id = 'tech-b';
  r.bays[1].is_active = false;
  r.config.technician_leave.value = [{ technician_id: 'tech-b', date: '2026-09-14' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  const rows = [booking(14, 7, 3, { stage: 'ELECTRICAL', assignee: 'Mechanic A' })];
  assert.deepEqual(plain(r.planner.workshopBestStageSlot('FITTING', '2026-09-14', 1, rows, 0, '2026-09-14', [], '', 'Mechanic A')),
    { stage: 'FITTING', bay: 1, dateKey: '2026-09-14', startMinutes: 180 });
});

test('explicitly unassigned shifted work does not acquire the bay default mechanic', () => {
  const r = createSlotRuntime();
  r.bays[0].default_technician_id = 'tech-a';
  r.config.technician_leave.value = [{ technician_id: 'tech-a', date: '2026-09-14' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  const result = r.planner.workshopFirstAvailableStartSlot('FITTING', 1, '2026-09-14', 1, [], 0, 1, at(13), [], '');
  assert.deepEqual(plain(result), { dateKey: '2026-09-14', startMinutes: 0 });
});

test('local conflict resolution also searches with the mechanic it preserves', () => {
  const r = createSlotRuntime();
  r.bays[0].default_technician_id = 'tech-b';
  r.config.technician_leave.value = [{ technician_id: 'tech-b', date: '2026-09-14' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  r.context.workshopVehicle = () => null;
  r.context.pmbStageLabel = value => value;
  r.context.window.confirm = () => true;
  const candidate = booking(14, 7, 1, { id: 'moving', assignee: 'Mechanic A' });
  const rows = [booking(14, 7, 1), booking(14, 7, 3, { id: 'mechanic-busy', stage: 'ELECTRICAL', assignee: 'Mechanic A' })];
  const result = r.planner.workshopResolveConflictByNextSlot(candidate, rows);
  assert.equal(result.assignee, 'Mechanic A');
  assert.equal(+new Date(result.startAt), +at(14, 10));
});

test('long jobs check leave on every occupied day, including Saturday', () => {
  const r = createSlotRuntime();
  r.bays[0].default_technician_id = 'tech-a';
  r.config.technician_leave.value = [{ technician_id: 'tech-a', date: '2026-09-19' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-18', 14, []), null);
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-18', 10, []), 0, 'finishing Friday does not occupy Saturday');
  assert.equal(r.planner.workshopNewBookingValidation(booking(18, 7, 10 + 1 / 60, { assignee: 'Mechanic A' })).error, 'technician_on_leave');
});

test('vehicle fallback mechanic participates when a bay has no default', () => {
  const r = createSlotRuntime();
  r.config.technician_leave.value = [{ technician_id: 'tech-a', date: '2026-09-14' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  assert.equal(r.planner.workshopBestStageSlot('FITTING', '2026-09-14', 1, [], 0, '2026-09-14', [], 'Mechanic A'), null);
});

test('inactive and unresolved assigned mechanics are not offered as valid slots', () => {
  const r = createSlotRuntime();
  r.bays[0].default_technician_id = 'tech-a';
  r.technicians[0].active = false;
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-14', 1, []), null);
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-14', 1, [], 0, [], 'Unknown mechanic'), null);
});

test('Admin blocks, bay bookings and exact five-hour vehicle handover all constrain the same search', () => {
  const r = createSlotRuntime();
  r.snapshot.admin_blocks.push({ id: 'admin', stage_code: 'FITTING', bay_number: 1, scheduled_start_at: at(14, 14).toISOString(), scheduled_end_at: at(14, 15).toISOString() });
  const vehicleWindows = [{ start_at: at(14, 7), end_at: at(14, 9) }];
  const rows = [booking(14, 15, 1)];
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-14', 1, rows, 0, vehicleWindows), 540);
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 2, '2026-09-14', 1, rows, 0, vehicleWindows), 420);
});

test('Saturday hours and Sunday closure carry a multi-day job into Monday', () => {
  const r = createSlotRuntime();
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-19', 1, []), 60);
  assert.equal(r.planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-09-19', 1, [], 300), null);
  const result = r.planner.workshopFirstAvailableStartSlot('FITTING', 1, '2026-09-20', 1, [], 0, 2, at(13));
  assert.deepEqual(plain(result), { dateKey: '2026-09-21', startMinutes: 0 });
  assert.equal(+r.planner.workshopEntryEnd({ startAt: at(19, 11, 30).toISOString(), hours: 1.5 }), +at(21, 8));
});

test('breaks and closures preserve duration, and leave on a skipped closure is irrelevant', () => {
  const r = createSlotRuntime();
  r.config.break_windows.value.push({ scope: 'working_day', start: '12:00', end: '12:30' });
  r.config.closures.value = [{ date: '2026-09-15' }];
  r.config.technician_leave.value = [{ technician_id: 'tech-a', date: '2026-09-15' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  const entry = booking(14, 11, 10, { assignee: 'Mechanic A' });
  assert.equal(r.planner.workshopNewBookingValidation(entry).ok, true);
  assert.equal(+r.planner.workshopEntryEnd(entry), +at(16, 11, 30));
  assert.equal(r.planner.workshopNewBookingValidation(booking(14, 12)).error, 'break_window');
  assert.equal(r.planner.workshopNewBookingValidation(booking(15)).error, 'closure_date');
});

test('overtime is reported only when operational minutes occupy it', () => {
  const r = createSlotRuntime();
  r.config.overtime_windows.value = [{ date: '2026-09-14', start: '17:00', end: '19:00' }];
  r.planner.workshopSyncConfigFromSharedSettings();
  assert.equal(r.planner.workshopNewBookingValidation(booking(14, 7, 10)).usesOvertime, false);
  assert.equal(r.planner.workshopNewBookingValidation(booking(14, 7, 10 + 1 / 60)).usesOvertime, true);
  assert.equal(r.planner.workshopNewBookingValidation(booking(14, 18, 1)).usesOvertime, true);
});

test('search stops at its authoritative loaded date boundary', () => {
  const r = createSlotRuntime();
  let outside = 0;
  const find = r.context.workshopFirstAvailableStartMinutes;
  r.context.workshopFirstAvailableStartMinutes = (...args) => {
    if (args[2] > '2026-09-14') outside++;
    return find(...args);
  };
  assert.equal(r.planner.workshopFirstAvailableStartSlot('FITTING', 1, '2026-09-14', 1,
    [booking(14, 7, 10)], 0, 260, at(13), [], null, '2026-09-14'), null);
  assert.equal(outside, 0);
});

test('57-hour validation visits work windows instead of restarting for every minute', () => {
  const r = createSlotRuntime();
  let calls = 0;
  const availability = r.context.workshopAvailabilityWindowsForDate;
  r.context.workshopAvailabilityWindowsForDate = date => { calls++; return availability(date); };
  assert.equal(r.planner.workshopNewBookingValidation(booking(14, 7, 57)).ok, true);
  assert.ok(calls < 100, `bounded calendar work for a seven-day job: ${calls}`);
  assert.equal(+r.planner.workshopEntryEnd(booking(14, 7, 57)), +at(21, 10));
});
