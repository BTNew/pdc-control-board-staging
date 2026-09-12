'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const api=require('./pdc-planner-slim.js');
const slimSource=fs.readFileSync(path.join(__dirname,'pdc-planner-slim.js'),'utf8');
test('compact cards reuse only an unambiguous canonical board key',()=>{
 const rows=[{sharedVehicleId:'v1',stock:'A',keyNumber:'233'}];
 assert.equal(api.recordedKey({sharedVehicleId:'v1'},rows),'233');
 assert.equal(api.recordedKey({sharedVehicleId:'v2',stock:'A'},rows),'','matching stock alone is insufficient');
 assert.equal(api.recordedKey({sharedVehicleId:'v1'},[...rows,...rows]),'','ambiguous rows remain unknown');
 assert.equal(api.recordedKey({sharedVehicleId:'v1',key_number:'25'},rows),'25','snapshot key retains priority');
 assert.equal(api.recordedKey({sharedVehicleId:'v1'},[{id:'v1',key_number:'233'}]),'233','raw authoritative board snapshot');
 assert.equal(api.recordedKey({sharedVehicleId:'v1'},[{id:'permanent-1',__emailVehicleId:'v1',keyNumber:'233'}]),'233','mapped board canonical ID');
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
 assert.match(output,/Key 9 · JC7/);assert.match(output,/A &amp; B/);
 assert.doesNotMatch(output,/JC Unknown|ETA old|Booking time|Parts:|Ordered|2\.50h/);
 assert.match(output,/<button disabled title="Missing ETA">Schedule<\/button>/);
 assert.equal((output.match(/<small/g)||[]).length,0);
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
 displayStockNumber:()=> '13021038',vehicleKeyNumber:v=>v.keyNumber,vehicleCustomerName:v=>v.client,workshopStageJobLines:()=>[],
 workshopQueueVehicleDescription:()=> 'Prado',workshopQueueEstimatedLabel:()=> '1.25h'};
 vm.runInNewContext(slimSource,ctx);
 const row=ctx.workshopSnapshotVehicleToPlannerRow({key_number:'12',job_card_number:'JC5'});
 assert.equal(row.keyNumber,'12');assert.equal(row.jobCardNumber,'JC5');
 assert.match(ctx.workshopQueueCardHtml(row,'FITTING'),/Key 12 · JC5/);
});
test('opening a planner after startup retries expire still installs compact cards once',()=>{
 const timers=[], listeners=new Set();
 const document={addEventListener:(type,fn,capture)=>{assert.equal(type,'load');assert.equal(capture,true);listeners.add(fn);},
  removeEventListener:(type,fn)=>listeners.delete(fn)};
 const ctx={window:{},document,setTimeout:fn=>timers.push(fn)};
 vm.runInNewContext(slimSource,ctx);
 for(let guard=0;timers.length&&guard<100;guard++) timers.shift()();
 assert.equal(timers.length,0,'startup retries are exhausted');
 assert.equal(ctx.window.PDC_PLANNER_SLIM_VERSION,undefined);
 Object.assign(ctx,{vehicleJobcardNumber:()=>'',workshopSnapshotVehicleToPlannerRow:()=>({}),
  workshopQueueCardHtml:()=>'<article draggable="false" aria-disabled="true"><b>Old tall layout</b><div class="workshop-queue-actions"><button disabled>Schedule</button></div></article>',
  workshopAdminBlockHtml:()=>'',workshopPartsSummary:()=>({text:'Received',status:'received'}),
  displayStockNumber:()=> '13021038',vehicleKeyNumber:()=> '12',vehicleCustomerName:()=> 'Test customer',workshopStageJobLines:()=>[],
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

test('daily identity replacement preserves geometry, selection, lifecycle and resize controls',()=>{
 const controls='<div class="workshop-plan-lifecycle-actions"><button data-workshop-start-plan="b1">Start job</button></div><span class="workshop-plan-resize" data-workshop-resize-plan="b1" title="Drag to change duration"></span>';
 const input='<article class="workshop-plan-chip has-lifecycle-actions is-search-match" draggable="true" data-workshop-plan-id="b1" data-workshop-job-vehicle="stock1" data-workshop-locate-key="stock1" style="--plan-left:10%;--plan-width:40%;" title="Mon 14 7:00am · 56h"><button class="workshop-plan-main" type="button" data-workshop-select-plan="b1"><strong>Old JC</strong><small>PLANNED · Craig Watson</small><small>Parts Not Ordered</small><small>Mon 14 · 56h</small></button>'+controls+'</article>';
 const out=api.compactPlan(input,{key:'K9',jc:'J123',stock:'S456',customer:'A & B',model:'Hilux <ECC>'});
 assert.match(out,/class="planner-identity-chip workshop-plan-chip has-lifecycle-actions is-search-match"/);
 assert.match(out,/draggable="true" data-workshop-plan-id="b1" data-workshop-job-vehicle="stock1" data-workshop-locate-key="stock1" style="--plan-left:10%;--plan-width:40%;"/);
 assert.match(out,/<button class="workshop-plan-main" type="button" data-workshop-select-plan="b1">/);
 assert.ok(out.endsWith(controls+'</article>'),'action and resize subtree is preserved verbatim');
 assert.match(out,/Key K9 · JC J123/);assert.match(out,/Stock S456/);assert.match(out,/A &amp; B/);assert.match(out,/Hilux &lt;ECC&gt;/);
 assert.doesNotMatch(out,/Old JC|PLANNED|Craig Watson|Parts|Mon 14|56h/);
});

test('daily locked booking retains its review control and never gains drag or resize',()=>{
 const input='<article class="workshop-plan-chip has-lifecycle-actions" data-workshop-plan-id="locked" style="--plan-left:0%;--plan-width:10%;" title="Old dates"><button class="workshop-plan-main" data-workshop-select-plan="locked">Old details</button><div class="workshop-legacy-ambiguity" role="status" title="Conflicting imported records">Legacy review required · editing blocked</div></article>';
 const out=api.compactPlan(input,{});
 assert.match(out,/Legacy review required · editing blocked/);
 assert.match(out,/title="Conflicting imported records"/);
 assert.doesNotMatch(out,/draggable|data-workshop-resize-plan/);
 assert.match(out,/Key — · JC Not recorded/);
});

test('weekly identity replacement preserves timetable geometry and booking identity',()=>{
 const input='<article class="workshop-week-card is-live historical-on-closure" draggable="true" data-workshop-week-plan="b2" data-workshop-job-vehicle="stock2" style="--week-top:20%;--week-height:4%;" title="Monday 07:00 · 0.5 hours"><strong>JC OLD</strong><span>Old model</span><small>LIVE · Craig Watson</small><em>0.5h</em></article>';
 const out=api.compactWeek(input,{key:'12',jc:'J2',stock:'S2',customer:'Test customer',model:'HiAce'});
 assert.match(out,/draggable="true" data-workshop-week-plan="b2" data-workshop-job-vehicle="stock2" style="--week-top:20%;--week-height:4%;"/);
 assert.match(out,/is-live historical-on-closure/);
 assert.match(out,/Key 12 · JC J2/);assert.match(out,/Stock S2/);assert.match(out,/Test customer/);assert.match(out,/HiAce/);
 assert.doesNotMatch(out,/JC OLD|Old model|LIVE ·|Craig Watson|Monday|0\.5|<em/);
});

test('five-field identity escapes supplied names and uses explicit missing-field fallbacks',()=>{
 const out=api.summaryHtml({key:'<K>',jc:'J"7',stock:'S&1',customer:'A <script>alert(1)</script>',model:'" onmouseover="bad'});
 assert.match(out,/Key &lt;K&gt; · JC J&quot;7/);
 assert.match(out,/Stock S&amp;1/);
 assert.doesNotMatch(out,/<script>|title="" onmouseover=/);
 const missing=api.summaryHtml();
 assert.match(missing,/Key — · JC Not recorded/);assert.match(missing,/Stock Not recorded/);
 assert.match(missing,/Customer not recorded/);assert.match(missing,/Model not recorded/);
 assert.equal(api.compactPlan('',{}),'');assert.equal(api.compactWeek('',{}),'');
 const prefixed=api.compactWeek('<article class="workshop-week-card" title="Old">Old</article>',{jc:'JC123'});
 assert.doesNotMatch(prefixed,/JC JC123/,'already prefixed job cards are not prefixed twice in the tooltip');
});

test('runtime resolves scheduled identity through the exact vehicle UUID and preserves inputs',()=>{
 const calls=[], vehicle={sharedVehicleId:'canonical-1',stock:'stock1',keyNumber:'K1',jobCardNumber:'J1',client:'Correct customer',model:'Correct model'};
 const entry=Object.freeze({id:'b1',sharedVehicleId:'canonical-1',vehicleKey:'ambiguous-stock',stage:'BUS4X4',hours:40});
 const day='<article class="workshop-plan-chip" data-workshop-plan-id="b1" style="--plan-left:0%;--plan-width:100%;" title="Old"><button class="workshop-plan-main" data-workshop-select-plan="b1">Old</button><div class="workshop-plan-lifecycle-actions"><button data-workshop-start-plan="b1">Start job</button></div></article>';
 const week='<article class="workshop-week-card" data-workshop-week-plan="b1" style="--week-top:0%;--week-height:10%;" title="Old">Old</article>';
 const ctx={window:{},setTimeout(){},vehicleJobcardNumber:()=>'',workshopSnapshotVehicleToPlannerRow:()=>({}),
  workshopQueueCardHtml:()=>'',workshopAdminBlockHtml:()=>'',
  workshopPlanChipHtml:(...args)=>{assert.equal(args[0],entry);assert.equal(args[1],'2026-09-14');return day;},
  workshopWeeklyCardHtml:(...args)=>{assert.equal(args[0],entry);assert.equal(args[1],'2026-09-14');return week;},
  workshopVehicle:(key,stage)=>{calls.push([key,stage]);return key==='canonical-1'?vehicle:null;},
  displayStockNumber:v=>v.stock,vehicleKeyNumber:v=>v.keyNumber,vehicleCustomerName:v=>v.client,
  workshopStageJobLines:()=>[],workshopQueueVehicleDescription:v=>v.model};
 vm.runInNewContext(slimSource,ctx);
 assert.match(ctx.workshopPlanChipHtml(entry,'2026-09-14',[]),/Correct customer/);
 assert.match(ctx.workshopWeeklyCardHtml(entry,'2026-09-14'),/Correct model/);
 assert.deepEqual(calls,[['canonical-1','BUS4X4'],['canonical-1','BUS4X4']]);
 assert.equal(entry.hours,40);assert.equal(entry.vehicleKey,'ambiguous-stock');
});
