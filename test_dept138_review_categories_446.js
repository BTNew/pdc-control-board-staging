/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r446 (F59): Dept 138 New Vehicles review uses the Bus 4x4 stations (Bhavesh 21 Oct 17:53 AWST; Craig approved 18:12 AWST).
// Regression for the root cause: Dept 138 lines were forced to Bus 4x4 with a disabled dropdown and the PD station strip.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const api=require('./pdc-new-vehicles.js');
const source=fs.readFileSync('pdc-new-vehicles.js','utf8');
const op=(id,department,extra={})=>({line_identity:id,source_line_id:'s-'+id,department,description:'Line '+id,stage_code:department==='138'?'BUS_4X4':'FITTING',estimated_hours:1,active:true,completed:false,source_kind:'authenticated',...extra});
const card=ops=>({vehicle_id:'v1',status:'pending',snapshot_hash:'h',operations:ops});

test('Dept 138 card strip is Needs Review + the 8 Bus 4x4 stations in Bhavesh\'s order, with no PD stations or Bus 4x4 bucket',()=>{
  const groups=api.stationGroups(card([op('a','138',{work_category:'BUS_QA'})]));
  assert.deepEqual(groups.map(g=>g.label),['Needs Review','Mechanical','Accessories','Electrical','QA','Tint','Tyre','Sublet','Pit – external']);
  assert.deepEqual(groups.map(g=>g.code),['','BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','TINT','TYRE','SUBLET','BUS_PIT']);
  assert.equal(groups.find(g=>g.code==='BUS_QA').lines.length,1);
});

test('Dept 139 card is unchanged',()=>{
  assert.deepEqual(api.STATIONS.map(([code])=>code),['FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','BUS_4X4','SUBLET']);
  const groups=api.stationGroups(card([op('a','139')]));
  assert.deepEqual(groups.map(g=>g.code),['','FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','BUS_4X4','SUBLET']);
  assert.deepEqual(api.assignmentsFor(card([op('a','139')]),{},{}),[{line_identity:'a',stage_code:'FITTING',estimated_hours:1}]);
});

test('mixed card shows both sets; each line accepts only its own department\'s stations',()=>{
  const row=card([op('a','138',{work_category:'BUS_ELECTRICAL'}),op('b','139',{stage_code:'ELECTRICAL'})]);
  const groups=api.stationGroups(row);
  assert.deepEqual(groups.map(g=>g.code),['','BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','FITTING','ELECTRICAL','FABRICATION','HOIST','BUS_4X4','TINT','TYRE','SUBLET','BUS_PIT']);
  assert.equal(groups.find(g=>g.code==='BUS_ELECTRICAL').label,'Electrical · 138');
  assert.equal(groups.find(g=>g.code==='ELECTRICAL').label,'Electrical · 139');
  assert.equal(groups.find(g=>g.code==='TINT').label,'Tint');
  assert.equal(api.validChoice(row.operations[0],'FITTING'),false);
  assert.equal(api.validChoice(row.operations[1],'BUS_QA'),false);
  assert.equal(api.validChoice(row.operations[0],'TINT'),true);
  assert.equal(api.validChoice(row.operations[1],'TINT'),true);
  assert.deepEqual(api.problems(row,{a:'FITTING'}),['Choose a station for every operation.']);
  assert.deepEqual(api.assignmentsFor(row,{a:'BUS_PIT',b:'HOIST'},{}),[
    {line_identity:'a',stage_code:'BUS_4X4',work_category:'BUS_PIT',estimated_hours:1},{line_identity:'b',stage_code:'HOIST',estimated_hours:1}]);
});

test('unallocated or missing Dept 138 category starts in Needs Review and blocks quick approval',()=>{
  for(const work_category of ['UNALLOCATED_MAPPING_REVIEW',undefined,'FITTING','']) {
    const row=card([op('a','138',{work_category,stage_code:'UNALLOCATED_MAPPING_REVIEW'})]);
    assert.equal(api.stationGroups(row)[0].lines.length,1,String(work_category));
    assert.ok(api.problems(row).includes('Choose a station for every operation.'));
    assert.ok(api.quickApprovalProblems({...row,vehicle_id:'v1',snapshot_hash:'h'}).length);
  }
  const ready=card([op('a','138',{work_category:'BUS_MECHANICAL'})]);
  assert.deepEqual(api.quickApprovalProblems(ready),[]);
});

