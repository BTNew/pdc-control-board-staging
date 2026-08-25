const assert = require('assert');
const fs = require('fs');
const path = require('path');
const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826220000_437_registered_replay_containment_repair.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 437 replay containment repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "current_user<>'postgres'",
  "session_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826215000'",
  "name='436_current_containment_read_repair'",
  "values('20260826220000','437_registered_replay_containment_repair'",
  "pg_get_functiondef('public.create_pdc_acceptance_vehicle_375",
  "pg_get_functiondef('public.pdc_acceptance_lifecycle_375",
  "public.pdc_acceptance_protected_digest_375() is distinct from v_receipt.response->''protected_state''",
  'execute repaired',
  'pdc_hermes_containment_contract_432()',
  'grant execute on function public.create_pdc_acceptance_vehicle_375',
  'grant execute on function public.pdc_acceptance_lifecycle_375',
]) assert.ok(sql.includes(marker), `437 migration missing ${marker}`);
assert.ok(!sql.includes('delete from public.vehicle_notifications'), '437 must not delete notifications');
assert.ok(!sql.includes('truncate '), '437 must not truncate');
assert.ok(!sql.includes('vjdtsswhroyguxyfjdkt'), '437 must not reference production');
console.log('registered_replay_containment_repair_437: PASS');
