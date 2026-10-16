'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const departments = require('./pdc-workshop-departments.js');
const plannerSource = fs.readFileSync(require.resolve('./workshop-planner.js'), 'utf8');
const appSource = fs.readFileSync(require.resolve('./app.js'), 'utf8');

function extract(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, name);
  const end = source.indexOf('\nfunction ', start + 10);
  return source.slice(start, end < 0 ? undefined : end);
}

function candidateFixture({ dedicatedStage = 'BUS_4X4', shared = true } = {}) {
  const state = { busBayGroup: 'mechanical' };
  const fallbackRows = [{ id: 'legacy-vehicle' }];
  const calls = { legacy: [], snapshot: 0 };
  const snapshot = {
    vehicles: [{ id: 'canonical-vehicle', stock_number: 'SYNTHETIC-001', version: 4 }],
    bookings: [], work_items: [],
    outstanding_candidates: [{
      vehicle_id: 'canonical-vehicle', schedule_enabled: true,
      work_categories: [
        { work_category: 'BUS_MECHANICAL', estimated_hours: 8, existing_booking: false, schedule_enabled: true },
        { work_category: 'BUS_ELECTRICAL', estimated_hours: 2, existing_booking: true, schedule_enabled: false, disabled_reason: 'active_booking_exists' },
      ],
    }],
  };
  const ctx = {
    window: { __activeWorkshopPlannerStage: dedicatedStage, PDC_WORKSHOP_DEPARTMENTS: departments,
      __workshopDataService: { getLastSnapshot: () => { calls.snapshot++; return snapshot; } } },
    workshopState: () => state,
    normalizePmbStage: value => value,
    workshopSharedModeActive: () => shared,
    workshopStageVehicles: stage => { calls.legacy.push(stage); return fallbackRows; },
    WORKSHOP_ELIGIBILITY_RUNTIME: { workshopCanonicalEligibility: () => ({ candidates: [] }) },
    pmbJobDefForStage: () => ({ key: 'bus_work' }),
    displayStockNumber: vehicle => vehicle.stock,
  };
  vm.createContext(ctx);
  for (const name of ['workshopDepartmentLayout', 'workshopCategoryAuthority',
    'workshopSnapshotVehicleToPlannerRow', 'workshopPlannerVehiclesForStage']) {
    vm.runInContext(extract(plannerSource, name), ctx);
  }
  return { ctx, state, snapshot, calls, fallbackRows };
}

test('dedicated shared planner projects current category authority without scanning legacy vehicles', () => {
  const h = candidateFixture();
  const mechanical = h.ctx.workshopPlannerVehiclesForStage('BUS_4X4');
  assert.equal(mechanical.length, 1);
  assert.equal(mechanical[0].sharedVehicleId, 'canonical-vehicle');
  assert.equal(mechanical[0].workshopEstimatedHoursByStage.BUS_4X4, 8);
  assert.equal(mechanical[0].__workshopOutstanding.scheduleEnabled, true);
  h.state.busBayGroup = 'electrical';
  const electrical = h.ctx.workshopPlannerVehiclesForStage('BUS_4X4');
  assert.equal(electrical[0].workshopEstimatedHoursByStage.BUS_4X4, 2);
  assert.equal(electrical[0].__workshopOutstanding.workCategory, 'BUS_ELECTRICAL');
  assert.equal(electrical[0].__workshopOutstanding.existingBooking, true);
  assert.equal(electrical[0].__workshopOutstanding.scheduleEnabled, false);
  assert.equal(electrical[0].__workshopOutstanding.disabledReason, 'active_booking_exists');
  h.snapshot.outstanding_candidates[0].work_categories[1].completed = true;
  assert.equal(h.ctx.workshopPlannerVehiclesForStage('BUS_4X4').length, 0,
    'later snapshot changes are reflected without a cached category projection');
  assert.equal(h.calls.snapshot, 3);
  assert.deepEqual(h.calls.legacy, []);
});

