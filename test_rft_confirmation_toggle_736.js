'use strict';
const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260829040000_736_authoritative_rft_confirmation_toggle.sql';
const sql = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8') : '';
const app = fs.readFileSync('app.js', 'utf8');
const serviceSource = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

assert.ok(sql, '736 authoritative RFT confirmation migration exists');
for (const marker of [
  'PDC_736_STAGING_ONLY',
  'pdc_rft_confirmation_receipts_736',
  "action IN('rft_confirmed','rft_unconfirmed')",
  'set_rft_confirmation_736',
  'rft_confirmation_required',
  'rft_confirmation_irreversible',
  'rft_confirmation_stale_version',
  'PDC_736_APPEND_ONLY',
  'PDC_736_SECURITY_POSTCONDITION_FAILED',
  'transport_lifecycle_successor_required',
  'dealer_transit_started_at=coalesce(dealer_transit_started_at,booked_at)',
]) assert.ok(sql.includes(marker), `736 migration marker: ${marker}`);
assert.match(serviceSource, /PDC_RFT_CONFIRMATION_RPC = 'set_rft_confirmation_736'/);
assert.match(serviceSource, /setRftConfirmation736/);
assert.match(serviceSource, /p_confirmed: confirmed === true/);
assert.match(app, /data-rft-confirmation-key/);
assert.match(app, /type="checkbox"/);
assert.match(app, /markRftConfirmation/);
assert.match(app, /setRftConfirmation736/);
assert.match(app, /rft_confirmation_irreversible/);
assert.match(app, /RFT’d/);
assert.doesNotMatch(app.slice(app.indexOf('function rftTransportControlsHtml'), app.indexOf('function rftTransportEmailStatusLabel')), /data-rft-transition-authority="authoritative"/);
assert.doesNotMatch(app.slice(app.indexOf('async function markRftConfirmation'), app.indexOf('function collectedVehicleRows')), /localStorage\.setItem|saveVehicleEdits/);

(async () => {
  const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');
  const calls = [];
  const api = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public' },
    getAccessToken: () => 'token',
    fetchImpl: async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body) });
      return { ok: true, json: async () => ({ ok: true, code: 'rft_confirmed', data: { receipt_id: 'receipt-736', vehicle_id: 'vehicle-736', vehicle_version_after: 8, rft_confirmed: calls.at(-1).body.p_confirmed } }) };
    },
  });
  const checked = await api.setRftConfirmation736('vehicle-736', 7, true, 'idempotency-736-on');
  const unchecked = await api.setRftConfirmation736('vehicle-736', 8, false, 'idempotency-736-off');
  assert.strictEqual(checked.ok, true, 'checked result is accepted');
  assert.strictEqual(unchecked.ok, true, 'permitted unchecked result is accepted');
  assert.deepStrictEqual(calls.map(call => call.body), [
    { p_vehicle_id: 'vehicle-736', p_expected_vehicle_version: 7, p_confirmed: true, p_idempotency_key: 'idempotency-736-on' },
    { p_vehicle_id: 'vehicle-736', p_expected_vehicle_version: 8, p_confirmed: false, p_idempotency_key: 'idempotency-736-off' },
  ], 'toggle service preserves exact vehicle/version/confirmation/idempotency payload');
  console.log('authoritative RFT confirmation toggle 736 contract passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
