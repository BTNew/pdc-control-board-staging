'use strict';

const assert = require('assert');
const fs = require('fs');
const serviceSource = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const appSource = fs.readFileSync('app.js', 'utf8');
const {
  PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF,
  PDC_PARTS_COMPLETE_RPC,
  PDC_PARTS_COMPLETE_SUCCESS_CODES,
  createPdcEmailVehicleLocationService,
} = require('./pdc-email-vehicle-location-service.js');

function ok(value, message) {
  assert.ok(value, message);
}

(async () => {
  ok(PDC_PARTS_COMPLETE_RPC === 'mark_pdc_parts_complete', 'shared Parts complete RPC name is explicit');
  ok(PDC_PARTS_COMPLETE_SUCCESS_CODES.has('parts_completed') && PDC_PARTS_COMPLETE_SUCCESS_CODES.has('replayed'), 'completion accepts only receipt-backed mutation outcomes');
  ok(serviceSource.includes('async function markPartsComplete'), 'shared Parts service exposes Mark Complete');
  ok(serviceSource.includes('PDC_PARTS_COMPLETE_RPC'), 'shared Parts service uses the complete RPC constant');
  ok(serviceSource.includes('markPartsComplete, vehicleHistory'), 'shared service returns Mark Complete');
  ok(appSource.includes('function vehicleLocationsScreenRows') && appSource.includes('return vehicleLocationsScreenRows().filter(partsQueueVisibleVehicle)'), 'Parts source is derived from the Vehicle Locations row set');
  ok(appSource.includes('function partsStateComplete') && appSource.includes('.filter(partsQueueVisibleVehicle)'), 'completed Parts state is excluded from the Parts queue');
  ok(appSource.includes('service.markPartsComplete') && appSource.includes('await service.markPartsComplete('), 'authoritative UI routes Mark Complete through the shared service');
  ok(/async function markVehiclePartsComplete[\s\S]*?authenticatedPartsTarget\(key, vehicle\)[\s\S]*?markPartsComplete[\s\S]*?receipt-backed/.test(appSource), 'manual Mark Complete resolves the canonical shared target and reconciles receipt-backed state');
  const manualCompleteSource = appSource.slice(appSource.indexOf('async function markVehiclePartsComplete'), appSource.indexOf('function markVehiclePartsStoppage'));
  ok(manualCompleteSource.includes('await refreshEmailVehicleLocations()') && !manualCompleteSource.includes('saveVehicleEdits('), 'manual completion removes/ticks only after authoritative snapshot reconciliation, never by a local guess');

  let request = null;
  const service = createPdcEmailVehicleLocationService({
    config: { url: `https://${PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'key' },
    getAccessToken: () => 'approved-token',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 200, async json() { return { ok: true, code: 'parts_completed', data: { receipt_id: 'receipt-1', vehicle_id: 'vehicle-uuid', vehicle_version: 14, changed: true } }; } };
    },
  });
  const result = await service.markPartsComplete('vehicle-uuid', 13);
  const body = JSON.parse(request.options.body);
  ok(result.ok === true && result.code === 'parts_completed' && request.url.endsWith('/rest/v1/rpc/mark_pdc_parts_complete'), 'Mark Complete uses the protected RPC and returns a receipt-backed outcome');
  ok(body.p_vehicle_id === 'vehicle-uuid' && body.p_expected_version === 13, 'Mark Complete binds canonical vehicle identity and version');

  let replayCalls = 0;
  const replayService = createPdcEmailVehicleLocationService({
    config: { url: `https://${PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'key' },
    getAccessToken: () => 'approved-token',
    fetchImpl: async (_url, _options) => {
      replayCalls += 1;
      return { ok: true, status: 200, async json() { return { ok: true, code: 'replayed', data: { receipt_id: 'receipt-1', vehicle_id: 'vehicle-uuid', vehicle_version: 14, changed: false } }; } };
    },
  });
  const replay = await replayService.markPartsComplete('vehicle-uuid', 14);
  ok(replay.ok === true && replay.code === 'replayed' && replay.data.changed === false && replayCalls === 1, 'exact completion replay is a no-op with the original receipt');

  const invalidReceiptService = createPdcEmailVehicleLocationService({
    config: { url: `https://${PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'key' },
    getAccessToken: () => 'approved-token',
    fetchImpl: async () => ({ ok: true, status: 200, async json() { return { ok: true, code: 'parts_completed', data: { vehicle_version: 14, changed: true } }; } }),
  });
  const invalidReceipt = await invalidReceiptService.markPartsComplete('vehicle-uuid', 13);
  ok(invalidReceipt.ok === false && invalidReceipt.code === 'parts_completion_receipt_invalid', 'completion without a receipt fails closed and cannot fabricate a tick');
  console.log('Shared Parts ordered/complete contract passed.');
})().catch(error => { console.error(error); process.exit(1); });
