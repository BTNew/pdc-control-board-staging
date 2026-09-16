'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('workshop-planner.js', 'utf8');
function slice(from, to) {
  const start = source.indexOf(from), end = source.indexOf(to, start);
  assert.ok(start >= 0 && end > start, from);
  return source.slice(start, end);
}
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
const flush = () => new Promise(resolve => setImmediate(resolve));

function fixture() {
  const calls = [], alerts = [], modals = [], handovers = [];
  const rows = [
    { id: 'ui-a', sharedBookingId: 'booking-a', sharedVersion: 7, vehicleKey: 'vehicle-a', stage: 'FITTING', status: 'started' },
    { id: 'other-ui-a', sharedBookingId: 'BOOKING-A', sharedVersion: 7, vehicleKey: 'vehicle-a', stage: 'FITTING', status: 'started' },
    { id: 'ui-b', sharedBookingId: 'booking-b', sharedVersion: 9, vehicleKey: 'vehicle-b', stage: 'FITTING', status: 'started' },
  ];
  let nextRpc, nextModal, nextDeployment, renders = 0;
  const c = {
    Map, Set, Date, window: { alert: value => alerts.push(value), PDC_VEHICLE_HANDOVER: { warn: async value => handovers.push(value) } },
    workshopLoadPlans: () => rows, workshopVehicle: () => ({}), workshopSharedModeActive: () => true,
    workshopEnsureCurrentDeployment: async () => nextDeployment ? nextDeployment.promise : true,
    workshopSharedLegacyAmbiguity: () => null, workshopAdministratorCanMove: () => false,
    workshopDescribeSharedActionError: result => `Failed: ${result?.error}`,
    workshopDescribeStartActionError: result => `Start failed: ${result?.error}`,
    renderWorkshopPlanner: () => { renders++; },
    workshopStoppageReasonModal: async () => { modals.push(true); return nextModal ? nextModal.promise : 'Parts unavailable'; },
  };
  c.window.__workshopSharedActions = Object.fromEntries(['startWork', 'stopWork', 'resumeWork', 'completeWork', 'moveBooking', 'resizeBooking', 'cascadeSchedule'].map(name => [name, async payload => {
    calls.push({ name, payload }); return nextRpc ? nextRpc.promise : { ok: true };
  }]));
  vm.createContext(c);
  vm.runInContext('const WORKSHOP_PENDING_STARTS=new Set(); const WORKSHOP_PENDING_BOOKING_ACTIONS=new Map(); let workshopStartFeedback={};' +
    slice('function workshopBeginBookingAction(', '// Human-readable,') +
    slice('async function startWorkshopPlan(', 'function workshopStoppageReasonModal(') +
    slice('async function stopWorkshopPlan(', 'function startWorkshopResize('), c);
  return { c, calls, alerts, modals, handovers, rows, get renders() { return renders; },
    holdRpc() { return nextRpc = deferred(); }, holdModal() { return nextModal = deferred(); }, holdDeployment() { return nextDeployment = deferred(); },
    feedback: () => vm.runInContext('workshopStartFeedback', c), pending: () => vm.runInContext('WORKSHOP_PENDING_BOOKING_ACTIONS.size', c) };
}

test('each shared lifecycle action suppresses repeated taps and releases its booking after completion', async () => {
  for (const action of ['start', 'stop', 'resume', 'complete']) {
    const f = fixture(), gate = f.holdRpc();
    f.rows[0].status = action === 'resume' ? 'stoppage' : action === 'start' ? 'planned' : 'started';
    const first = f.c[`${action}WorkshopPlan`]('ui-a');
    await f.c[`${action}WorkshopPlan`]('ui-a'); await flush();
    assert.equal(f.calls.length, 1, action); assert.equal(f.calls[0].payload.expectedVersion, 7);
    assert.equal(f.pending(), 1);
    gate.resolve({ ok: true }); await first;
    assert.equal(f.pending(), 0); assert.equal(f.alerts.length, 0);
    assert.equal(f.calls.length, 1, 'a suppressed tap is never replayed with a stale version');
  }
});

