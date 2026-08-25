'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260826120000_396_owner_supplied_document_jobcard_intake.sql';
const sql = fs.readFileSync(migrationPath, 'utf8');
const lower = sql.toLowerCase();

const operationLines = Array.from({ length: 18 }, (_, index) => ({
  operation_no: `OP${index + 1}`,
  description: `Owner supplied operation ${index + 1}`,
  hours: index < 14 ? Number((index * 0.25).toFixed(2)) : null,
}));
assert.strictEqual(operationLines.length, 18);
assert.strictEqual(operationLines.filter(row => row.hours !== null).length, 14);
assert.strictEqual(operationLines.filter(row => row.hours === null).length, 4);
assert.strictEqual(operationLines[0].hours, 0, 'an explicit 0.00 hours value must remain numeric zero');
assert.strictEqual(operationLines[14].hours, null, 'unknown hours must remain null');

for (const marker of [
  "'396_owner_supplied_document_jobcard_intake'",
  "provenance='owner_supplied_document'",
  "'owner_supplied_document'",
  "'craig.watson@broometoyota.com.au'",
  "'t_3ff7139c'",
  "'13080553'",
  "'J139125519'",
  'document_sha256',
  'document_byte_length',
  'document_content_type',
  'document_metadata',
  'pdc_owner_supplied_document_receipts_396',
  'pdc_owner_supplied_document_operation_receipts_396',
  'pdc_owner_supplied_document_review_items_396',
  'pdc_owner_supplied_document_undo_receipts_396',
  'pdc-owner-supplied-document-v1',
  'owner_supplied_document_unknown',
  'estimated_hours>=0',
  'estimated_hours IS NULL',
  'pdc_owner_supplied_document_jobcard_396',
  'pdc-owner-document-[A-Za-z0-9_-]{16,160}',
  'owner_document_idempotency_conflict',
  'owner_document_source_hash_conflict',
  'owner_document_navision_match_ambiguous',
  'pdc.owner_supplied_document_undo_396',
  'get_pdc_email_vehicle_location_snapshot_pre_396',
  'sibling.receipt_id<>r.canonical_import_receipt_id',
  'booking_created',
  'physical_completion_created',
  'vehicle_notifications',
  'workshop_bookings',
  'vehicle_movements',
  'GRANT EXECUTE ON FUNCTION public.process_pdc_owner_supplied_document_jobcard_396',
  'GRANT EXECUTE ON FUNCTION public.undo_pdc_owner_supplied_document_jobcard_396',
]) assert.ok(sql.includes(marker), `migration missing ${marker}`);

assert.match(sql, /jsonb_typeof\(op->'hours'\) NOT IN\('number','null'\)/i);
assert.match(sql, /jsonb_typeof\(op->'hours'\)='number'.*pdc_owner_document_numeric_396\(op->'hours'\).*<0/s);
assert.match(sql, /operation_no.*IS DISTINCT FROM 'OP'\|\|n::text/);
assert.match(sql, /source_contract='pdc-owner-supplied-document-v1'/);
assert.match(sql, /temporary_importer_writer_required/);
assert.match(sql, /r\.role='importer'/);
assert.match(sql, /w\.active AND w\.revoked_at IS NULL/);
assert.match(sql, /r\.is_current AND r\.record_status='current'/);
assert.match(sql, /normalize_vehicle_stock_number\([^\n]+\)=v_stock/);
assert.match(sql, /job_card_number.*J139125519/);
assert.match(sql, /NOT public\.pdc_monitor_staging_guard\(\)/);
assert.match(sql, /pdc_production_environment_sentinel/);
assert.doesNotMatch(lower, /monitored_mailboxes/);
assert.doesNotMatch(lower, /pdc_provider_email_observations/);
assert.doesNotMatch(lower, /attest_pdc_provider_email_observation/);
assert.doesNotMatch(lower, /gmail_authentication_results/);
assert.doesNotMatch(lower, /pdc_email_source_claims/);
assert.doesNotMatch(lower, /queue_vehicle_notification\s*\(/);
assert.doesNotMatch(lower, /create_pdc_sublet_booking\s*\(/);
assert.doesNotMatch(lower, /workshop_bookings\s*\(/);
assert.doesNotMatch(lower, /delete\s+from\s+public\.pdc_authenticated_email_import_receipts/);
assert.doesNotMatch(lower, /physical_completion_created\s*[:=]\s*true/);
assert.doesNotMatch(lower, /grant\s+(?:insert|update|delete|all)\s+on/);
assert.doesNotMatch(lower, /\btruncate\b|\bcascade\b/);

console.log('owner_supplied_document_jobcard_396: PASS');
