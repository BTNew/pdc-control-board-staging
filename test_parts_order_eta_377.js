'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const {
  PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF,
  PDC_PARTS_ORDERED_RPC,
  createPdcEmailVehicleLocationService,
} = require('./pdc-email-vehicle-location-service.js');

const app = fs.readFileSync('app.js', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/20260825140000_377_parts_order_requires_eta.sql', 'utf8');
assert.strictEqual(PDC_PARTS_ORDERED_RPC, 'mark_pdc_parts_ordered_377');
assert.ok(app.includes('function partsHasValidAuthoritativeEta'));
assert.ok(app.includes('Set Parts ETA before marking ordered'));
assert.match(app, /data-parts-ordered=[\s\S]{0,300}canMarkOrdered \? '' : ' disabled'/);
const orderedStart = app.indexOf('async function markVehiclePartsOrdered');
const orderedEnd = app.indexOf('\nasync function markVehiclePartsComplete', orderedStart);
const ordered = app.slice(orderedStart, orderedEnd);
assert.ok(ordered.indexOf('await refreshEmailVehicleLocations()') < ordered.indexOf('partsHasValidAuthoritativeEta(vehicle)'), 'click re-fetches before ETA decision');
assert.ok(ordered.includes('partsHasValidAuthoritativeEta(sharedVehicle)'), 'resolved authoritative target is rechecked before service mutation');
assert.ok(ordered.includes('crypto.randomUUID()'));
assert.ok(!ordered.includes('saveVehicleEdits('), 'ordered action has no local fallback');

const helperStart = app.indexOf('function partsWorstEtaValue');
const helperEnd = app.indexOf('\nfunction partsWorstEtaInputValue', helperStart);
const context = { cleanNavisionText: value => String(value || '').trim(), parseDateAU: () => null, parseIsoTimestamp: () => null };
vm.createContext(context);
vm.runInContext(app.slice(helperStart, helperEnd), context);
assert.strictEqual(context.partsHasValidAuthoritativeEta({ __emailVehicleServerAuthoritative: true, pdcPartsWorstEta: '2026-09-01' }), true);
assert.strictEqual(context.partsHasValidAuthoritativeEta({ __emailVehicleServerAuthoritative: true, pdcPartsWorstEta: '' }), false);
assert.strictEqual(context.partsHasValidAuthoritativeEta({ __emailVehicleServerAuthoritative: true, pdcPartsWorstEta: '2026-02-31' }), false);
assert.strictEqual(context.partsHasValidAuthoritativeEta({ pdcPartsWorstEta: '2026-09-01' }), false);

for (const marker of [
  'pdc_parts_order_receipts_377', 'pdc_parts_order_requires_eta_377', 'PDC_PARTS_ETA_REQUIRED', "'code','parts_eta_required'",
  'mark_pdc_parts_ordered_377', 'PDC_377_UNAUTHORIZED', 'vehicle_version_conflict', 'parts_already_received',
  'PDC_377_IDEMPOTENCY_PAYLOAD_MISMATCH', 'replay_containment_verified', 'authoritative_eta',
]) assert.ok(sql.includes(marker), `migration missing ${marker}`);
assert.doesNotMatch(sql, /queue_vehicle_notification\s*\(/i);

(async () => {
  let request;
  const service = createPdcEmailVehicleLocationService({
    config: { url: `https://${PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'key' },
    getAccessToken: () => 'approved-token',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 200, async json() { return { ok: true, code: 'parts_ordered', receipt_id: 'receipt-377', vehicle_id: 'vehicle-377', changed: true, vehicle_version_after: 12 }; } };
    },
  });
  const result = await service.markPartsOrdered('vehicle-377', 11, 'idem-377');
  const body = JSON.parse(request.options.body);
  assert.strictEqual(result.ok, true);
  assert.ok(request.url.endsWith('/rest/v1/rpc/mark_pdc_parts_ordered_377'));
  assert.deepStrictEqual(body, { p_vehicle_id: 'vehicle-377', p_expected_version: 11, p_idempotency_key: 'idem-377' });
  console.log('Parts ordered ETA prerequisite contract: PASS');
})().catch(error => { console.error(error); process.exit(1); });
