const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');const vm=require('node:vm');
const {present,forVehicleLine}=require('./pdc-estimated-hours.js');
const {mapServerVehicle}=require('./pdc-email-vehicle-location-service.js');
const {operationHoursHtml}=require('./pdc-new-vehicles.js');
const id='22222222-2222-4222-8222-222222222222';
const line={line_identity:'source:'+id,source_line_id:id,source_kind:'authenticated',operation_no:'PD001-12345678',description:'Fixture accessory',stage_code:'FITTING',estimated_hours:3,source_estimated_hours:0,hours_provenance:'ai_estimated',active:true,estimate_basis:'Guide fitting charge / rate',review_note:'Confirm kit'};
test('canonical adapter retains AI evidence and original source hours',()=>{
 const v=mapServerVehicle({id:'11111111-1111-4111-8111-111111111111',qc_operation_lines:[line]});
 const l=v.pdcQcOperationLines[0];assert.equal(l.hoursProvenance,'ai_estimated');assert.equal(l.sourceEstimatedHours,0);assert.equal(l.estimateBasis,line.estimate_basis);
 assert.equal(forVehicleLine(v,{operation_line_id:id,adjustmentId:'approved-adjustment'},3).ai,true);
 assert.equal(forVehicleLine(v,{operation_line_id:id},4).ai,false,'changed draft must not inherit old AI proof');
 v.pdcQcOperationLines[0].hoursProvenance='staff_estimate';assert.equal(forVehicleLine(v,{operation_line_id:id,hoursProvenance:'ai_estimated'},3).ai,false);
});
test('unknown, zero, source, manual and Sublet values are not coloured AI',()=>{
 for(const h of [null,undefined,'',0,-1,NaN,Infinity])assert.equal(present({...line,estimated_hours:h}).ai,false);
 for(const proof of ['source_explicit','staff_estimate','craig_electrical_default_1_5_hours','authenticated',''])assert.equal(present({...line,hours_provenance:proof}).ai,false);
 assert.equal(present({...line,stage_code:'SUBLET'}).ai,false);assert.equal(present(line,3,true).ai,false);
 assert.equal(present(line).ai,true);
});
test('ambiguous identity cannot borrow an AI label',()=>{
 const row={lineIdentity:'source:'+id,active:true,estimatedHours:3,hoursProvenance:'ai_estimated'};
 assert.equal(forVehicleLine({pdcQcOperationLines:[row,row]},{operation_line_id:id,hoursProvenance:'ai_estimated'},3).ai,false);
});
test('queue orange label clears for staff drafts; tooltip evidence is escaped',()=>{
 assert.match(operationHoursHtml(line),/class="nv-hours-hint pdc-ai-estimate"/);
 assert.doesNotMatch(operationHoursHtml(line,{[line.line_identity]:4}),/pdc-ai-estimate/);
 assert.doesNotMatch(operationHoursHtml({...line,estimate_basis:'<img src=x onerror=alert(1)>'}),/<img/);
});
test('planner renders a textual orange AI label beside the operation hours',()=>{
 const src=fs.readFileSync('workshop-planner.js','utf8');const start=src.indexOf('function workshopRequiredJobsForStageHtml(');const end=src.indexOf('\nfunction ',start+1);
 const context={normalizePmbStage:x=>x,cleanNavisionText:x=>String(x||''),vehicleJobcardNumber:()=>'',escapeHtml:x=>String(x).replaceAll('<','&lt;')};
 vm.runInNewContext(src.slice(start,end)+'\nthis.render=workshopRequiredJobsForStageHtml;',context);
 const html=context.render({},'FITTING',[{text:'Accessory',operationNo:'PD1',hours:3,hoursProvenance:'ai_estimated'}]);
 assert.match(html,/class="pdc-ai-estimate"/);assert.match(html,/AI estimate · 3 h/);
 assert.doesNotMatch(context.render({},'FITTING',[{text:'Accessory',operationNo:'PD1',hours:3,hoursProvenance:'staff_estimate'}]),/AI estimate/);
});
