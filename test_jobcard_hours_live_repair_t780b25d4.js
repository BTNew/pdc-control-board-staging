'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const migrationPath = 'supabase/staging_only/20260908103000_jobcard_hours_live_repair.sql';

const start = app.indexOf('function vehicleWorkshopHoursBatchRowsFromPage');
const end = app.indexOf('\nfunction vehicleWorkshopHoursBatchSyncDrafts', start);
assert.ok(start >= 0 && end > start, 'hours parser/validator seam must exist');
const context = {};
vm.createContext(context);
vm.runInContext(app.slice(start, end), context);

const id = '11111111-1111-4111-8111-111111111111';
const row = raw => ({
  operationLineId: id,
  lineKey: `source:${id}`,
  expectedLineVersion: 0,
  raw,
  estimatedHours: raw === '' ? null : Number(raw),
});
for (const raw of ['1', '1.0', '1.00', '1.5', '0.75', '0', '999.99']) {
  assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid(row(raw)), true, `${raw} must be accepted`);
}
assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid(row('')), true, 'blank must be accepted as unknown/null');
for (const raw of ['-1', 'Infinity', 'NaN', 'abc', '1e2', '0x10', '1.000', '0.001', '1000', '999.999']) {
  assert.strictEqual(context.vehicleWorkshopHoursBatchValueValid(row(raw)), false, `${raw} must be rejected truthfully`);
}

const workInput = { value: '1.5', dataset: { operationLineId: id, adjustmentId: '', adjustmentVersion: '0', lineKey: `source:${id}`, stage: 'FITTING', workKey: 'fitting' } };
const mixedPage = { querySelectorAll: selector => selector === '[data-vehicle-workshop-hours-batch-input]' ? [workInput] : [] };
const mixedRows = context.vehicleWorkshopHoursBatchRowsFromPage(mixedPage);
assert.strictEqual(mixedRows.length, 1, 'mixed Parts/work pages serialize only hour-bearing controls');
assert.strictEqual(mixedRows[0].estimatedHours, 1.5, 'typed/stepper number-input value is preserved');

const detailStart = app.indexOf('function vehicleWorkshopDetailRequestDealerCode');
const detailEnd = app.indexOf('\nfunction vehicleWorkshopHoursBatchDraftValue', detailStart);
assert.ok(detailStart >= 0 && detailEnd > detailStart, 'shared Workshop request/response contract helpers must exist');
const detailContext = { cleanNavisionText: value => String(value ?? '').trim() };
vm.createContext(detailContext);
vm.runInContext(app.slice(detailStart, detailEnd), detailContext);
assert.strictEqual(detailContext.vehicleWorkshopDetailRequestDealerCode({ __sharedNavisionDealerCode: '37047' }, { dealerCode: '14450' }), '37047', 'vehicle authority dealer wins over global config');
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(detailContext.vehicleWorkshopDetailResponse({ vehicle_id: id, requirements: [], bookings: [], line_adjustments: [] }, id))),
  { ok: true, detail: { vehicle_id: id, requirements: [], bookings: [], line_adjustments: [] }, message: '' },
  'complete shared Workshop DTO is accepted',
);
assert.strictEqual(detailContext.vehicleWorkshopDetailResponse({ ok: false, code: 'vehicle_not_in_dealer_scope', data: {} }, id).ok, false, 'structured server rejection stays unavailable');
assert.match(detailContext.vehicleWorkshopDetailResponse({ vehicle_id: id, requirements: [] }, id).message, /incomplete/i, 'partial DTO is rejected truthfully');

const navigation = require('./workshop-navigation.js');
const unknownOverride = navigation.projectWorkshopHours({ sourceEstimatedHours: 1.5, manualHoursUnknown: true });
assert.strictEqual(unknownOverride.schedulingHours, null, 'explicit blank manual override remains unknown instead of falling back to source');
assert.strictEqual(unknownOverride.rule, 'manual_unknown', 'unknown manual override has explicit audited provenance');

const displayStart = app.indexOf('function vehicleWorkshopDisplayLineHours');
const displayEnd = app.indexOf('\nfunction vehicleWorkshopHoursClass', displayStart);
assert.ok(displayStart >= 0 && displayEnd > displayStart, 'line-hour display fallback seam must exist');
const displayContext = {};
vm.createContext(displayContext);
vm.runInContext(app.slice(displayStart, displayEnd), displayContext);
assert.strictEqual(
  displayContext.vehicleWorkshopDisplayLineHours(unknownOverride, 2, 1),
  null,
  'an explicit unknown override must not be replaced by a single-line booking-duration fallback',
);
assert.strictEqual(
  displayContext.vehicleWorkshopDisplayLineHours({ schedulingHours: null, rule: 'unavailable' }, 2, 1),
  2,
  'ordinary unavailable source data retains the established single-line booking fallback',
);

assert.ok(fs.existsSync(migrationPath), 'STAGING successor migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');
for (const marker of [
  'pdc_pilbara_service_operations',
  'source_estimated_hours',
  'effective_estimated_hours',
  "'manual_operator_unknown'",
  'vehicle_workshop_hours_batch_receipts_768',
  'pdc_auditor_vehicle_dealer',
  'FOR UPDATE',
  'changed_count',
  'parts_not_hour_bearing',
]) assert.ok(sql.includes(marker), `migration missing ${marker}`);
assert.ok(!/UPDATE\s+public\.pdc_pilbara_service_operations/i.test(sql), 'immutable Pilbara source rows must never be updated');
assert.ok(!/UPDATE\s+public\.workshop_bookings/i.test(sql), 'hours batch must not mutate bookings');
assert.ok(!/UPDATE\s+public\.vehicle_parts_updates/i.test(sql), 'hours batch must not mutate Parts');
assert.match(
  sql,
  /UPDATE\s+public\.vehicle_workshop_line_adjustments\s+a[\s\S]*?FROM\s+pdc_hours_batch_changes_t780\s+c[\s\S]*?WHERE\s+a\.adjustment_id=c\.current_adjustment_id/i,
  'existing audited overrides must be updated, not silently omitted from the batch',
);
assert.match(
  sql,
  /REVOKE ALL ON FUNCTION public\.get_vehicle_workshop_detail\(uuid\) FROM public,anon,authenticated,service_role/i,
  'the unscoped SECURITY DEFINER Workshop read must not remain browser-executable',
);
assert.match(
  sql,
  /has_function_privilege\('authenticated','public\.get_vehicle_workshop_detail\(uuid\)','execute'\)/i,
  'the migration must verify that authenticated callers cannot bypass the scoped Workshop wrapper',
);
assert.ok(service.includes('p_estimated_rows'), 'complete batch payload remains explicit');

console.log('Job Card live-hours and Workshop contract regression passed');
