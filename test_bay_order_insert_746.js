'use strict';
// r746 (F350): Insert here between two jobs works for a booking that already exists (queued, no bay): the move cascades,
// and the requested start is never earlier than now.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const source = fs.readFileSync('workshop-planner.js', 'utf8');
function extract(name) {
  const match = new RegExp('(?:async )?function ' + name + '\\(').exec(source);
  assert.ok(match, name);
  const tail = source.slice(match.index);
  const next = /\n(?:async )?function \w+\(/.exec(tail);
  return next ? tail.slice(0, next.index) : tail;
}

test('the Schedule window asks for a cascading move; an existing shared booking then moves with cascade', () => {
  const modal = extract('openWorkshopScheduleModal');
  assert.match(modal, /cascadeNewBooking: true,\n\s+cascadeMove: true,/);
  const schedule = extract('scheduleWorkshopVehicle');
  assert.match(schedule, /cascadeMove = false, workCategoryValue/);
  assert.match(schedule, /const cascade = \(preferRequestedTime && movingBetweenBays\) \|\| cascadeMove === true;/);
  assert.match(schedule, /: \(cascade \? 'cascadeMoveBooking' : 'moveBooking'\);/, 'non-admin path still follows the same flag');
  assert.match(schedule, /\n\s+cascade,\n\s+metadata: \{ source: preferRequestedTime \? 'planner_chip_drop' : 'planner_booking_move'/);
  const best = extract('workshopScheduleVehicleNextAvailable');
  assert.doesNotMatch(best, /cascadeMove/, 'Next available (free slot) is unchanged');
});

test('Insert here never asks for a start before now', () => {
  const fn = extract('workshopBayQueuePlacement');
  assert.match(fn, /Math\.max\(workshopEntryStart\(target\)\.getTime\(\), workshopNormalizeStartDate\(new Date\(\)\)\.getTime\(\)\)/);
  const now = new Date('2026-10-30T01:49:10Z');
  const ctx = {
    workshopBayQueueRows: () => [{ id: 't1', status: 'planned', startAt: '2026-10-30T01:48:30Z' }, { id: 't2', status: 'planned', startAt: '2026-10-30T03:15:00Z' }],
    workshopBayQueueMovable: row => row.status !== 'started',
    workshopEntryStart: row => new Date(row.startAt),
    workshopEntryEnd: row => new Date(row.startAt),
    workshopNormalizeStartDate: () => now,
    workshopDateKey: d => d.toISOString().slice(0, 10),
    workshopMinuteOffset: d => d.getUTCHours() * 60 + d.getUTCMinutes() + d.getUTCSeconds() / 60,
    Date,
  };
  vm.runInNewContext(fn + ';this.f=workshopBayQueuePlacement;', ctx);
  const first = ctx.f('TYRE', 1, 't1', '');
  assert.equal(first.kind, 'before');
  assert.equal(first.startMinutes, ctx.workshopMinuteOffset(now), 'clamped to now, not 40 s in the past');
  const second = ctx.f('TYRE', 1, 't2', '');
  assert.equal(second.startMinutes, ctx.workshopMinuteOffset(new Date('2026-10-30T03:15:00Z')), 'a future start is kept');
});

test('planner script cache tag r746 on both loaders', () => {
  const app = fs.readFileSync('app.js', 'utf8');
  assert.equal((app.match(/workshop-planner\.js\?[^`]*&r746=2026\.10\.30\.r746`/g) || []).length, 2);
});
