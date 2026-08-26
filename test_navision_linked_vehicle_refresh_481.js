'use strict';
const assert=require('assert'),fs=require('fs');
const sql=fs.readFileSync('supabase/staging_only/20260827031000_481_navision_linked_vehicle_refresh.sql','utf8');
const app=fs.readFileSync('app.js','utf8');
const service=fs.readFileSync('pdc-email-vehicle-location-service.js','utf8');
for(const marker of [
  'pdc_owner_navision_link_rules_481','pdc_refresh_linked_vehicle_from_navision_481',
  "v.stock_number_normalized IS DISTINCT FROM stock","salesperson_manual_override THEN salesperson_id",
  "salesperson_manual_override THEN salesperson_reference","'lifecycle_mutated',false",
  "'job_card_overwritten',false",'navision_record_operational_reconcile',
  "'navision_colour'","'navision_salesperson_raw'",
]) assert.ok(sql.includes(marker),`missing migration marker: ${marker}`);
assert.match(sql,/CREATE OR REPLACE FUNCTION public\.reconcile_navision_operational_record[\s\S]+pdc_refresh_linked_vehicle_from_navision_481/);
assert.match(sql,/Exact Stock links one canonical operational vehicle/);
assert.match(service,/colour: String\(row\.navision_colour \|\| ''\)\.trim\(\)/);
assert.match(service,/navisionSalespersonRaw: String\(row\.navision_salesperson_raw \|\| ''\)\.trim\(\)/);
assert.match(app,/canonicalVehicleId: item\.canonical_vehicle_id \|\| ''/);
assert.match(app,/return !\(row\.boardActivated && canonicalId && activeCanonicalIds\.has\(canonicalId\)\)/);
assert.match(app,/linked into active rows/);
console.log('Navision linked vehicle refresh 481: PASS');
