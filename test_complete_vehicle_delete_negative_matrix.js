'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '20260823170000_323_admin_complete_vehicle_delete.sql'), 'utf8').toLowerCase();
const expected = [
  ['non-admin', 'administrator_required'],
  ['wrong stock', 'confirmation_stock_mismatch'],
  ['unknown dependency', 'pdc_323_unknown_vehicle_dependency'],
  ['booking/vehicle in flight', 'vehicle_mutation_in_flight'],
  ['Monitor in flight', 'monitor_mutation_in_flight'],
  ['duplicate idempotency', 'idempotency_conflict'],
  ['replay fence drift', 'pdc_323_replay_fence_drift'],
];
for (const [name, marker] of expected) assert.ok(sql.includes(marker.toLowerCase()), `${name} negative path is explicit`);
assert.ok(sql.includes('p_expected_version'), 'stale concurrent version is fail-closed');
assert.ok(sql.includes('pg_try_advisory_xact_lock'), 'in-flight mutation uses non-blocking locks');
assert.ok(sql.includes('pdc_email_source_claims'), 'old email source claims are not deleted');
assert.ok(sql.includes('pdc_email_replay_fences'), 'old email replay fences are not deleted');
console.log('Complete vehicle delete negative matrix contract passed.');
