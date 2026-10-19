'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
function extract(name) {
  const match = new RegExp('(?:async )?function ' + name + '\\(').exec(source);
  assert.ok(match, name);
  const tail = source.slice(match.index);
  const next = /\n(?:async )?function \w+\(/.exec(tail);
  return next ? tail.slice(0, next.index) : tail;
}

const context = {
  cleanNavisionText: value => String(value || '').trim(),
  workshopBayMechanic: (stage, bay) => ({ 1: 'Ben Palmer', 2: 'Thanh Truong' }[Number(bay)] || ''),
  pmbBayMechanic: () => '',
};
vm.createContext(context);
vm.runInContext(extract('workshopNextScheduleTechnician') + '\n' + extract('workshopUnallocatedHeadingCounts'), context);

test('a new booking follows the selected bay mechanic until the user chooses someone else', () => {
  const vehicle = {};
  assert.equal(context.workshopNextScheduleTechnician('HOIST', 1, vehicle), 'Ben Palmer');
  assert.equal(context.workshopNextScheduleTechnician('HOIST', 2, vehicle), 'Thanh Truong');
  assert.equal(context.workshopNextScheduleTechnician('HOIST', 2, vehicle, { followsBay: false, manualValue: 'Ben Palmer' }), 'Ben Palmer');
  assert.match(source, /technicianFollowsBay/);
  assert.match(source, /selectBayTechnician\(\)/);
});

test('unallocated counts use the snapshot totals instead of a partial vehicle list', () => {
  const outstanding = Array.from({ length: 98 }, (_, index) => ({
    id: 'v' + index,
    sharedVehicleId: 'v' + index,
    __workshopOutstanding: { existingBooking: index < 42 },
  }));
  const partial = {
    unallocated: outstanding.filter(vehicle => vehicle.__workshopOutstanding.existingBooking !== true).length,
    booked: outstanding.filter(vehicle => vehicle.__workshopOutstanding.existingBooking === true).length,
  };
  assert.equal(partial.unallocated, 56);
  assert.equal(partial.booked, 42);
  const counts = { outstanding_candidates: 100, unscheduled_candidates: 95 };
  const plain = value => ({ unallocated: value.unallocated, booked: value.booked });
  assert.deepEqual(plain(context.workshopUnallocatedHeadingCounts(outstanding, [], counts)), { unallocated: 95, booked: 5 });
  assert.deepEqual(plain(context.workshopUnallocatedHeadingCounts(outstanding.slice(0, 1), [{ sharedVehicleId: 'v0' }], counts)), { unallocated: 96, booked: 4 });
  assert.deepEqual(plain(context.workshopUnallocatedHeadingCounts([], [{ sharedVehicleId: 'missing' }], counts)), { unallocated: 95, booked: 5 });
});

test('an untrusted refresh keeps the last heading and a committed schedule closes the dialog', () => {
  assert.match(source, /retainedQueueHeading/);
  assert.match(source, /result\.committed === true/);
  assert.match(source, /if \(scheduled\) finish\(\)/);
});
