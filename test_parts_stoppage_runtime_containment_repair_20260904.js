const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260904011500_parts_stoppage_runtime_containment_repair.sql');
assert.ok(fs.existsSync(migrationPath), 'new guarded linear Parts STOPPAGE repair migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');

assert.match(sql, /cdsmnqxtyyoeoznmbidd/);
assert.doesNotMatch(sql, /vjdtsswhroyguxyfjdkt/);
assert.match(sql, /20260904011400/);
assert.match(sql, /pdc14_location_replay_partial_cleanup_identifier_repair/);
assert.match(sql, /d2a2e96c38633fec639a3cd6b2ef0adb18d96ff3640a2f08ef19feb7c19ea82f/);
assert.match(sql, /pg_get_functiondef\('public\.set_pdc_parts_stoppage_376\(uuid,integer,uuid,text,text\)'::regprocedure\)/);
assert.match(sql, /pdc_monitor_staging_guard\(\)/);
assert.match(sql, /v_notifications_after<>v_notifications_before/);
assert.match(sql, /pdc_parts_stoppage_receipts_376/);
assert.match(sql, /CREATE TABLE public\.pdc_parts_stoppage_verification_cleanup_20260904/);
assert.match(sql, /FORCE ROW LEVEL SECURITY/);
assert.match(sql, /PDC_PARTS_STOPPAGE_VERIFICATION_CLEANUP_IMMUTABLE/);
assert.match(sql, /SECURITY DEFINER/i);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.set_pdc_parts_stoppage_376\(uuid,integer,uuid,text,text\) FROM public,anon,authenticated,service_role/);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.set_pdc_parts_stoppage_376\(uuid,integer,uuid,text,text\) TO authenticated/);
assert.match(sql, /has_function_privilege\('anon'/);
assert.match(sql, /has_function_privilege\('service_role'/);
assert.match(sql, /20260904011500/);
assert.match(sql, /parts_stoppage_runtime_containment_repair/);
assert.doesNotMatch(sql, /DROP TABLE|ALTER TABLE .* DISABLE ROW LEVEL SECURITY|GRANT .* TO (anon|public|service_role)/i);

console.log('Parts STOPPAGE runtime containment repair migration contract: PASS');
