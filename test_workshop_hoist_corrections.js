/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
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

test('Fabrication uses the same snapshot totals after a drop', () => {
  const outstanding = Array.from({ length: 150 }, (_, index) => ({
    id: 'f' + index,
    sharedVehicleId: 'f' + index,
    __workshopOutstanding: { existingBooking: index < 31 },
  }));
  const partial = {
    unallocated: outstanding.filter(vehicle => vehicle.__workshopOutstanding.existingBooking !== true).length,
    booked: outstanding.filter(vehicle => vehicle.__workshopOutstanding.existingBooking === true).length,
  };
  assert.deepEqual(partial, { unallocated: 119, booked: 31 });
  const counts = { outstanding_candidates: 151, unscheduled_candidates: 150 };
  const heading = context.workshopUnallocatedHeadingCounts(outstanding, [], counts);
  assert.deepEqual({ unallocated: heading.unallocated, booked: heading.booked }, { unallocated: 150, booked: 1 });
  assert.match(source, /workshopUnallocatedHeadingCounts\(outstanding, returnedPlans/);
});

test('an untrusted refresh keeps the last heading and a confirmed write closes the dialog before refresh', () => {
  assert.match(source, /retainedQueueHeading/);
  assert.match(source, /result\.committed === true/);
  assert.match(source, /workshopBindScheduleCommitClose\(window\.__workshopDataService, finish\)/);
  assert.match(source, /if \(scheduled\) commitClose\.closeOnce\(\)/);
  const start = source.indexOf('const WORKSHOP_SCHEDULE_DIALOG_RPCS');
  const end = source.indexOf('function openWorkshopScheduleModal');
  vm.runInContext(source.slice(start, end), context);
  let closed = 0;
  const service = { setWriteCommittedListener(listener) { this.listener = listener; return null; } };
  const binding = context.workshopBindScheduleCommitClose(service, () => { closed += 1; });
  service.listener('start_workshop_work', { ok: true });
  assert.equal(closed, 0, 'an unrelated confirmed write leaves Add to planner open');
  service.listener('administrator_schedule_workshop_vehicle', { ok: false });
  assert.equal(closed, 0);
  service.listener('administrator_schedule_workshop_vehicle', { ok: true });
  service.listener('administrator_move_workshop_booking', { ok: true });
  assert.equal(closed, 1);
  binding.restore();
  assert.equal(service.listener, null);
});
