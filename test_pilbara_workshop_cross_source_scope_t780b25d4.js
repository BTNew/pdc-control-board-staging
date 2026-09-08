'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260908151000_pilbara_workshop_cross_source_scope.sql';
assert.ok(fs.existsSync(migrationPath), 'narrow Pilbara cross-source Workshop scope migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');

for (const marker of [
  'pdc_workshop_actor_vehicle_allowed',
  "p_scope->>'dealer_code'=v_vehicle_dealer",
  "p_scope->>'dealer_code'='14450'",
  "v_vehicle_dealer='37047'",
  'pdc_pilbara_service_operations',
  'get_vehicle_workshop_detail_scoped',
  'save_vehicle_workshop_line_hours_batch_768',
]) assert.ok(sql.includes(marker), `scope migration missing ${marker}`);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.pdc_workshop_actor_vehicle_allowed\(jsonb,uuid,text\) FROM public,anon,authenticated,service_role/i, 'authorization helper is internal-only');
assert.ok(!/GRANT EXECUTE ON FUNCTION public\.pdc_workshop_actor_vehicle_allowed/i.test(sql), 'browser roles cannot execute the authorization helper directly');
assert.ok(!/INSERT INTO public\.pdc_auditor_user_dealer_scopes/i.test(sql), 'repair must not broaden actor scope rows');
assert.ok(!/UPDATE\s+public\.(?:vehicles|pdc_pilbara_service_operations|vehicle_workshop_line_adjustments|workshop_bookings)/i.test(sql), 'scope repair must not mutate business data');
assert.ok(sql.includes("coalesce(p_scope->>'role','') NOT IN"), 'missing actor roles fail closed instead of yielding SQL null');
assert.ok(sql.includes("length(replace(d,old_predicate,''))"), 'dynamic batch patch requires exactly one legacy predicate');
assert.ok(sql.includes("VALUES('20260908151000','pilbara_workshop_cross_source_scope'"), 'migration ledger identity is exact');
assert.ok(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'migration is guarded to STAGING');
assert.ok(sql.includes("to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL"), 'migration refuses Production');

console.log('Narrow Pilbara cross-source Workshop authorization regression passed');
