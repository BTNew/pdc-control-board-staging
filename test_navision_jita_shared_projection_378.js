'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');

const base = {
  id: '00000000-0000-4000-8000-000000000378', permanent_vehicle_id: 'PERM-378', stock_number: 'HERMES-TEST-JITA-378',
  source_system: 'authenticated_email', work_items: [], operation_lines: [],
};
const exact = mapServerVehicle({ ...base, navision_jita_identity_verified: true, navision_jita_column_present: true,
  navision_jita_number_authority: 'validated-navision-import-v1', navision_jita_number: 'JITA-42017' });
const zero = mapServerVehicle({ ...base, navision_jita_identity_verified: true, navision_jita_column_present: true,
  navision_jita_number_authority: 'validated-navision-import-v1', navision_jita_number: '0' });
const blank = mapServerVehicle({ ...base, navision_jita_identity_verified: true, navision_jita_column_present: true,
  navision_jita_number_authority: 'validated-navision-import-v1', navision_jita_number: '' });
const ambiguous = mapServerVehicle({ ...base, navision_jita_identity_verified: false, navision_jita_column_present: false,
  navision_jita_number_authority: null, navision_jita_number: null });

const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf("const NAVISION_JITA_NUMBER_AUTHORITY");
const end = app.indexOf('\nfunction legacyVehicleFlag', start);
const context = { escapeHtml: value => String(value) };
vm.createContext(context);
vm.runInContext(app.slice(start, end), context);
assert.strictEqual(context.vehicleNavisionJitaNumber(exact), 'JITA-42017', 'exact canonical email/Board merge retains non-zero JITA');
assert.strictEqual(context.vehicleNavisionJitaNumber(zero), '', 'numeric zero never produces a tick');
assert.strictEqual(context.vehicleNavisionJitaNumber(blank), '', 'explicit blank clears the tick');
assert.strictEqual(context.vehicleNavisionJitaNumber(ambiguous), '', 'ambiguous canonical identity fails closed');
assert.match(context.jitaIndicator(exact), /aria-label="Navision JITA number JITA-42017"/);
assert.match(context.jitaIndicator(exact), /title="Navision JITA number JITA-42017"/);

const sql = fs.readFileSync('supabase/staging_only/20260825150000_378_navision_jita_shared_projection.sql', 'utf8');
for (const marker of [
  'get_pdc_email_vehicle_location_snapshot_pre_378', 'navision_jita_identity_verified', 'navision_jita_column_present',
  'navision_jita_number_authority', 'navision_jita_number', 'canonical_vehicle_id', "normalized_data->>'stock'",
  "WHEN candidate.match_count=1", "'ambiguous'", "'not_found'", "'exact'", 'Validated-navision-import-v1 authority',
]) assert.ok(sql.includes(marker), `migration missing ${marker}`);
assert.doesNotMatch(sql, /description[^\n]+(?:jita|jitQty)/i, 'JITA is never inferred from description/free text');

console.log('Navision JITA shared projection: PASS');
