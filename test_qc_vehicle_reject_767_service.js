'use strict';

const assert = require('assert');
const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');

const vehicleId = 'd777b071-a2b0-5367-893b-aa83a07fcfce';
const stock = '13000769';
const token = 'header.' + Buffer.from(JSON.stringify({ sub: '8a83b715-8d79-4b0e-95b2-02b55da6e8d7' })).toString('base64url') + '.signature';
const response = (body, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => body });

(async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return response({ ok: true, code: 'qc_vehicle_rejected_to_pmb_stoppage', receipt_id: '76600000-0000-5000-8000-000000000766', vehicle_id: vehicleId, stock_number: stock, vehicle_version_after: 35, status: 'Pending QC fixes', current_location: 'PMB', workshop_status: 'stoppage', notification_delta: 0 });
  };
  const service = createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'staging-test-key' }, getAccessToken: () => token, fetchImpl });
  const result = await service.rejectQcVehicleToPmb(vehicleId, stock, 34, 'Damage to rear bumper', '76600000-0000-5000-8000-000000000001');
  assert.strictEqual(result.ok, true);
  assert.strictEqual(calls.length, 1);
  assert.ok(calls[0].url.endsWith('/rpc/reject_pdc_qc_vehicle_to_pmb_stoppage_767'));
  assert.deepStrictEqual(JSON.parse(calls[0].init.body), { p_vehicle_id: vehicleId, p_stock_number: stock, p_expected_vehicle_version: 34, p_reason: 'Damage to rear bumper', p_idempotency_key: '76600000-0000-5000-8000-000000000001' });

  const rejected = createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'staging-test-key' }, getAccessToken: () => token, fetchImpl: async () => response({ ok: false, code: 'PDC_767_VEHICLE_VERSION_CONFLICT' }, 409) });
  assert.strictEqual((await rejected.rejectQcVehicleToPmb(vehicleId, stock, 34, 'incomplete work', '76600000-0000-5000-8000-000000000002')).ok, false);
  assert.strictEqual((await rejected.rejectQcVehicleToPmb('00000000-0000-4000-8000-000000000000', stock, 34, 'incomplete work', '76600000-0000-5000-8000-000000000003')).ok, false);
  assert.strictEqual((await rejected.rejectQcVehicleToPmb(vehicleId, 'WRONG', 34, 'incomplete work', '76600000-0000-5000-8000-000000000004')).ok, false);
  assert.strictEqual((await rejected.rejectQcVehicleToPmb(vehicleId, stock, 34, '', '76600000-0000-5000-8000-000000000005')).ok, false);
  assert.strictEqual((await rejected.rejectQcVehicleToPmb(vehicleId, stock, 34, 'incomplete work', '76600000-0000-5000-8000-000000000006')).ok, false);
  assert.strictEqual(calls.some(call => /finalize|rft|email|outbox/i.test(call.url)), false);
  console.log('QC vehicle reject 767 service contract passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
