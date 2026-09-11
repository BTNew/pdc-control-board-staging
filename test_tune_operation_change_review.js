'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {updateProblems,operationUpdateHtml}=require('./pdc-new-vehicles.js');
const added={change_id:'c1',vehicle_id:'v1',stock_number:'12345678',status:'pending',already_on_board:true,change_kind:'added',
  job_number:'J123',line_number:25,current_location:'PMB',customer_name:'Test',received_at:'2026-09-12T00:00:00Z',
  before:{},proposed:{operation_description:'Fit new light',source_estimated_hours:2,proposed_station:'ELECTRICAL'},effective_hours:2};
assert.deepEqual(updateProblems(added),[]);
assert.match(operationUpdateHtml(added),/Already on board/);
assert.match(operationUpdateHtml(added),/not on this vehicle yet/);
assert.match(operationUpdateHtml(added),/Approve operation change/);
assert.ok(updateProblems({...added,effective_hours:0}).some(x=>x.includes('positive')));
assert.deepEqual(updateProblems({...added,effective_hours:0},{stage:'SUBLET'}),[]);
assert.ok(updateProblems({...added,status:'superseded'}).length);
assert.ok(updateProblems({...added,already_on_board:false}).length);
const changed={...added,change_kind:'modified',before:{operation_description:'Original light',source_estimated_hours:1},
 current_work:{stage_code:'FITTING',estimated_hours:1.5,completed:false}};
assert.match(operationUpdateHtml(changed),/Original light/);
assert.match(operationUpdateHtml(changed),/Fit new light/);
assert.match(operationUpdateHtml(changed),/FITTING · 1.5 hours/);
assert.ok(updateProblems({...changed,current_work:{...changed.current_work,completed:true}}).some(x=>x.includes('completed')));
assert.match(operationUpdateHtml({...added,proposed:{...added.proposed,operation_description:'<script>alert(1)</script>'}}),/&lt;script&gt;/);
assert.match(operationUpdateHtml(added,{},false),/data-approve-update disabled/);
assert.match(operationUpdateHtml(added,{},true,true),/Saving…/);
const ui=fs.readFileSync('pdc-new-vehicles.js','utf8');
assert.match(ui,/p_snapshot_hash:row.snapshot_hash/);
assert.match(ui,/updateRequests\[id\]\.key/);
assert.match(ui,/bookings_changed!==false/);
assert.match(ui,/location_changed!==false/);
console.log('Tune operation review before/after, approval gating, escaping and receipt contract: PASS');
