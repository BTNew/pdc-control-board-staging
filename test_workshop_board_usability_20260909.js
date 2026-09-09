'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const {bookingPlans,inputMinutes}=require('./pdc-workshop-usability');
const guard=require('./vehicle-requirements-guard');
const {mapServerVehicle}=require('./pdc-email-vehicle-location-service');
for(const [key,stage] of [['fitting','FITTING'],['electrical','ELECTRICAL'],['fabrication','FABRICATION'],['tint','TINT'],['hoist','HOIST'],['tyre','TYRE'],['bus4x4','BUS_4X4']]){
 test(`fresh server ${stage} booking projects orange without a loaded planner`,()=>{
  const v=mapServerVehicle({id:'00000000-0000-4000-8000-000000000100',stock_number:'FIXTURE',version:3,work_items:[{work_key:key,required:true,completed:false}],workshop_bookings:[{booking_id:'00000000-0000-4000-8000-000000000101',stage_code:stage,status:'planned',scheduled_start_at:'2026-09-10T00:00:00Z',scheduled_end_at:'2026-09-10T01:00:00Z'}]});
  assert.equal(guard.projectWorkState({workKey:key,required:true,bookings:bookingPlans(v)}).state,'booked');
  v.salesWorkshopBookings[0].status='stoppage';assert.equal(guard.projectWorkState({workKey:key,required:true,bookings:bookingPlans(v)}).state,'stoppage');
  v.salesWorkshopBookings[0].status='cancelled';assert.equal(guard.projectWorkState({workKey:key,required:true,bookings:bookingPlans(v)}).state,'required');
  assert.equal(guard.projectWorkState({workKey:key,required:true,completed:true,bookings:bookingPlans(v)}).state,'completed');
 });
}
test('no local or another-vehicle booking is substituted for the canonical vehicle',()=>{
 assert.equal(bookingPlans({salesWorkshopBookings:[]}),null);
 const v={__emailVehicleServerAuthoritative:true,__emailVehicleId:'one',salesWorkshopBookings:[{bookingId:'two',stageCode:'TINT',status:'planned'}]};
 assert.equal(bookingPlans(v)[0].sharedVehicleId,'one');assert.equal(bookingPlans({...v,salesWorkshopBookings:[]}).length,0);
});
test('Admin values preserve decimal hours and long multi-day work',()=>{
 for(const [h,m] of [[.25,15],[.5,30],[1.5,90],[2.75,165],[15,900]])assert.equal(inputMinutes(String(h),'hours',600,15,60000),m);
 assert.equal(inputMinutes('2','working_days',600,15,60000),1200);
});
test('invalid Admin values cannot silently become the previous/default duration',()=>{
 for(const v of ['',0,-1,'bad','Infinity',100000,.1])assert.equal(inputMinutes(v,'hours',600,15,60000),null);
});
test('mobile and desktop expose explicit multi-item selection, atomic request, and no local completion',()=>{
 const s=fs.readFileSync('pdc-qc-mobile.js','utf8');new vm.Script(s);
 assert.match(s,/p_rejected_lines: lines\.map/);assert.match(s,/data-qc-reject-select/);
 assert.match(s,/function renderDesktop/);assert.match(s,/Select items \/ Reject QC/);
 assert.match(s,/draft\.request \|\|=/);assert.match(s,/received\.size !== lines\.length/);
 assert.doesNotMatch(s,/await service\.setQcOperationCompletion\(row\.__emailVehicleId/);
});
test('the Admin input handler leaves fractional text alone until commit',()=>{
 const s=fs.readFileSync('pdc-workshop-usability.js','utf8');
 assert.match(s,/input\?\.addEventListener\('input', \(\) => update\(false\)\)/);
 assert.match(s,/if \(normalise && input\)/);assert.match(s,/await refreshEmailVehicleLocations\(\)/);
 new vm.Script(s);
});