test('Stop owns the canonical booking before its reason dialog and cancel releases it', async () => {
  const f = fixture(), dialog = f.holdModal();
  const stopped = f.c.stopWorkshopPlan('ui-a');
  await f.c.stopWorkshopPlan('other-ui-a'); await f.c.completeWorkshopPlan('other-ui-a');
  const move = await f.c.workshopDispatchSharedAction('moveBooking', { bookingId: 'BOOKING-A', expectedVersion: 7 });
  assert.equal(move.error, 'booking_action_in_flight'); assert.equal(f.modals.length, 1); assert.equal(f.calls.length, 0);
  dialog.resolve(''); await stopped; assert.equal(f.pending(), 0);
  await f.c.completeWorkshopPlan('ui-a'); assert.equal(f.calls.length, 1);
});

test('move preflight blocks same-booking lifecycle and different move payloads without blocking another booking', async () => {
  const f = fixture(), deployment = f.holdDeployment();
  const first = f.c.workshopDispatchSharedAction('moveBooking', { bookingId: 'booking-a', expectedVersion: 7, bayNumber: 2 });
  await f.c.completeWorkshopPlan('ui-a');
  const duplicate = await f.c.workshopDispatchSharedAction('moveBooking', { bookingId: 'BOOKING-A', expectedVersion: 7, bayNumber: 3 });
  assert.equal(duplicate.error, 'booking_action_in_flight'); assert.equal(f.calls.length, 0);
  const independent = f.c.completeWorkshopPlan('ui-b');
  deployment.resolve(true); await Promise.all([first, independent]);
  assert.deepEqual(f.calls.map(call => call.name), ['moveBooking', 'completeWork']);
  assert.equal(f.calls[0].payload.bayNumber, 2); assert.equal(f.pending(), 0);
});

test('cascade extension shares the booking lock and releases it on rejected deployment', async () => {
  const f = fixture(), deployment = f.holdDeployment();
  const first = f.c.workshopDispatchSharedAction('cascadeSchedule', { operation: 'extend', targetId: 'booking-a', targetExpectedVersion: 7 });
  await f.c.completeWorkshopPlan('ui-a'); assert.equal(f.calls.length, 0);
  deployment.resolve(false); assert.equal((await first).error, 'stale_deployment_reload'); assert.equal(f.pending(), 0);
});

test('a sign-in change while the Stop dialog is open cannot submit the old action as the new user', async () => {
  const f = fixture(), dialog = f.holdModal();
  f.c.window.PDC_AUTH_CONTEXT = { userId: 'first-user', role: 'operator' };
  const first = f.c.stopWorkshopPlan('ui-a');
  f.c.window.PDC_AUTH_CONTEXT = { userId: 'second-user', role: 'operator' };
  dialog.resolve('Parts unavailable'); await first;
  assert.equal(f.calls.length, 0); assert.equal(f.pending(), 0);
});

test('uncertain HTTP outcomes never claim that no change was saved', () => {
  const c = { workshopAdministratorCanMove: () => false };
  vm.createContext(c);
  vm.runInContext(slice('function workshopDescribeSharedActionError(', 'function workshopPersistPlanAction('), c);
  for (const error of ['runtime_failure', 'request_failed', 'no_response']) {
    const message = c.workshopDescribeSharedActionError({ error });
    assert.match(message, /could not be confirmed.*Refresh/);
    assert.doesNotMatch(message, /No change|not saved|No update/i);
  }
  assert.match(c.workshopDescribeSharedActionError({ error: 'proxy_error', outcomeUnknown: true, status: 502 }), /could not be confirmed.*Refresh/);
});

test('canonical rejection and network exceptions release lifecycle locks without changing local rows', async () => {
  for (const throws of [false, true]) {
    const f = fixture(), gate = f.holdRpc(), before = JSON.stringify(f.rows);
    const first = f.c.completeWorkshopPlan('ui-a'); await flush();
    if (throws) gate.reject(Error('lost response')); else gate.resolve({ ok: false, error: 'version_conflict' });
    await first; assert.equal(f.pending(), 0); assert.equal(JSON.stringify(f.rows), before); assert.equal(f.alerts.length, 1);
  }
});

test('a confirmed write with unconfirmed readback is reported as saved and does not trigger dependent handover reads', async () => {
  const f = fixture(), gate = f.holdRpc();
  const first = f.c.workshopDispatchSharedAction('moveBooking', { bookingId: 'booking-a', expectedVersion: 7 });
  gate.resolve({ ok: true, reconciliation: 'pending', refreshRequired: true });
  assert.equal((await first).ok, true); assert.match(f.alerts[0], /change was saved.*could not refresh/);
  assert.equal(f.handovers.length, 0); assert.equal(f.pending(), 0);
  const start = await f.c.startWorkshopPlan('ui-a');
  assert.equal(start.ok, true); assert.match(f.feedback().message, /start was confirmed.*could not refresh/);
  assert.doesNotMatch(f.feedback().message, /No change|Start failed/);
});

