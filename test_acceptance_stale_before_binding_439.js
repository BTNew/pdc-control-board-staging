const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826222000_439_acceptance_stale_before_binding.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 439 stale-before-binding repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "current_user<>'postgres'",
  "session_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826221000'",
  "name='438_acceptance_stale_fast_path'",
  "values('20260826222000','439_acceptance_stale_before_binding'",
  "pg_get_functiondef('public.pdc_acceptance_lifecycle_375",
  'v.version is distinct from p_expected_version',
  "raise exception 'pdc_375_lifecycle_version_conflict'",
  'select b.* into v_binding',
  'v_notification_state_after<>v_notification_state_before',
  'v_outbound_after<>v_outbound_before',
  'execute repaired',
  'grant execute on function public.pdc_acceptance_lifecycle_375',
]) assert.ok(sql.includes(marker), `439 migration missing ${marker}`);
const insertion = sql.slice(sql.indexOf('insertion:='), sql.indexOf('repaired:=replace'));
const stale = insertion.indexOf('v.version is distinct from p_expected_version');
const binding = insertion.indexOf('select b.* into v_binding');
const runtimeLock = sql.indexOf('lock table public.pdc_email_monitor_pilot');
assert.ok(stale >= 0 && binding > stale && runtimeLock > stale, 'stale rejection must precede binding and containment lock path');
for (const forbidden of [
  'delete from public.vehicle_notifications',
  'delete from public.pdc_rft_transport_salesperson_outbox_412',
  'update public.vehicle_notifications',
  'update public.pdc_rft_transport_salesperson_outbox_412',
  'truncate ',
  'cascade',
  'vjdtsswhroyguxyfjdkt',
]) assert.ok(!sql.includes(forbidden), `439 migration must not contain ${forbidden}`);
console.log('acceptance_stale_before_binding_439: PASS');
