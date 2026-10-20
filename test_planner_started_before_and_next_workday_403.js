'use strict';
// r403: (F12) a booking that was started and then returned to the queue shows
// "Started before, can't re-plan yet" and cannot be dragged or scheduled;
// (planner default) after the Perth shift ends the planner opens on the next
// workday, and so does the Today button.
process.env.TZ = 'Australia/Perth';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
function extract(name) {
  const start = planner.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let i = planner.indexOf(') {', start) + 2, depth = 0;
  for (; i < planner.length; i += 1) {
    if (planner[i] === '{') depth += 1;
    if (planner[i] === '}' && --depth === 0) return planner.slice(start, i + 1);
  }
  throw new Error(name);
}
function constLine(name) {
  const start = planner.indexOf(`const ${name} =`);
  assert.ok(start >= 0, name);
  return planner.slice(start, planner.indexOf(';\n', start) + 1);
}
const escapeHtml = value => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

function chipContext(extra = {}) {
  const ctx = {
    escapeHtml,
    workshopVehicle: () => ({ id: 'v1' }),
    displayStockNumber: () => 'TEST-1',
    workshopVehicleIdentitySummaryHtml: () => '<b>TEST-1</b>',
    workshopQueueVehicleDescription: () => 'Test description',
    vehicleCustomerName: () => 'Test customer',
    alerts: [],
    ...extra,
  };
  ctx.workshopNotify = message => ctx.alerts.push(message);
  ctx.window = { alert() { throw new Error('F20: planner must not call window.alert'); }, __workshopDataService: { getTrustedSnapshot: () => ({}) } };
  vm.createContext(ctx);
  vm.runInContext([constLine('WORKSHOP_STARTED_BEFORE_HINT'), constLine('WORKSHOP_STARTED_BEFORE_MESSAGE'),
    extract('workshopPlanStartedBefore'), extract('workshopReturnedQueueCardHtml'), extract('workshopReturnedQueuePlans'),
    extract('workshopReturnedPlanForAction')].join('\n')
    + '\nthis.startedBefore=workshopPlanStartedBefore;this.card=workshopReturnedQueueCardHtml;this.forAction=workshopReturnedPlanForAction;', ctx);
  return ctx;
}
const returned = { id: 'p1', vehicleKey: 'k1', stage: 'HOIST', hours: 1.5, bay: 0, sharedBayId: null, sharedStatus: 'queued', status: 'planned' };
const startedReturned = { ...returned, id: 'p2', actualStartAt: '2026-10-20T07:00:00+08:00', actualEndAt: '' };

test('only a queued booking with an actual start and no finish counts as started before', () => {
  const ctx = chipContext();
  assert.equal(ctx.startedBefore(startedReturned), true);
  assert.equal(ctx.startedBefore(returned), false);
  assert.equal(ctx.startedBefore({ ...startedReturned, sharedStatus: 'started', status: 'started' }), false, 'running job');
  assert.equal(ctx.startedBefore({ ...startedReturned, actualEndAt: '2026-10-20T08:00:00+08:00' }), false, 'finished');
  assert.equal(ctx.startedBefore(null), false);
});

// r415 (F31): a started-then-returned job is re-planned like any other queued job;
// the server resumes it and keeps the time worked. The chip only notes it.
test('a started-before chip shows the hint and can be dragged, Best slot or Scheduled (r415)', () => {
  const ctx = chipContext();
  const html = ctx.card(startedReturned);
  assert.match(html, /Started before · time worked is kept/);
  assert.match(html, /draggable="true"/);
  assert.match(html, /is-started-before/);
  assert.equal(html.includes('aria-disabled'), false);
  assert.equal(html.includes(' disabled'), false, 'both buttons enabled');
  const normal = ctx.card(returned);
  assert.match(normal, /draggable="true"/);
  assert.equal(normal.includes('Started before'), false);
  assert.equal(normal.includes(' disabled'), false);
});