test('approval goes through the r446 RPC from review, quick approve and bulk approve',()=>{
  assert.equal(api.APPROVE_RPC,'approve_pdc_new_vehicle_review_446');
  assert.equal((source.match(/rpc\(APPROVE_RPC,/g)||[]).length,2);
  assert.doesNotMatch(source,/rpc\('approve_pdc_new_vehicle_review'/);
});

test('review tile and handlers no longer lock Dept 138 lines',()=>{
  const body=source.slice(source.indexOf('  function operation(line)'),source.indexOf('  async function approve()'));
  assert.doesNotMatch(body,/Tint and Tyres use shared bays/);
  assert.doesNotMatch(body,/department138\(selected\.operations/);
  assert.match(body,/validChoice\(line,code\)/);
  const context={...api,choices:{},hourDrafts:{},saving:false,sourceChanged:false,writable:()=>true};
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('  function operation(line)'),source.indexOf('  function stationSection(group)')),context);
  const html=context.operation(op('a','138',{work_category:'BUS_ACCESSORIES'}));
  assert.match(html,/draggable="true"/);
  assert.match(html,/<option value="BUS_ACCESSORIES" selected>Accessories/);
  assert.match(html,/--station-colour:#7c3aed/);
});

test('verifyApproval checks the Dept 138 category, not the server-owned stage, and keeps hours for a Sublet choice',()=>{
  const row=card([op('a','138',{work_category:'BUS_MECHANICAL',estimated_hours:2})]);
  const receipt=(extra)=>({ok:true,data:{vehicle_id:'v1',visible_on_board:true,bookings_created:0,operations:[{...row.operations[0],...extra}]}});
  assert.equal(api.verifyApproval(receipt({stage_code:'TYRE',work_category:'TYRE'}),row,{a:'TYRE'}),true);
  assert.equal(api.verifyApproval(receipt({stage_code:'PIT_INSPECTION',work_category:'BUS_PIT'}),row,{a:'BUS_PIT'}),true);
  assert.equal(api.verifyApproval(receipt({stage_code:'SUBLET',work_category:'SUBLET'}),row,{a:'SUBLET'}),true);
  assert.equal(api.verifyApproval(receipt({stage_code:'BUS_4X4',work_category:'BUS_MECHANICAL'}),row,{a:'BUS_QA'}),false);
  assert.equal(api.verifyApproval(receipt({stage_code:'BUS_4X4',work_category:'BUS_QA',estimated_hours:3}),row,{a:'BUS_QA'}),false);
});

test('new server codes have messages and validation failures let bulk continue',()=>{
  const msg=source.slice(source.indexOf('  function message(err)'),source.indexOf('  async function load('));
  for(const code of ['dept138_category_required','dept138_station_needs_review','dept138_sublet_needs_hours','category_readback_mismatch']) assert.match(msg,new RegExp(code));
  const bulk=source.slice(source.indexOf('async function approveReadyQueue'),source.indexOf('function bulkProgressText'));
  for(const code of ['dept138_category_required','category_only_for_dept138','dept138_station_needs_review','dept138_sublet_needs_hours']) assert.match(bulk,new RegExp(code));
});

test('Operation Updates for Dept 138 are unchanged (still routed by the server)',()=>{
  const row={change_id:'c1',status:'pending',already_on_board:true,effective_hours:1,proposed:{department:'138',description:'Accessory'},current_work:{stage_code:'BUS_4X4',completed:false}};
  assert.equal(api.updateStation(row,{stage:'FITTING'}),'BUS_4X4');
  assert.match(api.operationUpdateHtml(row,{}),/data-update-stage disabled/);
});

test('migration, undo and check ship together',()=>{
  const migration=fs.readdirSync('supabase/migrations').find(name=>/_r446_dept138_review_categories\.sql$/.test(name));
  assert.ok(migration,'migration present');
  const sql=fs.readFileSync('supabase/migrations/'+migration,'utf8');
  assert.match(sql,/CREATE FUNCTION public\.approve_pdc_new_vehicle_review_446/);
  assert.match(sql,/'dept138_review_categories_446','F59'/);
  assert.match(sql,/,true,245,'r446'\)/);
  assert.doesNotMatch(sql,/CREATE OR REPLACE FUNCTION public\.approve_pdc_new_vehicle_review\(/);
  assert.doesNotMatch(sql,/workshop_clock_tick\(boolean,timestamptz\)'::regprocedure\)<>'(?!84af7607bfd0ce9907c89bae8644d5b6)/);
  assert.ok(fs.existsSync('supabase/rollbacks/'+migration.replace('.sql','.down.sql')),'undo present');
  assert.ok(fs.existsSync('tests/dept138_review_categories_446.sql'));
});
