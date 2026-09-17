'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('./workshop-planner.js'), 'utf8');
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
function section(start, end) { const index = source.indexOf(start); assert.ok(index >= 0, start); return source.slice(index, source.indexOf(end, index)); }

function fixture() {
  const calls = [], assignments = [], alerts = [], renders = [], pending = new Set();
  const state = { stage: 'FITTING', date: '2026-09-17' };
  const bays = new Map([1, 2].map(bay => [bay, { id: `bay-${bay}`, version: 17 + bay, default_technician_id: `previous-${bay}` }]));
  let save = async () => ({ ok: true }), assign = async () => ({ ok: true }), plans = [], planReads = 0, token = 'token-one';
  const c = {
    app: { currentView: 'workshop' }, WORKSHOP_PENDING_BAY_ASSIGNMENTS: pending,
    window: { PDC_AUTH_CONTEXT: { userId: 'account-one', role: 'administrator' }, alert: message => alerts.push(message), __workshopReferenceDataService: {
      setBayDefaultTechnician: (...args) => { calls.push(args); return save(...args); },
    }, __workshopSharedActions: { assignBookingTechnician: args => { assignments.push(args); return assign(args); } } },
    cleanNavisionText: value => String(value).trim(), normalizePmbStage: value => String(value).toUpperCase(),
    getPdcSupabaseAccessToken: () => token,
    workshopSharedModeActive: () => true, workshopState: () => state,
    workshopSharedBayRef: (_stage, bay) => bays.get(Number(bay)) || null,
    workshopReferenceTechnicianRef: name => name === 'Missing' ? null : { technicianId: `technician-${name.toLowerCase()}` },
    workshopLoadPlans: () => { planReads++; return plans; },
    workshopStageBayCount: () => 2, workshopLoadAdminBlocks: () => [], workshopUnavailableTimeHtml: () => '',
    workshopEntrySegmentForDate: () => ({ start: 0, end: 60 }), workshopAdminBlockSegment: () => null,
    workshopBayMechanic: () => 'Previous', workshopPad: value => String(value).padStart(2, '0'),
    escapeHtml: value => String(value), workshopAssigneeOptions: () => '<option>Previous</option>', workshopDropPreviewHtml: () => '',
    workshopAdminBlockHtml: () => '', workshopPlanChipHtml: () => '',
  };
  c.renderWorkshopPlanner = () => renders.push(c.workshopBayRowsHtml('FITTING', state.date, []));
  vm.createContext(c);
  vm.runInContext(section('function workshopBayRowsHtml(', 'function workshopMechanicOptions(')
    + section('function workshopBayAssignmentError(', 'function bindWorkshopUnallocatedDrop('), c);
  return { c, calls, assignments, alerts, renders, pending, state, bays,
    setSave: fn => { save = fn; }, setAssign: fn => { assign = fn; }, setPlans: rows => { plans = rows; },
    setToken: value => { token = value; },
    get planReads() { return planReads; }, save: (bay = 1, name = 'Luke', stage = 'FITTING') => c.saveWorkshopBayMechanic(stage, bay, name) };
}
function selector(html, bay) { return html.match(new RegExp(`<select[^>]*data-workshop-bay-mechanic-number="${bay}"[^>]*>`))?.[0]; }
function plan(id, changes = {}) { return { id, sharedBookingId: `canonical-${id}`, sharedVersion: 30, stage: 'FITTING', bay: 1, status: 'planned', assignee: '', ...changes }; }

test('one pending assignment disables its own selector and duplicate taps do not issue another save', async () => {
  const f = fixture(), gate = deferred(); f.setSave(() => gate.promise);
  const first = f.save();
  assert.equal(f.calls.length, 1); assert.equal(f.pending.size, 1);
  assert.match(selector(f.renders.at(-1), 1), / disabled aria-busy="true"/);
  assert.doesNotMatch(selector(f.renders.at(-1), 2), /disabled|aria-busy/);
  await f.save(1, 'Zachary'); assert.equal(f.calls.length, 1);
  gate.resolve({ ok: true }); await first;
  assert.equal(f.pending.size, 0); assert.doesNotMatch(selector(f.renders.at(-1), 1), /disabled|aria-busy/);
});

