'use strict';
const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260829060000_739_rft_transport_email_draft_successor.sql';
const sql = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8') : '';
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const identity = fs.readFileSync('deployment-identity.json', 'utf8');

assert.ok(sql, '739 append-only RFT email draft migration exists');
for (const marker of [
  'PDC_739_STAGING_ONLY',
  'PDC_739_APPEND_ONLY',
  'pdc_rft_transport_email_drafts_739',
  'book_rft_transport_email_draft_739',
  'read_rft_transport_booking_context_739',
  'read_rft_transport_draft_739',
  'mime_bytes bytea NOT NULL',
  'mime_content_type text NOT NULL CHECK(mime_content_type=\'message/rfc822\')',
  'photo_bytes_base64',
  'photo_sha256',
  'photo_byte_length',
  'photo_content_type',
  'RFT transport status: BOOKED',
  'Completed work:',
  'Dates:',
  'Build times:',
  'Stoppages:',
  'Content-Disposition: attachment',
  'delivery_enabled',
  "'sent_at',null",
  "'delivered_at',null",
  'PDC_739_SECURITY_POSTCONDITION_FAILED',
  'LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE',
]) assert.ok(sql.includes(marker), `739 migration marker: ${marker}`);
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.book_rft_transport_email_draft_739\([\s\S]*public\.book_rft_transport_734/);
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.read_rft_transport_draft_739\(p_vehicle_id uuid\)/);
assert.match(service, /PDC_RFT_TRANSPORT_DRAFT_BOOK_RPC = 'book_rft_transport_email_draft_739'/);
assert.match(service, /bookRftTransport739/);
assert.match(service, /readRftTransportDraft739/);
assert.match(service, /storage\/v1\/object\/authenticated/);
assert.match(service, /p_photo_bytes_base64/);
assert.match(app, /service\.bookRftTransport739/);
assert.match(app, /rft_confirmation_required/);
assert.match(app, /qc_photo_storage_missing/);
assert.match(app, /qc_items_required/);
assert.match(identity, /20260829060000/);

(async () => {
  const { createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');
  const calls = [];
  const photoBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const api = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public' },
    getAccessToken: () => 'token',
    fetchImpl: async (url, options = {}) => {
      calls.push({ url, options });
      if (url.includes('/storage/v1/object/authenticated/')) return { ok: true, arrayBuffer: async () => photoBytes.buffer };
      const body = url.includes('read_rft_transport_booking_context_739')
        ? { ok: true, code: 'rft_transport_booking_context', data: { vehicle_id: 'vehicle-739', photo: { photo_receipt_id: 'photo-739', bucket_id: 'pdc-qc-evidence-staging', storage_path: 'qc-finalization/actor/vehicle/photo.jpg', content_type: 'image/jpeg', byte_length: 4, sha256: '32461d5bd1773012acef0ba15636752949bd7c2ce50f9172159d9f56cf0dd9af' }, salesperson: { salesperson_email: 'sales@example.com' }, completed_items: [{ operation_no: 'OP1', completed: true, estimated_hours: 1 }], } }
        : url.includes('read_rft_transport_draft_739')
          ? { ok: true, code: 'rft_transport_draft', data: { draft_id: 'draft-739', mime_base64: 'ZW1s', mime_sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' } }
          : { ok: true, code: 'rft_transport_booked', data: { receipt_id: 'receipt-739', vehicle_id: 'vehicle-739', draft_id: 'draft-739', draft_content_type: 'message/rfc822', draft_mime_sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', draft_mime_byte_length: 4, delivery_enabled: false, sent_at: null, delivered_at: null } };
      return { ok: true, json: async () => body };
    },
  });
  const result = await api.bookRftTransport739('vehicle-739', 32, 'key-739');
  assert.strictEqual(result.ok, true, '739 booking service returns authoritative success');
  const bookingCall = calls.find(call => call.url.includes('book_rft_transport_email_draft_739'));
  assert.ok(bookingCall, '739 booking RPC is called');
  const payload = JSON.parse(bookingCall.options.body);
  assert.deepStrictEqual(Object.keys(payload).sort(), [
    'p_expected_vehicle_version', 'p_idempotency_key', 'p_photo_bucket_id', 'p_photo_bytes_base64',
    'p_photo_byte_length', 'p_photo_content_type', 'p_photo_receipt_id', 'p_photo_sha256',
    'p_photo_storage_path', 'p_vehicle_id',
  ].sort(), '739 payload is bounded to canonical vehicle/version/photo evidence inputs');
  assert.strictEqual(payload.p_vehicle_id, 'vehicle-739');
  assert.strictEqual(payload.p_expected_vehicle_version, 32);
  assert.strictEqual(payload.p_idempotency_key, 'key-739');
  assert.strictEqual(payload.p_photo_bucket_id, 'pdc-qc-evidence-staging');
  assert.strictEqual(payload.p_photo_content_type, 'image/jpeg');
  assert.strictEqual(payload.p_photo_byte_length, 4);
  assert.strictEqual(payload.p_photo_receipt_id, 'photo-739');
  assert.ok(payload.p_photo_bytes_base64, 'exact photo bytes are carried to the atomic draft RPC');
  await api.readRftTransportDraft739('vehicle-739');
  assert.ok(calls.some(call => call.url.includes('read_rft_transport_draft_739')), 'staff draft readback RPC is exposed');
  console.log('RFT transport email draft 739 contract: PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
