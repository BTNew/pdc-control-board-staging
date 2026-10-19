'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const service=require('./pdc-email-vehicle-location-service.js');
const id='11111111-1111-4111-8111-111111111111';
function line(stage,extra={}) {return {line_identity:'source:'+id,source_line_id:id,description:'Synthetic work',stage_code:stage,active:true,completed:false,...extra};}
function map(lines,work=[]) {return service.reconcileVehicleRows([],[{id,stock_number:'TEST-ROW',visible_on_board:true,current_location:'PMB',work_items:work,qc_operation_lines:lines}],{authoritative:true}).rows[0];}
test('canonical zero-hour work remains required when materialized work summary is missing',()=>{
 const row=map(['TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','BUS_ELECTRICAL'].map(s=>line(s,{estimated_hours:0})));
 for(const field of ['Tint','Hoist','Fitting','Fabrication','Electrical','Tyre','Sublet','Bus4x4']) assert.equal(row['pdcRequires'+field],true,field);
 assert.equal(row.pdcCompleteElectrical,false);
});
test('inactive, rejected, completed lines and notes do not invent outstanding requirements',()=>{
 const row=map([line('ELECTRICAL',{active:false}),line('FITTING',{rejected:true}),line('HOIST',{completed:true}),line('JOB_CARD_NOTES')]);
 assert.equal(row.pdcRequiresElectrical,false);assert.equal(row.pdcRequiresFitting,false);assert.equal(row.pdcRequiresHoist,false);assert.equal(row.pdcHasUnclassifiedOperationWork,false);
});
test('unclassified work after the display cap still blocks QC; existing completion is preserved',()=>{
 const row=map([...Array.from({length:251},()=>line('JOB_CARD_NOTES')),line('UNALLOCATED_MAPPING_REVIEW')],[{work_key:'fitting',required:true,completed:true}]);
 assert.equal(row.pdcHasUnclassifiedOperationWork,true);assert.equal(row.pdcCompleteFitting,true);
 const source=fs.readFileSync('app.js','utf8'); const fn=source.slice(source.indexOf('function vehicleReadyForQualityControl('),source.indexOf('function vehicleInQualityControlGate('));
 const ctx={vehiclePdcLocation:()=> 'PMB',isPdcBlocked:()=>false,isActivePartsStoppage:()=>false,pdcQualityControlRequirementDefinitions:()=>[],pdcJobComplete:()=>true,normalizePmbStage:()=>'',inferredPmbStage:()=>''};vm.createContext(ctx);vm.runInContext(fn,ctx);
 assert.equal(ctx.vehicleReadyForQualityControl(row),false);assert.equal(ctx.vehicleReadyForQualityControl({}),true);
});
