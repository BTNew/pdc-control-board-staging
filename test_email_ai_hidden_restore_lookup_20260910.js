'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync('supabase/staging_only/20260910025526_email_ai_hidden_restore_lookup_v1.sql', 'utf8');

test('restore lookup is staging-only and restricted to the current Email AI runtime identity', () => {
  assert.match(sql, /pdc_monitor_staging_guard\(\)/);
  assert.match(sql, /pdc_email_ai_runtime_authorized_v1\(\)/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.pdc_email_ai_lookup_hidden_restore_context_v1/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.pdc_email_ai_lookup_hidden_restore_context_v1/);
});

test('lookup requires exact Stock, canonical vehicle and Navision backend identity', () => {
  assert.match(sql, /v_backend\.canonical_vehicle_id<>p_vehicle_id/);
  assert.match(sql, /normalized_data->>'batch'/);
  assert.match(sql, /current_backend_matches/);
  assert.match(sql, /competing_active_identities/);
});

test('lookup exposes only restore inputs and protected-state summaries, not archive snapshots', () => {
  assert.match(sql, /'tombstone_id',v_tombstone\.tombstone_id/);
  assert.match(sql, /'restore_receipt',v_receipt/);
  assert.match(sql, /'restore_event_exists',v_restored/);
  assert.match(sql, /'restore_eligible'/);
  assert.doesNotMatch(sql, /vehicle_snapshot/);
  assert.doesNotMatch(sql, /raw_evidence/);
});

test('lookup never mutates vehicle, review, booking or tombstone state', () => {
  assert.doesNotMatch(sql, /UPDATE\s+public\.vehicles/i);
  assert.doesNotMatch(sql, /INSERT\s+INTO\s+public\.pdc_new_vehicle_reviews/i);
  assert.doesNotMatch(sql, /DELETE\s+FROM/i);
  assert.match(sql, /STABLE/);
});
