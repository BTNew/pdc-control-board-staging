'use strict';
const assert = require('assert');
const fs = require('fs');
const path = 'supabase/staging_only/20260825170000_380_qc_operation_source_jc.sql';
assert.ok(fs.existsSync(path), 'migration 380 must exist');
const sql = fs.readFileSync(path, 'utf8');
for (const marker of [
  '380_qc_operation_source_jc',
  'CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379',
  "coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),''))",
  'JOIN public.vehicles v ON v.id=ol.vehicle_id',
  'PDC_380_STAGING_HEAD_OR_CONTAINMENT_MISMATCH',
  "jsonb_array_elements(v#>'{data,vehicles}')",
]) assert.ok(sql.includes(marker), `migration 380 missing ${marker}`);
assert.doesNotMatch(sql, /queue_vehicle_notification\s*\(/i);
assert.doesNotMatch(sql, /(?:INSERT|UPDATE|DELETE)\s+(?:INTO\s+|FROM\s+)?public\.(?:vehicles|vehicle_work_items|pdc_authenticated_email_operation_lines|vehicle_workshop_line_adjustments)/i,
  'migration 380 must not mutate vehicle/application rows');
console.log('QC operation source Job Card projection 380: PASS');
