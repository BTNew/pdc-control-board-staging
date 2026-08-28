'use strict';
const assert = require('assert');
const fs = require('fs');

const sqlPath = 'supabase/staging_only/20260829000000_734_durable_rft_transport_lifecycle.sql';
const sql = fs.existsSync(sqlPath) ? fs.readFileSync(sqlPath, 'utf8') : '';
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const stagingConfig = fs.readFileSync('pdc-supabase-config.staging.js', 'utf8');
const productionConfig = fs.existsSync('pdc-supabase-config.production.js') ? fs.readFileSync('pdc-supabase-config.production.js', 'utf8') : '';
const stagingHtml = fs.readFileSync('index.html', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');

assert.ok(sql, '734 durable RFT successor migration exists');
for (const marker of [
  'PDC_734_STAGING_ONLY',
  'pdc_rft_transport_lifecycle_receipts_734',
  'pdc_rft_transport_email_outbox_734',
  'pdc_rft_transport_email_evidence_734',
  'pdc_rft_dealer_transit_statistics_734',
  'book_rft_transport_734',
  'collect_rft_transport_734',
  'reconcile_navision_delivery_734',
  'Delivered - At Dealer',
  'dealer_transit_started_at',
  'dealer_transit_duration_seconds',
  "current_location='Collected'",
  "lifecycle_state='rft'",
  'started_booking_must_be_completed_before_collection',
  "'delivery_enabled',false",
  "'intercepted',true",
  'PDC_734_APPEND_ONLY',
  'transport_booking_required',
  'qc_items_required',
  "status::text IN('queued','planned','stoppage')",
  'old mail/Navision',
]) assert.ok(sql.includes(marker), `734 migration marker: ${marker}`);
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.rft_collect_vehicle[\s\S]*transport_lifecycle_successor_required/);
assert.match(sql, /CREATE FUNCTION public\.reconcile_navision_operational_record\([\s\S]*protected_collected_lifecycle/);
assert.match(service, /PDC_DURABLE_RFT_BOOK_RPC = 'book_rft_transport_734'/);
assert.match(service, /PDC_DURABLE_RFT_COLLECT_RPC = 'collect_rft_transport_734'/);
assert.match(service, /bookRftTransport734/);
assert.match(service, /collectRftTransport734/);
assert.match(service, /read_pdc_rft_transport_evidence_734/);
assert.match(app, /RFT Booked/);
assert.match(app, /Collected/);
assert.match(app, /bookRftTransport739\(vehicle\.__emailVehicleId/);
assert.match(app, /collectRftTransport734\(vehicle\.__emailVehicleId/);
assert.match(app, /vehicleRftCollectionEnabled/);
assert.match(app, /delivery_enabled/);
assert.match(stagingConfig, /durableRftLifecycle/);
assert.match(stagingConfig, /734/);
assert.match(stagingHtml, /id="collected-vehicles-content"/);
assert.match(css, /rft-booked-button/);
assert.match(css, /collected/);
assert.match(app, /!vehicleInCollectedState\(vehicle\)/);
assert.match(app, /Delivered vehicle history/);
assert.match(app, /durableRftLifecycleEnabled\(\)/);
assert.match(sql, /PDC_734_SECURITY_POSTCONDITION_FAILED/);
assert.match(sql, /protected_completed_lifecycle/);
if (productionConfig) assert.doesNotMatch(productionConfig, /durableRftLifecycle/);
assert.doesNotMatch(app.slice(app.indexOf('async function markRftVehicleCollected'), app.indexOf('function bindRftCollectedInputs')), /saveVehicleEdits/);

(async () => {
  const { createPdcEmailVehicleLocationService, mapServerVehicle } = require('./pdc-email-vehicle-location-service');
  const calls = [];
  const api = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public' },
    getAccessToken: () => 'token',
    fetchImpl: async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body) });
      const isRead = url.includes('read_pdc_rft_transport_evidence_734');
      const body = isRead
        ? { ok: true, code: 'rft_transport_evidence', receipts: [], outbox: [], email_evidence: [], statistics: [] }
        : { ok: true, code: 'rft_transport_booked', data: { receipt_id: 'receipt-734', vehicle_id: calls.at(-1).body.p_vehicle_id } };
      return { ok: true, json: async () => body };
    },
  });
  await api.bookRftTransport734('vehicle-734', 4, 'key-734');
  await api.collectRftTransport734('vehicle-734', 5, 'key-735');
  await api.readRftTransportEvidence734('vehicle-734');
  assert.deepStrictEqual(calls.map(call => call.body), [
    { p_vehicle_id: 'vehicle-734', p_expected_vehicle_version: 4, p_idempotency_key: 'key-734' },
    { p_vehicle_id: 'vehicle-734', p_expected_vehicle_version: 5, p_idempotency_key: 'key-735' },
    { p_vehicle_id: 'vehicle-734' },
  ], '734 service methods preserve canonical UUID/version/idempotency payloads');
  const collected = mapServerVehicle({ id: 'vehicle-734', permanent_vehicle_id: 'pdc-734', current_location: 'Collected', lifecycle_state: 'rft', pdc_lifecycle: { state: 'collected' }, rft_transport_outbox: { intercepted: true, delivery_enabled: false, evidence: { photo_receipt_id: 'photo', mime_sha256: 'hash' } } });
  assert.strictEqual(collected.vehicleCollectedState, true, 'Collected projection remains distinct from Completed');
  assert.strictEqual(collected.vehicleDeliveredState, false, 'Collected projection is not delivered');
  assert.strictEqual(collected.rftTransportEmailEvidence.photo_receipt_id, 'photo', 'MIME/photo evidence projects from the authoritative outbox');
  console.log('durable RFT transport lifecycle 734 contract passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
