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

// r424 (F38): a job that would now run into the same vehicle's next booking
// (for example Mechanical running past the booked Electrical start) comes back
// as later_bookings_warning with the exact push-backs. If the planner confirms,
// the same change is sent again with that plan's hash under a new request ID;
// the server re-checks the plan and refuses if anything changed meanwhile.
function workshopPushLaterWhen(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  try {
    return date.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false });
  } catch (_) { return date.toISOString(); }
}

function workshopPushLaterQuestion(result) {
  const lines = result.pushes.map(push => {
    const what = [push?.key_number ? `Key ${push.key_number}` : '', String(push?.work_category || '').replace(/^BUS_/, '').toLowerCase(), push?.bay_number ? `Bay ${push.bay_number}` : '']
      .filter(Boolean).join(' · ');
    return `• ${what}: ${workshopPushLaterWhen(push?.from_start)} → ${workshopPushLaterWhen(push?.to_start)}`;
  }).join('\n');
  return `${String(result.message || 'This job would run into the same vehicle\'s next booking.')}\n\n${lines}\n\nChoose OK to push ${result.pushes.length === 1 ? 'it' : 'them'} back (Perth time). Choose Cancel to leave everything as it is.`;
}

function workshopIsBayRuleWarning(result) {
  return Boolean(result && result.ok === false && result.warning === true && result.requires_confirmation === true
    && Array.isArray(result.rules) && result.rules.length);
}

function workshopIsPushLaterWarning(result) {
  return Boolean(result && result.ok === false && result.warning === true && result.requires_confirmation === true
    && result.error === 'later_bookings_warning' && typeof result.plan_hash === 'string' && result.plan_hash
    && Array.isArray(result.pushes) && result.pushes.length);
}

async function workshopConfirmBayRuleWarning(mutate, name, params, ask) {
  const confirmFn = typeof ask === 'function' ? ask
    : (typeof window === 'object' && typeof window.confirm === 'function' ? window.confirm.bind(window) : null);
  let current = params;
  let result = await mutate(name, current);
  // At most one bay-rule question and one push-back question per change.
  for (let round = 0; round < 2; round += 1) {
    if (workshopIsBayRuleWarning(result)) {
      if (current.p_metadata?.bay_rule_confirm) return result;
      if (!confirmFn || !confirmFn(workshopBayRuleQuestion(result))) {
        return { ok: false, error: 'bay_rule_not_confirmed', cancelled: true, rules: result.rules };
      }
      const rules = result.rules.map(rule => String(rule?.rule || '')).filter(Boolean);
      current = { ...current, p_metadata: { ...(current.p_metadata || {}), bay_rule_confirm: { rules } }, p_request_id: workshopBayRuleRequestId() };
    } else if (workshopIsPushLaterWarning(result)) {
      if (current.p_metadata?.push_later_confirm) return result;
      if (!confirmFn || !confirmFn(workshopPushLaterQuestion(result))) {
        return { ok: false, error: 'later_bookings_not_confirmed', cancelled: true, pushes: result.pushes };
      }
      current = { ...current, p_metadata: { ...(current.p_metadata || {}), push_later_confirm: { plan_hash: result.plan_hash } }, p_request_id: workshopBayRuleRequestId() };
    } else {
      return result;
    }
    result = await mutate(name, current);
  }
  return result;
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

    // r424 (F38): re-order or swap upcoming jobs within one bay. apply=false is
    // a preview only; apply=true must carry the planHash of that preview.
    resequenceBay({ bookingId, expectedVersion, targetBookingId, mode, apply = false, planHash = null, metadata = {}, requestId }) {
      return mutate('workshop_resequence_bay_424', {
        p_booking_id: bookingId,
        p_expected_version: expectedVersion,
        p_target_booking_id: targetBookingId,
        p_mode: mode,
        p_apply: apply === true,
        p_plan_hash: planHash,
        p_metadata: metadata || {},
        p_request_id: requestId,
      });
    },

    undoBayResequence({ receiptId, requestId }) {
      return mutate('workshop_undo_bay_resequence_424', {
        p_receipt_id: receiptId,
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
  module.exports = { buildWorkshopSharedActions, workshopConfirmBayRuleWarning, workshopBayRuleQuestion, workshopPushLaterQuestion };
}
if (typeof window !== 'undefined') {
  window.buildWorkshopSharedActions = buildWorkshopSharedActions;
}
