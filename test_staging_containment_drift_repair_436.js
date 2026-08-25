const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826215000_436_current_containment_read_repair.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 436 containment repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();

for (const marker of [
  "current_user<>'postgres'",
  "session_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826214000'",
  "name='435_acceptance_postcondition_delta'",
  "values('20260826215000','436_current_containment_read_repair'",
  'create or replace function public.pdc_hermes_containment_contract_432()',
  'pdc_acceptance_protected_digest_375()',
  'pdc_hermes_notification_state_sha256_432()',
  'pdc_hermes_outbound_state_sha256_432()',
  'v_protected_before',
  'v_protected_after',
  'v_notifications_before',
  'v_notifications_after',
  'v_outbound_before',
  'v_outbound_after',
  'execute repaired',
  "pg_get_functiondef('public.create_pdc_acceptance_vehicle_375",
  "pg_get_functiondef('public.pdc_acceptance_lifecycle_375",
  'grant execute on function public.read_pdc_hermes_test_mutation_state_365',
  'grant execute on function public.read_pdc_acceptance_vehicle_state_375',
]) assert.ok(sql.includes(marker), `436 migration missing ${marker}`);

assert.ok(sql.includes('sent_at is not null or delivered_at is not null'), '436 must keep sent/delivered outbound containment');
assert.ok(sql.includes('protected_state is not distinct from public.pdc_current_protected_state_digest_432()') === false, 'read contract must not freeze mutable protected state at 432 baseline');
assert.ok(sql.includes("position('v_notifications_before<>0' in repaired)>0"), '436 must explicitly reject retaining the stale create precondition');
assert.ok(sql.includes("position('v_notifications_after<>0' in repaired)>0"), '436 must explicitly reject retaining the stale lifecycle precondition');
assert.ok(sql.includes("position('(select count(*) from public.vehicle_notifications)<>0' in repaired)>0"), '436 must explicitly reject retaining the stale zero-row guard');
for (const forbidden of ['delete from public.vehicle_notifications', 'delete from public.pdc_rft_transport_salesperson_outbox_412', 'update public.vehicle_notifications', 'update public.pdc_rft_transport_salesperson_outbox_412', 'truncate ', 'cascade', 'vjdtsswhroyguxyfjdkt']) {
  assert.ok(!sql.includes(forbidden), `436 migration must not contain ${forbidden}`);
}
console.log('staging_containment_drift_repair_436: PASS');
