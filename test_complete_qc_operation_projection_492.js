'use strict';
const assert = require('assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/staging_only/20260827042000_492_complete_qc_operation_projection.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const identity = JSON.parse(fs.readFileSync('deployment-identity.json', 'utf8'));
for (const marker of [
  "coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key),'UNALLOCATED_MAPPING_REVIEW')",
  "'SUBLET','UNALLOCATED_MAPPING_REVIEW'",
  'source_operation_count=22', 'projected_operation_count=22', 'internal_station_count=7', 'sublet_count=1', 'mapping_review_count=14',
  'pdc_complete_qc_operation_projection_receipts_492', 'Production untouched'
]) assert.ok(sql.includes(marker), marker);
assert.match(sql, /version='20260827041000'.+name='491_bind_uid635_archive_paused_floor'/);
assert.match(app, /Unallocated – mapping review/);
assert.match(app, /Station mapping review is required before QC completion/);
assert.match(app, /stage === 'UNALLOCATED_MAPPING_REVIEW' \? 2 : stage === 'SUBLET' \? 1 : 0/);
assert.strictEqual(identity.application_version, '2026.08.27.14-navision-all-vehicle-guard');
assert.strictEqual(identity.observed_applied_database_migration.version, '20260827044000');
console.log('Complete QC/Board Job Card operation projection 492: PASS');
