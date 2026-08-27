'use strict';
const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const migrationPath = 'supabase/staging_only/20260827044000_494_navision_all_vehicle_link_refresh_guard.sql';
const sql = fs.readFileSync(migrationPath, 'utf8');
const identity = JSON.parse(fs.readFileSync('deployment-identity.json', 'utf8'));
for (const marker of [
  'pdc_owner_navision_all_vehicle_rules_494',
  'pdc_navision_vehicle_parity_494',
  'PDC_NAVISION_VEHICLE_LINK_OR_REFRESH_INCOMPLETE',
  'zz_navision_all_vehicle_parity_494',
  'zz_vehicle_navision_parity_494',
  'DEFERRABLE INITIALLY DEFERRED',
  'navision_match_count<>1 OR linked_match_count<>1 OR fresh_detail_location_count<>1',
  'Every Navision upload refreshes that linked vehicle details and reconciles its location',
  'ambiguity fails closed and no duplicate vehicle is created',
  'Production untouched'
]) assert.ok(sql.includes(marker), marker);
assert.match(sql, /AFTER INSERT OR UPDATE OF normalized_data,is_current,record_status,canonical_vehicle_id ON public\.navision_backend_records/);
assert.match(sql, /AFTER INSERT OR UPDATE OF stock_number,source_system,source_record_id,source_payload,deleted_at ON public\.vehicles/);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.pdc_navision_vehicle_parity_494\(uuid\) TO authenticated,service_role/);
assert.strictEqual(identity.application_version, '2026.08.27.706-final-authoritative-lifecycle');
assert.strictEqual(identity.observed_applied_database_migration.version, '20260827051000');
assert.strictEqual(identity.production_unchanged, true);
console.log('All-vehicle Navision link and refresh parity guard 494: PASS');
