'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createSlotRuntime, at, booking } = require('./tests/helpers/workshop-slot-runtime.cjs');
function runtime() {
  const r = createSlotRuntime();
  const now = +at(13);
  r.context.Date = class extends Date {
    constructor(...args) { super(...(args.length ? args : [now])); }
    static now() { return now; }
    static [Symbol.hasInstance](value) { return value instanceof Date; }
  };
  r.planner.workshopSyncConfigFromSharedSettings();
  return r;
}

test('new work uses the destination efficiency while repeated existing moves preserve the base', () => {
  const r = runtime(), p = r.planner;
  r.bays[0].efficiency_percent = 80;
  assert.equal(p.workshopBayAllocatedHours('FITTING', 1, 4), 5);
  const row = booking(14, 7, 5, { capacityBaseMinutes:240, capacityEfficiencyPercent:80 });
  assert.equal(p.workshopBookingDestinationHours(row, 'FITTING', 1, 4), 5);
  assert.equal(p.workshopBookingDestinationHours(row, 'FITTING', 2, 4), 4);
  const moved = { ...row, bay:2, hours:4, capacityEfficiencyPercent:100 };
  assert.equal(p.workshopBookingDestinationHours(moved, 'FITTING', 1, 4), 5);
  assert.equal(row.capacityBaseMinutes, 240);
});

test('manual and fractional base allocations survive different-bay moves without rounded-base drift', () => {
  const r = runtime(), p = r.planner;
  r.bays[0].efficiency_percent = 80;
  const manual = booking(14, 7, 6, { capacityBaseMinutes:288, capacityEfficiencyPercent:80 });
  assert.equal(p.workshopBookingDestinationHours(manual, 'FITTING', 2, 4), 4.8);
  const short = booking(14, 7, 41/60, { capacityBaseMinutes:32.8, capacityEfficiencyPercent:80 });
  assert.equal(p.workshopBookingDestinationHours(short, 'FITTING', 2, 0.5), 33/60);
  assert.equal(p.workshopBookingDestinationHours({ ...short, bay:2, hours:33/60 }, 'FITTING', 1, 0.5), 41/60);
  const legacy = booking(14, 7, 6);
  assert.equal(p.workshopBookingDestinationHours(legacy, 'FITTING', 2, 4), 6);
});

test('started and STOPPAGE previews keep allocated duration even across slower bays', () => {
  const r = runtime();
  r.bays[1].efficiency_percent = 50;
  for (const status of ['started', 'stoppage', 'completed']) {
    assert.equal(r.planner.workshopBookingDestinationHours(booking(14, 7, 41/60, { status }), 'FITTING', 2, 4), 41/60);
  }
});

test('Best slot measures each bay at its own speed and existing work is never scaled twice', () => {
  const r = runtime();
  r.bays[0].efficiency_percent = 80;
  const rows = [booking(14, 11, 6), booking(14, 11, 6, { id:'bay-two', bay:2 })];
  const fresh = r.planner.workshopBestStageSlot('FITTING', '2026-09-14', 4, rows);
  assert.equal(fresh.bay, 2, 'normal-speed bay fits four hours before the 11am booking');
  assert.equal(fresh.dateKey, '2026-09-14');
  const existing = booking(14, 7, 5, { capacityBaseMinutes:240, capacityEfficiencyPercent:80 });
  const move = r.planner.workshopBestStageSlot('FITTING', '2026-09-14', 5, rows, 0, '', [], '', null, existing);
  assert.equal(move.bay, 2, 'existing 5h allocation converts back to its 4h base at normal speed');
  assert.equal(move.dateKey, '2026-09-14');
});

test('unknown bay efficiency blocks new allocation without treating it as normal speed', () => {
  const r = runtime();
  r.bays.forEach(bay => { delete bay.efficiency_percent; });
  assert.equal(r.planner.workshopBayAllocatedHours('FITTING', 1, 4), null);
  assert.equal(r.planner.workshopBestStageSlot('FITTING', '2026-09-14', 4, []), null);
  assert.equal(r.planner.workshopBookingDestinationHours(booking(14, 7, 5), 'FITTING', 1, 4), 5);
});

test('slower multi-day allocation respects Saturday hours and the Sunday closure', () => {
  const r = runtime();
  r.bays[0].efficiency_percent = 50;
  const hours = r.planner.workshopBayAllocatedHours('FITTING', 1, 3);
  assert.equal(hours, 6);
  assert.equal(+r.planner.workshopEntryEnd({ startAt:at(18,16).toISOString(), hours }), +at(21,8));
});
