/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {resolveDealerScope} = require('./pdc-review-stations');
const {mapServerVehicle} = require('./pdc-email-vehicle-location-service');
const {createWorkshopDataService} = require('./workshop-data-service');
const fixtures = [
  {id:'393faf73-b1ca-40c1-a81a-7ea1df3925bc',stock_number:'1IXC427',key_number:'509'},
  {id:'af7a07ad-0bc5-4bc5-8f88-32f1ddaee414',stock_number:'U158851',key_number:'405'},
].map(row=>({...row,version:1,source_system:'tune_pmg',visible_on_board:true,
  department_codes:['138'],has_unknown_department:false}));
const mapped = fixtures.map(mapServerVehicle);

test('actual native mapper gives both reported non-Navision vehicles a PMG request scope',()=>{
  for(const vehicle of mapped) assert.equal(resolveDealerScope(vehicle,[]),'14450');
});

test('missing provenance, unknown/mixed/other departments, hidden and invalid identities stay unresolved',()=>{
  for(const change of [
    {source:'navision'}, {source:''}, {__emailVehicleServerAuthoritative:false},
    {pdcSheetVisible:false}, {pdcHasUnknownDepartment:true}, {pdcHasUnknownDepartment:undefined},
    {pdcDepartmentCodes:[]}, {pdcDepartmentCodes:['139']}, {pdcDepartmentCodes:['135']},
    {pdcDepartmentCodes:['138','139']}, {pdcDepartmentCodes:undefined},
    {__emailVehicleId:'not-a-uuid'}, {stock:''}, {dealer_code:'invalid'},
  ]) assert.equal(resolveDealerScope({...mapped[0],...change},[]),'',JSON.stringify(change));
});

test('exact Navision and bound dealer keep precedence, conflicting dealer evidence fails closed',()=>{
  const v=mapped[0], row={canonical_vehicle_id:v.__emailVehicleId,stock_number:v.stock,
    dealer_code:'37047',is_current:true,record_status:'current'};
  assert.equal(resolveDealerScope(v,[row]),'37047');
  assert.equal(resolveDealerScope(v,[],{canonicalId:v.__emailVehicleId,stockBaseline:v.stock,dealerCode:'37047'}),'37047');
  assert.equal(resolveDealerScope({...v,dealerCode:'14450'},[row]),'');
  assert.equal(resolveDealerScope(v,[{...row,stock_number:'OTHER'}]),'');
  assert.equal(resolveDealerScope(v,[row,{...row,dealer_code:'14450'}]),'');
});

test('planner and real data service send both exact UUIDs, and retain a server denial',async()=>{
  const calls=[];
  const service=createWorkshopDataService({config:{workshop:{sharedData:true}},
    getAccessToken:()=> 'synthetic-test-token',getRole:()=> 'operator',
    client:{rpc:async(auth,name,params)=>{calls.push({name,params});return {ok:true,body:{ok:true,
      results:params.p_vehicles.map((r,i)=>i===0?{...r,ok:true,bookings:[]}:{...r,ok:false,error:'dealer_scope_denied'})}};}}});
  const source=fs.readFileSync('workshop-planner.js','utf8');
  const start=source.indexOf('async function workshopLoadSearchBookings(');
  const tail=source.slice(start);const next=/\n(?:async )?function \w+\(/.exec(tail);
  const state={search:'405'};const snapshot={};
  service.getTrustedSnapshot=()=>snapshot;
  const context=vm.createContext({window:{__workshopDataService:service},
    workshopState:()=>state,workshopSharedModeActive:()=>true,cleanNavisionText:v=>v.trim(),
    workshopCurrentSearchLookup:()=>null,workshopLoadPlans:()=>[],
    workshopSearchMatchRows:()=>mapped.map(v=>({vehicleIdentity:`shared:${v.__emailVehicleId}`,vehicle:v})),
    vehicleWorkshopDetailRequestDealerCode:v=>resolveDealerScope(v,[]),
    workshopMapSearchBookings:r=>r.bookings});
  vm.runInContext(tail.slice(0,next.index),context);
  await context.workshopLoadSearchBookings('405');
  assert.equal(calls.length,1);
  assert.equal(calls[0].name,'get_workshop_booking_search_scoped');
  assert.deepEqual(calls[0].params.p_vehicles,fixtures.map(v=>({vehicle_id:v.id,dealer_code:'14450'})));
  const results=[...state.bookingSearchLookup.matches.values()];
  assert.equal(results[0].ok,true);
  assert.deepEqual(results[0].bookings,[]);
  assert.equal(results[1].ok,false);
  assert.equal(results[1].error,'dealer_scope_denied');
});
