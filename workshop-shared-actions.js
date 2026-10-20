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

// r417 (F32): a bay category or vehicle rule that does not match (Bay 8 is
// Electrical, Bay 3 is HiAce) comes back as a warning, not an error. Ask the
// planner; if they confirm, send the same change once more with the rules they
// confirmed, under a new request ID. The server logs every override.
function workshopBayRuleRequestId() {
  const cryptoApi = typeof globalThis === 'object' ? globalThis.crypto : null;
  if (cryptoApi && typeof cryptoApi.randomUUID === 'function') return cryptoApi.randomUUID();
  const bytes = new Uint8Array(16);
  if (cryptoApi && typeof cryptoApi.getRandomValues === 'function') cryptoApi.getRandomValues(bytes);
  else for (let i = 0; i < 16; i += 1) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function workshopBayRuleQuestion(result) {
  const lines = result.rules.map(rule => `• ${String(rule?.message || rule?.rule || 'A bay rule does not match.')}`).join('\n');
  return `This bay's rule does not match:\n\n${lines}\n\nBook it here anyway? The override is logged with your name. Choose Cancel to leave everything as it is.`;
}

async function workshopConfirmBayRuleWarning(mutate, name, params, ask) {
  const first = await mutate(name, params);
  if (!first || first.ok !== false || first.warning !== true || first.requires_confirmation !== true
      || !Array.isArray(first.rules) || !first.rules.length) return first;
  const confirmFn = typeof ask === 'function' ? ask
    : (typeof window === 'object' && typeof window.confirm === 'function' ? window.confirm.bind(window) : null);
  if (!confirmFn || !confirmFn(workshopBayRuleQuestion(first))) {
    return { ok: false, error: 'bay_rule_not_confirmed', cancelled: true, rules: first.rules };
  }
  const rules = first.rules.map(rule => String(rule?.rule || '')).filter(Boolean);
  return mutate(name, { ...params, p_metadata: { ...(params.p_metadata || {}), bay_rule_confirm: { rules } }, p_request_id: workshopBayRuleRequestId() });
}

function buildWorkshopSharedActions(dataService, { confirmBayRule = null } = {}) {
  function mutate(name, params) {
    return dataService.mutate(name, params);
  }

  return {
    setBookingTeam({ bookingId, expectedVersion, primaryTechnicianId, helperTechnicianIds, requestId, note }) {
      return mutate('set_pdc_bus_booking_team', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_primary_technician_id: primaryTechnicianId,
        p_helper_technician_ids: helperTechnicianIds || [],
        p_request_id: requestId,
        p_note: note || '',
      });
    },

    recordHelperLabour({ bookingId, expectedVersion, technicianId, workedAt, minutes, note, requestId }) {
      return mutate('record_pdc_bus_helper_labour', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_technician_id: technicianId,
        p_worked_at: workedAt,
        p_minutes: minutes,
        p_note: note,
        p_request_id: requestId,
      });
    },

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

    setStageEstimatedMinutes({ vehicleId, vehicleExpectedVersion, bookingId, bookingExpectedVersion, stageCode, totalMinutes, idempotencyKey }) {
      return mutate('set_workshop_stage_estimated_minutes_407', {
        p_vehicle_id: vehicleId,
        p_expected_vehicle_version: vehicleExpectedVersion,
        p_booking_id: bookingId,
        p_expected_booking_version: bookingExpectedVersion,
        p_stage_code: stageCode,
        p_total_minutes: totalMinutes,
        p_idempotency_key: idempotencyKey,
      });
    },

    cascadeMoveBooking({ bookingId, expectedVersion, stageCode, bayNumber, scheduledStartAt, durationMinutes, overrideReason = null, metadata = {} }) {
      return mutate('cascade_workshop_booking_move', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes,
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

    startWork({ bookingId, expectedVersion, actualStartAt, overrideReason, metadata }) {
      const actionMetadata = { ...(metadata || {}) };
      if (overrideReason) actionMetadata.parts_override_reason = overrideReason;
      return mutate('start_workshop_work', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_actual_start_at: actualStartAt ?? null,
        p_metadata: actionMetadata,
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

    completeVehicleDepartment({ vehicleId, workKey, expectedVehicleVersion, bookingId, expectedBookingVersion, idempotencyKey, requestHash, reason }) {
      return mutate('complete_pdc_vehicle_department_772', {
        p_vehicle_id: vehicleId,
        p_work_key: workKey,
        p_expected_vehicle_version: expectedVehicleVersion,
        p_booking_id: bookingId,
        p_expected_booking_version: expectedBookingVersion,
        p_idempotency_key: idempotencyKey,
        p_request_hash: requestHash,
        p_reason: reason,
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


    createAdminBlock({ expectedRevision, stageCode, bayNumber, blockType, label, scheduledStartAt, durationMinutes, metadata = {}, requestId = null }) {
      const requestKey = requestId || metadata.request_id || (
        typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
          ? crypto.randomUUID()
          : `admin-block-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`
      );
      return mutate('create_workshop_admin_block', {
        p_expected_revision: expectedRevision,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_block_type: blockType,
        p_label: label || null,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes,
        p_metadata: { ...metadata, request_id: requestKey },
      });
    },

    moveAdminBlock({ blockId, expectedVersion, stageCode, bayNumber, scheduledStartAt, metadata }) {
      return mutate('move_workshop_admin_block', {
        p_block_id: blockId,
        p_expected_version: expectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_metadata: metadata || {},
      });
    },

    resizeAdminBlock({ blockId, expectedVersion, durationMinutes, metadata }) {
      return mutate('resize_workshop_admin_block', {
        p_block_id: blockId,
        p_expected_version: expectedVersion,
        p_duration_minutes: durationMinutes,
        p_metadata: metadata || {},
      });
    },

    renameAdminBlock({ blockId, expectedVersion, label, metadata }) {
      return mutate('rename_workshop_admin_block_20260904', {
        p_block_id: blockId,
        p_expected_version: expectedVersion,
        p_label: label,
        p_metadata: metadata || {},
      });
    },

    administratorMoveBooking({ bookingId, expectedVersion, stageCode, bayNumber, scheduledStartAt, durationMinutes, overrideReason = null, metadata = {}, requestId, cascade = false }) {
      return workshopConfirmBayRuleWarning(mutate, 'administrator_move_workshop_booking', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes,
        p_override_reason: overrideReason,
        p_metadata: metadata,
        p_request_id: requestId,
        p_cascade: cascade,
      }, confirmBayRule);
    },

    administratorScheduleVehicle({ vehicleId, vehicleExpectedVersion, stageCode, bayNumber, scheduledStartAt, durationMinutes, technicianId = null, metadata = {}, requestId, cascade = true }) {
      return workshopConfirmBayRuleWarning(mutate, 'administrator_schedule_workshop_vehicle', {
        p_vehicle_id: vehicleId,
        p_vehicle_expected_version: vehicleExpectedVersion,
        p_stage_code: stageCode,
        p_bay_number: bayNumber,
        p_scheduled_start_at: scheduledStartAt,
        p_duration_minutes: durationMinutes,
        p_technician_id: technicianId,
        p_metadata: metadata,
        p_request_id: requestId,
        p_cascade: cascade,
      }, confirmBayRule);
    },

    undoAdministratorBookingMove({ receiptId, expectedVersion, requestId }) {
      return mutate('undo_administrator_workshop_booking_move', {
        p_receipt_id: receiptId,
        p_expected_version: expectedVersion,
        p_request_id: requestId,
      });
    },

    deleteAdminBlock({ blockId, expectedVersion, reason, metadata }) {
      return mutate('delete_workshop_admin_block', {
        p_block_id: blockId,
        p_expected_version: expectedVersion,
        p_reason: reason || null,
        p_metadata: metadata || {},
      });
    },
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { buildWorkshopSharedActions, workshopConfirmBayRuleWarning, workshopBayRuleQuestion };
}
if (typeof window !== 'undefined') {
  window.buildWorkshopSharedActions = buildWorkshopSharedActions;
}
