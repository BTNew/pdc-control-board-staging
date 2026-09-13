'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const ui=require('./pdc-new-vehicles.js');
const source=fs.readFileSync(path.join(__dirname,'pdc-new-vehicles.js'),'utf8');
const row={change_id:'change1',vehicle_id:'vehicle1',stock_number:'00123',snapshot_hash:'original-source',status:'pending',already_on_board:true,change_kind:'added',effective_hours:2,proposed:{proposed_station:'FITTING',operation_description:'Fit additional accessory'}};
const booking={booking_id:'booking1',vehicle_id:'vehicle1',stock_number:'00123',stage_code:'FITTING',bay_id:'bay1',bay_name:'Bay 1',previous_start_at:'2026-09-14T07:00:00+08:00',previous_end_at:'2026-09-14T09:00:00+08:00',start_at:'2026-09-14T07:00:00+08:00',end_at:'2026-09-14T11:00:00+08:00',previous_estimated_hours:2,estimated_hours:4,status:'planned'};
function receipt(bookings=[booking],stage='FITTING',hours=2){return {ok:true,data:{change_id:row.change_id,vehicle_id:row.vehicle_id,operation:{description:row.proposed.operation_description,stage_code:stage,estimated_hours:hours,completed:false},location_changed:false,bookings_changed:bookings.length>0,schedule:{bookings:JSON.parse(JSON.stringify(bookings)),changed_count:bookings.length,extended_count:bookings.filter(x=>x.estimated_hours>x.previous_estimated_hours).length,moved_count:bookings.filter(x=>Date.parse(x.start_at)!==Date.parse(x.previous_start_at)).length,buffer_minutes:300}}};}
const clone=value=>JSON.parse(JSON.stringify(value));
test('approval accepts exact operation and atomic extended/moved booking receipt, including minute precision',()=>{
  const next={...booking,booking_id:'booking2',vehicle_id:'vehicle2',stock_number:'00456',previous_start_at:booking.previous_end_at,previous_end_at:booking.end_at,start_at:booking.end_at,end_at:'2026-09-14T13:01:00+08:00',previous_estimated_hours:2+1/60,estimated_hours:2+1/60};
  const reply=receipt([booking,next]);
  assert.equal(ui.verifyUpdateApproval(reply,row,'FITTING',2),true);
  assert.match(ui.updateApprovalNotice(row,reply.data),/2 bay bookings updated; 1 extended; 1 moved to a later slot/);
  assert.match(ui.updateScheduleHtml(reply.data.schedule),/00456/);
  assert.equal(ui.verifyUpdateApproval(receipt([]),row,'FITTING',2),true);
  assert.equal(ui.verifyUpdateApproval(receipt([],'SUBLET',0),row,'SUBLET',null),true);
});
test('approval rejects false success for wrong operation, invalid schedule, duplicate identity and misleading counts',()=>{
  const changes=[r=>{r.data.vehicle_id='other';},r=>{r.data.change_id='other';},r=>{r.data.operation.description='other';},r=>{r.data.operation.estimated_hours=5;},r=>{r.data.operation.completed=true;},r=>{r.data.location_changed=true;},r=>{r.data.bookings_changed=false;},r=>{delete r.data.schedule;},r=>{r.data.schedule.buffer_minutes=30;},r=>{r.data.schedule.changed_count=2;},r=>{r.data.schedule.extended_count=0;},r=>{r.data.schedule.moved_count=1;},r=>{r.data.schedule.bookings.push(clone(booking));r.data.schedule.changed_count=2;r.data.schedule.extended_count=2;},r=>{r.data.schedule.bookings[0].start_at='bad';},r=>{r.data.schedule.bookings[0].end_at=booking.start_at;},r=>{r.data.schedule.bookings[0].bay_id='';},r=>{r.data.schedule.bookings[0].vehicle_id='';},r=>{r.data.schedule.bookings[0].status='completed';},r=>{r.data.schedule.bookings[0].estimated_hours=-1;},r=>{r.data.schedule.bookings[0].stage_code='SUBLET';},r=>{r.data.schedule.bookings[0].end_at=booking.previous_end_at;r.data.schedule.bookings[0].estimated_hours=2;}];
  for(const change of changes){const reply=receipt();change(reply);assert.equal(ui.verifyUpdateApproval(reply,row,'FITTING',2),false);}
});
test('schedule output escapes all source labels and distinguishes unchanged unbooked or Sublet work',()=>{
  const reply=receipt([{...booking,stock_number:'<script>',bay_name:'<img>'}]);
  assert.match(ui.updateScheduleHtml(reply.data.schedule),/&lt;script&gt;/);assert.doesNotMatch(ui.updateScheduleHtml(reply.data.schedule),/<img>/);
  assert.equal(ui.updateScheduleHtml(receipt([]).data.schedule),'');
  assert.match(ui.updateApprovalNotice(row,receipt([]).data),/No booking times needed to change/);
  assert.match(ui.updateApprovalNotice(row,receipt([],'SUBLET',0).data),/Sublet operation approved/);
});
test('approval rejects a schedule that moves a booking earlier than its accepted start',()=>{
  const reply=receipt();reply.data.schedule.bookings[0].start_at='2026-09-14T06:00:00+08:00';reply.data.schedule.moved_count=1;
  assert.equal(ui.verifyUpdateApproval(reply,row,'FITTING',2),false);
});
function fixture(){
  const calls=[],pending=[],refreshes=[];
  const context={...ui,console,crypto:{randomUUID:()=>`key${calls.length}`},window:{PDC_AUTH_CONTEXT:{userId:'actor',role:'administrator'},__workshopDataService:{loadSnapshot:async reason=>{refreshes.push(reason);return true;}}},token:'token',rpc:async(name,payload)=>{calls.push({name,payload});return new Promise((resolve,reject)=>pending.push({resolve,reject}));},getPdcSupabaseAccessToken:()=>context.token,refreshEmailVehicleLocations:async()=>{refreshes.push('locations');return true;},loadSharedNavisionVisibleRows:async()=>{refreshes.push('navision');return true;},render(){},load(){return Promise.resolve();}};
  vm.createContext(context);
  vm.runInContext(`let updateItems=${JSON.stringify([row])},updateTotal=1,updateDrafts={},updateRequests={},saving=false,error='',notice='',updateSchedule=null,sessionGeneration=0; const writable=()=>['operator','administrator'].includes(window.PDC_AUTH_CONTEXT.role);`,context);
  vm.runInContext(source.slice(source.indexOf('  function message(err)'),source.indexOf('  async function load('))+source.slice(source.indexOf('  async function approveUpdate(id)'),source.indexOf('  function bindUpdates()')),context);
  return {context,calls,pending,refreshes,state:()=>vm.runInContext('({updateItems,saving,error,notice,updateSchedule,updateRequests})',context)};
}
test('real approval handler sends one exact request and refreshes planner after verified schedule receipt',async()=>{
  const f=fixture(),approval=f.context.approveUpdate('change1');
  await f.context.approveUpdate('change1');assert.equal(f.calls.length,1);assert.equal(f.state().saving,true);
  assert.deepEqual(clone(f.calls[0].payload),{p_change_id:'change1',p_snapshot_hash:'original-source',p_stage_code:'FITTING',p_estimated_hours:2,p_idempotency_key:'key0'});
  f.pending[0].resolve(receipt());await approval;await new Promise(resolve=>setImmediate(resolve));
  assert.equal(f.state().saving,false);assert.equal(f.state().updateItems.length,0);assert.match(f.state().notice,/1 extended/);
  assert.deepEqual(f.refreshes,['locations','navision','tune_operation_change_approval']);
});
test('uncertain approval keeps the reviewed card and retries the exact idempotency key',async()=>{
  const f=fixture(),first=f.context.approveUpdate('change1');f.pending[0].reject(Error('offline'));await first;
  assert.equal(f.state().updateItems.length,1);assert.match(f.state().error,/could not be confirmed/);
  const retry=f.context.approveUpdate('change1');assert.equal(f.calls[0].payload.p_idempotency_key,f.calls[1].payload.p_idempotency_key);
  f.pending[1].resolve(receipt());await retry;assert.equal(f.state().updateItems.length,0);
});
test('invalid receipt does not remove pending work or claim that hours were saved',async()=>{
  const f=fixture(),approval=f.context.approveUpdate('change1'),reply=receipt();reply.data.schedule.changed_count=99;
  f.pending[0].resolve(reply);await approval;assert.equal(f.state().updateItems.length,1);assert.equal(f.state().notice,'');assert.equal(f.refreshes.length,0);
});
test('previous-session completion cannot overwrite a new session or pending save',async()=>{
  const f=fixture(),approval=f.context.approveUpdate('change1');
  vm.runInContext("sessionGeneration++;updateRequests={};notice='New session';saving=true;",f.context);f.context.window.PDC_AUTH_CONTEXT.userId='other';
  f.pending[0].resolve(receipt());await approval;assert.equal(f.state().notice,'New session');assert.equal(f.state().saving,true);assert.equal(f.refreshes.length,0);
  const token=fixture(),changed=token.context.approveUpdate('change1');token.context.token='renewed-token';token.pending[0].resolve(receipt());await changed;
  assert.equal(token.state().saving,false);assert.equal(token.state().notice,'');assert.match(token.state().error,/session changed/);
});
test('approved Sublet update sends no workshop hours and leaves no bay schedule',async()=>{
  const f=fixture();vm.runInContext("updateDrafts.change1={stage:'SUBLET'};",f.context);
  const approval=f.context.approveUpdate('change1');assert.equal(f.calls[0].payload.p_estimated_hours,null);
  f.pending[0].resolve(receipt([],'SUBLET',0));await approval;assert.match(f.state().notice,/Sublet operation approved/);assert.equal(f.state().updateSchedule.bookings.length,0);
});
test('real scheduling RPC preserves its safe conflict explanation and handler retains the pending approval',async()=>{
  const f=fixture(),blocker='A later job is already in progress in Hoist Bay 2. No changes were saved.';
  Object.assign(f.context,{URL,AbortController,setTimeout,clearTimeout,fetch:async()=>({ok:true,json:async()=>({ok:false,code:'operation_schedule_conflict',message:blocker})})});
  f.context.window.PDC_SUPABASE_CONFIG={url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'synthetic'};
  vm.runInContext("const PROJECT='cdsmnqxtyyoeoznmbidd'; const readable=()=>true;",f.context);
  vm.runInContext(source.slice(source.indexOf('  async function rpc(name,payload)'),source.indexOf('  function message(err)')),f.context);
  await f.context.approveUpdate('change1');assert.equal(f.state().error,blocker);assert.equal(f.state().updateItems.length,1);assert.equal(f.state().saving,false);assert.equal(f.state().notice,'');
  await assert.rejects(f.context.rpc('unrelated_rpc',{}),error=>error.message==='operation_schedule_conflict'&&error.userMessage===undefined);
});
