/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r535 (F149): Schedule on an unallocated vehicle offers Next available or Bay order.
// No SQL. Department 135 keeps the old dialog.
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
const modal = extract('openWorkshopScheduleModal');
const best = extract('workshopScheduleVehicleNextAvailable');

test('Schedule drops the clock fields and keeps one dialog for every station', () => {
  assert.match(modal, /Next available/);
  assert.match(modal, /Bay order/);
  assert.match(modal, /data-workshop-insert-before/);
  assert.match(modal, /data-workshop-insert-end/);
  assert.match(modal, /workshopBayQueuePlacement\(/);
  assert.match(modal, /cascadeNewBooking: true/);
  assert.match(modal, /assigneeValue: null/);
  assert.match(modal, /const categoryBays = workshopCategoryBays\(normalizedStage, scheduleCategory\)/);
  assert.match(modal, /categoryBays\.map/);
  assert.match(modal, /wholeJobChoice\?\.\(vehicle\.__workshopOutstanding\?\.workCategories\)/);
  assert.match(modal, /Whole job to one technician – /);
  assert.match(modal, /workCategoryValue: workCategory, baseHoursValue: wholeJob\.hours/);
  assert.match(modal, /Later bookings in this bay move automatically/);
  assert.doesNotMatch(modal, /name="date"|name="startMinutes"|name="hours"|name="assignee"|Start time|Planned hours|>Technician</);
  assert.doesNotMatch(modal, /normalizedStage === 'FITTING'|normalizedStage === 'TINT'|normalizedStage === 'TYRE'/);
  assert.match(best, /cascadeNewBooking: false/);
  assert.match(source, /data-workshop-best-slot-vehicle/);
  assert.match(source, /next free slot of a chosen bay/);
  assert.doesNotMatch(source, /use Schedule for a specific date and time/);
});

test('bay order is key, stock, customer and model, and a running job is not an insert point', () => {
  const vehicles = {
    R: { keyNumber: '235', stock: '13010001', client: 'Sample Motors', model: 'Hilux' },
    A: { keyNumber: '516', stock: '13010002', client: 'Sample Motors', model: 'Prado' },
    B: { keyNumber: '799', stock: '13010003', client: 'Sample Motors', model: 'Landcruiser' },
  };
  const rows = [
    { id: 'b', vehicleKey: 'B', stage: 'FITTING', bay: 1, status: 'planned', sharedStatus: 'planned', startAt: '2026-10-27T06:00:00.000Z', endAt: '2026-10-27T08:00:00.000Z' },
    { id: 'other', vehicleKey: 'A', stage: 'TINT', bay: 1, status: 'planned', sharedStatus: 'planned', startAt: '2026-10-27T01:00:00.000Z', endAt: '2026-10-27T02:00:00.000Z' },
    { id: 'run', vehicleKey: 'R', stage: 'FITTING', bay: 1, status: 'started', sharedStatus: 'started', startAt: '2026-10-27T00:00:00.000Z', endAt: '2026-10-27T01:00:00.000Z' },
    { id: 'a', vehicleKey: 'A', stage: 'FITTING', bay: 1, status: 'planned', sharedStatus: 'planned', startAt: '2026-10-27T02:00:00.000Z', endAt: '2026-10-27T04:00:00.000Z' },
    { id: 'done', vehicleKey: 'B', stage: 'FITTING', bay: 1, status: 'completed', sharedStatus: 'completed', startAt: '2026-10-26T01:00:00.000Z', endAt: '2026-10-26T02:00:00.000Z' },
  ];
  const context = {
    workshopLoadPlans: () => rows,
    normalizePmbStage: value => value,
    workshopEntryStart: row => new Date(row.startAt),
    workshopEntryEnd: row => new Date(row.endAt),
    workshopDateKey: date => date.toISOString(),
    workshopMinuteOffset: date => date.getTime(),
    workshopVehicle: key => vehicles[key] || null,
    workshopQueueVehicleDescription: vehicle => vehicle.model || '',
    vehicleKeyNumber: vehicle => vehicle.keyNumber || '',
    displayStockNumber: vehicle => vehicle.stock || '',
    vehicleCustomerName: vehicle => vehicle.client || '',
    cleanNavisionText: value => String(value || '').trim(),
    escapeHtml: value => String(value),
    // r746: the placement clamps to now; this fixture sits in 2026-10-27 so the target start wins.
    workshopNormalizeStartDate: () => new Date('2026-10-27T05:00:00.000Z'),
    Date,
  };
  vm.createContext(context);
  vm.runInContext(['workshopBayQueueRows', 'workshopBayQueueMovable', 'workshopBayQueueLabel', 'workshopBayQueueHtml', 'workshopBayQueuePlacement'].map(extract).join('\n'), context);
  const queue = context.workshopBayQueueRows('FITTING', 1, '');
  assert.deepEqual(queue.map(row => row.id), ['run', 'a', 'b']);
  const html = context.workshopBayQueueHtml(queue);
  assert.match(html, /Key 235 · Stock 13010001 · Sample Motors · Hilux/);
  assert.match(html, /Key 516 · Stock 13010002 · Sample Motors · Prado/);
  assert.match(html, /Key 799 · Stock 13010003 · Sample Motors · Landcruiser/);
  assert.equal(html.indexOf('Key 235') < html.indexOf('Insert here'), true);
  assert.equal((html.match(/data-workshop-insert-before="/g) || []).length, 2);
  assert.equal((html.match(/data-workshop-insert-end/g) || []).length, 1);
  assert.doesNotMatch(html, /\d{1,2}:\d{2}|Estimated|planned hours|h</i);
  const before = context.workshopBayQueuePlacement('FITTING', 1, 'b', '');
  assert.equal(before.kind, 'before');
  assert.equal(before.dateKey, '2026-10-27T06:00:00.000Z');
  assert.equal(before.startMinutes, Date.parse('2026-10-27T06:00:00.000Z'));
  assert.equal(context.workshopBayQueuePlacement('FITTING', 1, 'run', '').kind, 'blocked');
  const end = context.workshopBayQueuePlacement('FITTING', 1, '', '');
  assert.equal(end.kind, 'end');
  assert.equal(end.dateKey, '2026-10-27T08:00:00.000Z');
  assert.equal(context.workshopBayQueuePlacement('TYRE', 3, '', '').kind, 'next');
});

test('Next available sends the job hours, the bay technician and a cascade', () => {
  let submitted = null;
  const elements = { bay: { value: '2' } };
  const form = { elements, addEventListener(event, fn) { if (event === 'submit') form.submit = fn; } };
  const overlay = {
    setAttribute() {},
    addEventListener() {},
    remove() {},
    querySelector(selector) { return selector === '[data-workshop-schedule-form]' ? form : { addEventListener() {}, focus() {}, hidden: false }; },
    querySelectorAll() { return []; },
  };
  const context = {
    console,
    Date,
    WORKSHOP_STAGE_SEQUENCE: ['FITTING', 'BUS_4X4', 'TINT', 'TYRE', 'HOIST', 'FABRICATION', 'ELECTRICAL'],
    document: { createElement: () => overlay, querySelector: () => null, body: { appendChild() {}, classList: { add() {}, remove() {} } } },
    workshopNotify() {},
    workshopReturnedPlanForAction: () => null,
    normalizePmbStage: value => value,
    workshopVehicle: () => ({ stock: '12667943', client: 'Sample Motors' }),
    workshopVehicleEtaConstraint: () => ({ required: false, ok: true, earliestDateKey: '' }),
    workshopSchedulingDuration: () => ({ hours: 10.5 }),
    workshopDefaultBookingHours: () => 1,
    workshopSharedModeActive: () => false,
    workshopDepartmentLayout: () => null,
    workshopCategoryBays: () => [1, 2],
    workshopSchedulableBayNumbers: () => [1, 2],
    workshopBayAllocatedHours: () => 10.5,
    workshopBookingDestinationHours: () => 10.5,
    workshopVisibleBays: () => [1, 2],
    workshopBayChoiceLabel: (_stage, number) => 'Bay ' + number,
    workshopExactDurationHours: value => Number(value),
    escapeHtml: value => String(value ?? ''),
    pmbStageLabel: () => 'Fitting',
    displayStockNumber: () => '12667943',
    vehicleCustomerName: () => 'Sample Motors',
    vehicleJobcardNumber: () => '',
    workshopLoadPlans: () => [],
    workshopNormalizeStartDate: value => value,
    workshopDateKey: () => '2026-10-27',
    workshopDateKeyNotBefore: value => value,
    workshopMinuteOffset: () => 30,
    workshopFirstAvailableStartSlot: (...args) => {
      assert.equal(args[1], 2);
      assert.equal(args[3], 10.5);
      assert.equal(args[9], null);
      return { dateKey: '2026-10-27', startMinutes: 90 };
    },
    scheduleWorkshopVehicle: async value => { submitted = value; return true; },
    workshopBindScheduleCommitClose: (_service, finish) => ({ closeOnce: finish, restore() {} }),
    window: {},
  };
  vm.createContext(context);
  vm.runInContext(['workshopBayQueueRows', 'workshopBayQueueHtml', 'workshopBayQueuePlacement', 'workshopBindScheduleCommitClose', 'openWorkshopScheduleModal'].map(extract).join('\n'), context);
  context.openWorkshopScheduleModal('12667943', 'FITTING', '2026-10-27', '');
  assert.match(overlay.innerHTML, /Next available/);
  assert.match(overlay.innerHTML, /Bay order/);
  assert.match(overlay.innerHTML, /12667943/);
  assert.doesNotMatch(overlay.innerHTML, /name="date"|name="hours"|Start time|Planned hours/);
  return form.submit({ preventDefault() {}, currentTarget: form }).then(() => {
    assert.equal(submitted.bay, 2);
    assert.equal(submitted.dateKey, '2026-10-27');
    assert.equal(submitted.startMinutes, 90);
    assert.equal(submitted.hoursValue, 10.5);
    assert.equal(submitted.assigneeValue, null);
    assert.equal(submitted.cascadeNewBooking, true);
    assert.equal(submitted.stage, 'FITTING');
  });
});

test('Department 135 keeps the old Schedule dialog and is not cache-busted', () => {
  const frozen = fs.readFileSync('karratha/workshop-planner.js', 'utf8');
  const frozenModal = frozen.slice(frozen.indexOf('function openWorkshopScheduleModal('), frozen.indexOf('\nasync function extendWorkshopPlan('));
  assert.match(frozenModal, /Planned hours/);
  assert.match(frozenModal, /Start time/);
  assert.match(frozenModal, /name="assignee"/);
  assert.doesNotMatch(frozenModal, /Bay order/);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.equal((app.match(/workshop-planner\.js\?[^"'']*r535=2026\.10\.26\.r535/g) || []).length, 2);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('r535=2026.10.26.r535'), false);
  assert.match(fs.readFileSync('index.html', 'utf8'), /workshop-planner\.css\?[^"']*r535=2026\.10\.26\.r535/);
  assert.equal(fs.readFileSync('karratha/index.html', 'utf8').includes('r535=2026.10.26.r535'), false);
  assert.equal(fs.existsSync('supabase/migrations/20261026120000_r535_schedule_bay_order.sql'), false);
});
