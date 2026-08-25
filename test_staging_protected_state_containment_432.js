const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const migrationPath = path.join(root, 'supabase', 'staging_only', '20260826211000_432_current_hermes_containment_contract.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 432 containment correction must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');
const lower = sql.toLowerCase();

for (const marker of [
  "current_user<>'postgres'",
  "session_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826210000'",
  "name='431_intercept_storage_security_definer_predicate'",
  "version>'20260826210000'",
  "values('20260826211000','432_current_hermes_containment_contract'",
  'pdc_hermes_authorized_vehicle_432',
  'pdc_current_protected_state_digest_432',
  'pdc_hermes_containment_contract_432',
  'pdc_hermes_containment_baseline_432',
  'notification_state_sha256',
  'outbound_state_sha256',
  'CREATE OR REPLACE FUNCTION public.pdc_hermes_test_dependency_guard_365',
  'CREATE OR REPLACE FUNCTION public.read_pdc_hermes_test_mutation_state_365',
  'CREATE OR REPLACE FUNCTION public.read_pdc_acceptance_vehicle_state_375',
  'pdc_overnight_synthetic_fleet_registry_363',
  'pdc_acceptance_vehicle_bindings_375',
  'NOTIFY pgrst',
  'REVOKE ALL ON FUNCTION public.pdc_hermes_containment_contract_432()',
  'GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_mutation_state_365',
  'GRANT EXECUTE ON FUNCTION public.read_pdc_acceptance_vehicle_state_375',
]) assert.ok(lower.includes(marker.toLowerCase()), `migration missing ${marker}`);

assert.ok(lower.includes("running_status='stopped'"), 'monitor must be stopped');
assert.ok(lower.includes('not enabled') && lower.includes('not outbound_email_enabled'), 'outbound monitor must remain disabled');
assert.ok(lower.includes('active_mailboxes') || lower.includes('monitored_mailboxes'), 'active mailboxes must be guarded');
assert.ok(lower.includes('active_writers') || lower.includes('pdc_monitor_stage_activation_writers'), 'active writers must be guarded');
assert.ok(lower.includes('vehicle_notifications'), 'notification containment must be explicit');
assert.ok(lower.includes('sent_at') && lower.includes('delivered_at'), 'outbound sent/delivered state must be contained');
assert.ok(lower.includes('pdc_acceptance_vehicle_registry_375'), 'acceptance registry identity must be included');
assert.ok(lower.includes("source_batch_id='hermes-test-acceptance-20260825'") || lower.includes("source_batch_id<>'hermes-test-acceptance-20260825'"), 'acceptance identity must remain exact');
assert.ok(lower.includes("run_id='hermes-test-run-20260824'") || lower.includes("run_id<>'hermes-test-run-20260824'"), 'overnight identity must remain exact');

for (const forbidden of [
  'delete from public.vehicle_notifications',
  'delete from public.pdc_rft_transport_salesperson_outbox_412',
  'update public.vehicle_notifications',
  'update public.pdc_rft_transport_salesperson_outbox_412',
  'truncate ',
  'cascade',
  'production_ref',
  'vjdtsswhroyguxyfjdkt',
]) assert.ok(!lower.includes(forbidden), `migration must not contain ${forbidden}`);

assert.ok(lower.includes('protected_state is not distinct from public.pdc_current_protected_state_digest_432()'), 'ordinary protected-row drift must fail closed');
assert.ok(lower.includes('notification_state_sha256') && lower.includes('outbound_state_sha256'), 'ordinary notification/outbound drift must fail closed');
assert.ok(lower.includes('not public.pdc_hermes_authorized_vehicle_432(v.id)'), 'protected digest must exclude only authorised registry-bound vehicles');
assert.ok(lower.includes('order by n.id'), 'notification baseline must be deterministic');
assert.ok(lower.includes('order by o.notification_id'), 'outbound baseline must be deterministic');

console.log('staging_protected_state_containment_432: PASS');
