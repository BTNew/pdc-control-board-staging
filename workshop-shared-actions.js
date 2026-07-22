'use strict';

/*
 * Workshop shared actions bridge.
 *
 * Maps each Workshop Planner user action to the exact protected
 * transactional RPC + parameter shape defined by migration 010, and wraps
 * the data service's mutate() so callers get one clean async contract:
 *
 *   await workshopSharedActions.moveBooking({...})
 *     -> { ok: true, ... }            success: caller re-renders from the
 *                                       data service's now-reconciled
 *                                       snapshot (already refreshed by
 *                                       mutate() itself)
 *     -> { ok: false, error: '...' }   caller shows the error and re-renders
 *                                       from the (also already refreshed)
 *                                       authoritative snapshot -- the
 *                                       rejected change is never left
 *                                       displayed
 *
 * Parameter names/order below are verified directly against the deployed
 * staging schema (information_schema.parameters for each function), not
 * assumed from the migration source alone.
 *
 * This module contains NO DOM code and NO legacy-row-shape knowledge; it
 * only knows the RPC contract. workshop-planner.js is responsible for
 * calling the right bridge function at the top of each existing action
 * function when workshopSharedModeActive() is true, and for re-rendering
 * afterwards either way.
 */

function buildWorkshopSharedActions(dataService) {
  function mutate(name, params) {
    return dataService.mutate(name, params);
  }

  return {
    scheduleVehicleWork({ vehicleId, vehicleExpectedVersion, stageCode, bayNumber, scheduledStartAt, durationMinutes, technicianId, overrideReason, metadata }) {
      return mutate('schedule_vehicle_work', {
        p_vehicle_id: vehicleId,
        p_vehicle_expected_version: vehicleExpectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes,
        p_technician_id: technicianId ?? null,
        p_override_reason: overrideReason ?? null,
        p_metadata: metadata || {},
      });
    },

    moveBooking({ bookingId, expectedVersion, stageCode, bayNumber, scheduledStartAt, durationMinutes, overrideReason, metadata }) {
      return mutate('move_workshop_booking', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes ?? null,
        p_override_reason: overrideReason ?? null,
        p_metadata: metadata || {},
      });
    },

    resizeBooking({ bookingId, expectedVersion, durationMinutes, metadata }) {
      return mutate('resize_workshop_booking', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_duration_minutes: durationMinutes,
        p_metadata: metadata || {},
      });
    },

    cascadeSchedule({ operation, targetId, targetExpectedVersion, stageCode, bayNumber, scheduledStartAt, durationMinutes, technicianId = null, shiftMinutes = 0, overrideReason = null, metadata = {} }) {
      return mutate('cascade_workshop_schedule', {
        p_operation: operation,
        p_target_id: targetId,
        p_target_expected_version: targetExpectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes,
        p_technician_id: technicianId || null,
        p_shift_minutes: shiftMinutes,
        p_override_reason: overrideReason || null,
        p_metadata: metadata,
      });
    },

    changeBookingBay({ bookingId, expectedVersion, bayNumber, metadata }) {
      return mutate('change_booking_bay', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_bay_number: bayNumber,
        p_metadata: metadata || {},
      });
    },

    assignBookingTechnician({ bookingId, expectedVersion, technicianId, metadata }) {
      return mutate('assign_booking_technician', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_technician_id: technicianId ?? null,
        p_metadata: metadata || {},
      });
    },

    startWork({ bookingId, expectedVersion, actualStartAt, metadata }) {
      return mutate('start_workshop_work', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_actual_start_at: actualStartAt ?? null,
        p_metadata: metadata || {},
      });
    },

    stopWork({ bookingId, expectedVersion, reason, metadata }) {
      return mutate('stop_workshop_work', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_reason: reason,
        p_metadata: metadata || {},
      });
    },

    resumeWork({ bookingId, expectedVersion, metadata }) {
      return mutate('resume_workshop_work', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_metadata: metadata || {},
      });
    },

    completeWork({ bookingId, expectedVersion, workKey, actualEndAt, metadata }) {
      return mutate('complete_workshop_work', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_work_key: workKey ?? null,
        p_actual_end_at: actualEndAt ?? null,
        p_metadata: metadata || {},
      });
    },

    returnCompletedWork({ bookingId, expectedVersion, reason, metadata }) {
      return mutate('return_completed_work', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_reason: reason ?? null,
        p_metadata: metadata || {},
      });
    },

    returnWorkToQueue({ bookingId, expectedVersion, reason, metadata }) {
      return mutate('return_work_to_queue', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_reason: reason ?? null,
        p_metadata: metadata || {},
      });
    },

    cancelBooking({ bookingId, expectedVersion, reason, metadata }) {
      return mutate('cancel_workshop_booking', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_reason: reason ?? null,
        p_metadata: metadata || {},
      });
    },

    restoreBooking({ bookingId, expectedVersion, metadata }) {
      return mutate('restore_workshop_booking', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_metadata: metadata || {},
      });
    },

    approvePartsIncompleteOverride({ vehicleId, vehicleExpectedVersion, bookingId, intendedStageCode, reason, metadata }) {
      return mutate('approve_parts_incomplete_override', {
        p_vehicle_id: vehicleId,
        p_vehicle_expected_version: vehicleExpectedVersion,
        p_booking_id: bookingId ?? null,
        p_intended_stage_code: intendedStageCode ?? null,
        p_reason: reason,
        p_metadata: metadata || {},
      });
    },
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { buildWorkshopSharedActions };
}
if (typeof window !== 'undefined') {
  window.buildWorkshopSharedActions = buildWorkshopSharedActions;
}
