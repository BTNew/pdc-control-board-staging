'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const mainPath = 'supabase/staging_only/20260910013146_email_ai_hidden_restore_dynamic_revolution_import_v2.sql';
const fixPath = 'supabase/staging_only/20260910013634_email_ai_hidden_restore_generated_columns_fix_v4.sql';
const sql = fs.readFileSync(mainPath, 'utf8');
const fix = fs.readFileSync(fixPath, 'utf8');

test('hidden restore is staging-only, exact-identity bound and returns New Vehicles pending', () => {
  assert.match(sql, /pdc_monitor_staging_guard\(\)/);
  assert.match(sql, /pdc_email_ai_runtime_authorized_v1\(\)/);
  assert.match(sql, /v_backend\.canonical_vehicle_id<>p_vehicle_id/);
  assert.match(sql, /v_tombstone\.vehicle_id<>p_vehicle_id/);
  assert.match(sql, /visible_on_board=false/);
  assert.match(sql, /'pending','revolution_report'/);
  assert.match(sql, /'bookings_created',0/);
  assert.match(sql, /'completions_created',0/);
});

test('operation identity distinguishes same line number with different descriptions', () => {
  const identity = sql.match(/CREATE OR REPLACE FUNCTION public\.pdc_pilbara_service_operation_identity_hash_v2[\s\S]*?REVOKE ALL ON FUNCTION public\.pdc_pilbara_service_operation_identity_hash_v2/);
  assert.ok(identity, 'operation identity function must exist');
  assert.match(identity[0], /p_stock/);
  assert.match(identity[0], /p_repair_order/);
  assert.match(identity[0], /p_line/);
  assert.match(identity[0], /p_description/);
  assert.match(sql, /exact_duplicate_row_ignored/);
  assert.match(sql, /decision = ANY\(ARRAY\['insert','unchanged','duplicate','quarantine','conflict'\]\)/);
});

test('report importer is no longer pinned to the historical workbook', () => {
  assert.doesNotMatch(sql, /9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e/);
  assert.doesNotMatch(sql, /source_row_count\s*=\s*162/);
  assert.doesNotMatch(sql, /jsonb_array_length\(p_rows\)\s*<>\s*162/);
  assert.doesNotMatch(sql, /matched[^\n]{0,120}21/);
  assert.doesNotMatch(sql, /unmatched[^\n]{0,120}16/);
  assert.match(sql, /jsonb_array_length\(p_rows\) NOT BETWEEN 1 AND 1000000/);
});

test('immutable historical operation evidence is not updated in place', () => {
  assert.doesNotMatch(sql, /UPDATE\s+public\.pdc_pilbara_service_operations/i);
  assert.match(sql, /INSERT INTO public\.pdc_pilbara_service_operations/);
  assert.match(sql, /vehicle_workshop_line_adjustments/);
});

test('generated vehicle columns are repaired by the follow-on migration', () => {
  assert.match(fix, /stock_number_normalized/);
  assert.match(fix, /vin_normalized/);
  assert.match(fix, /source_system_normalized/);
  assert.match(fix, /source_record_id_normalized/);
  assert.match(fix, /EXECUTE patched/);
});

test('known source transcription error is absent', () => {
  assert.doesNotMatch(sql, /v_source_hash text:=lower\(btrim\(coalesce\(p_source_hash,''\)\);/);
  assert.match(sql, /v_source_hash text:=lower\(btrim\(coalesce\(p_source_hash,''\)\)\);/);
});
