'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/20260826140000_399_qc_finalization_photo_rft_salesperson_outbox.sql', 'utf8');

let count = 0;
function ok(value, message) { assert.ok(value, message); count += 1; }

ok(migration.includes("v_head IS DISTINCT FROM '20260826131500'"), 'migration is gated on exact 398 head');
ok(migration.includes('pdc_qc_finalization_photo_evidence_399'), 'migration stores durable QC photo evidence metadata');
ok(migration.includes('storage.buckets') && migration.includes('pdc-qc-evidence-staging'), 'migration creates a private staging evidence bucket');
ok(migration.includes('record_pdc_qc_photo_evidence_399'), 'migration exposes authenticated photo receipt RPC');
ok(migration.includes('finalize_pdc_qc_to_rft_399'), 'migration exposes one atomic QC finalization RPC');
ok(migration.includes('pdc_qc_salesperson_update_outbox_399'), 'migration stores an immutable salesperson outbox payload');
ok(migration.includes('pdc_qc_operation_lines_379'), 'finalization snapshots canonical QC operation lines');
ok(migration.includes("current_location='RFT'") && migration.includes('date_to_rft'), 'finalization moves the vehicle to RFT and records the milestone');
ok(migration.includes('vehicle_version_conflict') && migration.includes('idempotency'), 'finalization has stale-version and replay protection');
ok(migration.includes('delivered_at') && migration.includes('sent_at'), 'staging notification remains an unsent outbox record');
ok(migration.includes('image_width') && migration.includes('original_byte_length') && migration.includes('1048576'), 'compressed photo dimensions and hard 1MB post-compression limit are durable');

ok(service.includes('PDC_QC_PHOTO_BUCKET') && service.includes('uploadQcPhotoEvidence'), 'browser service uploads QC photos to the staging bucket');
ok(service.includes('compressQcPhoto') && service.includes('imageOrientation') && service.includes('750 * 1024'), 'client auto-orients, strips metadata through canvas and targets 750KB');
ok(service.includes('finalizeQcToRft'), 'browser service calls the atomic finalization RPC');
ok(app.includes('qcPhotoEvidence') && !app.includes('const qcPhotoDrafts = new Map()'), 'QC no longer uses an in-memory photo draft as authority');
ok(app.includes('Signed off and moved to RFT'), 'QC UI reports the combined finalization outcome');
ok(app.includes('uploadQcPhotoEvidence') && app.includes('finalizeQcToRft'), 'QC UI uses receipt-backed upload and finalization');
ok(!app.includes('data-transfer-rft-stock="${escapeHtml(key)}"'), 'successful QC finalization no longer exposes a separate manual RFT step');

console.log(`QC finalization 399 contract: ${count} assertions passed.`);