for (const options of [{ dedicatedStage: '', shared: true }, { dedicatedStage: 'FITTING', shared: false }]) {
  test(`legacy candidate fallback remains intact: ${JSON.stringify(options)}`, () => {
    const h = candidateFixture(options);
    assert.equal(h.ctx.workshopPlannerVehiclesForStage('FITTING'), h.fallbackRows);
    assert.deepEqual(h.calls.legacy, ['FITTING']);
    assert.equal(h.calls.snapshot, 0);
  });
}

function renderFixture({ raf = true, scheduler = true } = {}) {
  const pending = new Map(), paints = [];
  let sequence = 0, label = 'initial';
  const host = { set innerHTML(value) { paints.push(value); } };
  const state = { stage: 'FITTING' };
  const schedule = callback => { pending.set(++sequence, callback); return sequence; };
  const cancel = id => pending.delete(id);
  const ctx = {
    app: { currentView: 'workshop' },
    window: { __activeWorkshopPlannerStage: 'FITTING',
      __workshopDataService: { getLastSnapshot: () => null },
      setTimeout: schedule, clearTimeout: cancel,
      ...(raf ? { requestAnimationFrame: schedule, cancelAnimationFrame: cancel } : {}) },
    document: { querySelector: () => host },
    workshopState: () => state,
    workshopSharedModeActive: () => true,
    workshopSyncConfigFromSharedSettings: () => {},
    workshopApplyOpenDateDefault: () => {},
    normalizePmbStage: value => value,
    WORKSHOP_STAGE_SEQUENCE: ['FITTING'],
    WORKSHOP_VISIBLE_STAGE_SEQUENCE: ['FITTING'],
    workshopEnsureDedicatedShell: () => host,
    workshopStationSnapshotEmptyStateHtml: () => label,
  };
  vm.createContext(ctx);
  if (scheduler) {
    vm.runInContext(extract(appSource, 'cancelWorkshopPlannerRender') + '\n'
      + extract(appSource, 'scheduleWorkshopPlannerRender'), ctx);
  }
  vm.runInContext(extract(plannerSource, 'renderWorkshopPlanner'), ctx);
  return { ctx, pending, paints, setLabel: value => { label = value; },
    flush: () => { for (const [id, callback] of [...pending]) { pending.delete(id); callback(); } } };
}

for (const raf of [true, false]) {
  test(`direct planner render consumes queued paint and preserves later refreshes (${raf ? 'animation frame' : 'timer'})`, () => {
    const h = renderFixture({ raf });
    h.ctx.scheduleWorkshopPlannerRender();
    h.ctx.scheduleWorkshopPlannerRender();
    assert.equal(h.pending.size, 1);
    h.setLabel('fresh authoritative state');
    h.ctx.renderWorkshopPlanner();
    h.flush();
    assert.deepEqual(h.paints, ['fresh authoritative state']);
    assert.equal(h.pending.size, 0);
    h.setLabel('later authoritative state');
    h.ctx.scheduleWorkshopPlannerRender();
    h.flush();
    assert.deepEqual(h.paints, ['fresh authoritative state', 'later authoritative state']);
    assert.equal(h.pending.size, 0);
  });
}

test('standalone planner rendering works without the app render scheduler', () => {
  const h = renderFixture({ scheduler: false });
  h.ctx.renderWorkshopPlanner();
  assert.deepEqual(h.paints, ['initial']);
});

test('clock-only projection preserves a queued full render and its legacy reconciliation', () => {
  const h = renderFixture();
  h.ctx.scheduleWorkshopPlannerRender();
  h.setLabel('clock projection');
  h.ctx.renderWorkshopPlanner({ projectionOnly: true });
  assert.equal(h.pending.size, 1, 'projection-only rendering cannot consume normal reconciliation');
  h.setLabel('full refresh');
  h.flush();
  assert.deepEqual(h.paints, ['clock projection', 'full refresh']);
});