test('different bays can save independently with their observed assignment and expected bay version', async () => {
  const f = fixture(), first = deferred(), second = deferred();
  f.setSave(id => id === 'bay-1' ? first.promise : second.promise);
  const savingOne = f.save(1, 'Luke'), savingTwo = f.save(2, 'Zachary');
  assert.equal(f.calls.length, 2); assert.equal(f.pending.size, 2);
  assert.deepEqual(f.calls[0].slice(0, 3), ['bay-1', 18, 'technician-luke']);
  assert.equal(f.calls[0][3].observedTechnicianId, 'previous-1'); assert.equal(f.calls[0][3].isCurrent(), true);
  assert.equal(f.calls[1][3].observedTechnicianId, 'previous-2');
  second.resolve({ ok: true }); await savingTwo;
  assert.equal(f.pending.has('FITTING:1'), true); assert.equal(f.pending.has('FITTING:2'), false);
  first.resolve({ ok: true }); await savingOne; assert.equal(f.pending.size, 0);
});

test('clearing a default passes null to the protected service and never backfills bookings', async () => {
  const f = fixture(); f.bays.get(1).default_technician_id = null; f.setPlans([plan('a')]);
  await f.save(1, ''); assert.equal(f.calls[0][2], null); assert.equal(f.calls[0][3].observedTechnicianId, null);
  assert.equal(f.assignments.length, 0); assert.equal(f.planReads, 0); assert.equal(f.pending.size, 0);
});

test('confirmed default updates backfill only unassigned planned bookings in this bay using each booking version', async () => {
  const f = fixture(); f.setPlans([
    plan('a', { sharedVersion: 41 }), plan('b', { sharedVersion: 42 }),
    plan('other-bay', { bay: 2 }), plan('other-department', { stage: 'TINT' }),
    plan('live', { status: 'started' }), plan('stopped', { status: 'stoppage' }),
    plan('finished', { status: 'completed' }), plan('assigned', { assignee: 'Someone else' }),
  ]);
  await f.save();
  assert.deepEqual(f.assignments.map(row => [row.bookingId, row.expectedVersion, row.technicianId]), [
    ['canonical-a', 41, 'technician-luke'], ['canonical-b', 42, 'technician-luke'],
  ]);
  assert.equal(f.pending.size, 0); assert.equal(f.alerts.length, 0);
});

for (const result of [{ ok: true, refreshRequired: true }, { ok: true, alreadyApplied: true }]) {
  test(`${result.refreshRequired ? 'unconfirmed readback' : 'already applied assignment'} does not replay dependent booking updates`, async () => {
    const f = fixture(); f.setSave(async () => result); f.setPlans([plan('a')]); await f.save();
    assert.equal(f.calls.length, 1); assert.equal(f.assignments.length, 0); assert.equal(f.planReads, 0); assert.equal(f.pending.size, 0);
    if (result.refreshRequired) assert.match(f.alerts[0], /saved.*latest bay list could not be confirmed/i);
    else assert.equal(f.alerts.length, 0);
  });
}

test('navigation while the default is saving invalidates its callback and suppresses stale backfill and redraw', async () => {
  for (const target of ['view', 'stage', 'date']) {
    const f = fixture(), gate = deferred(); f.setSave(() => gate.promise); f.setPlans([plan('a')]);
    const saved = f.save();
    if (target === 'view') f.c.app.currentView = 'dashboard';
    if (target === 'stage') f.state.stage = 'TINT';
    if (target === 'date') f.state.date = '2026-09-18';
    assert.equal(f.calls[0][3].isCurrent(), false, target);
    gate.resolve({ ok: true }); await saved;
    assert.equal(f.assignments.length, 0, target); assert.equal(f.alerts.length, 0, target);
    assert.equal(f.renders.length, 1, target); assert.equal(f.pending.size, 0, target);
  }
});

test('navigation during booking backfill stops the remaining booking writes', async () => {
  const f = fixture(), first = deferred(); f.setPlans([plan('a'), plan('b'), plan('c')]); f.setAssign(() => first.promise);
  const saved = f.save(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.assignments.length, 1); f.c.app.currentView = 'dashboard';
  first.resolve({ ok: true }); await saved;
  assert.equal(f.assignments.length, 1); assert.equal(f.alerts.length, 0); assert.equal(f.pending.size, 0);
});

test('token, account or role changes while saving prevent the previous request from assigning bookings', async () => {
  for (const change of ['token', 'account', 'role', 'logout']) {
    const f = fixture(), gate = deferred(); f.setSave(() => gate.promise); f.setPlans([plan('a')]);
    const saved = f.save();
    if (change === 'token') f.setToken('token-two');
    if (change === 'account') f.c.window.PDC_AUTH_CONTEXT.userId = 'account-two';
    if (change === 'role') f.c.window.PDC_AUTH_CONTEXT.role = 'viewer';
    if (change === 'logout') f.setToken(null);
    assert.equal(f.calls[0][3].isCurrent(), false, change);
    gate.resolve({ ok: true }); await saved;
    assert.equal(f.assignments.length, 0, change); assert.equal(f.alerts.length, 0, change);
    assert.equal(f.renders.length, 1, change); assert.equal(f.pending.size, 0, change);
  }
});

