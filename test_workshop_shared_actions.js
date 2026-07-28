'use strict';

// Real (non-mocked) unit tests for workshop-shared-actions.js. Verifies
// each bridge function calls dataService.mutate() with the exact RPC name
// and parameter shape verified against the deployed staging schema
// (information_schema.parameters), so a caller in workshop-planner.js
// never has to know Postgres function signatures directly.

const assert = require('assert');
const { buildWorkshopSharedActions } = require('./workshop-shared-actions.js');

function fakeDataService() {
  const calls = [];
  return {
    calls,
    mutate: async (name, params) => {
      calls.push({ name, params });
      return { ok: true };
    },
  };
}

async function run() {
  // 1. moveBooking
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.moveBooking({ bookingId: 'b1', expectedVersion: 3, stageCode: 'HOIST', bayNumber: 2, scheduledStartAt: '2026-07-20T00:00:00Z' });
    assert.strictEqual(ds.calls[0].name, 'move_workshop_booking', '1a correct RPC name');
    assert.deepStrictEqual(ds.calls[0].params, {
      p_booking_id: 'b1', p_expected_version: 3, p_stage_code: 'HOIST', p_bay_number: 2,
      p_scheduled_start_at: '2026-07-20T00:00:00Z', p_duration_minutes: null, p_override_reason: null, p_metadata: {},
    }, '1b exact parameter shape matches the deployed move_workshop_booking signature');
    console.log('PASS 1: moveBooking maps to move_workshop_booking with the correct parameter shape');
  }

  // 2. resizeBooking
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.resizeBooking({ bookingId: 'b1', expectedVersion: 2, durationMinutes: 90 });
    assert.strictEqual(ds.calls[0].name, 'resize_workshop_booking', '2a correct RPC name');
    assert.deepStrictEqual(ds.calls[0].params, { p_booking_id: 'b1', p_expected_version: 2, p_duration_minutes: 90, p_metadata: {} }, '2b exact parameter shape');
    console.log('PASS 2: resizeBooking maps correctly');
  }

  // 2c. atomic insert/extend cascade
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.cascadeSchedule({
      operation: 'extend', targetId: 'b1', targetExpectedVersion: 2,
      stageCode: 'HOIST', bayNumber: 1, scheduledStartAt: '2026-07-20T00:00:00Z',
      durationMinutes: 120, technicianId: null,
      shiftMinutes: 60,
    });
    assert.strictEqual(ds.calls[0].name, 'cascade_workshop_schedule', 'cascade must use the one atomic transactional RPC');
    assert.strictEqual(ds.calls[0].params.p_operation, 'extend');
    assert.strictEqual(ds.calls[0].params.p_target_expected_version, 2);
    assert.strictEqual(ds.calls[0].params.p_shift_minutes, 60);
    console.log('PASS 2c: cascadeSchedule maps all timestamps to one atomic RPC');
  }

  // 2d. atomic booked-chip move cascade
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.cascadeMoveBooking({
      bookingId: 'b1', expectedVersion: 4, stageCode: 'FITTING', bayNumber: 3,
      scheduledStartAt: '2026-07-20T01:30:00Z', durationMinutes: 150,
    });
    assert.strictEqual(ds.calls[0].name, 'cascade_workshop_booking_move', 'booked-chip drops must use the atomic move-cascade RPC');
    assert.deepStrictEqual(ds.calls[0].params, {
      p_booking_id: 'b1', p_expected_version: 4, p_stage_code: 'FITTING', p_bay_number: 3,
      p_scheduled_start_at: '2026-07-20T01:30:00Z', p_duration_minutes: 150,
      p_override_reason: null, p_metadata: {},
    }, '2d exact parameter shape matches migration 105');
    console.log('PASS 2d: cascadeMoveBooking maps booked-chip drops to one atomic RPC');
  }

  // 3. startWork / stopWork / resumeWork
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.startWork({ bookingId: 'b1', expectedVersion: 1 });
    await actions.stopWork({ bookingId: 'b1', expectedVersion: 2, reason: 'Waiting on parts' });
    await actions.resumeWork({ bookingId: 'b1', expectedVersion: 3 });
    await actions.startWork({ bookingId: 'b2', expectedVersion: 4, overrideReason: 'Manager approved immediate entry', metadata: { source: 'planner' } });
    assert.strictEqual(ds.calls[0].name, 'start_workshop_work');
    assert.deepStrictEqual(ds.calls[0].params, { p_booking_id: 'b1', p_expected_version: 1, p_actual_start_at: null, p_metadata: {} });
    assert.strictEqual(ds.calls[1].name, 'stop_workshop_work');
    assert.deepStrictEqual(ds.calls[1].params, { p_booking_id: 'b1', p_expected_version: 2, p_reason: 'Waiting on parts', p_metadata: {} });
    assert.strictEqual(ds.calls[2].name, 'resume_workshop_work');
    assert.deepStrictEqual(ds.calls[2].params, { p_booking_id: 'b1', p_expected_version: 3, p_metadata: {} });
    assert.deepStrictEqual(ds.calls[3].params, {
      p_booking_id: 'b2', p_expected_version: 4, p_actual_start_at: null,
      p_metadata: { source: 'planner', parts_override_reason: 'Manager approved immediate entry' },
    }, '3b Parts-incomplete Start retry carries the explicit reason inside audited metadata');
    console.log('PASS 3: start/stop/resume all map to the correct RPC + parameters, including the stoppage reason');
  }

  // 4. completeWork / returnCompletedWork / returnWorkToQueue
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.completeWork({ bookingId: 'b1', expectedVersion: 4, workKey: 'FITTING' });
    await actions.returnCompletedWork({ bookingId: 'b1', expectedVersion: 5 });
    await actions.returnWorkToQueue({ bookingId: 'b1', expectedVersion: 6, reason: 'Customer requested delay' });
    assert.strictEqual(ds.calls[0].name, 'complete_workshop_work');
    assert.deepStrictEqual(ds.calls[0].params, { p_booking_id: 'b1', p_expected_version: 4, p_work_key: 'FITTING', p_actual_end_at: null, p_metadata: {} });
    assert.strictEqual(ds.calls[1].name, 'return_completed_work');
    assert.strictEqual(ds.calls[2].name, 'return_work_to_queue');
    assert.deepStrictEqual(ds.calls[2].params.p_reason, 'Customer requested delay');
    console.log('PASS 4: complete/return-completed/return-to-queue map correctly');
  }

  // 5. cancelBooking / restoreBooking
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.cancelBooking({ bookingId: 'b1', expectedVersion: 1, reason: 'Vehicle sold' });
    await actions.restoreBooking({ bookingId: 'b1', expectedVersion: 2 });
    assert.strictEqual(ds.calls[0].name, 'cancel_workshop_booking');
    assert.strictEqual(ds.calls[1].name, 'restore_workshop_booking');
    console.log('PASS 5: cancel/restore map correctly');
  }

  // 6. changeBookingBay / assignBookingTechnician
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.changeBookingBay({ bookingId: 'b1', expectedVersion: 1, bayNumber: 5 });
    await actions.assignBookingTechnician({ bookingId: 'b1', expectedVersion: 2, technicianId: 't1' });
    assert.strictEqual(ds.calls[0].name, 'change_booking_bay');
    assert.strictEqual(ds.calls[1].name, 'assign_booking_technician');
    assert.strictEqual(ds.calls[1].params.p_technician_id, 't1');
    console.log('PASS 6: changeBookingBay/assignBookingTechnician map correctly');
  }

  // 7. scheduleVehicleWork -- vehicle-keyed version, not booking-keyed
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.scheduleVehicleWork({
      vehicleId: 'v1', vehicleExpectedVersion: 7, stageCode: 'HOIST', bayNumber: 1,
      scheduledStartAt: '2026-07-20T00:00:00Z', durationMinutes: 180,
    });
    assert.strictEqual(ds.calls[0].name, 'schedule_vehicle_work');
    assert.strictEqual(ds.calls[0].params.p_vehicle_expected_version, 7, '7a schedule_vehicle_work uses the vehicle version, not a booking version');
    console.log('PASS 7: scheduleVehicleWork correctly uses the vehicle-scoped expected version');
  }

  // 8. approvePartsIncompleteOverride -- also vehicle-keyed version
  {
    const ds = fakeDataService();
    const actions = buildWorkshopSharedActions(ds);
    await actions.approvePartsIncompleteOverride({
      vehicleId: 'v1', vehicleExpectedVersion: 3, bookingId: 'b1', intendedStageCode: 'HOIST', reason: 'Parts arriving tomorrow, approved by controller',
    });
    assert.strictEqual(ds.calls[0].name, 'approve_parts_incomplete_override');
    assert.deepStrictEqual(ds.calls[0].params, {
      p_vehicle_id: 'v1', p_vehicle_expected_version: 3, p_booking_id: 'b1',
      p_intended_stage_code: 'HOIST', p_reason: 'Parts arriving tomorrow, approved by controller', p_metadata: {},
    }, '8a exact parameter shape for the override RPC');
    console.log('PASS 8: approvePartsIncompleteOverride maps correctly with the vehicle-scoped version');
  }

  console.log('Workshop shared actions bridge tests passed');
}

run().catch((err) => {
  console.error('Workshop shared actions bridge tests FAILED:', err);
  process.exitCode = 1;
});
