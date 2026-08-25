'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
const start = source.indexOf('function workshopCascadePlans');
const end = source.indexOf('function workshopCascadeAndSave', start);
assert.ok(start >= 0 && end > start, 'cascade function exists');
const cascadeSource = source.slice(start, end);
assert.match(cascadeSource, /if \(shared\) return \{ rows: rows\.map\(entry => \(\{ \.\.\.entry \}\)\), changed: false \};/,
  'shared rows return exact authoritative positions without browser-only shifting');
assert.match(cascadeSource, /Persisted server cascade receipts are the only source of shared positions/);

let shiftCalls = 0;
const context = {
  workshopLoadPlans: () => [],
  workshopSharedModeActive: () => true,
  workshopClampDurationHours: value => value,
  workshopEntryIsLive: () => true,
  workshopEntryIsOvertime: () => true,
  workshopEntryEffectiveEnd: row => new Date(row.startAt),
  workshopEntryEnd: row => new Date(row.startAt),
  workshopEntryStart: row => new Date(row.startAt),
  workshopWorkMinutesBetween: () => 60,
  workshopShiftEveryLaterPlannedRow: () => { shiftCalls += 1; return {moved: []}; },
};
vm.createContext(context);
vm.runInContext(`${cascadeSource} this.cascade = workshopCascadePlans;`, context);
const rows = [
  {id: 'stopped', status: 'stoppage', stage: 'TYRE', bay: 1, startAt: '2026-08-24T23:00:00Z', hours: 1.2},
  {id: 'later', status: 'planned', stage: 'TYRE', bay: 1, startAt: '2026-08-25T01:00:00Z', hours: 1.2},
];
const result = context.cascade(rows, new Date('2026-08-25T02:00:00Z'));
assert.strictEqual(result.changed, false);
assert.deepStrictEqual(JSON.parse(JSON.stringify(result.rows)), rows);
assert.strictEqual(shiftCalls, 0, 'shared client must not simulate a reversible cascade');
assert.notStrictEqual(result.rows[0], rows[0], 'returned rows are safe clones');
console.log('Shared Workshop avoids reversible browser-only cascades: PASS');
