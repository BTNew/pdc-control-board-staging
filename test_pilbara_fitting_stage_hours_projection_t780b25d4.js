'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260908150000_pilbara_fitting_stage_hours_projection.sql';
assert.ok(fs.existsSync(migrationPath), 'successor migration for Pilbara Fitting stage hours must exist');

const sql = fs.readFileSync(migrationPath, 'utf8');
const functionBody = sql.slice(
  sql.indexOf('CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours'),
  sql.indexOf('REVOKE ALL ON FUNCTION public.workshop_vehicle_stage_estimated_hours'),
);
assert.ok(functionBody.includes('pdc_authenticated_email_operation_lines'), 'existing authenticated-email operation source stays projected');
assert.ok(functionBody.includes('pdc_pilbara_service_operations'), 'Pilbara Service operation rows feed planner hours');
assert.ok(functionBody.includes('pdc_pilbara_service_classification_current'), 'Pilbara operation classification controls its planner stage');
assert.ok(functionBody.includes('pdc_overnight_synthetic_estimates_369'), 'existing isolated synthetic regression source stays intact');
assert.match(functionBody, /CASE\s+WHEN\s+a\.adjustment_id\s+IS\s+NOT\s+NULL\s+THEN\s+a\.estimated_hours\s+ELSE\s+o\.effective_estimated_hours\s+END/i, 'a present explicit-unknown adjustment must not fall back to Pilbara source hours');
assert.match(functionBody, /coalesce\(a\.active,true\)/i, 'inactive source-line adjustments remain excluded');
assert.ok(!/UPDATE\s+public\.(?:pdc_pilbara_service_operations|pdc_authenticated_email_operation_lines|vehicle_workshop_line_adjustments|vehicles|workshop_bookings)/i.test(sql), 'projection repair is read-only over business data');
assert.ok(sql.includes("VALUES('20260908150000','pilbara_fitting_stage_hours_projection'"), 'migration ledger identity is exact');
assert.ok(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'migration is guarded to STAGING project');
assert.ok(sql.includes("to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL"), 'migration refuses a Production sentinel');

console.log('Pilbara Fitting planner stage-hours projection regression passed');
