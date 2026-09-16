'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
function slice(from,to){const start=source.indexOf(from);assert.ok(start>=0,from);const end=source.indexOf(to,start);assert.ok(end>start,to);return source.slice(start,end);}
function fixture({shared=true}={}) {
  const rows=[{id:'target',sharedBookingId:'canonical-target',sharedVersion:9,vehicleKey:'vehicle-a',stage:'FITTING',bay:1,status:'planned'},
    {id:'earlier-tint',vehicleKey:'vehicle-a',stage:'TINT',bay:2,status:'planned'},
    {id:'cached-live',vehicleKey:'vehicle-b',stage:'FITTING',bay:1,status:'started'}];
  const calls=[],alerts=[],renders=[];let release,reply={ok:true},localChecks=0;
  const pending=new Promise(resolve=>release=resolve);
  const c={Set,window:{alert:message=>alerts.push(message)},escapeHtml:String,
    workshopLoadPlans:()=>rows,workshopVehicle:()=>({stock:'TEST-STOCK'}),
    workshopSharedModeActive:()=>shared,workshopStartedBayConflict:()=>{localChecks++;return rows[2];},
    pmbStageLabel:value=>value,workshopAdministratorCanMove:()=>false,
    workshopAdministratorErrorDetail:()=>'',
    renderWorkshopPlanner:()=>renders.push(c.workshopPlanLifecycleActionsHtml(rows[0])),
    workshopDispatchSharedAction:async(action,payload,_render,options)=>{calls.push({action,payload,options});await pending;return reply;}};
  vm.createContext(c);
  vm.runInContext('const WORKSHOP_PENDING_STARTS=new Set(); let workshopStartFeedback={stage:"",message:""};'+
    slice('function workshopDescribeSharedActionError(','function workshopPersistPlanAction(')+
    slice('function workshopPlanLifecycleActionsHtml(','function workshopPlanChipHtml(')+
    slice('function workshopDescribeStartActionError(','async function completeWorkshopPlan('),c);
  return {c,rows,calls,alerts,renders,get localChecks(){return localChecks;},
    feedback:()=>vm.runInContext('workshopStartFeedback',c),finish(result={ok:true}){reply=result;release();}};
}
test('shared Start reaches the canonical server despite cached vehicle and live-bay conflicts',async()=>{
  const f=fixture(),before=JSON.stringify(f.rows),running=f.c.startWorkshopPlan('target');
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].action,'startWork');
  assert.deepEqual(JSON.parse(JSON.stringify(f.calls[0].payload)),{bookingId:'canonical-target',expectedVersion:9});
  assert.equal(f.localChecks,0,'cached conflicts must not pre-empt server priority and protected-work validation');
  assert.equal(f.alerts.length,0);assert.equal(JSON.stringify(f.rows),before,'no optimistic status or queue edits');
  assert.match(f.feedback().message,/Starting job/);assert.doesNotMatch(f.feedback().message,/Job started/);
  assert.match(f.renders.at(-1),/disabled aria-busy="true"/);assert.match(f.renders.at(-1),/Starting…/);
  f.finish();await running;assert.match(f.feedback().message,/Job started/);
  assert.equal(JSON.stringify(f.rows),before,'client must rely on the service snapshot rather than editing rows itself');
});
test('duplicate Start taps share one in-flight action and pending controls clear after canonical rejection',async()=>{
  const f=fixture();const running=f.c.startWorkshopPlan('target');await f.c.startWorkshopPlan('target');
  assert.equal(f.calls.length,1);assert.match(f.c.workshopPlanLifecycleActionsHtml(f.rows[0]),/aria-busy="true"/);
  f.finish({ok:false,error:'admin_block_conflict'});await running;
  assert.equal(f.rows[0].status,'planned');assert.match(f.feedback().message,/admin block/);
  assert.doesNotMatch(f.feedback().message,/Job started/);assert.doesNotMatch(f.renders.at(-1),/aria-busy|Starting…/);
});
test('planner success explains only the server-confirmed rescheduling count',async()=>{
  for(const [reply,expected]of [
    [{ok:true,start_priority:true,shifted_count:3},/3 affected bookings moved later/],
    [{ok:true,start_priority:true,shifted_count:0},/No other bookings needed to move/],
    [{ok:true,already_started:true,start_priority:false,shifted_count:0},/already running/],
    [{ok:true},/^Job started\.$/],
  ]) {
    const f=fixture(),running=f.c.startWorkshopPlan('target');f.finish(reply);await running;
    assert.match(f.feedback().message,expected);
  }
});
test('canonical live and schedule protections stay authoritative with no client fallback or partial save',async()=>{
  for(const code of ['fixed_booking_conflict','live_booking_conflict','vehicle_overlap','technician_overlap','schedule_changed','schedule_write_order_blocked']) {
    const f=fixture(),before=JSON.stringify(f.rows),running=f.c.startWorkshopPlan('target');
    f.finish({ok:false,error:code});const result=await running;
    assert.equal(result.ok,false);assert.equal(JSON.stringify(f.rows),before);
    assert.equal(f.localChecks,0);assert.equal(f.calls.length,1);assert.doesNotMatch(f.feedback().message,/Job started/);
  }
});
test('Start distinguishes protected vehicle and mechanic work from an unconfirmed network result',()=>{
  const f=fixture();
  assert.match(f.c.workshopDescribeStartActionError({error:'vehicle_overlap'}),/protected booking.*could not be moved safely/);
  assert.doesNotMatch(f.c.workshopDescribeStartActionError({error:'vehicle_overlap'}),/Best slot/);
  assert.match(f.c.workshopDescribeStartActionError({error:'technician_overlap'}),/mechanic.*running or stopped/);
  for(const error of ['no_response','runtime_failure','request_failed']) {
    const message=f.c.workshopDescribeStartActionError({error});assert.match(message,/could not be confirmed/);
    assert.doesNotMatch(message,/No changes were saved/);
  }
});
test('legacy local mode retains its original started-bay guard',async()=>{
  const f=fixture({shared:false});await f.c.startWorkshopPlan('target');
  assert.equal(f.localChecks,1);assert.equal(f.calls.length,0);assert.match(f.alerts[0],/already has a started job/);
});
