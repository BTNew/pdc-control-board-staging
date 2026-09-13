'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
const start=source.indexOf('function workshopQueueCardHtml(');
const queue=source.slice(start,source.indexOf('\nfunction ',start+10));
function fixture(){
 const context={
  escapeHtml:v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),
  vehicleKey:v=>v.stock,isPdcBlocked:()=>false,workshopPartsSummary:()=>({status:'none',text:'Unknown'}),
  workshopState:()=>({stage:'FITTING',date:'2026-09-14'}),workshopQueueEstimatedLabel:()=> '8 h',
  workshopSchedulingDuration:()=>({hours:8}),workshopVehicleEtaConstraint:()=>({ok:true,required:false}),
  workshopSharedModeActive:()=>true,workshopOutstandingDisabledReasonLabel:v=>v||'',
  workshopVehicleIdentitySummaryHtml:v=>'<strong>'+v.stock+'</strong>',workshopQueueVehicleDescription:()=> 'Hilux',
  vehicleCustomerName:()=> 'Sample customer',
  workshopBestStageSlot:()=>{throw Error('Rendering must not search availability');},
 };
 vm.createContext(context);vm.runInContext(queue,context);return context;
}
test('waiting-list rendering never searches future slots and retains clickable canonical vehicle identity',()=>{
 const ctx=fixture();
 for(let i=0;i<100;i++){
  const html=ctx.workshopQueueCardHtml({stock:'fixture-'+i},'FITTING','2026-09-14',[]);
  assert(html.includes('data-workshop-best-slot-vehicle="fixture-'+i+'"'));
  assert(html.includes('data-workshop-best-slot-stage="FITTING"'));
  assert(html.includes('data-workshop-best-slot-hours="8"'));
  assert(!html.includes('data-workshop-best-slot-bay'));
 }
});
test('unavailable hours, ETA, existing bookings and authority still disable scheduling',()=>{
 const ctx=fixture();
 const assertDisabled=vehicle=>{
  const html=ctx.workshopQueueCardHtml(vehicle,'FITTING','2026-09-14',[]);
  assert(!html.includes('data-workshop-best-slot-vehicle='));assert(html.includes('draggable="false"'));assert(html.includes('disabled title='));
 };
 assertDisabled({stock:'test',__workshopOutstanding:{existingBooking:true,scheduleEnabled:true}});
 assertDisabled({stock:'test',__workshopOutstanding:{existingBooking:false,scheduleEnabled:false}});
 ctx.workshopSchedulingDuration=()=>null;assertDisabled({stock:'test'});
 ctx.workshopSchedulingDuration=()=>({hours:8});ctx.workshopVehicleEtaConstraint=()=>({required:true,ok:false,reason:'missing_eta',location:'IT'});assertDisabled({stock:'test'});
});
test('Best slot click invokes the fresh scheduling path and prevents duplicate submissions',async()=>{
 const begin=source.indexOf("root.querySelectorAll('[data-workshop-best-slot-vehicle]')");
 const handler=source.slice(begin,source.indexOf("root.querySelectorAll('[data-workshop-admin-block-id]')",begin));
 let click,resolve;const calls=[];
 const button={dataset:{workshopBestSlotVehicle:'canonical-fixture',workshopBestSlotStage:'FITTING',workshopBestSlotHours:'8'},disabled:false,isConnected:true,
  addEventListener:(type,fn)=>{click=fn;},setAttribute:()=>{},removeAttribute:()=>{}};
 const context={root:{querySelectorAll:()=>[button]},workshopScheduleVehicleNextAvailable:args=>{calls.push(args);return new Promise(done=>{resolve=done;});}};
 vm.runInNewContext(handler,context);const event={preventDefault(){},stopPropagation(){}};
 const pending=click(event);await click(event);assert.equal(calls.length,1);assert.equal(calls[0].vehicleKeyValue,'canonical-fixture');assert.equal(calls[0].stage,'FITTING');assert.equal(calls[0].hours,8);assert(button.disabled);
 resolve(false);await pending;assert.equal(button.disabled,false);
});
