/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const layout = require('./pdc-workshop-departments.js');
const app = fs.readFileSync(__dirname+'/app.js','utf8');
function appFunction(name, context) {
  const start = app.indexOf('function '+name+'(');
  assert.ok(start>=0);
  const rest=app.slice(start), end=/\n(?:async )?function /.exec(rest.slice(1));
  vm.createContext(context); vm.runInContext(rest.slice(0,end.index+1),context);
  return context[name];
}
test('department categories retain separate shared bay destinations and an external Pit',()=>{
  assert.deepEqual(layout.categoryChoices('138'),['BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET']);
  assert.deepEqual(layout.PD,['HOIST','FABRICATION','FITTING','ELECTRICAL']);
  assert.equal(layout.categoryStage('BUS_PIT'),'PIT_INSPECTION');
  assert.equal(layout.category('BUS_PIT').external,true);
  assert.deepEqual(layout.category('BUS_PIT').bays,[]);
  assert.equal(layout.category('progression'),null,'Progression is a physical override bay, not imported work');
  assert.deepEqual(layout.group('progression').bays,[5,6]);
});
test('one category uses its own hours and booking state',()=>{
  const row={estimated_hours:62,existing_booking:true,schedule_enabled:false,disabled_reason:'active_booking_exists',work_categories:[
    {work_category:'BUS_MECHANICAL',estimated_hours:60,existing_booking:true,schedule_enabled:true,completed:false},
    {work_category:'BUS_ELECTRICAL',estimated_hours:2,existing_booking:false,schedule_enabled:true,completed:false},
  ]};
  const selected=layout.selectedCategory(row,'BUS_ELECTRICAL');
  assert.equal(selected.estimated_hours,2); assert.equal(selected.existing_booking,false); assert.equal(selected.schedule_enabled,true);
  assert.equal(row.estimated_hours,62,'Does not mutate the station response');
  assert.equal(layout.selectedCategory({...row,disabled_reason:'vehicle_blocked'},'BUS_ELECTRICAL').schedule_enabled,false,'Category selection cannot clear another station guard');
  const absent=layout.selectedCategory(row,'BUS_QA');
  assert.equal(absent.schedule_enabled,false); assert.equal(absent.estimated_hours,null); assert.equal(absent.completed,true);
});
test('completed and unknown-hour categories cannot offer a new booking',()=>{
  const row={work_categories:[{work_category:'BUS_QA',estimated_hours:1,completed:true,schedule_enabled:true},
    {work_category:'BUS_ELECTRICAL',estimated_hours:null,completed:false,schedule_enabled:false}]};
  assert.equal(layout.selectedCategory(row,'BUS_QA').schedule_enabled,false);
  assert.equal(layout.selectedCategory(row,'BUS_ELECTRICAL').schedule_enabled,false);
});
test('job-card groups display exact category lines and their own bookings',()=>{
  const legacy={booking_id:'whole'},m={booking_id:'m',work_category:'BUS_MECHANICAL'},e={booking_id:'e',work_category:'BUS_ELECTRICAL'};
  const groups=layout.splitGroups([{stage:'BUS_4X4',requirements:[],lines:[
    {line_identity:'conversion',work_category:'BUS_MECHANICAL',estimated_hours:60},
    {line_identity:'lights',work_category:'BUS_ELECTRICAL',estimated_hours:2}],bookings:[legacy,m,e]}]);
  assert.deepEqual(groups.map(x=>x.category),['BUS_MECHANICAL','BUS_ELECTRICAL']);
  assert.deepEqual(groups[0].bookings,[legacy,m]); assert.deepEqual(groups[1].bookings,[legacy,e]);
  assert.equal(groups[1].lines[0].estimated_hours,2);
});
test('canonical job-card display preserves a 1.5-hour estimate and explicit zero',()=>{
  const project=appFunction('vehicleWorkshopHoursProjection',{window:{WorkshopNavigation:{projectWorkshopHours:()=>{throw Error('Stale browser rules must not replace canonical hours');}}}});
  assert.equal(project({authoritativeJobCardLine:true,estimated_hours:1.5,sourceEstimatedHours:1}).schedulingHours,1.5);
  assert.equal(project({authoritativeJobCardLine:true,estimated_hours:0}).schedulingHours,0);
  assert.equal(project({authoritativeJobCardLine:true,estimated_hours:null}).schedulingHours,null);
});
test('conversion tyres keep their source scope while ordinary tyres are shared',()=>{
  assert.equal(layout.sharedStation('6 x Super Single Tyres & Rims - Coaster'),'BUS_4X4');
  assert.equal(layout.sharedStation('New tyres and wheel alignment'),'TYRE');
  assert.equal(layout.sharedStation('Darkest Legal Tint Commuter van'),'TINT');
});
