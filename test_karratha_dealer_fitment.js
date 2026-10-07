'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const local = require('./karratha/vehicle-location-lifecycle.js');
const pmg = require('./vehicle-location-lifecycle.js');
const fs = require('node:fs');
const source = {navisionSubLocationDescription:'Delivered - At Dealer'};
test('135 exact dealer arrival enters local fitment without changing source status', () => {
 for (const current_location of ['Other','YH','IT','At Dealer']) {
  const result=local.resolveVehicleLifecycleLocation({...source,current_location});
  assert.equal(result.location,'PMB');assert.equal(result.status,'delivered - at dealer');
 }
 assert.equal(local.resolveVehicleLifecycleLocation({toyotaStatus:'Delivered - At Body Builder'}).location,'PMB');
});
test('135 dealer arrival preserves actual QC, RFT, pit and completed progress', () => {
 for(const current_location of ['QC','PIT','RFT','Completed'])
  assert.equal(local.resolveVehicleLifecycleLocation({...source,current_location}).location,current_location);
 assert.equal(local.resolveVehicleLifecycleLocation({...source,lifecycle_state:'completed',current_location:'Other'}).location,'Completed');
});
test('135 arrival requires exact source evidence, not a code or comment', () => {
 for(const v of [{navisionLocationStatus:'OD'},{comments:'Delivered - At Dealer'},{toyotaStatus:'dealer received'}])
  assert.equal(local.resolveVehicleLifecycleLocation(v).location,'Other');
});
test('PMG dealer delivery semantics remain unchanged', () => {
 assert.equal(pmg.resolveVehicleLifecycleLocation({...source,current_location:'PMB'}).location,'Completed');
 assert.equal(pmg.resolveVehicleLifecycleLocation({...source,current_location:'YH'}).location,'YH');
});
test('135 migration preserves source identity, staff review and protected workflow functions', () => {
 const sql=fs.readFileSync(__dirname+'/supabase/migrations/20261007023141_karratha135_dealer_fitment_arrival.sql','utf8');
 assert.equal(/CREATE OR REPLACE FUNCTION public\./i.test(sql),false);
 assert.equal(/^\s*(?:GRANT|ALTER .*DISABLE TRIGGER|DROP FUNCTION|UPDATE .*vehicles\b)/im.test(sql.split('AS $function$')[0]),false);
 assert.ok(sql.includes("'dealer_fitment_not_terminal'"));
 assert.ok(sql.includes("'intake_review_required'"));
 assert.ok(sql.includes("r.status='pending'"));
 assert.ok(sql.includes("v_status IN ('deliveredatbodybuilder','deliveredatdealer')"));
 assert.equal(/CREATE OR REPLACE FUNCTION .*approve_pdc|CREATE OR REPLACE FUNCTION .*qc_|CREATE OR REPLACE FUNCTION .*parts_/i.test(sql),false);
});

