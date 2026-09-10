'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const api=require('./pdc-planner-slim.js');
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
