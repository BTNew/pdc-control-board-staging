'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {build}=require('./workshop-display-identity.js');
const id='12345678-0000-4000-8000-000000000001';
const row=extra=>({__emailVehicleId:id,__emailVehicleServerAuthoritative:true,keyNumber:'246',pdcQcOperationLinesProjectionPresent:true,pdcQcOperationLines:[{stageCode:'TINT',jobCardNumber:'JC1',active:true},{stageCode:'FITTING',jobCardNumber:'JC2',active:true}],...extra});
test('display supplements use canonical identity and the operation station',()=>{
 const result=build([row()]);
 assert.deepEqual(result.get(`${id}:TINT`),{key:'246',job:'JC1'});
 assert.deepEqual(result.get(`${id}:FITTING`),{key:'246',job:'JC2'});
 assert.deepEqual(result.get(`${id}:HOIST`),{key:'246',job:''});
});
test('local, conflicting, missing UUID and duplicate authority never supplement cards',()=>{
 for(const records of [[row({__emailVehicleServerAuthoritative:false})],[row({__emailVehicleIdentityConflict:true})],[row({__emailVehicleId:'13021292'})],[row(),row()]]) assert.equal(build(records).size,0);
 assert.equal(build([row({__emailVehicleId:undefined,id,stock:'13021292'})]).size,0);
});
test('current empty projection excludes older import lines and inactive lines',()=>{
 const old=[{stage_code:'TINT',job_card_number:'OLD'}];
 assert.equal(build([row({pdcQcOperationLines:[],pdcEmailOperationLines:old})]).get(`${id}:TINT`).job,'');
 assert.equal(build([row({pdcQcOperationLines:[{stageCode:'TINT',jobCardNumber:'OLD',active:false}]})]).get(`${id}:TINT`).job,'');
 assert.equal(build([row({pdcQcOperationLinesProjectionPresent:false,pdcEmailOperationLines:old})]).get(`${id}:TINT`).job,'OLD');
});
test('multiple active job cards remain distinct and duplicate lines do not repeat them',()=>{
 const result=build([row({pdcQcOperationLines:[{stageCode:'Tint',jobCardNumber:'JC2'},{stageCode:'Tint',jobCardNumber:'JC1'},{stageCode:'Tint',jobCardNumber:'JC2'}]})],s=>s.toUpperCase());
 assert.equal(result.get(`${id}:TINT`).job,'JC2, JC1');
});
