'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const api=require('./pdc-new-vehicles.js');
test('only uncertain operations start in Needs Review; confident stations and Department 138 are retained',()=>{
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
