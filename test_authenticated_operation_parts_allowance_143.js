'use strict';
const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/143_authenticated_operation_parts_allowance.sql', 'utf8');
const runner = fs.readFileSync('scripts/apply_migration_143_staging.py', 'utf8');

assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'Migration 143 must be staging-sentinel guarded');
assert(sql.includes("v_old_allow_list constant text := '(''bus4x4'',''tint'',''hoist'',''fitting'',''fabrication'',''electrical'',''tyre'',''pitInspection'')'"));
assert(sql.includes("v_new_allow_list constant text := '(''bus4x4'',''tint'',''hoist'',''fitting'',''fabrication'',''electrical'',''tyre'',''pitInspection'',''parts'')'"));
for (const marker of [
  'pdc_monitor_staging_guard()',
  'jsonb_array_length(v_operations) not between 1 and 50',
  'source_receipt_not_found',
  'operation_identity_conflict',
  'estimated_hours_conflict',
  "'''booking_created'',false",
  "'''completed_work_reopened'',false",
]) assert(sql.includes(marker), `Migration 143 must retain safety marker ${marker}`);
assert(sql.includes("revoke all on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) from public,anon,authenticated"));
assert(sql.includes("grant execute on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) to authenticated"));
assert(!sql.includes('create table') && !sql.includes('insert into public.pdc_authenticated_email_operation_lines'), 'Migration 143 must only repair the existing function definition');

assert(runner.includes('"work_key": "parts"'), 'Rehearsal must include a Parts operation');
assert(runner.includes('"work_key": "fitting"'), 'Rehearsal must prove a mixed payload is no longer blocked');
assert(runner.includes('result.get("code") != "source_receipt_not_found"'), 'Rehearsal must prove validation advances beyond invalid_operation_lines');
assert(runner.includes('data_signature(cur)'), 'Rehearsal must prove operation/work data and revision stay unchanged');
assert(runner.includes('conn.rollback()'), 'Dry run must roll back');
assert(runner.includes('refusing Migration 143 apply from unreviewed or dirty worktree'), 'Apply must require a reviewed clean commit');

console.log('Authenticated operation Parts allowance migration 143 contract passed');
