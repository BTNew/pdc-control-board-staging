'use strict';

const assert = require('assert');
const {
  PDC_QC_PHOTO_BUCKET,
  PDC_QC_RETEST_PHOTO_RPC,
  PDC_QC_RETEST_FINALIZATION_RPC,
  mapServerVehicle,
  createPdcEmailVehicleLocationService,
} = require('./pdc-email-vehicle-location-service');

const vehicleId = 'd777b071-a2b0-5367-893b-aa83a07fcfce';
const cycleId = '245974d0-2e8f-5215-bd85-3e8e10fe9a0e';
const photoId = 'c5bf1ec3-7a1e-5b4e-a6b6-0eae6a4e9876';
const actorId = '8a83b715-8d79-4b0e-95b2-02b55da6e8d7';
const lines = Array.from({ length: 17 }, (_, index) => ({
  line_identity: `source:${String(index + 1).padStart(8, '0')}-0000-0000-0000-000000000000`,
  source_kind: 'authenticated', source_line_id: `11111111-1111-5111-8111-${String(index + 1).padStart(12, '0')}`,
  operation_no: `OP${index + 1}`, description: `Operation ${index + 1}`, job_card_number: 'J139125493',
  estimated_hours: 1, stage_code: 'FITTING', active: true, completed: true, line_version: 1,
}));
const mapped = mapServerVehicle({ id: vehicleId, version: 34, stock_number: '13000769', current_location: 'QC', lifecycle_state: 'active', operation_lines: lines, qc_retest: { cycle_id: cycleId, fresh_cycle_open: true, fresh_photo_accepted: false } });
assert.strictEqual(mapped.pdcQcOperationLines.length, 17);
assert.strictEqual(mapped.pdcQcRetestCycleId, cycleId);

const originalCrypto = global.crypto;
const originalCreateImageBitmap = global.createImageBitmap;
const originalDocument = global.document;
const originalFile = global.File;
const originalBlob = global.Blob;
global.createImageBitmap = async () => ({ width: 100, height: 100, close() {} });
global.document = { createElement: () => ({ width: 100, height: 100, getContext: () => ({ drawImage() {} }), toBlob: callback => callback(new Blob([Buffer.from([1, 2, 3, 4])], { type: 'image/jpeg' })) }) };

const tokenPayload = Buffer.from(JSON.stringify({ sub: actorId })).toString('base64url');
const token = `header.${tokenPayload}.signature`;
const calls = [];
const response = body => ({ ok: true, status: 200, json: async () => body });
const fetchImpl = async (url, init) => {
  calls.push({ url, init });
  if (url.includes('/storage/v1/object/')) return response({ Key: 'staged' });
  if (url.endsWith(`/rpc/${PDC_QC_RETEST_PHOTO_RPC}`)) return response({ ok: true, code: 'qc_retest_photo_accepted', cycle_id: cycleId, photo_receipt_id: photoId, vehicle_id: vehicleId, vehicle_version: 34, sha256: 'a'.repeat(64) });
  if (url.endsWith(`/rpc/${PDC_QC_RETEST_FINALIZATION_RPC}`)) return response({ ok: true, code: 'qc_retest_signed_off_to_rft', cycle_id: cycleId, vehicle_id: vehicleId, vehicle_version_after: 36 });
  throw new Error(`unexpected request ${url}`);
};
(async () => {
  const service = createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'staging-test-key' }, getAccessToken: () => token, fetchImpl });
  const file = { name: 'mobile-qc.jpg', type: 'image/jpeg', size: 128, arrayBuffer: async () => Uint8Array.from([9, 8, 7]).buffer };
  const upload = await service.uploadQcPhotoEvidence(vehicleId, 34, cycleId, file);
  assert.strictEqual(upload.ok, true);
  const photoRequest = JSON.parse(calls[1].init.body);
  assert.strictEqual(calls[1].url.endsWith(`/rpc/${PDC_QC_RETEST_PHOTO_RPC}`), true);
  assert.strictEqual(photoRequest.p_vehicle_id, vehicleId);
  assert.strictEqual(photoRequest.p_cycle_id, cycleId);
  assert.strictEqual(photoRequest.p_bucket_id, PDC_QC_PHOTO_BUCKET);
  assert.match(photoRequest.p_storage_path, new RegExp(`^qc-finalization/${actorId}/[0-9a-f-]{36}/`));
  const final = await service.finalizeQcRetest(vehicleId, 34, cycleId, photoId, '37b8b3d0-6b0a-4f59-8d29-4c5a1df1e0cf');
  assert.strictEqual(final.ok, true);
  const finalRequest = JSON.parse(calls[2].init.body);
  assert.strictEqual(calls[2].url.endsWith(`/rpc/${PDC_QC_RETEST_FINALIZATION_RPC}`), true);
  assert.deepStrictEqual({ vehicle: finalRequest.p_vehicle_id, version: finalRequest.p_expected_vehicle_version, cycle: finalRequest.p_cycle_id, photo: finalRequest.p_photo_receipt_id }, { vehicle: vehicleId, version: 34, cycle: cycleId, photo: photoId });
  console.log('QC mobile staging-base retest projection, iOS fallback, cycle receipt and finalize contract passed');
})().finally(() => { global.createImageBitmap = originalCreateImageBitmap; global.document = originalDocument; global.File = originalFile; global.Blob = originalBlob; }).catch(error => { console.error(error); process.exitCode = 1; });
