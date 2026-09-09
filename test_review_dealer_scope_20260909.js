'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {resolveDealerScope} = require('./pdc-review-stations');
const {mapServerVehicle} = require('./pdc-email-vehicle-location-service');
const appSource = fs.readFileSync('app.js','utf8');
const id='00000000-0000-4000-8000-000000000100';
const raw={id,permanent_vehicle_id:'REGRESSION-ONLY',stock_number:'REVIEW-TEST',version:22,current_location:'PMB',visible_on_board:true};
const vehicle=mapServerVehicle(raw);
const shared={canonical_vehicle_id:id,stock_number:raw.stock_number,dealer_code:'37047',is_current:true,record_status:'current'};
function sourceFunction(name) {
 const start=appSource.indexOf(`function ${name}(`);assert.ok(start>=0,name);
 const end=appSource.slice(start+1).search(/\n(?:async )?function /);assert.ok(end>0,name);
 return appSource.slice(start,start+1+end);
}
test('reproduce default-dealer defect with the actual raw snapshot mapper and old request helper',()=>{
 const c=vm.createContext({cleanNavisionText:x=>String(x??'').trim()});
 vm.runInContext(sourceFunction('vehicleWorkshopDetailRequestDealerCode'),c);
 assert.equal(vehicle.__sharedNavisionDealerCode,undefined);
 assert.equal(c.vehicleWorkshopDetailRequestDealerCode(vehicle,{dealerCode:'14450'}),'14450');
 assert.equal(resolveDealerScope(vehicle,[shared]),'37047');
});
test('each dealership resolves from its exact authenticated UUID and Stock',()=>{
 for(const dealer_code of ['14450','37047'])assert.equal(resolveDealerScope(vehicle,[{...shared,dealer_code}]),dealer_code);
});
test('same Stock belonging to a different UUID never provides dealer authority',()=>{
 assert.equal(resolveDealerScope(vehicle,[{...shared,canonical_vehicle_id:'00000000-0000-4000-8000-000000000999'}]),'');
});
test('missing or retired scope never falls back to the site default',()=>{
 assert.equal(resolveDealerScope(vehicle,[]),'');
 assert.equal(resolveDealerScope(vehicle,[{...shared,is_current:false}]),'');
 assert.equal(resolveDealerScope(vehicle,[{...shared,record_status:'completed'}]),'');
});
test('wrong Stock, invalid dealer and conflicting dealer assignments fail closed',()=>{
 assert.equal(resolveDealerScope(vehicle,[{...shared,stock_number:'WRONG'}]),'');
 assert.equal(resolveDealerScope(vehicle,[{...shared,dealer_code:'99999'}]),'');
 assert.equal(resolveDealerScope(vehicle,[shared,{...shared,dealer_code:'14450'}]),'');
 assert.equal(resolveDealerScope({...vehicle,dealerCode:'14450'},[shared]),'');
});
test('an exact open-modal identity supplies scope without borrowing another vehicle context',()=>{
 const bound={canonicalId:id,stockBaseline:raw.stock_number,dealerCode:'37047'};
 assert.equal(resolveDealerScope(vehicle,[],bound),'37047');
 assert.equal(resolveDealerScope(vehicle,[],{...bound,stockBaseline:'WRONG'}),'');
 assert.equal(resolveDealerScope(vehicle,[],{...bound,canonicalId:'WRONG'}),'');
});
test('explicit current-vehicle dealer remains supported and must agree with the shared projection',()=>{
 assert.equal(resolveDealerScope({...vehicle,dealerCode:'37047'},[]),'37047');
 assert.equal(resolveDealerScope({...vehicle,dealerCode:'37047',dealer_code:'14450'},[]),'');
});
test('actual asynchronous Workshop-detail loader submits the correct scoped request',async()=>{
 const requests=[];
 const detail={vehicle_id:id,vehicle_version:22,requirements:[],bookings:[],line_adjustments:[]};
 const state={sharedNavisionVisibleRows:[shared],vehicleWorkshopDetailCache:new Map(),vehicleWorkshopDetailRequestGeneration:0,vehicleDetailPage:'details',vehicleModalIdentity:null};
 const c=vm.createContext({console,Map,Number,String,Array,Date,Promise,
  app:state,window:{PDC_SUPABASE_CONFIG:{url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'synthetic-public-key',dealerCode:'14450'}},
  cleanNavisionText:x=>String(x??'').trim(),displayStockNumber:x=>x.stock,vehicleKey:x=>x.stock,
  getPdcSupabaseAccessToken:()=> 'not-a-real-credential',
  vehicleWorkshopDetailRequestDealerCode:v=>resolveDealerScope(v,state.sharedNavisionVisibleRows,state.vehicleModalIdentity),
  fetch:async(url,options)=>{requests.push({url,payload:JSON.parse(options.body)});return {ok:true,json:async()=>detail};},
 });
 vm.runInContext(sourceFunction('vehicleWorkshopDetailCanonicalId'),c);
 vm.runInContext(sourceFunction('vehicleWorkshopDetailResponse'),c);
 vm.runInContext('async '+sourceFunction('loadVehicleWorkshopDetail'),c);
 const result=await c.loadVehicleWorkshopDetail(vehicle,{force:true});
 assert.equal(result.vehicle_id,id);
 assert.equal(requests.length,1);
 assert.equal(requests[0].payload.p_dealer_code,'37047');
 assert.equal(state.vehicleWorkshopDetailCache.get(id).status,'ready');
});
test('published Review module adds inline controls and keeps diagnostic errors separate from conflicts',()=>{
 const source=fs.readFileSync('pdc-review-stations.js','utf8');
 assert.match(source,/authenticatedEmailOperationLinesHtml = function/);
 assert.match(source,/data-operation-station="REVIEW"/);
 assert.match(source,/loadSharedNavisionVisibleRows\(\{ force: true \}\)/);
 assert.match(source,/dealer_scope_unavailable/);
 assert.match(source,/station_detail_unavailable/);
 const boot=fs.readFileSync('canonical-entry.js','utf8');
 assert.match(boot,/pdc-review-stations\.js\?v=2026\.09\.09\.12/);
 assert.match(boot,/pdc-review-stations\.css\?v=2026\.09\.09\.12/);
});
