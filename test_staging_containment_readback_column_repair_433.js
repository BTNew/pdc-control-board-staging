const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260826212000_433_containment_readback_column_repair.sql');
assert.ok(fs.existsSync(migrationPath), 'append-only 433 readback repair must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel') is not null",
  "version='20260826211000'",
  "name='432_current_hermes_containment_contract'",
  "values('20260826212000','433_containment_readback_column_repair'",
  'create or replace function public.read_pdc_hermes_test_mutation_state_365',
  "jsonb_agg(to_jsonb(h) order by h.id) from public.workshop_booking_history",
  'pdc_hermes_containment_contract_432()',
  "grant execute on function public.read_pdc_hermes_test_mutation_state_365",
]) assert.ok(sql.includes(marker), `433 repair missing ${marker}`);
assert.ok(sql.includes('pdc_365_read_containment_drift'), 'repair must keep the fail-closed read error');
for (const forbidden of ['delete from public.vehicle_notifications', 'truncate ', 'cascade', 'vjdtsswhroyguxyfjdkt']) {
  assert.ok(!sql.includes(forbidden), `433 repair must not contain ${forbidden}`);
}
console.log('staging_containment_readback_column_repair_433: PASS');
