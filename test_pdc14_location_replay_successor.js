'use strict';

const assert = require('assert');
const fs = require('fs');

const actions = fs.readFileSync('vehicle-lifecycle-actions.js', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const migrationPath = 'supabase/staging_only/20260904011000_pdc14_location_replay_idempotency.sql';
assert.ok(fs.existsSync(migrationPath), 'append-only location replay successor exists');
const sql = fs.readFileSync(migrationPath, 'utf8');

for (const marker of [
  'pdc_vehicle_location_receipts_20260904',
  'p_request_key text',
  'request_hash',
  "PERFORM public.require_pdc_role('operator')",
  'vehicle_version_conflict',
  'not_in_active_lifecycle',
  'invalid_pdc_location_transition',
  'pit_requires_pmb_unallocated',
  'SET search_path=pg_catalog,public',
  'audit_pdc_event',
  "'20260904011000'",
  "'cdsmnqxtyyoeoznmbidd'",
]) assert.ok(sql.includes(marker), `location replay migration missing ${marker}`);
assert.match(sql, /ENABLE ROW LEVEL SECURITY[\s\S]*FORCE ROW LEVEL SECURITY/i, 'receipt table has forced RLS');
assert.match(sql, /REVOKE ALL ON TABLE public\.pdc_vehicle_location_receipts_20260904 FROM public,anon,authenticated,service_role/i, 'receipt table is private');
assert.match(sql, /IF v_receipt\.request_hash<>v_request_hash[\s\S]*idempotency_conflict/i, 'request-key reuse with another payload fails closed');
assert.match(sql, /RETURN v_receipt\.response/i, 'same request replay returns the persisted original response');
assert.match(actions, /setPdcLocation\(\{ vehicleId, expectedVersion, location, requestKey \}\)[\s\S]{0,300}p_request_key: requestKey/, 'typed client action sends request key');
assert.match(app, /function pdcLocationRequestKey[\s\S]{0,300}vehicleId[\s\S]{0,300}expectedVersion[\s\S]{0,300}normalizePdcLocation/, 'Vehicle Detail derives a retry-stable key from the logical mutation');
assert.match(app, /setPdcLocation\(\{[\s\S]{0,300}requestKey: pdcLocationRequestKey\(ref\.vehicleId, ref\.version, pdcLocation\)/, 'Vehicle Detail reuses the logical mutation key across ambiguous retries');

console.log('PDC-14 location replay-idempotency successor: PASS');
