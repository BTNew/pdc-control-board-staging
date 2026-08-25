'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('workshop-planner.js', 'utf8');
const start = source.indexOf('function workshopMapSnapshotBookingToLegacyRow');
const end = source.indexOf('function workshopAnnotateLegacyAmbiguity', start);
assert.ok(start >= 0 && end > start);
const context = {
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  workshopExactDurationHours: value => Math.round(Number(value) * 60) / 60,
  workshopDefaultBookingHours: () => 1,
};
vm.createContext(context);
vm.runInContext(`${source.slice(start, end)} this.map = workshopMapSnapshotBookingToLegacyRow;`, context);
const row = context.map({
  booking_id: 'aeb0c3a1', vehicle_id: 'vehicle-a',
  stage: { code: 'HOIST' }, bay: { id: 'bay-3', bay_number: 3 },
  status: 'started', scheduled_start_at: '2026-08-25T03:37:00.000Z', scheduled_end_at: '2026-08-25T06:52:00.000Z',
  default_duration_minutes: 195, estimated_operation_hours: 1.5,
  vehicle: { stock_number: '13000549' },
});
assert.strictEqual(row.hours, 3.25, 'scheduled allocation wins over stale operation estimate');
assert.strictEqual(row.scheduledDurationMinutes, 195);
assert.strictEqual(row.endAt, '2026-08-25T06:52:00.000Z');
assert.strictEqual(row.operationEstimateHours, 1.5);
console.log('Workshop scheduled allocation authority contract passed.');
