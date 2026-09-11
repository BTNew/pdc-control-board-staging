'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const api=require('./pdc-planner-slim.js');
test('compact cards reuse only an unambiguous canonical board key',()=>{
 const rows=[{sharedVehicleId:'v1',stock:'A',keyNumber:'233'}];
 assert.equal(api.recordedKey({sharedVehicleId:'v1'},rows),'233');
 assert.equal(api.recordedKey({sharedVehicleId:'v2',stock:'A'},rows),'','matching stock alone is insufficient');
 assert.equal(api.recordedKey({sharedVehicleId:'v1'},[...rows,...rows]),'','ambiguous rows remain unknown');
 assert.equal(api.recordedKey({sharedVehicleId:'v1',key_number:'25'},rows),'25','snapshot key retains priority');
});
test('JC display uses recorded aliases and ignores placeholder values',()=>{
 assert.equal(api.jobCard({jobCardNumber:'Unknown',job_card_number:'JC1424638'}),'JC1424638');
 assert.equal(api.jobCard({pdcJobcard:'JC1',job_card_number:'JC2'}),'JC1');
 assert.equal(api.jobCard({},[{job_card_number:'JC3',active:true},{jobCardNumber:'JC3'},{jobCardNumber:'OLD',active:false}]),'JC3');
 assert.equal(api.jobCard({stock:'13056889'}),'');
});
test('slim tile retains drag and scheduling controls while showing just requested fields',()=>{
 const original='<article draggable="false" aria-disabled="true" data-workshop-vehicle-key="x"><strong>JC Unknown</strong><small>ETA old</small><div class="workshop-queue-actions"><button disabled title="Missing ETA">Schedule</button></div></article>';
 const output=api.compactQueue(original,{key:'9',jc:'JC7',customer:'A & B',model:'Prado',duration:'2.50h',parts:'Ordered',partsStatus:'ordered'});
 assert.match(output,/draggable="false" aria-disabled="true"/);
 assert.match(output,/Key 9 · JC7/);assert.match(output,/A &amp; B/);assert.match(output,/Booking time: 2.50h/);
 assert.doesNotMatch(output,/JC Unknown|ETA old/);
 assert.match(output,/<button disabled title="Missing ETA">Schedule<\/button>/);
 assert.equal((output.match(/<small/g)||[]).length,2);
});
test('Admin edit is visible outside hover controls and absent for read-only blocks',()=>{
 const input='<article><strong>ADMIN</strong><span class="workshop-admin-block-controls"><button type="button" data-workshop-admin-block-rename aria-label="Rename admin block">Rename</button><button data-admin-block-delete>×</button></span></article>';
 const out=api.visibleAdminEdit(input);
 assert.equal((out.match(/data-workshop-admin-block-rename/g)||[]).length,1);
 assert.ok(out.indexOf('Edit description')<out.indexOf('workshop-admin-block-controls'));
 assert.match(out,/data-admin-block-delete/);
 assert.equal(api.visibleAdminEdit('<article>Read only</article>'),'<article>Read only</article>');
});
test('runtime preserves snapshot key and JC and does not alter scheduling input',()=>{
 const ctx={window:{},setTimeout(){},vehicleJobcardNumber:()=>'',workshopSnapshotVehicleToPlannerRow:()=>({sharedVehicleId:'v'}),
 workshopQueueCardHtml:(v)=>'<article draggable="true"><b>old</b><div class="workshop-queue-actions">Schedule</div></article>',
 workshopAdminBlockHtml:()=>'<article>Read only</article>',workshopPartsSummary:()=>({text:'Received',status:'received'}),
 vehicleKeyNumber:v=>v.keyNumber,vehicleCustomerName:v=>v.client,workshopStageJobLines:()=>[],
 workshopQueueVehicleDescription:()=> 'Prado',workshopQueueEstimatedLabel:()=> '1.25h'};
 vm.runInNewContext(fs.readFileSync('pdc-planner-slim.js','utf8'),ctx);
 const row=ctx.workshopSnapshotVehicleToPlannerRow({key_number:'12',job_card_number:'JC5'});
 assert.equal(row.keyNumber,'12');assert.equal(row.jobCardNumber,'JC5');
 assert.match(ctx.workshopQueueCardHtml(row,'FITTING'),/Key 12 · JC5/);
});
test('opening a planner after startup retries expire still installs compact cards once',()=>{
 const timers=[], listeners=new Set();
 const document={addEventListener:(type,fn,capture)=>{assert.equal(type,'load');assert.equal(capture,true);listeners.add(fn);},
  removeEventListener:(type,fn)=>listeners.delete(fn)};
 const ctx={window:{},document,setTimeout:fn=>timers.push(fn)};
 vm.runInNewContext(fs.readFileSync('pdc-planner-slim.js','utf8'),ctx);
 for(let guard=0;timers.length&&guard<100;guard++) timers.shift()();
 assert.equal(timers.length,0,'startup retries are exhausted');
 assert.equal(ctx.window.PDC_PLANNER_SLIM_VERSION,undefined);
 Object.assign(ctx,{vehicleJobcardNumber:()=>'',workshopSnapshotVehicleToPlannerRow:()=>({}),
  workshopQueueCardHtml:()=>'<article draggable="false" aria-disabled="true"><b>Old tall layout</b><div class="workshop-queue-actions"><button disabled>Schedule</button></div></article>',
  workshopAdminBlockHtml:()=>'',workshopPartsSummary:()=>({text:'Received',status:'received'}),
  vehicleKeyNumber:()=> '12',vehicleCustomerName:()=> 'Test customer',workshopStageJobLines:()=>[],
  workshopQueueVehicleDescription:()=> 'Prado',workshopQueueEstimatedLabel:()=> '1.25h'});
 for(const listener of [...listeners]) listener({target:{id:'unrelated-script'}});
 assert.equal(ctx.window.PDC_PLANNER_SLIM_VERSION,undefined,'ignore unrelated script loads');
 const ready=[...listeners][0];
 ready({target:{id:'workshop-planner-script'}});
 const installed=ctx.workshopQueueCardHtml;
 const html=installed({},'FITTING');
 assert.match(html,/planner-slim-details/);
 assert.match(html,/draggable="false" aria-disabled="true"/);
 assert.match(html,/<button disabled>Schedule/);
 assert.doesNotMatch(html,/Old tall layout/);
 assert.equal(listeners.size,0,'readiness listener removed after installation');
 ready({target:{id:'workshop-planner-script'}});
 assert.equal(ctx.workshopQueueCardHtml,installed,'repeated notification never wraps twice');
});
