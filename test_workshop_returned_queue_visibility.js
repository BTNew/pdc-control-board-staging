'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('workshop-planner.js', 'utf8');
const start = source.indexOf('function workshopReturnedQueuePlans(');
const end = source.indexOf('function renderWorkshopPlanner(', start);
const context = {
  workshopVehicle: key => ({stock: key}), displayStockNumber: v => v.stock,
  escapeHtml: value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'),
};
vm.createContext(context);
vm.runInContext(source.slice(start,end),context);
const base={id:'returned',sharedVehicleId:'v1',vehicleKey:'123',stage:'BUS_4X4',sharedStatus:'queued',sharedBayId:'',bay:0,hours:88.3167};
const rows=[base,{...base,id:'electrical',workCategory:'BUS_ELECTRICAL'},
  {...base,id:'reserved',sharedStatus:'planned',sharedBayId:'bay1',bay:1},
  {...base,id:'completed',sharedStatus:'completed'}, {...base,id:'other',stage:'FITTING'}];
const result=context.workshopReturnedQueuePlans(rows,'BUS_4X4','BUS_MECHANICAL');
assert.deepEqual(Array.from(result,row=>row.id),['returned']);
assert.equal(context.workshopReturnedQueuePlans(rows,'BUS_4X4').length,2);
assert.equal(result[0],base,'retain canonical booking identity and hours');
const html=context.workshopReturnedQueueCardHtml(base);
assert.match(html,/data-workshop-plan-id="returned"/);
assert.match(html,/88.32 allocated hours retained/);
assert.match(html,/draggable="true"/);
assert.match(html,/data-workshop-select-returned-plan="returned"/);
const state={stage:'BUS_4X4',searchOpen:true};
let selected='', rendered=0, opened=null;
let trusted=true;
Object.assign(context,{
  workshopState:()=>state,workshopSelectedBusGroup:()=>({code:'BUS_MECHANICAL'}),
  workshopLoadPlans:()=>rows,workshopSharedModeActive:()=>true,
  window:{__workshopDataService:{getTrustedSnapshot:()=>trusted?{}:null}},
  workshopSelectPlanForDetail:id=>{selected=id;},
  renderWorkshopPlanner:()=>{rendered++;},document:{querySelector:()=>null},
  openWorkshopVehicleJob:(key,stage,id)=>{opened={key,stage,id};},
});
assert.equal(context.workshopSelectReturnedPlan('returned'),true);
assert.equal(selected,'returned','select existing reservation without creating another');
assert.deepEqual(opened,{key:'123',stage:'BUS_4X4',id:'returned'},'open existing booking in the vehicle job dialog');
assert.equal(state.searchOpen,false);
assert.equal(state.searchHighlightPlanId,'returned');
assert.equal(context.workshopSelectReturnedPlan('electrical'),false,'respect current category');
assert.equal(context.workshopSelectReturnedPlan('reserved'),false,'reject already scheduled reservation');
trusted=false;
assert.equal(context.workshopSelectReturnedPlan('returned'),false,'stale snapshot cannot select a reservation');
assert.equal(rendered,1);
assert.doesNotMatch(html,/data-workshop-schedule-vehicle/,'do not create a duplicate booking');
assert.match(source,/sharedStatus: booking.status/);
assert.match(source,/entry.status !== 'completed' && Number\(entry.bay\) > 0/,'bay counters exclude queued reservations');
console.log('Returned booking visibility and canonical drag identity: PASS');
