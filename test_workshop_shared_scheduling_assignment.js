'use strict';

const assert = require('assert');

global.normalizePmbStage = value => String(value || '').toUpperCase();
global.escapeHtml = value => String(value == null ? '' : value);
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.nowIsoString = () => new Date(2026, 6, 20, 9, 0, 0, 0).toISOString();
global.pmbStageLabel = value => String(value || '');

global.window = {
  alert: () => {},
  addEventListener: () => {},
  workshopSharedModeEnabled: cfg => !!(cfg && cfg.workshop && cfg.workshop.sharedData === true),
  PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
};

const planner = require('./workshop-planner.js');

function configurationRows(leave = []) {
  return {
    day_start_time: { value: '08:00' },
    day_end_time: { value: '16:00' },
    scheduling_increment_minutes: { value: 15 },
    default_booking_duration_minutes: { value: 180 },
    working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'] },
    closures: { value: [] },
    break_windows: { value: [] },
    overtime_windows: { value: [] },
    technician_leave: { value: leave },
  };
}

function installSharedState({ technicians = [], snapshotBookings = [], leave = [] } = {}) {
  const alerts = [];
  window.alert = message => alerts.push(String(message));
  window.__workshopReferenceDataService = {
    getCachedTechnicians: () => ({ state: 'connected_editable', rows: technicians }),
    getCachedWorkshopConfiguration: () => ({ state: 'connected_editable', rows: configurationRows(leave) }),
  };
  window.__workshopDataService = {
    isEnabled: () => true,
    getLastSnapshot: () => ({ bookings: snapshotBookings, active_stoppages: [], vehicles: [] }),
  };
  planner.workshopSyncConfigFromSharedSettings();
  return alerts;
}

function request(assignee, stage = 'HOIST') {
  const start = new Date(2026, 6, 20, 9, 0, 0, 0).toISOString();
  return {
    requestedCandidate: { id: '__new_workshop_booking__', stage, bay: 2, status: 'planned', startAt: start, hours: 2, assignee },
    vehicleRef: { vehicleId: 'vehicle-uuid', version: 7 },
    stageCode: stage,
    bayNumber: 2,
    scheduledStartAt: start,
    durationMinutes: 120,
  };
}

async function attempt(options) {
  const calls = [];
  const ok = await planner.workshopScheduleSharedNewBooking(options, async (name, payload) => {
    calls.push({ name, payload });
    return { ok: true };
  });
  return { ok, calls };
}

async function run() {
  const activeId = '11111111-1111-4111-8111-111111111111';
  installSharedState({ technicians: [{ id: activeId, name: 'Active Tech', active: true }] });
  let result = await attempt(request('Active Tech'));
  assert.strictEqual(result.ok, true, 'active selected technician schedules successfully');
  assert.strictEqual(result.calls.length, 1, 'active selected technician dispatches exactly one action');
  assert.strictEqual(result.calls[0].name, 'cascadeSchedule');
  assert.strictEqual(result.calls[0].payload.shiftMinutes, 120, 'insert cascade delay equals the inserted booking duration');
  assert.strictEqual(result.calls[0].payload.technicianId, activeId, 'stable reference UUID is retained in the scheduling payload');
  console.log('PASS 1: active selected technician dispatches the stable UUID');

  installSharedState({ technicians: [{ id: activeId, name: 'Active Tech', active: true }] });
  result = await attempt(request(''));
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.calls.length, 1);
  assert.strictEqual(result.calls[0].payload.technicianId, null, 'blank selection is an explicit null assignment');
  console.log('PASS 2: blank selection dispatches null');

  result = await attempt(request('', 'SUBLET'));
  assert.strictEqual(result.ok, false, 'Sublet cannot be scheduled through the generic shared booking helper');
  assert.strictEqual(result.calls.length, 0, 'Sublet must be rejected before dispatching any mutation RPC');
  assert.strictEqual(planner.workshopRequireSchedulableCandidate({ ...request('').requestedCandidate, stage: 'SUBLET' }), false, 'Sublet move/resize candidates must fail the shared schedulability guard');
  console.log('PASS 2b: Sublet is rejected before shared mutation dispatch and resize validation');

  let alerts = installSharedState({ technicians: [{ id: activeId, name: 'Active Tech', active: true }] });
  result = await attempt(request('Missing Tech'));
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.calls.length, 0, 'unresolved nonblank selection must dispatch no RPC action');
  assert.ok(alerts.some(message => /could not be matched to an active technician/i.test(message)));
  console.log('PASS 3: unresolved nonblank selection is blocked before dispatch');

  const inactiveId = '22222222-2222-4222-8222-222222222222';
  alerts = installSharedState({
    technicians: [{ id: inactiveId, name: 'Inactive Tech', active: false }],
    snapshotBookings: [{ assignment: { technician_id: inactiveId, technician_name: 'Inactive Tech' } }],
  });
  result = await attempt(request('Inactive Tech'));
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.calls.length, 0, 'inactive technician must not be recovered from the defensive snapshot fallback');
  console.log('PASS 4: inactive technician is blocked before dispatch');

  installSharedState({
    technicians: [{ id: activeId, name: 'Active Tech', active: true }],
    leave: [{ technician_id: activeId, date: '2026-07-20' }],
  });
  result = await attempt(request('Active Tech'));
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.calls.length, 0, 'technician leave must block before dispatch');
  console.log('PASS 5: technician on leave is blocked before dispatch');

  const authoritativeBooking = {
    booking_id: 'booking-uuid',
    version: 1,
    vehicle: { id: 'vehicle-uuid', stock_number: 'SYN-STK-1' },
    stage: { code: 'HOIST' },
    bay: { bay_number: 2 },
    scheduled_start_at: new Date(2026, 6, 20, 9, 0, 0, 0).toISOString(),
    default_duration_minutes: 120,
    assignment: { technician_id: activeId, technician_name: 'Active Tech' },
    status: 'planned',
  };
  const reconciled = planner.workshopMapSnapshotBookingToLegacyRow(authoritativeBooking);
  assert.strictEqual(reconciled.assignee, 'Active Tech');
  assert.strictEqual(reconciled.technicianId, activeId, 'authoritative reconciliation retains the chosen stable technician ID');
  console.log('PASS 6: authoritative snapshot reconciliation retains technician name and UUID');

  const { buildWorkshopSharedActions } = require('./workshop-shared-actions.js');
  const rpcCalls = [];
  const actions = buildWorkshopSharedActions({ mutate: async (name, params) => { rpcCalls.push({ name, params }); return { ok: true }; } });
  await actions.scheduleVehicleWork({
    vehicleId: 'vehicle-uuid', vehicleExpectedVersion: 7, stageCode: 'HOIST', bayNumber: 2,
    scheduledStartAt: new Date(2026, 6, 20, 9, 0, 0, 0).toISOString(), durationMinutes: 120, technicianId: activeId,
  });
  assert.strictEqual(rpcCalls[0].name, 'schedule_vehicle_work');
  assert.strictEqual(rpcCalls[0].params.p_technician_id, activeId, 'bridge sends selected UUID as p_technician_id');
  console.log('PASS 7: shared action bridge sends the selected UUID in p_technician_id');

  console.log('Shared scheduling technician assignment checks passed: 7/7');
}

run().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
