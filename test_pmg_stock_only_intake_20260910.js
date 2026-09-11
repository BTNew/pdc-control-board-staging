'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const ui=require('./pdc-new-vehicles.js');
test('Department 138 cannot be split through drag/drop or supplied choices',()=>{
  const row={operations:[{line_identity:'a',department:'138',stage_code:'ELECTRICAL',estimated_hours:0},{line_identity:'b',department:'139',stage_code:'TYRE',estimated_hours:1.5}]};
  assert.deepEqual(ui.assignmentsFor(row,{a:'TINT',b:'FITTING'}),[{line_identity:'a',stage_code:'BUS_4X4'},{line_identity:'b',stage_code:'FITTING'}]);
  const group=ui.stationGroups(row,{a:'TINT'}).find(x=>x.code==='BUS_4X4');
  assert.equal(group.lines.length,1);assert.equal(group.hours,null,'zero-hour work still needs hours even when Department 138 fixes its station');
});
test('unknown station stays available for review while known proposals remain selected',()=>{
  const row={operations:[{line_identity:'a',department:'139',stage_code:'REVIEW'},{line_identity:'b',department:'139',stage_code:'ELECTRICAL'}]};
  assert.deepEqual(ui.assignmentsFor(row),[{line_identity:'a',stage_code:''},{line_identity:'b',stage_code:'ELECTRICAL'}]);
});
test('new unbound queue is read-only in the UI and cleared at signout',()=>{
  const source=fs.readFileSync('pdc-new-vehicles.js','utf8');
  assert.match(source,/list_pdc_unidentified_tune_reviews/);
  const fragment=source.slice(source.indexOf('if(unidentified) {\n      page.innerHTML'),source.indexOf('const issues=selected'));
  assert.ok(fragment.length>0);
  assert.doesNotMatch(fragment,/data-nv-approve|approve_pdc_new_vehicle_review/);
  assert.match(source,/pdc-auth-locked[^\n]*unidentifiedItems=\[\]/);
});
