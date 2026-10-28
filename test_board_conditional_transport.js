'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const api = require('./pdc-email-vehicle-location-service');
const reply = (body, status=200) => ({ ok: status>=200 && status<300, status, json: async()=>body });
const fixture = (revision=1, generation='1:first') => ({ok:true,code:'board',snapshot_token:generation,data:{revision,vehicles:[{id:'synthetic',operation_lines:[{estimated_hours:5,source_estimated_hours:2,description:'Synthetic operation'}],qc_operation_lines:[{completed:false,active:true}],parts_flags:{preserve:true},workshop_bookings:[{status:'queued',bay_id:null}]}]}});
function runtime(responses, factory=api.createPdcEmailVehicleLocationService, extra={}) {
  let token='session-A'; const calls=[];
  const service=factory({config:{url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'synthetic-key'},getAccessToken:()=>token,...extra,fetchImpl:async(url,options)=>{
    calls.push({url,options,body:JSON.parse(options.body||'{}')});
    const next=responses.shift(); if(next instanceof Error) throw next;
    return typeof next==='function' ? next(calls.at(-1)) : next;
  }});
  return {service,calls,setToken:value=>{token=value;}};
}
const unchanged=token=>reply({ok:true,code:'not_modified',not_modified:true,snapshot_token:token});

test('conditional board reuses exact payload without changing hours, QC, parts or queued history', async()=>{
  const full=fixture(); const r=runtime([reply(full),unchanged(full.snapshot_token)]);
  const first=await r.service.snapshot();
  assert.match(r.calls[0].url,/get_pdc_email_vehicle_board_snapshot_conditional$/);
  assert.deepEqual(r.calls[0].body,{p_snapshot_token:null,p_accept_delta:true});
  first.data.vehicles[0].operation_lines[0].estimated_hours=999;
  const second=await r.service.snapshot();
  assert.equal(r.calls[1].body.p_snapshot_token,'1:first');
  assert.equal(second.data.vehicles[0].operation_lines[0].estimated_hours,5,'consumer edits cannot corrupt retained server data');
  assert.deepEqual(second,{ok:true,code:'board',data:fixture().data});
});

test('new generation replaces retained board and does not use revision alone',async()=>{
  const r=runtime([reply(fixture()),reply(fixture(1,'1:later')),unchanged('1:later')]);
  await r.service.snapshot(); await r.service.snapshot(); const last=await r.service.snapshot();
  assert.equal(r.calls[2].body.p_snapshot_token,'1:later'); assert.equal(last.data.revision,1);
});

test('changing session or logging out never sends another session snapshot token',async()=>{
  const r=runtime([reply(fixture()),reply(fixture(2,'2:B')),reply(fixture(3,'3:C'))]);
  await r.service.snapshot(); r.setToken('session-B'); await r.service.snapshot();
  assert.equal(r.calls[1].body.p_snapshot_token,null); assert.equal(r.calls[1].options.headers.Authorization,'Bearer session-B');
  r.setToken(null); assert.equal((await r.service.snapshot()).code,'not_authenticated');
  r.setToken('session-B'); await r.service.snapshot(); assert.equal(r.calls[2].body.p_snapshot_token,null);
});

test('missing additive endpoint falls back once and retains legacy compatibility',async()=>{
  const r=runtime([reply({code:'PGRST202'},404),reply({ok:true,data:fixture().data}),reply({ok:true,data:fixture(2).data})]);
  assert.equal((await r.service.snapshot()).data.revision,1);
  assert.match(r.calls[1].url,/\/get_pdc_email_vehicle_board_snapshot$/);
  assert.deepEqual(r.calls[1].body,{});
  assert.equal((await r.service.snapshot()).data.revision,2);
  assert.match(r.calls[2].url,/\/get_pdc_email_vehicle_board_snapshot$/);
});

for(const [label,response] of [
 ['permission denied',reply({ok:false,code:'unauthorized'},403)],
 ['database failure',reply({code:'57014'},500)],
 ['generic not found',reply({code:'not_found'},404)],
 ['network failure',new Error('offline')],
]) test(`conditional transport never falls back after ${label}`,async()=>{
  const r=runtime([reply(fixture()),response,reply(fixture(2,'2:after-error'))]);
  await r.service.snapshot(); const failed=await r.service.snapshot(); assert.equal(failed.ok,false); assert.equal(r.calls.length,2);
  await r.service.snapshot(); assert.equal(r.calls[2].body.p_snapshot_token,null,'failed authority/read clears retained response');
});

test('unexpected or mismatching not-modified replies fail closed',async()=>{
  const r=runtime([unchanged('unknown'),reply(fixture()),unchanged('wrong')]);
  assert.equal((await r.service.snapshot()).code,'snapshot_protocol_error');
  await r.service.snapshot(); assert.equal((await r.service.snapshot()).code,'snapshot_protocol_error');
  assert.equal(r.calls.length,3,'protocol failures are not permission-bypassing retries');
});

test('late responses from a timed-out read cannot replace a newer retained generation',async()=>{
  let finishOld; const timers=[];
  const r=runtime([()=>new Promise(resolve=>{finishOld=resolve;}),reply(fixture(2,'2:new')),unchanged('2:new')],api.createPdcEmailVehicleLocationService,{scheduleTimeout:fn=>{timers.push(fn);return timers.length;},clearScheduledTimeout:()=>{}});
  const old=r.service.snapshot(); timers[0](); assert.equal((await old).code,'snapshot_timeout');
  await r.service.snapshot(); finishOld(reply(fixture(1,'1:old'))); await new Promise(resolve=>setImmediate(resolve));
  const final=await r.service.snapshot(); assert.equal(r.calls[2].body.p_snapshot_token,'2:new'); assert.equal(final.data.revision,2);
});

test('classic browser export runs the same conditional read implementation',async()=>{
  const context={window:{},AbortController,setTimeout,clearTimeout};vm.createContext(context);
  vm.runInContext(fs.readFileSync(require.resolve('./pdc-email-vehicle-location-service'),'utf8'),context);
  const r=runtime([reply(fixture()),unchanged('1:first')],context.window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE.createPdcEmailVehicleLocationService);
  await r.service.snapshot(); const second=await r.service.snapshot();
  assert.deepEqual(JSON.parse(JSON.stringify(second.data)),fixture().data);
});

test('subscription teardown releases the retained snapshot before the next read',async()=>{
  let unsubscribed=0;
  const r=runtime([reply(fixture()),reply(fixture(2,'2:new'))],api.createPdcEmailVehicleLocationService,{subscribeRealtime:()=>({unsubscribe(){unsubscribed+=1;}})});
  const subscription=r.service.subscribe(()=>{}); await r.service.snapshot(); subscription.unsubscribe();
  await r.service.snapshot(); assert.equal(unsubscribed,1); assert.equal(r.calls[1].body.p_snapshot_token,null);
});


test('an old-session network failure cannot clear a newer in-flight conditional read',async()=>{
  let rejectOld,finishCurrent;
  const r=runtime([()=>new Promise((resolve,reject)=>{rejectOld=reject;}),reply(fixture(2,'2:B')),()=>new Promise(resolve=>{finishCurrent=resolve;})]);
  const old=r.service.snapshot(); r.setToken('session-B'); await r.service.snapshot();
  const current=r.service.snapshot(); assert.equal(r.calls[2].body.p_snapshot_token,'2:B');
  rejectOld(new Error('old connection failed')); assert.equal((await old).code,'not_authenticated');
  finishCurrent(unchanged('2:B'));
  assert.equal((await current).data.revision,2);
});
