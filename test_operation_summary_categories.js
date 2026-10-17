'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
function fixture(lines) {
  const state = { vehicleWorkshopDetailCache: new Map([['synthetic', {status:'ready', detail:{vehicle_version:2, job_card_lines:lines}}]]) };
  const context = vm.createContext({app:state, cleanNavisionText:x=>String(x??'').trim(),
    vehicleWorkshopDetailCanonicalId:()=> 'synthetic', vehicleKey:()=> 'synthetic',
    escapeHtml:x=>String(x??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;'),
    vehicleWorkshopLineIdentity:(_s,l)=>`source:${l.operation_line_id}`, vehicleWorkshopStageCode:s=>String(s).toUpperCase()});
  vm.runInContext(source.slice(source.indexOf('function authenticatedOperationLineValid('), source.indexOf('function refreshAuthenticatedOperationSummaryRow(')), context);
  return {context,state};
}
function line(n, category, hours, stage='BUS_4X4', extra={}) {
  return {line_identity:`source:synthetic-${n}`, source_line_id:`synthetic-${n}`, operation_no:`OP${n}`,
    description:`Synthetic work ${n}`, source_kind:'authenticated', department:'138', active:true,
    work_category:category, stage_code:stage, estimated_hours:hours, ...extra};
}
test('expanded locations card separates authoritative Bus categories with exact hours and identity',()=>{
  const lines=[line(1,'BUS_MECHANICAL',60),line(2,'BUS_ELECTRICAL',1),line(3,'BUS_ELECTRICAL',3),
    line(4,'BUS_ACCESSORIES',0.01),line(5,'BUS_QA',0),line(6,'BUS_PIT',null,'PIT_INSPECTION'),
    line(7,'TINT',1,'TINT'),line(8,'TYRE',2,'TYRE'),line(9,'SUBLET',0.01,'SUBLET'),
    line(10,'UNALLOCATED_MAPPING_REVIEW',null,'REVIEW'),line(11,'ELECTRICAL',2,'ELECTRICAL',{department:'139'}),
    line(12,'BUS_MECHANICAL',99,'BUS_4X4',{active:false})];
  const {context}=fixture(lines);
  const vehicle={pdcEmailOperationLines:[{operation_no:'OP90',description:'Obsolete import',work_key:'bus4x4',estimatedHours:999}]};
  const html=context.authenticatedEmailOperationLinesHtml(vehicle);
  for(const key of ['bus_mechanical','bus_electrical','bus_accessories','bus_qa','bus_pit','tint','tyre','sublet','review','electrical']) {
    assert.equal((html.match(new RegExp(`data-operation-category="${key}"`,'g'))||[]).length,1,key);
  }
  assert.match(html,/Bus 4×4 · Electrical<\/strong><small>2 jobs · 4\.00 h/);
  assert.match(html,/Bus 4×4 · QA<\/strong><small>1 job · 0\.00 h/);
  assert.match(html,/Pit \(external\)<\/strong><small>1 job · Unknown hours/);
  assert.doesNotMatch(html,/Obsolete import|Synthetic work 12|data-operation-category="bus4x4"/);
  const projected=context.authenticatedOperationSummaryLines(vehicle);
  assert.equal(projected[1].work_key,'bus4x4','display categories must not change planner physical station keys');
  assert.equal(projected[1].summaryStationKey,'bus_electrical');
  assert.equal(projected[1].workshopLineKey,'source:synthetic-2');
  assert.equal(projected.reduce((sum,l)=>sum+Math.round((l.estimatedHours||0)*100),0),6902);
});
test('authoritative empty list cannot resurrect stale imported lines; manual work is retained',()=>{
  const {context,state}=fixture([]);
  const vehicle={pdcEmailOperationLines:[{operation_no:'OP1',description:'Removed',work_key:'bus4x4'}]};
  assert.equal(context.authenticatedEmailOperationLinesHtml(vehicle),'');
  state.vehicleWorkshopDetailCache.get('synthetic').detail.job_card_lines=[line(1,'BUS_ELECTRICAL',2,'BUS_4X4',{source_kind:'manual',operation_no:null,description:'Manual <repair>'})];
  assert.match(context.authenticatedEmailOperationLinesHtml(vehicle),/Manual &lt;repair>/);
});
test('legacy adjustment fallback keeps Bus physical station without inventing Mechanical category',()=>{
  const {context,state}=fixture(undefined);
  state.vehicleWorkshopDetailCache.get('synthetic').detail.line_adjustments=[{source_kind:'source',line_key:'source:legacy',stage_code:'BUS_4X4',estimated_hours:4}];
  const html=context.authenticatedEmailOperationLinesHtml({pdcEmailOperationLines:[{operation_line_id:'legacy',operation_no:'OP1',description:'Legacy',work_key:'bus4x4',estimatedHours:2}]});
  assert.match(html,/data-operation-category="bus4x4"/);
  assert.match(html,/1 job · 4\.00 h/);
  assert.doesNotMatch(html,/data-operation-category="bus_mechanical"/);
});
test('a newly accepted operation invalidates the older expanded-card cache without another approval',async()=>{
  const {context,state}=fixture([line(1,'BUS_MECHANICAL',60)]);
  let requests=0, paints=0;
  const vehicle={__emailVehicleVersion:3};
  Object.assign(context, { selectedVehicle:()=>vehicle, refreshAuthenticatedOperationSummaryRow:()=>{paints++;return true;},
    getPdcSupabaseAccessToken:()=> 'synthetic-token', window:{PDC_SUPABASE_CONFIG:{url:'https://synthetic.invalid',publishableKey:'synthetic'}},
    vehicleWorkshopDetailRequestDealerCode:()=> 'synthetic-dealer', vehicleWorkshopDetailResponse:detail=>({ok:true,detail}),
    fetch:async()=>{requests++;return {ok:true,json:async()=>({vehicle_version:3,job_card_lines:[line(1,'BUS_MECHANICAL',60),line(2,'BUS_ELECTRICAL',3)]})};} });
  vm.runInContext(source.slice(source.indexOf('async function loadAuthenticatedOperationSummary('), source.indexOf('function bindAuthenticatedOperationSummaries(')), context);
  const row={dataset:{incomingRow:'synthetic'},querySelector:()=>null};
  await context.loadAuthenticatedOperationSummary(row);
  assert.equal(requests,1);
  assert.equal(paints,1);
  assert.match(context.authenticatedEmailOperationLinesHtml(vehicle),/Bus 4×4 · Electrical/);
  await context.loadAuthenticatedOperationSummary(row);
  assert.equal(requests,1,'unchanged version reuses detail without slowing bay navigation');
  assert.equal(state.vehicleWorkshopDetailCache.get('synthetic').detail.vehicle_version,3);
});