function clockFixture() {
  let callback, renders = 0, lines = 0, modal = 'hidden', drag = null;
  const active = { tagName: 'BUTTON', closest: () => null };
  const c = { app: { currentView: 'workshop' }, document: { hidden: false, activeElement: active, querySelector: selector => {
    if (selector.includes('.modal-overlay')) return modal === 'visible' || modal === 'dialog' ? {} : selector === '.modal-overlay' && modal === 'hidden' ? {} : null;
    return null;
  } }, window: { setInterval: fn => { callback = fn; return 1; }, clearInterval: () => {} },
  workshopCurrentDragPreview: () => drag, renderWorkshopPlanner: options => { assert.equal(options.projectionOnly, true); renders++; }, updateWorkshopNowLine: () => { lines++; } };
  vm.createContext(c);
  vm.runInContext('let workshopActiveQueuePointerDrag=null,workshopActivePointerResize=null;const WORKSHOP_PENDING_BOOKING_ACTIONS=new Map();' +
    slice('function setupWorkshopPlannerClock(', 'function updateWorkshopNowLine('), c);
  c.setupWorkshopPlannerClock();
  return { c, active, tick: () => callback(), modal: value => { modal = value; }, drag: value => { drag = value; },
    get renders() { return renders; }, get lines() { return lines; }, set: code => vm.runInContext(code, c) };
}

test('hidden permanent modals do not suppress minute carryover redraw, while a hidden page does no work', () => {
  const f = clockFixture(); f.tick(); assert.equal(f.renders, 1);
  f.c.document.hidden = true; f.tick(); assert.equal(f.renders, 1); assert.equal(f.lines, 0);
});

test('visible dialogs, editing, pending actions and active drags/resizes retain DOM while the clock line updates', () => {
  const scenarios = [
    f => f.modal('visible'), f => f.modal('dialog'), f => f.drag({ type: 'plan' }),
    f => f.set('workshopActiveQueuePointerDrag={}'), f => f.set('workshopActivePointerResize={}'),
    f => f.set('WORKSHOP_PENDING_BOOKING_ACTIONS.set("a",{})'),
    f => { f.active.closest = selector => selector === '.workshop-job-detail, .workshop-search' ? {} : null; },
    f => { f.active.tagName = 'INPUT'; f.active.closest = selector => selector === '#workshop-planner-root' ? {} : null; },
  ];
  for (const setup of scenarios) { const f = clockFixture(); setup(f); f.tick(); assert.equal(f.renders, 0); assert.equal(f.lines, 1); }
});

test('cancelling a booking resize releases its clock protection and preview without dispatching a save', () => {
  const events = new Map(), chip = { dataset: {}, style: { setProperty() {} } };
  const lane = { getBoundingClientRect: () => ({ width: 600 }) };
  let renders = 0;
  const c = {
    document: { addEventListener: (name, fn) => events.set(name, fn), removeEventListener: name => events.delete(name) },
    workshopLoadPlans: () => [{ id: 'a', hours: 1, scheduledDurationMinutes: 60 }],
    workshopEntrySegmentForDate: () => ({ start: 0 }), workshopState: () => ({ date: '2026-09-16' }),
    workshopSnapMinutes: Math.round, WORKSHOP_PLANNER_CONFIG: { dayLengthMinutes: 600 },
    renderWorkshopPlanner: () => { renders++; },
  };
  vm.createContext(c);
  vm.runInContext('let workshopActivePointerResize=null;' + slice('function startWorkshopResize(', 'function workshopWeeklyCardHtml('), c);
  c.startWorkshopResize({ dataset: { workshopResizePlan: 'a' }, closest: selector => selector === '[data-workshop-plan-id]' ? chip : lane }, { clientX: 0, preventDefault() {}, stopPropagation() {} });
  assert.ok(vm.runInContext('workshopActivePointerResize', c));
  events.get('pointermove')({ clientX: 60 }); assert.equal(chip.dataset.previewHours, '2');
  events.get('pointercancel')({ type: 'pointercancel' });
  assert.equal(vm.runInContext('workshopActivePointerResize', c), null); assert.equal(events.size, 0);
  assert.equal(chip.dataset.previewHours, undefined); assert.equal(renders, 1);
});
