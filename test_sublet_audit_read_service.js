'use strict';

const assert = require('assert');
const serviceModule = require('./pdc-email-vehicle-location-service');

(async () => {
  let request;
  const service = serviceModule.createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public-test-key' },
    getAccessToken: () => 'auditor-token',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 200, json: async () => ({ ok: true, code: 'ok', data: { booking_instances: [], booking_history: [], email_update_receipts: [] } }) };
    },
  });
  const result = await service.readSubletAuditLedgers('b3c293fb-0453-56da-86a6-9c3511cc2fe7', '13080534', 'J139125425');
  assert.deepStrictEqual(result, { ok: true, code: 'ok', data: { booking_instances: [], booking_history: [], email_update_receipts: [] } });
  assert.ok(request.url.endsWith('/rest/v1/rpc/get_pdc_sublet_audit_ledgers'));
  assert.strictEqual(request.options.method, 'POST');
  assert.strictEqual(request.options.headers.Authorization, 'Bearer auditor-token');
  assert.deepStrictEqual(JSON.parse(request.options.body), {
    p_vehicle_id: 'b3c293fb-0453-56da-86a6-9c3511cc2fe7',
    p_stock_number: '13080534',
    p_job_card_number: 'J139125425',
  });
  console.log('Sublet authenticated ledger read service contract passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
