/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
function extract(name){const m=new RegExp('(?:async )?function '+name+'\\(').exec(source);const tail=source.slice(m.index);const next=/\n(?:async )?function \w+\(/.exec(tail);return next?tail.slice(0,next.index):tail;}
const layout=require('./pdc-workshop-departments.js');
const state={stage:'BUS_4X4',busBayGroup:'accessory'};
const vehicle={id:'v',sharedVehicleId:'v',vehicleKey:'TEST',stockNumber:'TEST'};
const snapshot={vehicles:[vehicle],outstanding_candidates:[{vehicle_id:'v',stage_code:'BUS_4X4',schedule_enabled:true,work_categories:[{work_category:'BUS_ELECTRICAL',schedule_enabled:true,estimated_hours:2}]}]};
const c={app:{data:[vehicle]},window:{__workshopDataService:{getTrustedSnapshot:()=>snapshot},PDC_WORKSHOP_DEPARTMENTS:layout},
 workshopState:()=>state,cleanNavisionText:String,workshopSnapshotVehicleToPlannerRow:x=>x,workshopVehicleSearchText:()=> 'test jc-test',
 workshopSharedModeActive:()=>true,workshopSharedVehicleRef:()=>({vehicleId:'v'}),vehicleKey:()=> 'TEST',normalizePmbStage:x=>x,
 workshopSortBookingsClosest:x=>x,workshopPlanVehicleIdentity:()=> 'shared:v',workshopSearchRank:()=>0,statusCategory:()=> 'pmb',displayStockNumber:()=> 'TEST'};
vm.createContext(c);vm.runInContext(['workshopDepartmentLayout','workshopCategoryAuthority','workshopSelectedBusGroup','workshopReturnedQueuePlans','workshopSearchMatchRows'].map(extract).join('\n'),c);
const row=(id,stage,bay,workCategory)=>({id,stage,bay,workCategory,status:'planned'});
const rows=[row('tint','TINT',1),row('tyre','TYRE',1),row('mechanical','BUS_4X4',1,'BUS_MECHANICAL'),row('electrical','BUS_4X4',8,'BUS_ELECTRICAL'),row('accessories','BUS_4X4',10,'BUS_ACCESSORIES'),row('legacy-mech','BUS_4X4',1)];
assert.deepEqual(Array.from(c.workshopSearchMatchRows('JC-TEST',rows)[0].bookings,b=>b.id),['accessories']);
assert.equal(c.workshopSearchMatchRows('TEST',[]).length,0,'Electrical-only work does not become an Accessories candidate');
state.busBayGroup='electrical';
assert.equal(c.workshopSearchMatchRows('TEST',[])[0].candidateAvailable,true,'matching category can be selected');
assert.deepEqual(Array.from(c.workshopSearchMatchRows('TEST',rows)[0].bookings,b=>b.id),['electrical']);
state.busBayGroup='mechanical';
assert.deepEqual(Array.from(c.workshopSearchMatchRows('TEST',rows)[0].bookings,b=>b.id),['mechanical','legacy-mech'],'legacy whole-job booking follows its physical bay when no category was recorded');
state.stage='TINT';
assert.deepEqual(Array.from(c.workshopSearchMatchRows('TEST',rows)[0].bookings,b=>b.id),['tint']);
state.stage='TYRE';
assert.deepEqual(Array.from(c.workshopSearchMatchRows('TEST',rows)[0].bookings,b=>b.id),['tyre']);
console.log('Planner search isolates current station, category, legacy bay and outstanding work: PASS');
