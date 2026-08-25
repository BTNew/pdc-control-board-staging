'use strict';

const assert = require('assert');
const fs = require('fs');
const service = require('./pdc-email-vehicle-location-service.js');

const sqlPath = 'supabase/staging_only/20260825230000_386_authoritative_salesperson_assignment.sql';
const sql = fs.readFileSync(sqlPath, 'utf8');
const detailSql = fs.readFileSync('supabase/staging_only/20260825232000_388_authoritative_vehicle_detail_fields.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

for (const marker of [
  'pdc_vehicle_salesperson_assignment_receipts_386',
  'pdc_vehicle_salesperson_assignment_history_386',
  'assign_pdc_vehicle_salesperson_386',
  'p_vehicle_id uuid',
  'p_expected_vehicle_version integer',
  'p_salesperson_code text',
  'p_idempotency_key uuid',
  'request_sha256',
  'PDC_386_VEHICLE_VERSION_CONFLICT',
  'PDC_386_IDEMPOTENCY_PAYLOAD_MISMATCH',
  'PDC_386_MANUAL_SALESPERSON_OVERRIDE',
  'PDC_386_SALESPERSON_NOT_ACTIVE',
  'notification_delta',
  'get_pdc_email_vehicle_location_snapshot',
  "'salesperson_code'",
  "'salesperson_name'",
  "'salesperson_email'",
  "NOTIFY pgrst,'reload schema'",
]) assert.ok(sql.includes(marker), `missing contract marker: ${marker}`);

assert.strictEqual(service.PDC_SALESPERSON_ASSIGNMENT_RPC, 'assign_pdc_vehicle_salesperson_386');
assert.strictEqual(service.PDC_VEHICLE_DETAIL_FIELDS_RPC, 'update_pdc_vehicle_detail_fields_388');
assert.strictEqual(service.mapServerVehicle({ salesperson_code: 'BG', salesperson_name: 'Bryce Guthrie', salesperson_email: 'bg@example.test' }).salespersonEmail, 'bg@example.test');
assert.strictEqual(service.mapServerVehicle({ salesperson_code: '', salesperson_name: '', salesperson_email: '' }).consultant, 'Unassigned');
assert.ok(typeof service.createPdcEmailVehicleLocationService === 'function');

assert.match(app, /updateSalespersonAssignment/);
assert.match(app, /salesperson_assignment/);
assert.match(app, /saveAuthoritativeVehicleChanges/);
assert.match(app, /detailChanges\.client_name/);
assert.match(app, /detailChanges\.key_number/);
assert.match(app, /detailChanges\.job_card_number/);
assert.doesNotMatch(app, /saveVehicleEdits\(key, updates\);[\s\S]{0,500}consultant/);
assert.match(html, /pdc-email-vehicle-location-service\.js\?v=/);
for (const marker of ['pdc_vehicle_detail_edit_receipts_388', 'pdc_vehicle_detail_edit_history_388', 'update_pdc_vehicle_detail_fields_388', 'key_not_editable_outside_pmb', 'key_number_in_use', 'client_name_invalid', 'job_card_number_invalid', 'PDC_388_APPEND_ONLY', 'notification_delta']) {
  assert.ok(detailSql.includes(marker), `missing detail contract marker: ${marker}`);
}

(async () => {
  const vehicleId = '11111111-1111-4111-8111-111111111111';
  let requestBody = null;
  const client = service.createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-key' },
    getAccessToken: () => 'test-token',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return { ok: true, status: 200, json: async () => ({
        ok: true, code: 'salesperson_assigned', receipt_id: '33333333-3333-4333-8333-333333333333', request_sha256: 'a'.repeat(64),
        data: { vehicle_id: vehicleId, vehicle_version_after: 4 },
      }) };
    },
  });
  const result = await client.updateSalespersonAssignment(vehicleId, 3, 'cw', '44444444-4444-4444-8444-444444444444');
  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(requestBody, {
    p_vehicle_id: vehicleId,
    p_expected_vehicle_version: 3,
    p_salesperson_code: 'CW',
    p_idempotency_key: '44444444-4444-4444-8444-444444444444',
  });
  console.log('Authoritative salesperson assignment 386 contract: PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
