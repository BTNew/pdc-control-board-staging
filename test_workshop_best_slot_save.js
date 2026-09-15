'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createSlotRuntime, at } = require('./tests/helpers/workshop-slot-runtime.cjs');
function setup() {
 const r = createSlotRuntime();
 r.context.window.PDC_AUTH_CONTEXT = { role: 'administrator' };
 r.context.workshopRequireSchedulableCandidate = () => true;
 r.context.workshopConfirmOtherDepartmentPlans = () => true;
 r.context.workshopLoadPlans = () => [];
 return r;
}
const args = () => ({ requestedCandidate: { stage: 'FITTING' }, vehicleRef: { vehicleId: 'vehicle', version: 4 }, stageCode: 'FITTING', bayNumber: 1, scheduledStartAt: at(14).toISOString(), durationMinutes: 60 });
test('Best slot saves a free space without cascading later jobs', async () => {
 const r=setup(), calls=[];
 assert.equal(await r.planner.workshopScheduleSharedNewBooking({...args(),cascade:false},async (action,payload)=>{calls.push({action,payload});return {ok:true};}),true);
 assert.equal(calls.length,1);
 assert.equal(calls[0].action,'administratorScheduleVehicle');
 assert.equal(calls[0].payload.cascade,false);
 assert.equal(calls[0].payload.metadata.source,'planner_best_slot');
 assert.equal(calls[0].payload.scheduledStartAt,args().scheduledStartAt);
});
test('Explicit drag placement retains its existing cascade behaviour', async () => {
 const r=setup(); let saved;
 await r.planner.workshopScheduleSharedNewBooking(args(),async (action,payload)=>{saved=payload;return {ok:true};});
 assert.equal(saved.cascade,true);
 assert.equal(saved.metadata.reason,'website_drag_drop');
});
test('An uncertain save retries the exact same non-cascading request', async () => {
 const r=setup(), calls=[];
 assert.equal(await r.planner.workshopScheduleSharedNewBooking({...args(),cascade:false},async (action,payload)=>{calls.push(payload);return calls.length===1?{ok:false,error:'no_response'}:{ok:true};}),true);
 assert.equal(calls.length,2);
 assert.equal(calls[0],calls[1]);
 assert.equal(calls[1].cascade,false);
 assert.ok(calls[1].requestId);
});
test('Definite scheduling conflicts are not blindly retried', async () => {
 const r=setup();let calls=0;
 assert.equal(await r.planner.workshopScheduleSharedNewBooking({...args(),cascade:false},async()=>{calls++;return {ok:false,error:'vehicle_overlap'};}),false);
 assert.equal(calls,1);
});
test('Best slot carries free-space intent through the ordinary scheduling entry point',()=>{
 const source=fs.readFileSync('workshop-planner.js','utf8');
 const start=source.indexOf('async function workshopScheduleVehicleNextAvailable');
 const end=source.indexOf('async function scheduleWorkshopVehicle',start);
 assert.match(source.slice(start,end),/cascadeNewBooking: false/);
 assert.match(source.slice(end),/cascade: cascadeNewBooking/);
});
