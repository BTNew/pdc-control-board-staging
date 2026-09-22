'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/workshop-planner.js', 'utf8');
const {createWorkshopDataService} = require('./workshop-data-service.js');
const {compactPlan,compactWeek} = require('./pdc-planner-slim.js');
const UUID = '11111111-1111-4111-8111-111111111111';
const BOOK = '22222222-2222-4222-8222-222222222222';
const PAUL = '33333333-3333-4333-8333-333333333333';
const REN = '44444444-4444-4444-8444-444444444444';
const ANDREW = '55555555-5555-4555-8555-555555555555';
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function functions(names, context = {}) {
  vm.createContext(context);
  for (const name of names) {
    const match = new RegExp('(?:async )?function ' + name + '\\(').exec(source);
    assert.ok(match, name);
    const rest = source.slice(match.index);
    const boundary = /\n(?:async )?function /.exec(rest.slice(1));
    vm.runInContext(rest.slice(0, boundary ? boundary.index + 1 : rest.length), context);
  }
  return context;
}
function uiFixture() {
  const state = {}, calls = [], alerts = [];
  const entry = {id:BOOK,sharedBookingId:BOOK,sharedVehicleId:UUID,sharedVersion:4,vehicleKey:'12311021',
    stage:'BUS_4X4',bay:4,status:'started',hours:88.28,assignee:'Ren Karlos',technicianId:REN,
    actualStartAt:'2026-09-23T00:00:00Z',helperAssignments:[{technicianId:PAUL,name:'Paul Guiye'}],
    helperLabourMinutes:0,helperLabour:[]};
  const roster = [{id:PAUL,name:'Paul Guiye',active:true},{id:REN,name:'Ren Karlos',active:true},{id:ANDREW,name:'Andrew McCormick',active:true}];
  const c = {Date,Set,Map,JSON,escapeHtml:esc,cleanNavisionText:v=>String(v||'').trim(),
    WORKSHOP_UUID_PATTERN:/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    WORKSHOP_INCREMENTAL_RENDER_BATCH:12, vehicleKey:v=>v.vehicleKey||v.stock||'',
    workshopState:()=>state, workshopLoadPlans:()=>[entry],workshopSharedModeActive:()=>true,
    workshopBusShift:entry=>entry.stage==='BUS_4X4'?{startMinutes:360,endMinutes:900}:null,
    workshopNewRequestId:()=>UUID,renderWorkshopPlanner:()=>{},
    FormData:class {constructor(form){this.data=form.values;}get(k){return this.data[k]??null;}getAll(k){return this.data[k]||[];}},
    window:{alert:v=>alerts.push(v),PDC_AUTH_CONTEXT:{userId:'controller',role:'operator'},
      __workshopReferenceDataService:{getCachedTechnicians:()=>({rows:roster})},
      __workshopSharedActions:{setBookingTeam(){},recordHelperLabour(){}}},
    workshopDispatchSharedAction:async(action,payload)=>{calls.push({action,payload});return {ok:true};},
  };
  functions(['workshopIncrementalRenderRows','workshopBookingTeamLabel','workshopTeamRoster',
    'workshopHelperLabourTechnicians','workshopHelperLabourHtml','saveWorkshopHelperLabour','workshopBookingTeamHtml','saveWorkshopBookingTeam'],c);
  return {c,state,calls,alerts,entry,roster};
}
test('HTTP P0001 parts rejection retains canonical code and exact workflow stage after authoritative refresh', async () => {
  const calls = [];
  const service = createWorkshopDataService({config:{workshop:{sharedData:true}},getAccessToken:()=> 'test-session',getRole:()=> 'operator',
    client:{rpc:async(_token,name,params)=>{
      calls.push({name,params});
      if (name.includes('snapshot')) return {ok:true,status:200,body:{revision:1,vehicles:[],bookings:[]}};
      return {ok:false,status:400,body:{code:'P0001',message:'Workshop Planner validation rejected booking: {"ok":false,"error":"bus_stage_parts_required","workflow_stage":"accessory"}'}};
    }}});
  await service.loadSnapshot('initial');
  const result = await service.mutate('move_workshop_booking',{p_booking_id:BOOK,p_expected_version:4});
  assert.equal(result.error,'bus_stage_parts_required');
  assert.equal(result.workflow_stage,'accessory');
  assert.equal(result.outcomeUnknown,undefined);
  assert.equal(calls.filter(c=>c.name==='move_workshop_booking').length,1,'no readiness override or retry');
  assert.equal(calls.filter(c=>c.name.includes('snapshot')).length,2);
  const c=functions(['workshopDescribeSharedActionError'],{workshopAdministratorCanMove:()=>false});
  assert.match(c.workshopDescribeSharedActionError(result),/accessory parts check/);
  assert.match(c.workshopDescribeSharedActionError(result),/save.*retry.*Unallocated/i);
});
test('searched 38th candidate is visible in first batch without granting readiness or dropping queue rows', () => {
  const {c}=uiFixture();
  const rows=Array.from({length:38},(_,i)=>({vehicleKey:String(i),__workshopOutstanding:{scheduleEnabled:i!==37,disabledReason:i===37?'bus_stage_parts_required':''}}));
  const before=JSON.stringify(rows), batch=c.workshopIncrementalRenderRows(rows,12,'37');
  assert.equal(batch.visible.length,12);assert.equal(batch.remaining,26);assert.equal(batch.visible[0],rows[37]);
  assert.equal(batch.visible[0].__workshopOutstanding.scheduleEnabled,false);
  assert.equal(JSON.stringify(rows),before);
  const expanded=c.workshopIncrementalRenderRows(rows,38,'37');
  assert.equal(new Set(expanded.visible.map(v=>v.vehicleKey)).size,38);
  assert.equal(expanded.remaining,0);
  assert.equal(c.workshopIncrementalRenderRows(rows,12,'unknown').visible[0],rows[0]);
});
test('authoritative candidate hours survive null vehicle estimates and blocked candidates stay visible', () => {
  const vehicles=[{id:UUID,stock_number:'12311021',workshop_estimated_hours_by_stage:{BUS_4X4:null}},{id:BOOK,stock_number:'13017938'}];
  const snapshot={vehicles,work_items:[],bookings:[],outstanding_candidates:[
    {vehicle_id:UUID,existing_booking:false,schedule_enabled:true,estimated_hours:88.28,requirements:[]},
    {vehicle_id:BOOK,existing_booking:false,schedule_enabled:false,disabled_reason:'bus_stage_parts_required',estimated_hours:19.82,requirements:[]} ]};
  const c=functions(['workshopPlannerVehiclesForStage'],{
    workshopStageVehicles:()=>[],normalizePmbStage:v=>v,workshopSharedModeActive:()=>true,
    window:{__activeWorkshopPlannerStage:'BUS_4X4',__workshopDataService:{getLastSnapshot:()=>snapshot}},
    WORKSHOP_ELIGIBILITY_RUNTIME:{workshopCanonicalEligibility:()=>({candidates:[]})},
    workshopSnapshotVehicleToPlannerRow:v=>({sharedVehicleId:v.id,stock:v.stock_number,pmbJobs:{},workshopEstimatedHoursByStage:{BUS_4X4:null}}),
    displayStockNumber:v=>v.stock,
  });
  const rows=c.workshopPlannerVehiclesForStage('BUS_4X4');
  assert.equal(rows.length,2); assert.equal(rows[0].workshopEstimatedHoursByStage.BUS_4X4,88.28);
  assert.equal(rows[1].__workshopOutstanding.scheduleEnabled,false);assert.equal(rows[1].__workshopOutstanding.existingBooking,false);
});
test('team editor submits primary plus helpers as one booking mutation with no bay/duration rewrite', async () => {
  const {c,entry,calls}=uiFixture(), before=JSON.stringify(entry);
  const form={dataset:{workshopBookingId:BOOK,workshopBookingVersion:'4'},values:{primaryTechnicianId:REN,helperTechnicianIds:[PAUL,ANDREW],teamNote:'Training together'}};
  assert.equal(await c.saveWorkshopBookingTeam({preventDefault(){},currentTarget:form}),true);
  assert.equal(calls.length,1);assert.equal(calls[0].action,'setBookingTeam');
  assert.deepEqual(JSON.parse(JSON.stringify(calls[0].payload)),{bookingId:BOOK,expectedVersion:4,primaryTechnicianId:REN,helperTechnicianIds:[PAUL,ANDREW],requestId:UUID,note:'Training together'});
  assert.equal(JSON.stringify(entry),before);
  assert.match(c.workshopBookingTeamHtml(entry),/one physical bay/);
  assert.match(c.workshopBookingTeamHtml(entry),/Paul Guiye/);
});
test('team edit blocks duplicate primary/helper, inactive IDs and stale booking versions before sending', async () => {
  for (const kind of ['duplicate','inactive','stale']) {
    const {c,calls}=uiFixture();
    const form={dataset:{workshopBookingId:BOOK,workshopBookingVersion:kind==='stale'?'3':'4'},
      values:{primaryTechnicianId:REN,helperTechnicianIds:[kind==='duplicate'?REN:kind==='inactive'?UUID:PAUL]}};
    assert.equal(await c.saveWorkshopBookingTeam({preventDefault(){},currentTarget:form}),false);assert.equal(calls.length,0,kind);
  }
});
test('helper actual minutes use Perth time and retain exact receipt on an uncertain retry', async () => {
  const {c,state,entry,calls}=uiFixture();let tries=0;
  c.workshopDispatchSharedAction=async(action,payload)=>{calls.push({action,payload});return ++tries===1?{ok:false,error:'no_response'}:{ok:true};};
  const form={dataset:{workshopBookingId:BOOK,workshopBookingVersion:'4'},
    values:{helperTechnicianId:PAUL,helperWorkedAt:'2026-09-23T09:00',helperMinutes:'90',helperNote:'Mechanical training'}};
  assert.equal(await c.saveWorkshopHelperLabour({preventDefault(){},currentTarget:form}),false);
  assert.ok(state.helperLabourPending); entry.sharedVersion=5;
  assert.equal(await c.saveWorkshopHelperLabour({preventDefault(){},currentTarget:form}),true);
  assert.equal(calls[0].action,'recordHelperLabour');assert.equal(calls[0].payload,calls[1].payload);
  assert.equal(calls[0].payload.workedAt,'2026-09-23T01:00:00.000Z');assert.equal(calls[0].payload.minutes,90);
  assert.equal(calls[0].payload.expectedVersion,4);assert.equal(entry.hours,88.28);assert.equal(entry.helperLabourMinutes,0);
  assert.equal(state.helperLabourPending,null);
});
test('unconfirmed helper time cannot be changed or submitted twice while in flight', async () => {
  const {c,state,calls}=uiFixture();
  let release;
  c.workshopDispatchSharedAction=async(action,payload)=>{calls.push({action,payload});return new Promise(resolve=>{release=resolve;});};
  const form={dataset:{workshopBookingId:BOOK,workshopBookingVersion:'4'},
    values:{helperTechnicianId:PAUL,helperWorkedAt:'2026-09-23T09:00',helperMinutes:'90',helperNote:'Training'}};
  const event={preventDefault(){},currentTarget:form};
  const first=c.saveWorkshopHelperLabour(event);
  assert.equal(await c.saveWorkshopHelperLabour(event),false);assert.equal(calls.length,1);
  release({ok:false,error:'request_failed'});await first;
  form.values.helperMinutes='120';
  assert.equal(await c.saveWorkshopHelperLabour(event),false);assert.equal(calls.length,1);assert.ok(state.helperLabourPending);
});
test('compact daily and weekly chips retain primary/helper names and escape them', () => {
  const team='Primary: Ren Karlos · Helpers: Paul <Guiye>';
  for(const render of [compactPlan,compactWeek]){
    const html=render('<article class="workshop-plan-chip" data-booking-id="b" style="top:2%"><button class="workshop-plan-main">old</button></article>',{stock:'12311021',team});
    assert.match(html,/Primary: Ren Karlos/);assert.match(html,/Paul &lt;Guiye&gt;/);assert.match(html,/data-booking-id="b"/);
  }
});
test('readiness action uses requested canonical vehicle and never reverse matches Key412', () => {
  const {c,state,entry}=uiFixture();
  c.displayStockNumber=v=>v.stock;c.workshopDescribeSharedActionError=()=> 'Check accessory parts';
  functions(['workshopRememberReadinessFailure','workshopReadinessFailureHtml'],c);
  assert.equal(c.workshopRememberReadinessFailure({error:'bus_stage_parts_required'},{vehicleId:'412'}),false);
  assert.equal(c.workshopRememberReadinessFailure({error:'bus_stage_parts_required'},{vehicleId:UUID}),true);
  assert.match(c.workshopReadinessFailureHtml('BUS_4X4',[{sharedVehicleId:UUID,stock:'12311021'}],[]),new RegExp('data-bus-workflow-open="'+UUID+'"'));
  assert.equal(c.workshopReadinessFailureHtml('BUS_4X4',[],[]),'');
  assert.equal(c.workshopReadinessFailureHtml('TINT',[],[entry]),'');
});
test('crew conflicts include helpers across bays, while one team remains one booking', () => {
  const c=functions(['workshopTechnicianIdForEntry','workshopEntryTechnicianIds','workshopAssigneeConflict'],{
    cleanNavisionText:v=>String(v||'').trim(),workshopSelectedTechnicianRef:()=>null,
    workshopEntryStart:v=>new Date(v.startAt),workshopEntryEffectiveEnd:v=>new Date(v.endAt),
    workshopIntervalsOverlap:(a,b,c,d)=>a<d&&c<b,
  });
  const a={id:'a',stage:'BUS_4X4',bay:4,status:'planned',technicianId:REN,helperAssignments:[{technicianId:PAUL}],startAt:'2026-09-23T00:00:00Z',endAt:'2026-09-23T03:00:00Z'};
  const b={...a,id:'b',bay:2,technicianId:PAUL,helperAssignments:[]};
  assert.equal(c.workshopAssigneeConflict(a,[a]),null);assert.equal(c.workshopAssigneeConflict(a,[a,b]),b);
  assert.equal(c.workshopAssigneeConflict(a,[{...b,status:'deleted'}]),null);
});
test('verified closure dates skip Dept138 production only, leaving historic ends and other departments unchanged', () => {
  global.parseIsoTimestamp=v=>v?new Date(v):null;
  global.cleanNavisionText=v=>String(v||'').trim();
  const p=require('./workshop-planner.js');
  global.window={__workshopDataService:{getLastSnapshot:()=>({planning_calendar:{verified:true,closures:['2026-09-28']}})}};
  Object.assign(p.WORKSHOP_CONFIG,{dayStartMinutes:360,dayEndMinutes:900,dayLengthMinutes:540,workingDayIndexes:[1,2,3,4,5],closureDateKeys:[],breakWindowsByDateOrScope:[],overtimeWindowsByDateOrScope:[]});
  const date=new Date(2026,8,28,6),bus={stage:'BUS_4X4',bay:4,calendarVehicle:{bus_workflow_department138:true}};
  assert.equal(p.workshopAvailabilityWindowsForDate(date,bus).length,0);
  assert.ok(p.workshopAvailabilityWindowsForDate(date,{...bus,calendarVehicle:{department_codes:['139']}}).length);
  assert.equal(p.workshopAddWorkMinutes(new Date(2026,8,25,14),120,bus).getDate(),29);
  const history={...bus,startAt:new Date(2026,8,25,14).toISOString(),endAt:date.toISOString(),hours:2};
  assert.equal(p.workshopEntryEnd(history).toISOString(),history.endAt);
  delete global.window;
});
test('completed bookings retain historical helpers for late actual-time entry without restoring reservations', async () => {
  const {c,entry,calls}=uiFixture();
  entry.status='completed';entry.busWorkflowDepartment138=true;entry.bay=null;
  entry.actualEndAt='2026-09-23T03:00:00Z';
  entry.helperAssignmentHistory=[...entry.helperAssignments];
  entry.helperAssignments=[];
  assert.match(c.workshopBookingTeamHtml(entry),/Record helper time/);
  assert.doesNotMatch(c.workshopBookingTeamHtml(entry),/>Save team</);
  const form={dataset:{workshopBookingId:BOOK,workshopBookingVersion:'4'},
    values:{helperTechnicianId:PAUL,helperWorkedAt:'2026-09-23T09:00',helperMinutes:'90',helperNote:'Actual training time'}};
  assert.equal(await c.saveWorkshopHelperLabour({preventDefault(){},currentTarget:form}),true);
  assert.equal(calls[0].action,'recordHelperLabour');
  assert.equal(entry.helperAssignments.length,0);
});
test('viewer and fitter profiles cannot submit team changes or helper labour', async () => {
  for(const role of ['viewer','fitter']) {
    const {c,calls}=uiFixture();c.window.PDC_AUTH_CONTEXT.role=role;
    const event={preventDefault(){},currentTarget:{}};
    assert.equal(await c.saveWorkshopBookingTeam(event),false);
    assert.equal(await c.saveWorkshopHelperLabour(event),false);
    assert.equal(calls.length,0);
  }
});
test('previously started queued work accepts historical helper time without recreating its released team', async () => {
  const {c,entry,calls}=uiFixture();
  entry.status='queued';entry.busWorkflowDepartment138=true;entry.bay=0;
  entry.helperAssignmentHistory=[...entry.helperAssignments];entry.helperAssignments=[];
  assert.match(c.workshopBookingTeamHtml(entry),/Record helper time/);
  assert.doesNotMatch(c.workshopBookingTeamHtml(entry),/>Save team</);
  const event={preventDefault(){},currentTarget:{dataset:{workshopBookingId:BOOK,workshopBookingVersion:'4'},
    values:{helperTechnicianId:PAUL,helperWorkedAt:'2026-09-23T09:00',helperMinutes:'90',helperNote:'Work before release'}}};
  assert.equal(await c.saveWorkshopHelperLabour(event),true);
  assert.equal(calls[0].action,'recordHelperLabour');
  assert.equal(await c.saveWorkshopBookingTeam(event),false);
  entry.actualStartAt=null;
  assert.doesNotMatch(c.workshopBookingTeamHtml(entry),/Record helper time/);
  assert.equal(await c.saveWorkshopHelperLabour(event),false);
  assert.equal(calls.length,1);
});
