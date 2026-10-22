/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const api=require('./pdc-new-vehicles.js');
test('only uncertain operations start in Needs Review; Department 138 starts on its server category',()=>{
  const row={status:'pending',operations:[{line_identity:'a',department:'139',stage_code:'FITTING',estimated_hours:0.5,active:true,completed:false},{line_identity:'b',department:'139',stage_code:'ELECTRICAL',estimated_hours:2,active:true,completed:false},{line_identity:'c',department:'138',stage_code:'TINT',work_category:'TINT',estimated_hours:3,active:true,completed:false}]};
  row.operations.push({line_identity:'d',department:'139',stage_code:'UNALLOCATED_MAPPING_REVIEW',estimated_hours:0.5,active:true,completed:false});
  const before=JSON.stringify(row),choices=api.reviewChoices(row);
  assert.deepEqual(api.assignmentsFor(row,choices).map(x=>x.stage_code),['FITTING','ELECTRICAL','TINT',''],'r459: a Dept 138 line is sent on the station its category maps to');
  assert.deepEqual(api.assignmentsFor(row,choices).map(x=>x.work_category),[undefined,undefined,'TINT',undefined],'only Dept 138 lines carry a category');
  assert.equal(api.stationGroups(row,choices)[0].lines.length,1);
  assert.ok(api.problems(row,choices).length);
  choices.d='FABRICATION';
  assert.deepEqual(api.problems(row,choices),[]);
  assert.equal(api.stationGroups(row,choices)[0].lines.length,0);
  choices.a='';
  assert.equal(api.stationGroups(row,choices)[0].lines.length,1);
  assert.equal(JSON.stringify(row),before);
});

test('r446 (F59): Department 138 chooses any Bus 4x4 station, Sublet needs no hours, PD stations are refused',()=>{
 const row={status:'pending',operations:[{line_identity:'a',department:'138',stage_code:'BUS_4X4',work_category:'BUS_MECHANICAL',estimated_hours:0,active:true,completed:false}]};
 assert.equal(api.assignmentsFor(row)[0].stage_code,'BUS_4X4','server-owned stage is sent unchanged');
 assert.equal(api.assignmentsFor(row)[0].work_category,'BUS_MECHANICAL');
 assert(api.problems(row).some(issue=>issue.includes('hours')),'workshop category still needs hours');
 assert.deepEqual(api.problems(row,{a:'SUBLET'}),[],'Sublet needs no hours');
 assert.equal(api.assignmentsFor(row,{a:'SUBLET'},{})[0].work_category,'SUBLET');
 assert.equal('estimated_hours' in api.assignmentsFor(row,{a:'SUBLET'},{})[0],false);
 assert(api.problems(row,{a:'FITTING'}).some(issue=>issue.includes('station')),'PD station refused for Dept 138');
 assert.equal(api.stationGroups(row,{a:'SUBLET'}).find(g=>g.code==='SUBLET').lines.length,1);
 assert.equal(api.stationGroups(row,{a:'FITTING'})[0].lines.length,1,'invalid choice shows in Needs Review');
 assert.equal(api.stationGroups(row).some(g=>g.code==='BUS_4X4'||g.code==='FITTING'),false,'no Bus 4x4 bucket or PD stations on a Dept 138 card');
 assert.equal(row.operations[0].estimated_hours,0);
});
