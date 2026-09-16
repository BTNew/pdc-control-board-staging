'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const api=require('./pdc-new-vehicles.js');
test('only uncertain operations start in Needs Review; Department 138 uses Bus 4x4',()=>{
  const row={status:'pending',operations:[{line_identity:'a',department:'139',stage_code:'FITTING',estimated_hours:0.5,active:true,completed:false},{line_identity:'b',department:'139',stage_code:'ELECTRICAL',estimated_hours:2,active:true,completed:false},{line_identity:'c',department:'138',stage_code:'TINT',estimated_hours:3,active:true,completed:false}]};
  row.operations.push({line_identity:'d',department:'139',stage_code:'UNALLOCATED_MAPPING_REVIEW',estimated_hours:0.5,active:true,completed:false});
  const before=JSON.stringify(row),choices=api.reviewChoices(row);
  assert.deepEqual(api.assignmentsFor(row,choices).map(x=>x.stage_code),['FITTING','ELECTRICAL','BUS_4X4','']);
  assert.equal(api.stationGroups(row,choices)[0].lines.length,1);
  assert.ok(api.problems(row,choices).length);
  choices.d='FABRICATION';
  assert.deepEqual(api.problems(row,choices),[]);
  assert.equal(api.stationGroups(row,choices)[0].lines.length,0);
  choices.a='';
  assert.equal(api.stationGroups(row,choices)[0].lines.length,1);
  assert.equal(JSON.stringify(row),before);
});

test('Department 138 stays in Bus 4x4 and needs workshop hours despite stale Sublet choices',()=>{
 const row={status:'pending',operations:[{line_identity:'a',department:'138',stage_code:'BUS_4X4',estimated_hours:0,active:true,completed:false}]};
 assert.equal(api.assignmentsFor(row)[0].stage_code,'BUS_4X4');
 assert.equal(api.assignmentsFor(row,{a:'SUBLET'},{})[0].stage_code,'BUS_4X4');
 assert(api.problems(row,{a:'SUBLET'}).some(issue=>issue.includes('hours')));
 assert.equal(api.assignmentsFor(row,{a:'SUBLET'},{})[0].estimated_hours,null);
 assert(api.problems(row,{a:'FITTING'}).length);
 assert.equal(api.stationGroups(row,{a:'SUBLET'}).find(g=>g.code==='SUBLET').lines.length,0);
 assert.equal(api.stationGroups(row,{a:'SUBLET'}).find(g=>g.code==='BUS_4X4').lines.length,1);
 assert.equal(row.operations[0].estimated_hours,0);
});
