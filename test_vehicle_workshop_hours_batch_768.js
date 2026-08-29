'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const serviceSource = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const migrationPath = 'supabase/staging_only/20260830070000_768_vehicle_workshop_hours_batch.sql';

assert.ok(fs.existsSync(migrationPath), 'batch migration must be present');
const sql = fs.readFileSync(migrationPath, 'utf8');
for (const marker of [
  'save_vehicle_workshop_line_hours_batch_768',
  'p_stock_number',
  'p_job_card_number',
  'p_expected_vehicle_version',
  'p_idempotency_key',
  'request_hash',
  'FOR UPDATE',
  'parts_not_hour_bearing',
  'vehicle_version_conflict',
  'line_version_conflict',
  'before_data',
  'after_data',
  'booking_created',
]) assert.ok(sql.includes(marker), `batch migration missing ${marker}`);
assert.ok(!sql.includes('update public.workshop_bookings'), 'hours batch must never mutate bookings');
assert.ok(!sql.includes('update public.vehicle_parts_updates'), 'hours batch must never mutate Parts');

for (const marker of [
  'Save all hours',
  'data-vehicle-workshop-hours-batch-input',
  'data-vehicle-workshop-hours-batch-save',
  'data-vehicle-workshop-hours-batch-reset',
  'saveVehicleWorkshopLineHoursBatch',
]) assert.ok(app.includes(marker), `app missing ${marker}`);
assert.ok(!app.includes('data-vehicle-workshop-hours-save'), 'per-row immediate hour save control must be removed');
assert.ok(serviceSource.includes('save_vehicle_workshop_line_hours_batch_768'), 'service must expose the batch RPC');

const service = require('./pdc-email-vehicle-location-service.js');
const calls = [];
const fakeFetch = async (url, options) => {
  calls.push({ url, options, body: JSON.parse(options.body) });
  return { ok: true, status: 200, async json() {
    return { ok: true, code: 'workshop_hours_batch_saved', data: {
      receipt_id: 'receipt-768', request_sha256: 'a'.repeat(64),
      vehicle_id: '11111111-1111-4111-8111-111111111111', vehicle_version_after: 8,
      changes: [{ operation_line_id: '22222222-2222-4222-8222-222222222222', before: { estimated_hours: 1 }, after: { estimated_hours: 0 } }],
    } };
  } };
};
const api = service.createPdcEmailVehicleLocationService({
  config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public-test-key' },
  getAccessToken: () => 'token',
  fetchImpl: fakeFetch,
});
assert.strictEqual(typeof api.saveVehicleWorkshopLineHoursBatch, 'function');

(async () => {
  const result = await api.saveVehicleWorkshopLineHoursBatch({
    vehicleId: '11111111-1111-4111-8111-111111111111', stockNumber: '13000765', jobCardNumber: 'JC-768',
    expectedVehicleVersion: 7, idempotencyKey: '33333333-3333-4333-8333-333333333333',
    rows: [{ operationLineId: '22222222-2222-4222-8222-222222222222', adjustmentId: null, lineKey: 'source:22222222-2222-4222-8222-222222222222', workKey: 'fitting', stageCode: 'FITTING', expectedLineVersion: 0, estimatedHours: 0 }],
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(calls.length, 1, 'one Save all hours action must make one network mutation');
  assert.strictEqual(calls[0].url.endsWith('/rpc/save_vehicle_workshop_line_hours_batch_768'), true);
  assert.strictEqual(calls[0].body.p_estimated_rows[0].estimated_hours, 0, 'explicit zero must remain zero');
  assert.strictEqual(calls[0].body.p_estimated_rows[0].operation_line_id, '22222222-2222-4222-8222-222222222222');
  console.log('Vehicle workshop batch-hours service contract passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
