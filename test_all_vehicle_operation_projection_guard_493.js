'use strict';
const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const migrationPath = 'supabase/staging_only/20260827043000_493_all_vehicle_operation_projection_guard.sql';
const sql = fs.readFileSync(migrationPath, 'utf8');
const identity = JSON.parse(fs.readFileSync('deployment-identity.json', 'utf8'));
for (const marker of [
  'pdc_operation_projection_parity_493',
  'PDC_OPERATION_PROJECTION_INCOMPLETE',
  'pdc_operation_projection_parity_source_493',
  'pdc_operation_projection_parity_adjustment_493',
  'DEFERRABLE INITIALLY DEFERRED',
  "ELSE 'UNALLOCATED_MAPPING_REVIEW'",
  "'source_operation_count'",
  "'projected_operation_count'",
  "'mismatch_count'",
  'Verify zero existing staging mismatches before commissioning',
  'Production untouched'
]) assert.ok(sql.includes(marker), marker);
assert.match(sql, /source_count<>projected_count OR source_count<>distinct_projected_count/);
assert.match(sql, /jsonb_array_length\(missing_source_line_ids\)<>0/);
assert.match(sql, /AFTER INSERT OR UPDATE OR DELETE ON public\.pdc_authenticated_email_operation_lines/);
assert.match(sql, /AFTER INSERT OR UPDATE OR DELETE ON public\.vehicle_workshop_line_adjustments/);
assert.strictEqual(identity.application_version, '2026.08.27.706-final-authoritative-lifecycle');
assert.strictEqual(identity.observed_applied_database_migration.version, '20260827051000');
assert.strictEqual(identity.production_unchanged, true);
console.log('All-vehicle Job Card operation projection parity guard 493: PASS');
