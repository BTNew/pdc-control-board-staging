/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r414 (F30): a stored QC completion photo is read back after a refresh, so "Sign off QC -> RFT" shows.
// Key 208 / 13017935 (and Key 454): the receipt was stored, but the page kept it only in memory. After a refresh,
// re-uploading the same photo was refused as qc_photo_already_recorded (one receipt per QC inspection), a code the page
// did not know, and the preview stayed on "receipt validation is pending" with no Sign off button.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');

const ID = '20261020230636_r414_qc_photo_receipt_readback';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const NEW = '313140d87083899267fff7ea3275ca5b';

function fnBody(sql) {
  const start = sql.indexOf('AS $function$') + 'AS $function$'.length;
  return sql.slice(start, sql.indexOf('$function$', start));
}
function extract(src, name) {
  let start = src.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  if (src.slice(start - 6, start) === 'async ') start -= 6;
  let depth = 0; let i = src.indexOf(') {', start) + 2;
  for (; i < src.length; i += 1) { if (src[i] === '{') depth += 1; else if (src[i] === '}') { depth -= 1; if (depth === 0) break; } }
  return src.slice(start, i + 1);
}

test('migration adds only a read function and the F30 check, staging-guarded, inside the release window', () => {
  assert.equal(md5(fnBody(up)), NEW);
  assert.match(up, /CREATE FUNCTION public\.get_pdc_qc_photo_receipt_414\(p_vehicle_id uuid\)/);
  assert.match(up, /STABLE SECURITY DEFINER/);
  assert.match(up, /REVOKE ALL ON FUNCTION public\.get_pdc_qc_photo_receipt_414\(uuid\) FROM PUBLIC, anon;/);
  assert.match(up, /GRANT EXECUTE ON FUNCTION public\.get_pdc_qc_photo_receipt_414\(uuid\) TO authenticated, service_role;/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.doesNotMatch(up, /vjdtsswhroyguxyfjdkt/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION|ALTER TABLE|DROP |UPDATE |DELETE /i);
  assert.match(up, /'qc_photo_receipt_readable','F30'/);
  // Same role rule as the upload, and only the current inspection's receipt.
  assert.match(fnBody(up), /u\.role IN\('operator','administrator'\) AND u\.active AND u\.account_status='approved'/);
  assert.match(fnBody(up), /qc_inspection_key IS NOT DISTINCT FROM inspection_key/);
  assert.match(fnBody(up), /storage_object_present/);
});

test('undo asserts the r414 md5, removes the function and the check, and nothing else', () => {
  assert.match(down, new RegExp(`IS DISTINCT FROM '${NEW}'`));
  assert.match(down, /DROP FUNCTION public\.get_pdc_qc_photo_receipt_414\(uuid\);/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='qc_photo_receipt_readable' AND added_in='r414';/);
  assert.match(down, /NOT BETWEEN 2 AND 45/);
});

test('service reads the stored receipt and accepts it only when the file exists for this vehicle', async () => {
  assert.match(service, /const PDC_QC_PHOTO_READ_RPC = 'get_pdc_qc_photo_receipt_414';/);
  assert.match(service, /uploadQcPhotoEvidence, readQcPhotoReceipt, finalizeQcToRft,/);
  const fn = extract(service, 'readQcPhotoReceipt');
  const run = async body => {
    const ctx = { getAccessToken: () => 'token', url: 'https://x', key: 'k', PDC_QC_PHOTO_READ_RPC: 'get_pdc_qc_photo_receipt_414',
      request: async () => ({ ok: true, json: async () => body }), JSON, String, result: null };
    vm.runInNewContext(`${fn}; result = readQcPhotoReceipt('c0f52efe-1f1e-4800-a842-04a937bd3866');`, ctx);
    return ctx.result;
  };
  const data = { photo_receipt_id: 'a435b36a-7234-55fe-bc2d-dab6cbb08f75', vehicle_id: 'c0f52efe-1f1e-4800-a842-04a937bd3866', storage_object_present: true };
  assert.equal((await run({ ok: true, code: 'qc_photo_stored', data })).ok, true);
  assert.equal((await run({ ok: true, code: 'qc_photo_none', data: {} })).data, null);
  assert.equal((await run({ ok: true, code: 'qc_photo_storage_missing', data: { ...data, storage_object_present: false } })).code, 'qc_photo_storage_missing');
  assert.equal((await run({ ok: true, code: 'qc_photo_stored', data: { ...data, vehicle_id: '9d78a4ef-3ea6-4216-b640-1d9e4e30f155' } })).ok, false);
});

test('QC page loads the stored photo, uses it on qc_photo_already_recorded and never shows a stuck pending receipt', () => {
  assert.match(app, /async function qcPageLoadStoredPhoto\(/);
  assert.match(app, /if \(selected\) void qcPageLoadStoredPhoto\(qcPageVehicleKey\(selected\)\);/);
  assert.match(app, /result\?\.code === 'qc_photo_already_recorded' && await qcPageLoadStoredPhoto\(cleanKey, \{ force: true \}\)/);
  assert.match(app, /qc_photo_already_recorded: 'A completion photo is already stored for this QC/);
  assert.doesNotMatch(app, /Selected image; receipt validation is pending\./);
  assert.match(app, /Not stored\. Clear it and choose the photo again\./);
  // The stored receipt (no local preview) passes the same validity rule the Sign off button uses.
  const valid = extract(app, 'qcPhotoEvidenceIsValid');
  const ctx = { result: null, String, Number };
  const stored = { status: 'accepted', photoReceiptId: 'a435b36a-7234-55fe-bc2d-dab6cbb08f75', bucket_id: 'pdc-qc-evidence-staging',
    storage_path: 'qc-finalization/u/v/x.jpg', content_type: 'image/jpeg', byteLength: 338462, originalByteLength: 338462, imageWidth: 1600, imageHeight: 1200,
    sha256: 'a'.repeat(64), url: '' };
  vm.runInNewContext(`${valid}; result = qcPhotoEvidenceIsValid(${JSON.stringify(stored)});`, ctx);
  assert.equal(ctx.result, true);
  // A second upload is blocked while a receipt is stored (it can only be refused and leave an orphan file).
  assert.match(extract(app, 'qcPagePhotoDisabledReason'), /A completion photo is already stored for this QC\./);
});

test('FAULT_LOG has F30 with cause, fix, undo and check', () => {
  const row = log.split('\n').find(line => line.startsWith('| F30 |')) || '';
  assert.match(row, /Key 208/);
  assert.match(row, /qc_photo_already_recorded/);
  assert.match(row, /20261020230636/);
  assert.match(row, /qc_photo_receipt_readable/);
});
