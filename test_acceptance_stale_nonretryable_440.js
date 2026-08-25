const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826223000_440_acceptance_stale_nonretryable.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 440 non-retryable stale repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "current_user<>'postgres'",
  "session_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826222000'",
  "name='439_acceptance_stale_before_binding'",
  "values('20260826223000','440_acceptance_stale_nonretryable'",
  "pg_get_functiondef('public.pdc_acceptance_lifecycle_375",
  'v.version is distinct from p_expected_version',
  "raise exception 'pdc_375_lifecycle_version_conflict' using errcode='p0001'",
  "raise exception 'pdc_375_lifecycle_version_conflict' using errcode='40001'",
  'v_notification_state_after<>v_notification_state_before',
  'v_outbound_after<>v_outbound_before',
  'execute repaired',
  'grant execute on function public.pdc_acceptance_lifecycle_375',
]) assert.ok(sql.includes(marker), `440 migration missing ${marker}`);
assert.ok(!sql.includes('delete from public.vehicle_notifications'), '440 must not delete notifications');
assert.ok(!sql.includes('delete from public.pdc_rft_transport_salesperson_outbox_412'), '440 must not delete outbound');
assert.ok(!sql.includes('vjdtsswhroyguxyfjdkt'), '440 must not reference production');
console.log('acceptance_stale_nonretryable_440: PASS');
