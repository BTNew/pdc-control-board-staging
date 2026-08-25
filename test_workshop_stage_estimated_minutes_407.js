'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const actions = fs.readFileSync('workshop-shared-actions.js', 'utf8');
const service = fs.readFileSync('workshop-data-service.js', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/20260826160000_407_workshop_stage_estimated_minutes.sql', 'utf8');

assert.match(planner, /step="any" inputmode="decimal"/);
assert.doesNotMatch(planner, /step="0\.0166666667"/);
assert.match(planner, /const requestedMinutes = Math\.round\(requestedHours \* 60\)/);
assert.match(planner, /workshopDispatchSharedAction\('setStageEstimatedMinutes'/);
assert.match(planner, /workshopVehicle\(key, scopedStage\)/);
assert.match(planner, /pdcQcOperationLinesProjectionPresent === true/);
assert.match(planner, /directOperationLines = \[\]/);

const displayStart = planner.indexOf('function workshopDurationInputValue');
const displayEnd = planner.indexOf('\nfunction workshopStageEstimateSharedPayload', displayStart);
const payloadEnd = planner.indexOf('\nfunction workshopLoadView', displayEnd);
assert.ok(displayStart >= 0 && displayEnd > displayStart && payloadEnd > displayEnd);
const context = {
  Math,
  Number,
  String,
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  workshopNewRequestId: () => '407-test-idempotency',
};
vm.createContext(context);
vm.runInContext(planner.slice(displayStart, payloadEnd), context);
assert.strictEqual(context.workshopDurationInputValue(5), '5');
assert.strictEqual(context.workshopDurationInputValue(5.000000008), '5');
assert.strictEqual(context.workshopDurationInputValue(1.6), '1.6');
assert.strictEqual(context.workshopDurationInputValue(1.9), '1.9');
assert.deepStrictEqual(JSON.parse(JSON.stringify(context.workshopStageEstimateSharedPayload(
  { id: 'vehicle-1', version: 4 },
  { id: 'booking-1', sharedVersion: 2 },
  'fitting',
  Math.round(5 * 60),
))), {
  vehicleId: 'vehicle-1', vehicleExpectedVersion: 4,
  bookingId: 'booking-1', bookingExpectedVersion: 2,
  stageCode: 'FITTING', totalMinutes: 300,
  idempotencyKey: '407-test-idempotency',
});

for (const token of [
  "setStageEstimatedMinutes({ vehicleId, vehicleExpectedVersion, bookingId, bookingExpectedVersion, stageCode, totalMinutes, idempotencyKey })",
  "mutate('set_workshop_stage_estimated_minutes_407'",
  'p_expected_vehicle_version: vehicleExpectedVersion',
  'p_expected_booking_version: bookingExpectedVersion',
  'p_total_minutes: totalMinutes',
]) assert.ok(actions.includes(token), token);
assert.ok(service.includes("'set_workshop_stage_estimated_minutes_407'"));
assert.ok(service.includes("set_workshop_stage_estimated_minutes_407: 'p_expected_booking_version'"));

for (const token of [
  'PDC_407_STAGING_HEAD_OR_CONTAINMENT_MISMATCH',
  "v_head IS DISTINCT FROM '20260826154500'",
  'pdc_workshop_stage_estimate_receipts_407',
  'set_workshop_stage_estimated_minutes_407',
  "pdc.defer_workshop_adjustment_reconcile",
  "v_line_key:='manual:planner-stage:'||v_stage",
  'estimated_minutes_below_authenticated_work',
  'workshop_vehicle_stage_estimated_duration_minutes',
  'cascade_workshop_schedule',
  'PDC_407_CANONICAL_MINUTE_RECONCILIATION_FAILED',
  'PDC_407_BOOKING_READBACK_FAILED',
  'pdc.hermes_test_wrapper_vehicle_365',
  'idempotency_payload_mismatch',
  "GRANT EXECUTE ON FUNCTION public.set_workshop_stage_estimated_minutes_407",
  "VALUES('20260826160000','407_workshop_stage_estimated_minutes'",
]) assert.ok(migration.includes(token), token);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.set_workshop_stage_estimated_minutes_407[^;]+FROM public,anon,authenticated,service_role/);
assert.doesNotMatch(migration, /UPDATE public\.pdc_authenticated_email_operation_lines/i);
assert.doesNotMatch(migration, /DISABLE TRIGGER/i);

console.log('Workshop whole-minute stage estimate 407 contract passed.');
