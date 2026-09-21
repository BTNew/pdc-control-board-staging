'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
global.parseIsoTimestamp=value=>{if(!value)return null;const d=new Date(value);return Number.isNaN(d.getTime())?null:d;};
global.cleanNavisionText=value=>String(value??'').trim();
const planner=require('./workshop-planner.js');
const config=planner.WORKSHOP_CONFIG;
Object.assign(config,{dayStartMinutes:360,dayEndMinutes:990,dayLengthMinutes:630,workingDayIndexes:[1,2,3,4,5,6],closureDateKeys:['2026-09-23'],breakWindowsByDateOrScope:[{startMinutes:720,endMinutes:750,dateKey:'',scope:'global'}],overtimeWindowsByDateOrScope:[{startMinutes:990,endMinutes:1080,dateKey:'',scope:'global',overtime:true}]});
const at=(day,hour,minute=0)=>new Date(2026,8,day,hour,minute);
const context=bay=>({stage:'BUS_4X4',bay,calendarVehicle:{bus_workflow_department138:true}});
test('verified 138 preview uses bay8/9 06–14 and other Bus bays06–15 with existing breaks',()=>{
  assert.deepEqual(planner.workshopAvailabilityWindowsForDate(at(21,6),context(8)).map(w=>[w.startMinutes,w.endMinutes]),[[360,720],[750,840]]);
  assert.deepEqual(planner.workshopAvailabilityWindowsForDate(at(21,6),context(3)).map(w=>[w.startMinutes,w.endMinutes]),[[360,720],[750,900]]);
  assert.equal(planner.workshopNewBookingValidation({...context(8),startAt:at(21,6).toISOString(),hours:8,status:'planned'}).ok,true);
  assert.equal(planner.workshopNewBookingValidation({...context(8),startAt:at(21,14).toISOString(),hours:1,status:'planned'}).error,'outside_work_window');
});
test('long electrical previews and preflight retain Friday/weekend/closure limits',()=>{
  const end=planner.workshopAddWorkMinutes(at(21,6),16*60,context(8));
  assert.equal(end.getDate(),24);assert.equal(end.getHours(),7);assert.equal(end.getMinutes(),0);
  assert.deepEqual(planner.workshopAvailabilityWindowsForDate(at(26,6),context(3)),[]);
  assert.deepEqual(planner.workshopAvailabilityWindowsForDate(at(23,6),context(3)),[]);
  assert.equal(planner.workshopNewBookingValidation({...context(3),startAt:at(26,6).toISOString(),hours:1}).error,'non_working_day');
});
test('Dept139, unknown memberships and nonBus stations retain shared hours and overtime',()=>{
  for(const c of [{stage:'BUS_4X4',bay:8,calendarVehicle:{bus_workflow_department138:false,department_codes:['139']}},{stage:'BUS_4X4',bay:8,calendarVehicle:{}},{stage:'FITTING',bay:8,calendarVehicle:{bus_workflow_department138:true}}]){
    assert.equal(planner.workshopBusShift(c),null);
    assert(planner.workshopAvailabilityWindowsForDate(at(26,6),c).some(w=>w.endMinutes===1080));
    assert.equal(planner.workshopNewBookingValidation({...c,startAt:at(21,15).toISOString(),hours:1}).ok,true);
  }
  assert.equal(config.dayEndMinutes,990,'No global planner configuration mutation');
});
test('new preview ends follow scoped bay, existing canonical ends remain unchanged',()=>{
  const c={...context(8),startAt:at(21,6).toISOString(),hours:8};
  assert.equal(planner.workshopEntryEnd(c).getDate(),22);assert.equal(planner.workshopEntryEnd(c).getHours(),6);assert.equal(planner.workshopEntryEnd(c).getMinutes(),30);
  const legacy={...c,endAt:at(21,16).toISOString()};assert.equal(planner.workshopEntryEnd(legacy).toISOString(),legacy.endAt);
});
