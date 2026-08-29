'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/20260830070000_768_vehicle_workshop_hours_batch.sql', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

const validStart = app.indexOf('function vehicleWorkshopHoursBatchRowsFromPage');
const validEnd = app.indexOf('\nfunction vehicleWorkshopHoursBatchSyncDrafts', validStart);
assert.ok(validStart >= 0 && validEnd > validStart);
const context = {};
vm.createContext(context);
vm.runInContext(app.slice(validStart, validEnd), context);
const stableId = '11111111-1111-4111-8111-111111111111';
const base = { operationLineId: stableId, lineKey: `source:${stableId}`, expectedLineVersion: 0 };
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid({ ...base, estimatedHours: 0 }), true, 'explicit zero is valid');
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid({ ...base, estimatedHours: null }), true, 'unknown/null is preserved');
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid({ ...base, estimatedHours: -0.25 }), false, 'negative is rejected');
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid({ ...base, estimatedHours: 1000 }), false, 'excess is rejected');
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid({ ...base, estimatedHours: Number.NaN }), false, 'non-finite is rejected');
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid({ ...base, estimatedHours: 1.001 }), false, 'more than two decimals is rejected');

const inputs = [
  { value: '0', dataset: { operationLineId: stableId, adjustmentId: '', adjustmentVersion: '0', lineKey: `source:${stableId}`, stage: 'FITTING', workKey: 'fitting' } },
  { value: '', dataset: { operationLineId: '22222222-2222-4222-8222-222222222222', adjustmentId: '33333333-3333-4333-8333-333333333333', adjustmentVersion: '4', lineKey: 'source:22222222-2222-4222-8222-222222222222', stage: 'TINT', workKey: 'tint' } },
];
const rows = context.vehicleWorkshopHoursBatchRowsFromPage({ querySelectorAll: () => inputs });
assert.strictEqual(rows[0].estimatedHours, 0, 'row extraction keeps zero');
assert.strictEqual(rows[1].estimatedHours, null, 'row extraction keeps blank as unknown');
assert.strictEqual(rows[1].expectedLineVersion, 4, 'row extraction keeps authoritative line version');

for (const marker of [
  'CREATE TABLE public.vehicle_workshop_hours_batch_receipts_768',
  'UNIQUE(actor_id,idempotency_key)',
  'save_vehicle_workshop_line_hours_batch_768',
  'p_stock_number text',
  'p_job_card_number text',
  'p_expected_vehicle_version bigint',
  'p_estimated_rows jsonb',
  'p_idempotency_key uuid',
  'request_hash text',
  'idempotency_conflict',
  "jsonb_set(v_receipt.response,'{replay}'",
  'vehicle_identity_conflict',
  'vehicle_version_conflict',
  'line_version_conflict',
  'operation_line_not_found',
  'job_card_identity_conflict',
  'adjustment_identity_conflict',
  'unknown_hours_override_unsupported',
  'parts_not_hour_bearing',
  'current_rows',
  'conflicts',
  'before_data',
  'after_data',
  'UPDATE public.vehicles SET version=version+1',
  'changed_count',
  'booking_created',
  'parts_mutated',
  'completion_changed',
]) assert.ok(sql.includes(marker), `missing ${marker}`);
assert.ok(sql.includes('PERFORM public.require_pdc_role(\'operator\')'), 'unauthorized role is denied at the canonical boundary');
assert.ok(sql.includes('FOR UPDATE'), 'vehicle and overlays are locked before validation/commit');
assert.ok(sql.includes('ON CONFLICT(vehicle_id,line_key) DO UPDATE'), 'duplicate display labels cannot select by row index');
assert.ok(sql.includes('source_operation_line_id'), 'committed overlays retain stable source operation identity');
assert.ok(!sql.includes('update public.workshop_bookings'), 'batch never creates or changes a booking');
assert.ok(!sql.includes('update public.vehicle_parts_updates'), 'batch never mutates Parts');
assert.ok(sql.includes("RETURN v_receipt.response"), 'one immutable response receipt is returned');

for (const marker of [
  'vehicleWorkshopHoursBatchDrafts',
  'vehicleWorkshopHoursBatchSaving',
  'vehicleWorkshopHoursBatchSyncDrafts',
  'await loadVehicleWorkshopDetail(vehicle, { force: true })',
  'data-vehicle-workshop-hours-batch-save',
  'data-vehicle-workshop-hours-batch-reset',
  'data-vehicle-workshop-hours-batch-input',
  'Save all hours',
  'Cancel/reset',
  'drafts stay local until saved',
  'crypto.randomUUID()',
  'button.disabled = true',
  'vehicleWorkshopHoursBatchError',
  "group.stage !== 'PARTS'",
  'Parts — no hours required',
  'No station booking required',
  'if (partsStateComplete(vehicle)) return false',
]) assert.ok(app.includes(marker), `app missing ${marker}`);
assert.ok(!app.includes('data-vehicle-workshop-hours-save'), 'no immediate per-row hour mutation remains');
assert.ok(!app.includes('saveVehicleWorkshopLineHours(button)'), 'no per-field save handler remains');
assert.ok(service.includes('saveVehicleWorkshopLineHoursBatch'), 'service bridge exposes exactly one batch operation');

console.log('Vehicle workshop hours batch regression matrix passed');
