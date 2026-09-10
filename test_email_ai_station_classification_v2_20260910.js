'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/staging_only/20260910032452_email_ai_dynamic_station_classification_v2.sql',
  'utf8'
);

test('classifier v2 is staging-only and restricted to the active Email AI runtime', () => {
  assert.match(migration, /pdc_monitor_staging_guard\(\)/);
  assert.match(migration, /pdc_email_ai_runtime_authorized_v1\(\)/);
  assert.match(migration, /pdc_pilbara_service_classification_source_v2/);
  assert.match(migration, /pdc_pilbara_service_classification_preview_v2/);
  assert.match(migration, /pdc_pilbara_service_classification_apply_v2/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.pdc_pilbara_service_classification_source_v2\(uuid\) TO authenticated/);
});

test('classifier v2 is dynamic and is not pinned to the historical workbook', () => {
  assert.doesNotMatch(migration, /9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e/);
  assert.doesNotMatch(migration, /ab7483a0-9b6c-4777-a7f9-9481e16023ff/);
  assert.doesNotMatch(migration, /jsonb_array_length\([^\n]+\)<>122/);
  assert.doesNotMatch(migration, /schema_head_changed/);
  assert.match(migration, /count\(DISTINCT oh\.operation_id\)/);
});

test('classification binds to operation UUID plus immutable source hashes', () => {
  assert.match(migration, /operation_id/);
  assert.match(migration, /source_semantic_hash/);
  assert.match(migration, /source_description_hash/);
  assert.match(migration, /op\.operation_id=\(rowj->>'operation_id'\)::uuid/);
  assert.doesNotMatch(migration, /natural_identity/);
});

test('all operational stations are allowed and Review is confidence fallback only', () => {
  for (const stage of ['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW']) {
    assert.match(migration, new RegExp(`'${stage}'`));
  }
  assert.match(migration, /category='REVIEW' AND \(method<>'review' OR confidence>=0\.80\)/);
  assert.match(migration, /category<>'REVIEW' AND confidence<0\.80/);
  assert.match(migration, /assign station at >=0\.80; use REVIEW below 0\.80/);
});

test('classifier cannot book, complete, approve, or expose admin credentials', () => {
  assert.match(migration, /'booking_changes',0/);
  assert.match(migration, /'completion_changes',0/);
  assert.match(migration, /'work_item_changes',0/);
  assert.doesNotMatch(migration, /approve_pdc_new_vehicle_review\s*\(/);
  assert.doesNotMatch(migration, /INSERT INTO public\.workshop_bookings/i);
  assert.doesNotMatch(migration, /UPDATE public\.pdc_qc_operation_completions/i);
  assert.doesNotMatch(migration, /service_role/i);
});

test('classification source exposes prior exact-description hints for learned routing', () => {
  assert.match(migration, /prior_exact_description_hint/);
  assert.match(migration, /regexp_replace\(btrim\(po\.operation_description\)/);
  assert.match(migration, /ORDER BY ph\.confidence DESC,ph\.created_at DESC/);
});
