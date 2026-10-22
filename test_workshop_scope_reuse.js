/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createWorkshopDataService } = require('./workshop-data-service');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const scope = stageCode => ({stageCode,dateFrom:'2026-10-19',dateTo:'2026-10-19'});
function fixture() {
 let token='one',role='operator',time=0,serial=0;
 let revision=1,probe=async()=>({ok:true,body:[{revision}]});
 const calls=[], delivered=[], timers=new Map();
 const client={readRevision:async(...args)=>{calls.push('revision');return probe(...args);},rpc:async(_token,name,p)=>{
  calls.push(name); return {ok:true,status:200,body:name.includes('snapshot') ? {revision,scope:{stage_code:p.p_stage_code,date_from:p.p_date_from,date_to:p.p_date_to},bookings:[{version:revision}]} : {ok:true}};
 }};
 const service=createWorkshopDataService({config:{workshop:{sharedData:true}},scope:scope('FITTING'),client,
  getAccessToken:()=>token,getRole:()=>role,now:()=>time,onSnapshot:(body,reason)=>delivered.push({body,reason}),
  scheduleTimeout:(fn,ms)=>{timers.set(++serial,{fn,ms});return serial;},clearScheduledTimeout:id=>timers.delete(id)});
 return {service,calls,delivered,timers,setProbe:fn=>probe=fn,setRevision:v=>revision=v,setTime:v=>time=v,setToken:v=>token=v,setRole:v=>role=v,
  reads:()=>calls.filter(c=>c.includes('snapshot')).length,
  fire:ms=>{const [id,t]=[...timers].find(([,t])=>t.ms===ms)||[];assert.ok(t);timers.delete(id);t.fn();},
  ready:async()=>{await service.startConnecting();await service.onReconnect();await service.setScope(scope('HOIST'));}};
}
test('return to a station verifies a small revision without downloading its snapshot again',async()=>{
 const f=fixture();await f.ready();const gate=deferred();f.setProbe(()=>gate.promise);
 const returning=f.service.setScope(scope('FITTING'));await tick();
 assert.equal(f.service.getLastSnapshot(),null);assert.equal(f.service.getTrustedSnapshot(),null);
 gate.resolve({ok:true,body:[{revision:1}]});await returning;
 assert.equal(f.reads(),2);assert.equal(f.service.getTrustedSnapshot().scope.stage_code,'FITTING');
 assert.equal(f.delivered.at(-1).reason,'scope_revision_verified');assert.equal(f.timers.size,0);
 f.service.destroy();
});
test('changed revision downloads current bookings once',async()=>{
 const f=fixture();await f.ready();f.setRevision(2);await f.service.setScope(scope('FITTING'));
 assert.equal(f.reads(),3);assert.equal(f.service.getTrustedSnapshot().revision,2);f.service.destroy();
});
for(const response of [{ok:false,status:401},{ok:false,status:403},{ok:true,body:[]},{ok:true,body:[{revision:'invalid'}]}]){
 test('permission or malformed revision cannot restore cached rows '+JSON.stringify(response),async()=>{
  const f=fixture();await f.ready();f.setProbe(async()=>response);await f.service.setScope(scope('FITTING'));
  assert.equal(f.service.getTrustedSnapshot(),null);assert.equal(f.service.getLastSnapshot(),null);assert.equal(f.reads(),2);f.service.destroy();
 });
}
for(const mode of ['logout','role','token','destroy','scope','channel']){
 test('late return check cannot restore superseded '+mode,async()=>{
  const f=fixture();await f.ready();const gate=deferred();f.setProbe(()=>gate.promise);
  const returning=f.service.setScope(scope('FITTING'));await tick();
  if(mode==='logout')f.setToken(null);
  if(mode==='token')f.setToken('two');
  if(mode==='role')f.setRole('viewer');
  if(mode==='destroy')f.service.destroy();
  if(mode==='channel')f.service.onAuthorityLost();
  if(mode==='scope')await f.service.setScope(scope('TYRE'));
  gate.resolve({ok:true,body:[{revision:1}]});await returning;
  if(mode==='scope')assert.equal(f.service.getTrustedSnapshot().scope.stage_code,'TYRE');
  else assert.equal(f.service.getTrustedSnapshot(),null);
  f.service.destroy();assert.equal(f.timers.size,0);
 });
}
test('stalled return probe is bounded and falls back to a full read',async()=>{
 const f=fixture();await f.ready();f.setProbe(()=>new Promise(()=>{}));const returning=f.service.setScope(scope('FITTING'));await tick();
 f.fire(1500);await returning;assert.equal(f.reads(),3);assert.equal(f.service.getTrustedSnapshot().revision,1);assert.equal(f.timers.size,0);f.service.destroy();
});
test('expired scopes and a new authorization token never use retained rows',async()=>{
 for(const mode of ['expired','token']){const f=fixture();await f.ready();if(mode==='expired')f.setTime(90001);else f.setToken('two');
 const before=f.calls.filter(c=>c==='revision').length;await f.service.setScope(scope('FITTING'));assert.equal(f.reads(),3);
 assert.equal(f.calls.filter(c=>c==='revision').length,before);f.service.destroy();}
});
test('revision event arriving during the return check wins over its older answer',async()=>{
 const f=fixture();await f.ready();const gate=deferred();f.setProbe(()=>gate.promise);
 const returning=f.service.setScope(scope('FITTING'));await tick();f.setRevision(2);f.service.onRevisionSignal(2);
 gate.resolve({ok:true,body:[{revision:1}]});await returning;
 assert.equal(f.service.getTrustedSnapshot().revision,2);assert.equal(f.reads(),3);f.service.destroy();
});
test('explicit mutation clears other station reuse and still refreshes after saving',async()=>{
 const f=fixture();await f.ready();await f.service.mutate('move_workshop_booking',{p_booking_id:'test',p_expected_version:1});
 const before=f.reads();await f.service.setScope(scope('FITTING'));assert.equal(f.reads(),before+1);f.service.destroy();
});
test('a completed newer refresh cannot be overwritten by a delayed cached revision',async()=>{
 const f=fixture();await f.ready();const gate=deferred();f.setProbe(()=>gate.promise);
 const returning=f.service.setScope(scope('FITTING'));await tick();f.setRevision(2);await f.service.loadSnapshot('manual_refresh');
 gate.resolve({ok:true,body:[{revision:1}]});await returning;
 assert.equal(f.service.getTrustedSnapshot().revision,2);assert.equal(f.reads(),3);f.service.destroy();
});
