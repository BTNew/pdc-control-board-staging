const assert = require('assert');
const fs = require('fs');
const path = require('path');
const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826213000_434_acceptance_containment_rebind.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 434 acceptance containment rebind must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826212000'",
  "name='433_containment_readback_column_repair'",
  "values('20260826213000','434_acceptance_containment_rebind'",
  "pg_get_functiondef('public.create_pdc_acceptance_vehicle_375",
  "pg_get_functiondef('public.pdc_acceptance_lifecycle_375",
  'pdc_hermes_containment_contract_432()',
  'v_notifications_before',
  'execute repaired',
  'v_notifications_after<>v_notifications_before',
  'grant execute on function public.create_pdc_acceptance_vehicle_375',
  'grant execute on function public.pdc_acceptance_lifecycle_375',
]) assert.ok(sql.includes(marker), `434 migration missing ${marker}`);
assert.ok(sql.includes('v_notifications_after<>v_notifications_before') || sql.includes('(select count(*) from public.vehicle_notifications)<>v_notifications_before'), 'notification checks must be delta-based');
for (const forbidden of ['delete from public.vehicle_notifications', 'truncate ', 'cascade', 'vjdtsswhroyguxyfjdkt']) {
  assert.ok(!sql.includes(forbidden), `434 migration must not contain ${forbidden}`);
}
console.log('acceptance_containment_rebind_434: PASS');