test('actions on a started-before booking go to the server, which resumes it (r415)', () => {
  const plans = [returned, startedReturned];
  const ctx = chipContext({
    workshopState: () => ({ stage: 'HOIST' }),
    workshopSharedModeActive: () => true,
    workshopSelectedBusGroup: () => null,
    workshopLoadPlans: () => plans,
  });
  assert.equal(ctx.forAction('p1').id, 'p1');
  assert.equal(ctx.forAction('p2').id, 'p2');
  assert.equal(ctx.forAction('p2', { explain: true }).id, 'p2');
  assert.equal(ctx.alerts.length, 0);
});

test('drag start and drops no longer refuse started-before bookings (r415)', () => {
  const dragStart = planner.indexOf("root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragstart'");
  assert.ok(dragStart > 0);
  assert.equal(/workshopPlanStartedBefore/.test(planner.slice(dragStart, dragStart + 400)), false);
  assert.equal(/workshopPlanStartedBefore/.test(extract('moveWorkshopDroppedPlan')), false);
});

function dateContext(dayEndMinutes = 16 * 60) {
  const ctx = {
    WORKSHOP_PLANNER_CONFIG: { dayStartMinutes: 6 * 60, dayEndMinutes, workingDayIndexes: [1, 2, 3, 4, 5], closureDateKeys: ['2026-12-25'] },
    workshopPad: value => String(value).padStart(2, '0'),
    workshopBusShift: () => null,
    window: {},
  };
  vm.createContext(ctx);
  vm.runInContext(['workshopSetClock', 'workshopDateKey', 'workshopCalendarStartMinutes', 'workshopIsConfiguredWorkingDay',
    'workshopIsClosureDate', 'workshopIsWorkday', 'workshopCoerceWorkDate', 'workshopPerthMinutesOfDay', 'workshopDefaultOpenDateKey'].map(extract).join('\n')
    + '\nthis.open=workshopDefaultOpenDateKey;this.perth=workshopPerthMinutesOfDay;', ctx);
  return ctx;
}

test('the planner opens on today during the shift and on the next workday after it ends (Perth)', () => {
  const ctx = dateContext(16 * 60);
  assert.equal(ctx.perth(new Date('2026-10-20T08:30:00Z')), 16 * 60 + 30);
  assert.equal(ctx.open(new Date('2026-10-21T05:00:00+08:00')), '2026-10-21', 'before the shift');
  assert.equal(ctx.open(new Date('2026-10-21T15:59:00+08:00')), '2026-10-21', 'during the shift');
  assert.equal(ctx.open(new Date('2026-10-21T16:00:00+08:00')), '2026-10-22', 'shift over');
  assert.equal(ctx.open(new Date('2026-10-20T21:00:00+08:00')), '2026-10-21', 'Tuesday night opens Wednesday');
  assert.equal(ctx.open(new Date('2026-10-23T18:00:00+08:00')), '2026-10-26', 'Friday night opens Monday');
  assert.equal(ctx.open(new Date('2026-10-25T18:00:00+08:00')), '2026-10-26', 'Sunday night opens Monday, not Tuesday');
  assert.equal(ctx.open(new Date('2026-12-24T17:00:00+08:00')), '2026-12-28', 'skips a closure day and the weekend');
});

test('the shift end follows the configured day end', () => {
  const ctx = dateContext(17 * 60);
  assert.equal(ctx.open(new Date('2026-10-21T16:30:00+08:00')), '2026-10-21');
  assert.equal(ctx.open(new Date('2026-10-21T17:00:00+08:00')), '2026-10-22');
});

test('the Today button uses the same next-workday rule', () => {
  const at = planner.indexOf("root.querySelector('[data-workshop-today]')?.addEventListener('click'");
  assert.ok(at > 0);
  assert.match(planner.slice(at, at + 300), /state\.date = workshopDefaultOpenDateKey\(new Date\(\)\);/);
});
