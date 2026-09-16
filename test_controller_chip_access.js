'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createSlotRuntime, at } = require('./tests/helpers/workshop-slot-runtime.cjs');
function setup(role) {
 const r=createSlotRuntime();
 r.context.window.PDC_AUTH_CONTEXT={role};
 r.context.window.alert=()=>{};
 r.context.workshopRequireSchedulableCandidate=()=>true;
 r.context.workshopConfirmOtherDepartmentPlans=()=>true;
 r.context.workshopLoadPlans=()=>[];
 return r;
}
const args=()=>({requestedCandidate:{stage:'FITTING'},vehicleRef:{vehicleId:'vehicle',version:4},stageCode:'FITTING',bayNumber:1,scheduledStartAt:at(18).toISOString(),durationMinutes:60});
for(const role of ['operator','administrator']) {
 test(`${role} can place unallocated chips with receipt-safe retries`,async()=>{
  const r=setup(role), calls=[];
  const ok=await r.planner.workshopScheduleSharedNewBooking(args(),async(action,payload)=>{calls.push({action,payload});return calls.length===1?{ok:false,error:'no_response'}:{ok:true};});
  assert.equal(ok,true); assert.equal(calls.length,2);
  assert.equal(calls[0].action,'administratorScheduleVehicle');
  assert.equal(calls[0].payload,calls[1].payload);
  assert.equal(calls[0].payload.cascade,true);
 });
 test(`${role} moves an existing chip between bays and can undo its receipt`,async()=>{
  const r=setup(role), c=r.context, calls=[];
  c.workshopLoadPlans=()=>[{id:'booking',sharedBookingId:'booking',sharedVersion:3,vehicleKey:'vehicle',stage:'FITTING',bay:1,status:'planned',hours:1}];
  c.workshopVehicle=()=>({}); c.workshopRequireEtaSchedule=()=>true;
  c.workshopSchedulingDuration=()=>({hours:1});
  c.workshopBookingDestinationHours=()=>1;
  c.workshopBayMechanic=()=>''; c.pmbBayMechanic=()=>'';
  c.workshopDispatchSharedAction=async(action,payload)=>{calls.push({action,payload});return {ok:true,receipt_id:'receipt',booking_id:'booking',booking_version:4};};
  assert.equal(await c.scheduleWorkshopVehicle({planId:'booking',stage:'FITTING',bay:2,dateKey:'2026-09-18',startMinutes:60,preferRequestedTime:true}),true);
  assert.equal(calls[0].action,'administratorMoveBooking');
  assert.equal(calls[0].payload.expectedVersion,3);
  assert.equal(calls[0].payload.cascade,true);
  assert.equal(await c.workshopUndoLastAdministratorMove(),true);
  assert.equal(calls[1].action,'undoAdministratorBookingMove');
  assert.equal(calls[1].payload.receiptId,'receipt');
  assert.equal(calls[1].payload.expectedVersion,4);
 });
}
for(const role of ['viewer','importer','fitter','',null]) {
 test(`${role || 'no role'} cannot place an unallocated chip`,async()=>{
  const r=setup(role);let called=false;
  assert.equal(await r.planner.workshopScheduleSharedNewBooking(args(),async()=>{called=true;return {ok:true};}),false);
  assert.equal(called,false);
  assert.equal(r.context.workshopAdministratorCanMove(),false);
 });
}
test('Controller vehicle moves do not unlock administrator blocks',()=>{
 const r=setup('operator');
 assert.equal(r.context.workshopAdministratorCanMove(),true);
 assert.equal(r.context.workshopAdminBlockCanMutate(),false);
 assert.equal(r.context.workshopAdminBlockCanMutate('administrator'),true);
});
