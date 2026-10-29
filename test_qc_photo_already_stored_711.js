'use strict';
// r711 (F320): an upload refused as qc_photo_already_recorded hands back the photo already stored for this QC.
const test = require('node:test');
const assert = require('node:assert/strict');
const { PDC_QC_PHOTO_BUCKET, createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');

const vehicleId = 'ad620eef-0000-4000-8000-000000000711';
const receiptId = 'af8bad33-0888-5eaf-a0c1-000000000711';
const token = `h.${Buffer.from(JSON.stringify({ sub: '8a83b715-8d79-4b0e-95b2-02b55da6e8d7' })).toString('base64url')}.s`;
const stored = { photo_receipt_id: receiptId, vehicle_id: vehicleId, bucket_id: PDC_QC_PHOTO_BUCKET, storage_path: 'qc-finalization/x/y.jpg', content_type: 'image/jpeg',
  byte_length: 517006, original_byte_length: 2100000, image_width: 1600, image_height: 1200, sha256: 'b'.repeat(64), original_filename: 'IMG_2320.jpeg', storage_object_present: true };
const file = { name: 'IMG_9999.jpeg', type: 'image/jpeg', size: 300000, arrayBuffer: async () => Uint8Array.from([1, 2, 3]).buffer };
function service(receiptReply, readReply) {
  const calls = [];
  const response = body => ({ ok: true, status: 200, json: async () => body });
  const fetchImpl = async (url, init) => {
    calls.push(url);
    if (url.includes('/storage/v1/object/')) return response({ Key: 'staged' });
    if (url.endsWith('/rpc/record_pdc_qc_photo_evidence_399')) return response(receiptReply);
    if (url.endsWith('/rpc/get_pdc_qc_photo_receipt_414')) return response(readReply);
    throw new Error(`unexpected ${url}`);
  };
  return { calls, svc: createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, getAccessToken: () => token, fetchImpl }) };
}
const withCanvas = async fn => {
  const saved = { b: global.createImageBitmap, d: global.document };
  global.createImageBitmap = async () => ({ width: 800, height: 600, close() {} });
  global.document = { createElement: () => ({ width: 100, height: 100, getContext: () => ({ drawImage() {} }), toBlob: cb => cb(new Blob([Buffer.from([1, 2, 3, 4])], { type: 'image/jpeg' })) }) };
  try { await fn(); } finally { global.createImageBitmap = saved.b; global.document = saved.d; }
};

test('already recorded: the stored photo comes back as the upload result', () => withCanvas(async () => {
  const { svc, calls } = service({ ok: false, code: 'qc_photo_already_recorded' }, { ok: true, code: 'qc_photo_stored', data: stored });
  const result = await svc.uploadQcPhotoEvidence(vehicleId, 40, file);
  assert.equal(result.ok, true);
  assert.equal(result.code, 'qc_photo_already_stored');
  assert.equal(result.data.photo_receipt_id, receiptId);
  assert.equal(result.data.vehicle_id, vehicleId);
  assert.ok(calls.some(url => url.endsWith('/rpc/get_pdc_qc_photo_receipt_414')));
}));

test('already recorded but the stored photo cannot be read: the refusal stands', () => withCanvas(async () => {
  const { svc } = service({ ok: false, code: 'qc_photo_already_recorded' }, { ok: false, code: 'qc_photo_vehicle_not_in_qc' });
  const result = await svc.uploadQcPhotoEvidence(vehicleId, 40, file);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'qc_photo_already_recorded');
}));

test('other refusals are not changed and do not read the stored photo', () => withCanvas(async () => {
  const { svc, calls } = service({ ok: false, code: 'qc_photo_vehicle_not_in_qc' }, { ok: true, code: 'qc_photo_stored', data: stored });
  const result = await svc.uploadQcPhotoEvidence(vehicleId, 40, file);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'qc_photo_vehicle_not_in_qc');
  assert.ok(!calls.some(url => url.endsWith('/rpc/get_pdc_qc_photo_receipt_414')));
}));
