const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826221000_438_acceptance_stale_fast_path.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 438 stale fast-path repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "current_user<>'postgres'",
  "session_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826220000'",
  "name='437_registered_replay_containment_repair'",
  "values('20260826221000','438_acceptance_stale_fast_path'",
  "pg_get_functiondef('public.pdc_acceptance_lifecycle_375",
  'v.version is distinct from p_expected_version',
  "raise exception 'pdc_375_lifecycle_version_conflict'",
  'v_notification_state_after<>v_notification_state_before',
  'v_outbound_after<>v_outbound_before',
  'pdc_hermes_containment_contract_432()',
  'execute repaired',
  'grant execute on function public.pdc_acceptance_lifecycle_375',
]) assert.ok(sql.includes(marker), `438 migration missing ${marker}`);
const early = sql.indexOf('v.version is distinct from p_expected_version');
const runtimeLock = sql.indexOf('lock table public.pdc_email_monitor_pilot');
assert.ok(early >= 0 && runtimeLock > early, 'stale rejection must precede containment lock path');
for (const forbidden of [
  'delete from public.vehicle_notifications',
  'delete from public.pdc_rft_transport_salesperson_outbox_412',
  'update public.vehicle_notifications',
  'update public.pdc_rft_transport_salesperson_outbox_412',
  'truncate ',
  'cascade',
  'vjdtsswhroyguxyfjdkt',
]) assert.ok(!sql.includes(forbidden), `438 migration must not contain ${forbidden}`);
console.log('acceptance_stale_fast_path_438: PASS');
