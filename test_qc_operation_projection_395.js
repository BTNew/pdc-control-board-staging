'use strict';
const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260826110000_395_restore_qc_operation_projection.sql';
assert.ok(fs.existsSync(migrationPath), 'migration 395 must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');
for (const marker of [
  '395_restore_qc_operation_projection',
  'PDC_395_STAGING_HEAD_OR_CONTAINMENT_MISMATCH',
  'get_pdc_email_vehicle_location_snapshot_pre_395',
  'pdc_qc_operation_lines_379',
  "'qc_operation_lines'",
  'snapshot_has_qc',
  'pdc_acceptance_protected_digest_375',
  'vehicle_notifications',
  'NOTIFY pgrst',
]) assert.ok(sql.includes(marker), `migration 395 missing ${marker}`);
assert.match(sql, /ALTER FUNCTION public\.get_pdc_email_vehicle_location_snapshot\(\)[\s\S]*RENAME TO get_pdc_email_vehicle_location_snapshot_pre_395/);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.get_pdc_email_vehicle_location_snapshot\(\) TO authenticated/);
assert.doesNotMatch(sql, /queue_vehicle_notification\s*\(/i);
assert.doesNotMatch(sql, /(?:INSERT|UPDATE|DELETE)\s+(?:INTO\s+|FROM\s+)?public\.(?:vehicles|vehicle_work_items|pdc_authenticated_email_operation_lines|pdc_qc_operation_completions_379|pdc_qc_operation_completion_receipts_379)/i,
  'migration 395 must not mutate operational or QC evidence rows');
console.log('QC operation projection restoration 395: PASS');
