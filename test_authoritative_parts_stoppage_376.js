'use strict';

const assert = require('assert');
const fs = require('fs');
const {
  PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF,
  PDC_PARTS_STOPPAGE_RPC,
  createPdcEmailVehicleLocationService,
} = require('./pdc-email-vehicle-location-service.js');

const app = fs.readFileSync('app.js', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/20260825130000_376_authoritative_parts_stoppage.sql', 'utf8');
const setStart = app.indexOf('async function markVehiclePartsStoppage');
const setEnd = app.indexOf('\nasync function updateVehiclePartsWorstEta', setStart);
const clearStart = app.indexOf('async function clearVehiclePartsStoppage');
const clearEnd = app.indexOf('\nfunction exportPartsCsv', clearStart);
const setBody = app.slice(setStart, setEnd);
const clearBody = app.slice(clearStart, clearEnd);

assert.strictEqual(PDC_PARTS_STOPPAGE_RPC, 'set_pdc_parts_stoppage_376');
for (const body of [setBody, clearBody]) {
  assert.match(body, /authenticatedPartsTarget\(key, vehicle\)/);
  assert.match(body, /await service\.setPartsStoppage\(/);
  assert.match(body, /await refreshEmailVehicleLocations\(\)/);
  assert.match(body, /await refreshSharedVehicleWorkState\(sharedVehicle\)/);
  assert.match(body, /__emailVehicleServerAuthoritative === true/);
}
assert.ok(setBody.includes("app.partsOperationalFilter = 'stoppage'"));
assert.ok(!setBody.includes('offerSalespersonChangeEmail('), 'no email is offered before or instead of authoritative persistence');
assert.match(clearBody, /Reason for clearing Parts STOPPAGE/);

for (const marker of [
  'pdc_parts_stoppage_receipts_376', 'UNIQUE(actor_id,idempotency_key)', 'PDC_376_RECEIPT_APPEND_ONLY',
  "v_vehicle_before.version<>p_expected_version", "v_code:='parts_already_received'", "v_code:='vehicle_inactive_or_issued'",
  'PDC_376_UNAUTHORIZED', 'PDC_376_IDEMPOTENCY_PAYLOAD_MISMATCH', 'replay_containment_verified',
  "'recorded_at',clock_timestamp()", "'reason',v_reason", 'notification_delta',
]) assert.ok(sql.includes(marker), `migration missing ${marker}`);
assert.doesNotMatch(sql, /queue_vehicle_notification\s*\(/i);
assert.doesNotMatch(sql, /GRANT\s+(?:INSERT|UPDATE|DELETE|ALL)\s+ON/i);

(async () => {
  let request;
  const service = createPdcEmailVehicleLocationService({
    config: { url: `https://${PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'key' },
    getAccessToken: () => 'approved-token',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 200, async json() { return { ok: true, code: 'parts_stoppage_recorded', receipt_id: 'receipt-376', vehicle_id: 'vehicle-376', changed: true, vehicle_version_after: 9 }; } };
    },
  });
  const result = await service.setPartsStoppage('vehicle-376', 8, 'set', 'HERMES-TEST delayed component', 'idem-376');
  const body = JSON.parse(request.options.body);
  assert.strictEqual(result.ok, true);
  assert.ok(request.url.endsWith('/rest/v1/rpc/set_pdc_parts_stoppage_376'));
  assert.deepStrictEqual(body, { p_vehicle_id: 'vehicle-376', p_expected_version: 8, p_idempotency_key: 'idem-376', p_action: 'set', p_reason: 'HERMES-TEST delayed component' });
  console.log('authoritative Parts STOPPAGE/recovery contract: PASS');
})().catch(error => { console.error(error); process.exit(1); });
