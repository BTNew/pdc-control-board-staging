/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
const layout=require('./pdc-workshop-departments');
function fn(name){const start=source.indexOf('function '+name+'(');assert(start>=0);const tail=source.slice(start),end=/\n(?:async )?function \w+\(/.exec(tail);return end?tail.slice(0,end.index):tail;}
test('category survives canonical board projection and the Mechanical dialog excludes Electrical/QA',()=>{
 const state={stage:'BUS_4X4',busBayGroup:'',busShowAllBays:true,focusedBookingMode:true};
 const mapServerVehicle=require('./pdc-email-vehicle-location-service').mapServerVehicle;
 const board=mapServerVehicle({id:'vehicle',qc_operation_lines:[
  {source_line_id:'00000000-0000-4000-8000-000000000001',line_identity:'source:00000000-0000-4000-8000-000000000001',active:true,operation_no:'OP1',description:'Conversion',stage_code:'BUS_4X4',work_category:'BUS_MECHANICAL',estimated_hours:60},
  {source_line_id:'00000000-0000-4000-8000-000000000002',line_identity:'source:00000000-0000-4000-8000-000000000002',active:true,operation_no:'OP2',description:'Light bar',stage_code:'BUS_4X4',work_category:'BUS_ELECTRICAL',estimated_hours:2.2},
  {source_line_id:'00000000-0000-4000-8000-000000000003',line_identity:'source:00000000-0000-4000-8000-000000000003',active:true,operation_no:'OP3',description:'Fuel',stage_code:'BUS_4X4',work_category:'BUS_QA',estimated_hours:.15}]});

 const c={app:{currentRequestedView:'planner-bus-mechanical'},window:{PDC_WORKSHOP_DEPARTMENTS:layout},
  workshopState:()=>state,workshopSharedModeActive:()=>true,pdcSheetVehicles:()=>[board],cleanNavisionText:x=>String(x||''),
  normalizePmbStage:x=>x,vehicleWorkshopStageCode:x=>x,WORKSHOP_STAGE_SEQUENCE:['BUS_4X4','TINT'],
  vehicleJobcardNumber:()=>'',vehiclePdcJobLines:()=>[],workshopExactDurationHours:x=>Number(x),
  workshopStageBayCount:()=>10};
 vm.createContext(c);vm.runInContext(['workshopDepartmentLayout','workshopSelectedBusGroup','workshopVisibleBays','workshopImportedJobLines','workshopResolvedJobLines','workshopStageJobLines'].map(fn).join('\n'),c);
 const vehicle={id:'vehicle'};
 assert.deepEqual(Array.from(c.workshopStageJobLines(vehicle,'BUS_4X4'),l=>l.text),['Conversion']);
 assert.deepEqual(Array.from(c.workshopVisibleBays('BUS_4X4')),[1,2,3,4],'route wins over stale all-bays/focused flags');
 c.app.currentRequestedView='planner-bus-electrical';
 assert.deepEqual(Array.from(c.workshopVisibleBays('BUS_4X4')),[8,9]);
 assert.deepEqual(Array.from(c.workshopStageJobLines(vehicle,'BUS_4X4'),l=>l.hours),[2.2]);
 assert.equal(c.workshopStageJobLines(vehicle,'BUS_4X4','BUS_QA')[0].hours,.15,'explicit booking category owns dialog');
 c.app.currentRequestedView='workflow';
 assert.equal(c.workshopVisibleBays('BUS_4X4').length,10,'Control Board retains all physical bays');
 assert.equal(c.workshopStageJobLines(vehicle,'BUS_4X4','').length,3,'explicit whole-job history remains inspectable');
});
test('known database station rejection is explained without leaking arbitrary database text',async()=>{
 const s=fs.readFileSync('pdc-new-vehicles.js','utf8');
 let response={code:'23514',message:'department_138_requires_correct_station'};
 const c={URL,AbortController,setTimeout,clearTimeout,sessionGeneration:0,PROJECT:'cdsmnqxtyyoeoznmbidd',
  window:{PDC_SUPABASE_CONFIG:{url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'fixture'},PDC_AUTH_CONTEXT:{userId:'fixture',role:'administrator'}},
  getPdcSupabaseAccessToken:()=> 'fixture',readable:()=>true,fetch:async()=>({ok:false,json:async()=>response})};
 vm.createContext(c);vm.runInContext(s.slice(s.indexOf('  async function rpc(name,payload)'),s.indexOf('  async function load({')),c);
 await assert.rejects(c.rpc('approve_pdc_new_vehicle_review',{}),e=>/selected station conflicts/.test(c.message(e)));
 response={code:'23514',message:'private arbitrary SQL contents'};
 await assert.rejects(c.rpc('approve_pdc_new_vehicle_review',{}),e=>!c.message(e).includes('private arbitrary'));
});
test('Schedule offers the selected category bays, and both planner loaders are cache busted',()=>{
 const modal=source.slice(source.indexOf('function openWorkshopScheduleModal'),source.indexOf('\nasync function ',source.indexOf('function openWorkshopScheduleModal')));
 assert.match(modal,/const categoryBays = workshopCategoryBays\(normalizedStage, scheduleCategory\)/);assert.match(modal,/categoryBays\.map/);
 assert.doesNotMatch(modal,/Choose any suitable Bus4x4 bay/);
 const app=fs.readFileSync('app.js','utf8');
 assert.equal((app.match(/workshop-planner\.js\?station-scope=2026\.10\.19\.03/g)||[]).length,2);
 const mapper=fs.readFileSync('pdc-email-vehicle-location-service.js','utf8');
 assert.match(mapper,/workCategory: String\(item\?\.work_category/);
});

