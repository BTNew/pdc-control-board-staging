'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const api=require('./pdc-new-vehicles.js');
const sublet=require('./pdc-sublet-intake.js');
const row=()=>({status:'pending',vehicle_id:'vehicle',operations:[{line_identity:'source:1',source_line_id:'1',description:'Supplied kit',estimated_hours:0,stage_code:'FITTING',active:true,completed:false}]});
test('zero, missing and malformed hours cannot release a review; positive entered hours preserve source',()=>{
  for(const value of [null,undefined,'',0,'0',-1,'bad',1000,0.001,Infinity]){
    const r=row();r.operations[0].estimated_hours=value;assert.ok(api.problems(r).some(x=>/hours/.test(x)));
  }
  const r=row(),before=JSON.stringify(r),draft={'source:1':'0.25'};
  assert.deepEqual(api.problems(r,{},draft),[]);
  assert.equal(api.assignmentsFor(r,{},draft)[0].estimated_hours,0.25);
  assert.equal(api.stationGroups(r,{},draft).find(x=>x.code==='FITTING').hours,0.25);
  assert.equal(JSON.stringify(r),before);
  assert.equal(api.assignmentsFor(r,{}, {'source:1':''})[0].estimated_hours,null);
});
test('approval readback must contain the entered hours; a source-hours-only receipt is rejected',()=>{
  const r=row(),draft={'source:1':'0.5'};
  const result={ok:true,data:{vehicle_id:r.vehicle_id,visible_on_board:true,bookings_created:0,operations:r.operations.map(l=>({...l,estimated_hours:0.5}))}};
  assert.equal(api.verifyApproval(result,r,{},draft),true);
  result.data.operations[0].estimated_hours=0;
  assert.equal(api.verifyApproval(result,r,{},draft),false);
});
test('Sublet notes carry only active outstanding Sublet job details and escape source HTML',()=>{
  const v={__emailVehicleServerAuthoritative:true,pdcQcOperationLinesProjectionPresent:true,pdcQcOperationLines:[
    {stageCode:'SUBLET',active:true,completed:false,description:'Supplier <kit>',jobCardNumber:'JC123',estimatedHours:0.5},
    {stageCode:'SUBLET',active:true,completed:true,description:'Done'},
    {stageCode:'FITTING',active:true,completed:false,description:'Fitting'},
    {stageCode:'SUBLET',active:false,completed:false,description:'Removed'}]};
  assert.equal(sublet.jobs(v).length,1);
  assert.equal(sublet.notes(v),'JC JC123 · Supplier <kit>');
  assert.match(sublet.detailsHtml(v),/Supplier &lt;kit&gt;/);
  assert.deepEqual(sublet.jobs({...v,__emailVehicleServerAuthoritative:false}),[]);
  assert.deepEqual(sublet.jobs({...v,pdcQcOperationLinesProjectionPresent:false}),[]);
});
test('review uses hour controls and drag targets without Move to selectors',()=>{
  const js=fs.readFileSync('pdc-new-vehicles.js','utf8');
  assert.doesNotMatch(js,/nv-pill-move|data-nv-station|or use Move to/);
  assert.match(js,/data-nv-hours/);assert.match(js,/addEventListener\('drop'/);
});

test('Sublet needs no hours, preserves source and responds to station changes',()=>{
 for(const value of [null,0,2.5]){const r=row();r.operations[0].stage_code='SUBLET';r.operations[0].estimated_hours=value;const draft={'source:1':'5'};assert.deepEqual(api.problems(r,{},draft),[]);assert.equal(Object.hasOwn(api.assignmentsFor(r,{},draft)[0],'estimated_hours'),false);const result={ok:true,data:{vehicle_id:r.vehicle_id,visible_on_board:true,bookings_created:0,operations:r.operations.map(l=>({...l}))}};assert.equal(api.verifyApproval(result,r,{},draft),true);result.data.operations[0].estimated_hours=99;assert.equal(api.verifyApproval(result,r,{},draft),false);}
 const r=row();assert.ok(api.problems(r).length);assert.deepEqual(api.problems(r,{'source:1':'SUBLET'}),[]);r.operations[0].stage_code='SUBLET';assert.ok(api.problems(r,{'source:1':'FITTING'}).length);r.operations[0].department='138';assert.ok(api.problems(r,{'source:1':'SUBLET'}).length);
});
