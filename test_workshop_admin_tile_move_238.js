'use strict';
const assert = require('assert');
const fs = require('fs');
const { buildWorkshopSharedActions } = require('./workshop-shared-actions.js');

const calls = [];
const actions = buildWorkshopSharedActions({ mutate: async (name, params) => { calls.push({ name, params }); return { ok: true }; } });

(async () => {
  const requestId = '11111111-1111-4111-8111-111111111111';
  await actions.administratorMoveBooking({
    bookingId: 'b1', expectedVersion: 7, stageCode: 'FITTING', bayNumber: 3,
    scheduledStartAt: '2026-08-14T00:00:00Z', durationMinutes: 120,
    metadata: { source: 'planner_chip_drop' }, requestId, cascade: true,
  });
  assert.deepStrictEqual(calls[0], {
    name: 'administrator_move_workshop_booking', params: {
      p_booking_id: 'b1', p_expected_version: 7, p_stage_code: 'FITTING', p_bay_number: 3,
      p_scheduled_start_at: '2026-08-14T00:00:00Z', p_duration_minutes: 120,
      p_override_reason: null, p_metadata: { source: 'planner_chip_drop' }, p_request_id: requestId, p_cascade: true,
    }
  });
  await actions.undoAdministratorBookingMove({ receiptId: 'r1', expectedVersion: 8, requestId });
  assert.deepStrictEqual(calls[1], { name: 'undo_administrator_workshop_booking_move', params: {
    p_receipt_id: 'r1', p_expected_version: 8, p_request_id: requestId,
  }});

  const service = fs.readFileSync('workshop-data-service.js', 'utf8');
  const planner = fs.readFileSync('workshop-planner.js', 'utf8');
  const sql = fs.readFileSync('supabase/staging_only/238_workshop_admin_tile_move_receipts_and_undo.sql', 'utf8');
  assert(service.includes("'administrator_move_workshop_booking'"));
  assert(service.includes("administrator_move_workshop_booking: 'p_expected_version'"));
  assert(service.includes("'undo_administrator_workshop_booking_move'"));
  assert(planner.includes("window.PDC_AUTH_CONTEXT?.role"));
  assert(planner.includes("? 'administratorMoveBooking'"));
  assert(planner.includes('data-workshop-undo-admin-move'));
  assert(sql.includes("v_role<>'administrator'"));
  assert(sql.includes("session_user<>'authenticator'"));
  assert(sql.includes('revoke execute on function public.move_workshop_booking'));
  assert(sql.includes('workshop_booking_move_receipts'));
  assert(sql.includes('unique(actor_user_id,request_id)'));
  assert(sql.includes("status not in('queued','planned')"));
  assert(sql.includes("return jsonb_build_object('ok',false,'error','undo_conflict')"));
  assert(sql.includes("event_type,before_data,after_data,metadata,actor_user_id,actor_email"));
  console.log('PASS administrator tile move bridge, narrow role, idempotency, audit, protection and Undo contract');
})().catch(error => { console.error(error); process.exit(1); });
