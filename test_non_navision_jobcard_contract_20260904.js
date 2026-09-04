'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(
  __dirname,
  'supabase/staging_only/20260904010500_non_navision_jobcard_current_contract.sql',
);
assert.ok(fs.existsSync(migrationPath), 'append-only non-Navision successor migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');

for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "v_head IS DISTINCT FROM '20260904010400'",
  'pdc_process_non_navision_jobcard_pre209',
  "'active',true,'YH'",
  "'initial_location',case when v_r.vehicle_created then 'YH'",
  "date_to_pmb IS NULL",
  'pdc_email_safe_nonnegative_numeric_20260904',
  "'sublet'",
  "'owner_supplied_document'",
  'pdc_non_navision_mapping_reviews_20260904',
  "work_key<>'owner_supplied_document'",
  "booking_created',false",
  "completion_created',false",
]) assert.ok(sql.includes(marker), `missing contract marker: ${marker}`);

assert.ok(/n\s*<\s*0\s+or\s+n\s*>\s*p_max/i.test(sql), 'explicit numeric zero must be accepted');
assert.ok(!/coalesce\([^\n]*estimated_hours[^\n]*,\s*0\s*\)/i.test(sql), 'missing hours must never be coerced to zero');
assert.ok(/jsonb_typeof\(a->'estimated_hours'\)<>\s*'number'/i.test(sql), 'missing/non-numeric hours must fail closed');

const classifierCases = [
  ["d~'(^| )(sub|sublet)( |$)'", "then 'sublet'"],
  ['wheel nut indicator', "then 'tyre'"],
  ['fire extinguisher', "then 'fabrication'"],
  ['external provider', "then 'sublet'"],
  ['pit inspection|pit inspect|pit and weigh', "then 'pitInspection'"],
];
for (const [pattern, result] of classifierCases) {
  assert.ok(sql.includes(pattern), `classifier must include ${pattern}`);
  assert.ok(sql.slice(sql.indexOf(pattern), sql.indexOf(pattern) + 180).toLowerCase().includes(result.toLowerCase()), `${pattern} classification mismatch`);
}

assert.ok(/pdc_non_navision_operation_lines_immutable/.test(sql), 'immutable operation trigger remains in force');
assert.ok(/revoke all on function public\.pdc_process_non_navision_jobcard_pre209/i.test(sql), '209 inner function remains private');
assert.ok(/grant execute on function public\.process_pdc_non_navision_jobcard/i.test(sql), 'authenticated outer 209 wrapper remains callable');
assert.ok(/PIT[^\n]*retained[^\n]*non-bookable/i.test(sql), 'PIT must remain retained and non-bookable');

const applyPath = path.join(__dirname, 'scripts/apply_non_navision_jobcard_contract_20260904.py');
assert.ok(fs.existsSync(applyPath), 'guarded STAGING dry-run/apply/read-back script must exist');
const applyScript = fs.readFileSync(applyPath, 'utf8');
for (const marker of [
  'cdsmnqxtyyoeoznmbidd',
  '20260904010500',
  'dry-run',
  'ROLLBACK',
  'production_contacted',
  'pdc_email_safe_nonnegative_numeric_20260904',
  'pdc_non_navision_mapping_reviews_20260904',
]) assert.ok(applyScript.includes(marker), `apply/read-back script missing ${marker}`);
assert.ok(!applyScript.includes('vjdtsswhroyguxyfjdkt'), 'apply/read-back script must not contain or contact Production');

console.log('Non-Navision Job Card current contract regression: PASS');
