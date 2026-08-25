const assert = require('assert');
const fs = require('fs');
const path = require('path');
const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826214000_435_acceptance_postcondition_delta.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 435 acceptance postcondition repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "version='20260826213000'",
  "name='434_acceptance_containment_rebind'",
  "values('20260826214000','435_acceptance_postcondition_delta'",
  "pg_get_functiondef('public.create_pdc_acceptance_vehicle_375",
  'v_notifications_before',
  '(select count(*) from public.vehicle_notifications)<>v_notifications_before',
  'execute repaired',
  'pdc_hermes_containment_contract_432()',
]) assert.ok(sql.includes(marker), `435 migration missing ${marker}`);
assert.ok(sql.includes("v_notifications_before<>0"), '435 must explicitly target the stale zero-row postcondition');
for (const forbidden of ['delete from public.vehicle_notifications', 'truncate ', 'cascade', 'vjdtsswhroyguxyfjdkt']) {
  assert.ok(!sql.includes(forbidden), `435 migration must not contain ${forbidden}`);
}
console.log('acceptance_postcondition_delta_435: PASS');
