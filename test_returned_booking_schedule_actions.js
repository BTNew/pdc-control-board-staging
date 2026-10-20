'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
function extract(name){const m=new RegExp('(?:async )?function '+name+'\\(').exec(source);assert.ok(m,name);const tail=source.slice(m.index);const next=/\n(?:async )?function \w+\(/.exec(tail);return next?tail.slice(0,next.index):tail;}
const plan={id:'retained-id',vehicleKey:'TEST',stage:'BUS_4X4',workCategory:'BUS_MECHANICAL',sharedStatus:'queued',bay:0,hours:88.3166666667};
const state={stage:'BUS_4X4',date:'2026-10-19',busBayGroup:'mechanical'};
const vehicle={vehicleKey:'TEST',sharedVehicleId:'v',__workshopOutstanding:{scheduleEnabled:false,disabledReason:'active_booking_exists'}};
let rows=[plan],trusted=true,submitted=null,slotArgs=null,submitHandler=null,dialogCount=0;
const elements={bay:{value:'1'},date:{value:'2026-10-19'},startMinutes:{value:'60'},hours:{value:'88.32'},assignee:{value:''}};
const form={elements,addEventListener:(event,fn)=>{if(event==='submit')submitHandler=fn;}};
const overlay={setAttribute(){},querySelector:s=>s==='[data-workshop-schedule-form]'?form:{addEventListener(){},focus(){}},querySelectorAll:()=>[],addEventListener(){},remove(){}};
const c={console,Date,WORKSHOP_STAGE_SEQUENCE:['BUS_4X4'],window:{alert(){},PDC_VEHICLE_HANDOVER:{read:async()=>({windows:[]})},__workshopDataService:{getTrustedSnapshot:()=>trusted?{}:null,setScope:async()=>{},loadSnapshot:async()=>{}}},
 document:{createElement:()=>{dialogCount++;return overlay;},querySelector:()=>null,body:{appendChild(){},classList:{add(){},remove(){}}}},
 workshopState:()=>state,workshopSelectedBusGroup:()=>({code:'BUS_MECHANICAL',bays:[1,2,3,4]}),workshopLoadPlans:()=>rows,
 workshopSharedModeActive:()=>true,workshopVehicle:()=>vehicle,workshopRequirePlannerStage:x=>x,normalizePmbStage:x=>x,workshopDepartmentLayout:()=>({category:()=>null}),
 workshopVehicleEtaConstraint:()=>({required:false,ok:true}),workshopSchedulableBayNumbers:()=>[1],workshopVisibleBays:()=>[1],workshopBayAllocatedHours:()=>plan.hours,
 workshopBookingDestinationHours:entry=>entry.hours,workshopDefaultBookingHours:()=>1,workshopExactDurationHours:Number,workshopClampDurationHours:Number,
 workshopDateFromKey:s=>new Date(s+'T00:00:00Z'),workshopDateKey:()=>state.date,workshopCoerceWorkDate:x=>x,workshopDateKeyNotBefore:x=>x,
 workshopFirstAvailableStartSlot:(...args)=>{assert.ok(!args[4].some(r=>r.id===plan.id));return {dateKey:state.date,startMinutes:60};},
 workshopStageBayCount:()=>1,workshopBayChoiceLabel:()=>'',workshopScheduleTimeOptions:()=>'',workshopAssigneeOptions:()=>'',escapeHtml:String,
 workshopBayMechanic:()=>'',pmbBayMechanic:()=>'',pmbStageLabel:x=>x,displayStockNumber:()=> 'TEST',vehicleCustomerName:()=> 'Synthetic',
 workshopIsWorkday:()=>true,scheduleWorkshopVehicle:async x=>{submitted=x;return true;},renderWorkshopPlanner(){},
 workshopSharedVehicleRef:()=>({vehicleId:'v'}),vehicleKey:()=> 'TEST',workshopNormalizeStartDate:x=>x,workshopCalendarDateKeyOffset:x=>x,
 workshopMinuteOffset:()=>60,workshopBestStageSlot:(...args)=>{slotArgs=args;return {bay:1,dateKey:state.date,startMinutes:60};},workshopSaveView(){}
};
const dialogRpcs=source.slice(source.indexOf('const WORKSHOP_SCHEDULE_DIALOG_RPCS'),source.indexOf('function workshopBindScheduleCommitClose'));
vm.createContext(c);vm.runInContext([dialogRpcs,...['workshopCategoryBays','workshopBindScheduleCommitClose','workshopReturnedQueuePlans','workshopReturnedPlanForAction','openWorkshopScheduleModal','workshopScheduleVehicleNextAvailable'].map(extract)].join('\n'),c);
(async()=>{
 c.openWorkshopScheduleModal('TEST','BUS_4X4',state.date,plan.id);
 assert.match(overlay.innerHTML,/value="88.32"/,'returned duration is presented without changing reservation');
 await submitHandler({preventDefault(){},currentTarget:form});
 assert.equal(submitted.planId,plan.id,'Schedule moves the existing booking');
 submitted=null;
 assert.equal(await c.workshopScheduleVehicleNextAvailable({vehicleKeyValue:'TEST',stage:'BUS_4X4',planId:plan.id}),true);
 assert.equal(submitted.planId,plan.id,'Best slot reuses the existing booking');
 assert.equal(submitted.hoursValue,plan.hours,'full retained estimate reaches the scheduling authority');
 assert.equal(slotArgs[9],plan,'capacity planner receives durable booking basis');
 assert.equal(slotArgs[3].length,0,'current reservation cannot conflict with itself');
 rows=[{...plan,workCategory:'BUS_ELECTRICAL'}];submitted=null;
 assert.equal(await c.workshopScheduleVehicleNextAvailable({vehicleKeyValue:'TEST',stage:'BUS_4X4',planId:plan.id}),false);
 assert.equal(submitted,null,'wrong-category reservation never schedules');
 trusted=false;c.openWorkshopScheduleModal('TEST','BUS_4X4',state.date,plan.id);
 assert.equal(dialogCount,1,'missing authoritative snapshot cannot reopen stale reservation');
 console.log('Returned Schedule and Best slot retain booking identity, hours and scope: PASS');
})().catch(e=>{console.error(e);process.exitCode=1;});
