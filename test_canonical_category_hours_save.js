'use strict';
// r409 (F25): app.js shows its messages with pdcNotify() toasts, not alert(); this
// fixture records them through the test's existing alert sink.
const pdcNotifyFixture = ctx => { if (typeof ctx.pdcNotify !== 'function') ctx.pdcNotify = message => (ctx.window && typeof ctx.window.alert === 'function' ? ctx.window : ctx).alert(message); return ctx; };
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const app=fs.readFileSync('app.js','utf8');
function section(start,end){const a=app.indexOf(start),b=app.indexOf(end,a+start.length);assert.ok(a>=0&&b>a);return app.slice(a,b);}
test('canonical groups retain writable station identity for hours without collapsing categories',()=>{
 const c={window:{PDC_WORKSHOP_DEPARTMENTS:require('./pdc-workshop-departments')},vehicleWorkshopStageCode:x=>x,vehicleWorkshopBookingsForStage:()=>[]};
 vm.createContext(pdcNotifyFixture(c));vm.runInContext(section('function vehicleWorkshopGroups(', 'function vehicleWorkshopJobCardValue('),c);
 const lines=[['FABRICATION','FABRICATION'],['BUS_4X4','BUS_ELECTRICAL'],['TYRE','TYRE']].map(([stage,cat],i)=>({category_rule:'craig_jobcard_categories_20261015',stage_code:stage,work_category:cat,line_identity:'source:'+i,source_line_id:String(i),estimated_hours:0,source_estimated_hours:0,source_kind:'authenticated',department:stage==='BUS_4X4'?'138':'139'}));
 const result=c.vehicleWorkshopGroups({}, {job_card_lines:lines,requirements:[],bookings:[],line_adjustments:[]}).flatMap(g=>g.lines);
 assert.deepEqual(Array.from(result,x=>x.work_key).sort(),['bus4x4','fabrication','tyre']);
 assert.ok(result.every(x=>x.sourceEstimatedHours===0&&x.estimatedHours===0));
});
test('Save all hours sends only explicitly changed rows, preserving other job cards and unmapped work',async()=>{
 const id='11111111-1111-4111-8111-111111111111',calls=[];
 const inputs=[{value:'1.5',dataset:{originalHours:'0',operationLineId:id,lineKey:'source:'+id,stage:'FABRICATION',workKey:'fabrication'}},
 {value:'4',dataset:{originalHours:'4',operationLineId:'22222222-2222-4222-8222-222222222222',lineKey:'source:22222222-2222-4222-8222-222222222222',stage:'REVIEW',workKey:'review'}}];
 const page={querySelectorAll:()=>inputs,querySelector:()=>null};
 const c={app:{vehicleWorkshopHoursBatchDrafts:new Map(),vehicleWorkshopDetailCache:new Map([['v',{detail:{vehicle_version:2}}]]),emailVehicleLocationService:{saveVehicleWorkshopLineHoursBatch:async r=>{calls.push(r);return{ok:true,data:{changed_count:1}}}}},
 selectedVehicle:()=>({}),vehicleWorkshopDetailCanonicalId:()=> 'v',displayStockNumber:()=> 'TEST',vehicleJobcardNumber:()=> 'TEST-JC',crypto:{randomUUID:()=> 'request'},loadVehicleWorkshopDetail:async()=>{},window:{alert:msg=>{throw Error(msg)}}};
 vm.createContext(pdcNotifyFixture(c));vm.runInContext(section('function vehicleWorkshopHoursBatchRowsFromPage(', 'function resetVehicleWorkshopLineHoursBatch('),c);
 assert.equal(await c.saveVehicleWorkshopLineHoursBatch({closest:()=>page,isConnected:false}),true);
 assert.equal(calls.length,1);assert.equal(calls[0].rows.length,1);assert.equal(calls[0].rows[0].workKey,'fabrication');assert.equal(calls[0].rows[0].estimatedHours,1.5);
});

