'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createService,planningHints,addWeekdays,fromLocalDate,localDate,panelHtml,supplierHtml}=require('./pdc-bus-workflow.js');
const vehicle='a3333333-aaaa-4444-bbbb-111111111111';
const booking='b3333333-aaaa-4444-bbbb-111111111111';
const technician='c3333333-aaaa-4444-bbbb-111111111111';
function fixture(request,extra={}) {
  let c={actor:'actor-a',token:'session-a',role:'operator',config:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test-only',workshop:{sharedData:true}}};
  let n=0;
  return {service:createService({context:()=>c,request,uuid:()=>`request-${++n}`,timeoutMs:250,...extra}),change:next=>{c={...c,...next};}};
}
const ok=body=>({ok:true,status:200,body:{ok:true,...body}});
const snapshot=()=>({ok:true,vehicle_id:vehicle,version:0,supplier_lines:[],forecasts:{},bookings:[]});
const line={line_identity:'source:operation-1',scope_hash:'snapshot-hash',description:'MMT seat covers <script>alert(1)</script>',status:'vendor_completed',supplier_phase:'early',stage_code:'BUS_4X4',source_hours:0.01,version:2};

test('read requires exact vehicle identity and authoritative version',async()=>{
  const f=fixture(async(name,params)=>{assert.equal(name,'get_pdc_bus_workflow');assert.deepEqual(params,{p_vehicle_id:vehicle});return ok(snapshot());});
  assert.equal((await f.service.read(vehicle)).version,0);
  const wrong=fixture(async()=>ok({...snapshot(),vehicle_id:booking}));
  await assert.rejects(wrong.service.read(vehicle),e=>e.code==='invalid_response');
});
test('planner writes are blocked for fitter/viewer, missing sign-in, wrong project and disabled shared mode',async()=>{
  for(const c of [{role:'fitter'},{role:'viewer'},{token:''},{actor:''},{config:{projectRef:'different'}},{config:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',workshop:{sharedData:false}}}]){
    let called=false;const f=fixture(async()=>{called=true;return ok({});});f.change(c);
    await assert.rejects(f.service.save(vehicle,0,{current_stage:'yard'}),e=>e.code==='session_changed');assert.equal(called,false);
  }
});
test('physical verification requires exact booking and technician; fitter cannot record vendor assertions',async()=>{
  const calls=[],f=fixture(async(name,params)=>{calls.push({name,params});return ok({});});f.change({role:'fitter'});
  const change={vehicleId:vehicle,lineIdentity:line.line_identity,scopeHash:line.scope_hash,expectedVersion:2,status:'technician_verified',note:'Both rows physically checked',bookingId:booking,technicianId:technician};
  await assert.rejects(f.service.supplier({...change,bookingId:''}),e=>e.code==='supplier_verification_required');
  await f.service.supplier(change);
  assert.equal(calls[0].name,'set_pdc_bus_supplier_status');assert.equal(calls[0].params.p_expected_version,2);assert.equal(calls[0].params.p_booking_id,booking);
  await assert.rejects(f.service.supplier({...change,status:'vendor_completed'}),e=>e.code==='session_changed');assert.equal(calls.length,1);
});
test('uncertain save locks later writes and retries immutable payload with identical request ID',async()=>{
  const calls=[],f=fixture(async(name,params)=>{calls.push(JSON.stringify({name,params}));if(calls.length===1)throw Error('network interrupted');return ok({replayed:true});});
  const patch={forecasts:{vehicle_ready:'2026-09-25T00:00:00Z'}};
  await assert.rejects(f.service.save(vehicle,0,patch),e=>e.code==='unconfirmed');
  patch.forecasts.vehicle_ready='2027-01-01T00:00:00Z';
  assert.equal(f.service.retryPending,true);
  await assert.rejects(f.service.save(vehicle,0,{current_stage:'mechanical'}),e=>e.code==='unconfirmed');
  assert.equal((await f.service.retry()).replayed,true);assert.equal(calls[0],calls[1]);assert.equal(f.service.retryPending,false);
});
test('HTTP 500 is an uncertain write and known rejected versions are not retried',async()=>{
  const fail=fixture(async()=>({ok:false,status:500,body:{}}));await assert.rejects(fail.service.save(vehicle,0,{}),e=>e.code==='unconfirmed');assert.equal(fail.service.retryPending,true);
  const conflict=fixture(async()=>ok({ok:false,error:'stale_workflow'}));await assert.rejects(conflict.service.save(vehicle,0,{}),e=>e.code==='stale_workflow');assert.equal(conflict.service.retryPending,false);
});
test('session change invalidates late result and cannot retry under another actor',async()=>{
  let release;const f=fixture(()=>new Promise(resolve=>release=resolve));const pending=f.service.save(vehicle,0,{current_stage:'mechanical'});
  f.change({actor:'actor-b',token:'session-b'});release(ok({version:1}));
  await assert.rejects(pending,e=>e.code==='session_changed');assert.equal(f.service.retryPending,false);
});
test('one in-flight write at a time; explicit invalidation makes read inert',async()=>{
  let release;const f=fixture(()=>new Promise(resolve=>release=resolve));const first=f.service.save(vehicle,0,{});
  await assert.rejects(f.service.save(vehicle,0,{}),e=>e.code==='busy');release(ok({}));await first;
  const read=f.service.read(vehicle);f.service.invalidate();release(ok(snapshot()));await assert.rejects(read,e=>e.code==='session_changed');
});
test('Perth dates round-trip and impossible dates are rejected',()=>{
  assert.equal(fromLocalDate('2026-09-21T06:00'),'2026-09-20T22:00:00.000Z');
  assert.equal(localDate('2026-09-20T22:00:00Z'),'2026-09-21T06:00');
  assert.equal(fromLocalDate(''),null);
  assert.throws(()=>fromLocalDate('2026-02-30T06:00'));
});
test('two-to-three-day advisory skips weekends without inventing dates when progress unknown',()=>{
  assert.equal(addWeekdays('2026-09-18T07:00:00Z',2),'2026-09-22T07:00:00.000Z');
  assert.equal(addWeekdays('2026-09-18T07:00:00Z',3),'2026-09-23T07:00:00.000Z');
  assert.equal(addWeekdays(null,2),null);
  const hints=planningHints({forecasts:{}});assert(hints.some(h=>h.code==='mechanical_forecast'));assert(hints.some(h=>h.code==='ready_forecast'));assert(!hints.some(h=>h.code==='buffer'));
});
test('pit notice distinguishes required from requested and booked and flags delivery risks',()=>{
  const now=Date.parse('2026-09-21T00:00:00Z'),ready=new Date(now+60*3600000).toISOString();
  let hints=planningHints({forecasts:{vehicle_ready:ready},pit_status:'required'},now);
  assert.equal(hints.find(h=>h.code==='pit_notice').tone,'review');
  for(const status of ['requested','booked','passed','not_required'])assert(!planningHints({forecasts:{vehicle_ready:ready},pit_status:status},now).some(h=>h.code==='pit_notice'));
  hints=planningHints({forecasts:{vehicle_ready:ready,delivery:'2026-09-21T12:00:00Z'},downstream_review_required:true},now);
  assert(hints.some(h=>h.code==='delivery_risk'));assert(hints.some(h=>h.code==='downstream_review'));
});
test('supplier controls preserve source evidence and only explicit physical confirmation closes work',()=>{
  let html=supplierHtml([line],{vehicleId:vehicle,editable:true,controller:false,bookingId:booking,technicianId:technician});
  assert.match(html,/Internal labour: 0 h \(source: 0.01 h retained\)/);assert.match(html,/physical_check/);assert.match(html,/Confirm physical check/);assert.doesNotMatch(html,/<script>/);assert.doesNotMatch(html,/<select name="status"/);
  html=supplierHtml([line],{vehicleId:vehicle,editable:true,controller:true});assert.match(html,/Save supplier progress/);assert.doesNotMatch(html,/data-bus-supplier-verify/);
  html=supplierHtml([{...line,status:'technician_verified'}],{vehicleId:vehicle,editable:true,controller:true,bookingId:booking,technicianId:technician});assert.doesNotMatch(html,/Save supplier progress|data-bus-supplier-verify/);assert.match(html,/Physically verified/);
});
test('controller plan keeps unknown parts distinct, no booking side-effects and no direct RFT release',()=>{
  const html=panelHtml(snapshot(),{identity:'Stock <bad>',editable:true});
  assert.match(html,/Stock &lt;bad&gt;/);assert.match(html,/Needs checking/);assert.match(html,/Confirmed available for this stage/);assert.match(html,/ready_for_qc_check/);assert.doesNotMatch(html,/value="technician_verified"/);assert.match(html,/creates no booking/);assert.match(html,/does not certify release/);
  assert.match(panelHtml(snapshot(),{editable:true,stale:true}),/data-bus-plan-form[\s\S]*<select name="current_stage" disabled/);
});
