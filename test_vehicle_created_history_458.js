/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r458 (F71, Craig 22 Oct, decision 6): a vehicle's creation shows as 'Created' in Detailed history instead of an
// update with every value going to blank. Display only (the history rows are not changed). Frontend only, so no
// daily database check; this test is the check.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {isVehicleCreationEvent,presentVehicleCreationEvents}=require('./pdc-email-vehicle-location-service.js');
const at='2026-10-16T04:26:36.677844+00:00';
const created={id:'e1',table_name:'vehicles',action:'update',row_id:'v1',created_at:at,metadata:{contract:'tune_daily_fields_v5'},
  before_data:{id:'v1',created_at:'2026-10-16 04:26:36.677844+00',stock_number:'TEST-1',vin:null,current_location:'Yard Hold',lifecycle_state:'active'},
  after_data:{details:{customer_name:'Test Customer',vehicle_description:'TEST MODEL',vin:null},parts_status:'review'}};
test('r458: the creation record becomes one Created entry with the values the vehicle was created with',()=>{
  assert.equal(isVehicleCreationEvent(created),true);
  const out=presentVehicleCreationEvents({audit_events:[created]}).audit_events;
  assert.equal(out.length,1);
  assert.equal(out[0].action,'Created');assert.equal(out[0].table_name,'vehicle');
  assert.deepEqual(out[0].before_data,{});assert.deepEqual(out[0].after_data,{});
  assert.deepEqual(out[0].metadata,{stock_number:'TEST-1',vehicle_description:'TEST MODEL',customer_name:'Test Customer',current_location:'Yard Hold',lifecycle_state:'active',parts_status:'review',source:'tune_daily_fields_v5'});
  assert.equal(created.action,'update','the original record is not changed');
});
test('r458: records sharing the creation instant merge into the one Created entry',()=>{
  const also={...created,id:'e2',after_data:{current_location:'Kewdale'},metadata:{}};
  const out=presentVehicleCreationEvents({audit_events:[also,created]}).audit_events;
  assert.equal(out.length,1);assert.equal(out[0].metadata.current_location,'Kewdale');assert.equal(out[0].metadata.customer_name,'Test Customer');
});
test('r458: ordinary updates, full-row updates and other tables are left alone',()=>{
  const later={...created,created_at:'2026-10-17T01:00:00+00:00'};
  const fullRow={...created,after_data:{id:'v1',stock_number:'TEST-2'}};
  const other={...created,table_name:'pdc_new_vehicle_reviews'};
  const insert={...created,action:'insert'};
  for(const e of [later,fullRow,other,insert]) assert.equal(isVehicleCreationEvent(e),false);
  const data={audit_events:[later,fullRow,other]};assert.equal(presentVehicleCreationEvents(data),data);
  assert.equal(presentVehicleCreationEvents(null),null);
});
test('r458: vehicleHistory applies it and index.html cache-busts the service',()=>{
  const src=fs.readFileSync('pdc-email-vehicle-location-service.js','utf8');
  assert.match(src,/data: presentVehicleCreationEvents\(body\.data \|\| body\)/);
  assert.match(fs.readFileSync('index.html','utf8'),/pdc-email-vehicle-location-service\.js\?[^"]*vehicle-created=2026\.10\.22\.r458" defer>/);
});