test('token, account or role changes during backfill stop subsequent booking writes', async () => {
  for (const change of ['token', 'account', 'role']) {
    const f = fixture(), gate = deferred(); f.setPlans([plan('a'), plan('b')]); f.setAssign(() => gate.promise);
    const saved = f.save(); await new Promise(resolve => setImmediate(resolve)); assert.equal(f.assignments.length, 1);
    if (change === 'token') f.setToken('token-two');
    if (change === 'account') f.c.window.PDC_AUTH_CONTEXT.userId = 'account-two';
    if (change === 'role') f.c.window.PDC_AUTH_CONTEXT.role = 'viewer';
    gate.resolve({ ok: true }); await saved;
    assert.equal(f.assignments.length, 1, change); assert.equal(f.alerts.length, 0, change);
    assert.equal(f.pending.size, 0, change); assert.equal(f.renders.length, 1, change);
  }
});

test('a backfill exception preserves the confirmed bay-save outcome and does not continue writing', async () => {
  const f = fixture(); f.setPlans([plan('a'), plan('b')]); f.setAssign(async () => { throw new Error('Network disconnected'); });
  await assert.doesNotReject(f.save());
  assert.equal(f.calls.length, 1); assert.equal(f.assignments.length, 1); assert.equal(f.pending.size, 0);
  assert.match(f.alerts[0], /bay default was saved.*unassigned bookings could not be completed/i);
  assert.doesNotMatch(f.alerts[0], /bay assignment could not be confirmed/i);
});

test('protected-service errors produce useful messages and leave selectors usable without booking changes', async () => {
  const cases = [
    [{ ok: false, code: 'version_conflict' }, /another session.*latest assignment/i],
    [{ ok: false, error: 'bay_assignment_changed' }, /another session/i],
    [{ ok: false, error: 'technician_already_assigned_to_bay', conflict: { bay_code: 'TINT-02' } }, /TINT-02.*Clear that assignment/],
    [{ ok: false, code: 'technician_already_assigned_to_bay', detail: { conflict: { bay_code: 'HOIST-01' } } }, /HOIST-01.*Clear that assignment/],
    [{ ok: false, code: 'permission_denied' }, /Sign in again/i],
    [{ ok: false, error: 'technician_inactive' }, /no longer active/i],
    [{ ok: false, error: 'request_timeout' }, /connection/i],
  ];
  for (const [result, expected] of cases) {
    const f = fixture(); f.setSave(async () => result); f.setPlans([plan('a')]); await f.save();
    assert.match(f.alerts[0], expected); assert.equal(f.assignments.length, 0); assert.equal(f.pending.size, 0);
    assert.doesNotMatch(selector(f.renders.at(-1), 1), /disabled|aria-busy/);
  }
});

test('cancelled service work is silent and thrown network errors are caught with pending state released', async () => {
  for (const error of ['assignment_cancelled', 'authority_superseded']) {
    const cancelled = fixture(); cancelled.setSave(async () => ({ ok: false, error })); await cancelled.save();
    assert.equal(cancelled.alerts.length, 0); assert.equal(cancelled.pending.size, 0);
  }
  const failed = fixture(); failed.setSave(async () => { throw new Error('Network disconnected'); });
  await assert.doesNotReject(failed.save()); assert.equal(failed.pending.size, 0); assert.equal(failed.assignments.length, 0);
  assert.match(failed.alerts[0], /could not be confirmed.*connection/i);
  failed.setSave(async () => ({ ok: true })); await failed.save(); assert.equal(failed.calls.length, 2, 'retry is possible after failure');
});

test('missing bay, inactive selection or absent service does not send a mutation', async () => {
  for (const mode of ['bay', 'technician', 'service']) {
    const f = fixture();
    if (mode === 'bay') f.bays.delete(1);
    if (mode === 'service') f.c.window.__workshopReferenceDataService = null;
    await f.save(1, mode === 'technician' ? 'Missing' : 'Luke');
    assert.equal(f.calls.length, 0); assert.equal(f.assignments.length, 0); assert.equal(f.pending.size, 0); assert.equal(f.alerts.length, 1);
  }
});
