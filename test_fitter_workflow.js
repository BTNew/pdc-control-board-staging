'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createService,progressHtml,esc}=require('./pdc-fitters.js');
function fixture(fetch) {
  let context={actor:'staff-a',token:'test-session',role:'operator',config:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test-only',workshop:{sharedData:true}}};
  let seq=0;
  return {service:createService({context:()=>context,fetch,uuid:()=>`request-${++seq}`,timeoutMs:100}),setContext:c=>{context={...context,...c};}};
}
const reply=body=>({ok:true,json:async()=>body});
test('fitter RPC targets the existing authenticated staging project',async()=>{
  const calls=[];const {service}=fixture(async(url,options)=>{calls.push({url,options});return reply({ok:true,jobs:[]});});
  await service.jobs('mechanic-a');
  assert.equal(calls[0].url,'https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/get_fitter_jobs');
  assert.equal(calls[0].options.headers.Authorization,'Bearer test-session');
  assert.deepEqual(JSON.parse(calls[0].options.body),{p_technician_id:'mechanic-a'});
});
test('viewer, missing auth and wrong project cannot write',async()=>{
  for(const change of [{role:'viewer'},{token:''},{actor:''},{config:{projectRef:'wrong'}}]){
    let called=false;const f=fixture(async()=>{called=true;return reply({ok:true});});f.setContext(change);
    await assert.rejects(f.service.command({p_action:'start'}));assert.equal(called,false);
  }
});
test('rapid duplicate commands are blocked while a save is pending',async()=>{
  let release;const f=fixture(()=>new Promise(resolve=>release=resolve));
  const first=f.service.command({p_action:'line'});
  await assert.rejects(f.service.command({p_action:'line'}),e=>e.code==='busy');
  release(reply({ok:true}));await first;assert.equal(f.service.busy,false);
});
test('uncertain save retries the exact same idempotency key and payload',async()=>{
  const bodies=[];const f=fixture(async(_,o)=>{bodies.push(o.body);if(bodies.length===1)throw Error('offline');return reply({ok:true,replayed:true});});
  await assert.rejects(f.service.command({p_action:'line',p_note:'Bracket fitted'}),e=>e.code==='unconfirmed');
  assert.equal(f.service.retryPending,true);
  await assert.rejects(f.service.command({p_action:'complete'}),e=>e.code==='unconfirmed');
  const r=await f.service.retry();assert.equal(r.replayed,true);assert.equal(bodies[0],bodies[1]);assert.equal(f.service.retryPending,false);
});
test('session changes discard late responses and never replay under another actor',async()=>{
  let release;const f=fixture(()=>new Promise(resolve=>release=resolve));const pending=f.service.command({p_action:'start'});
  f.setContext({actor:'staff-b',token:'other-session'});release(reply({ok:true}));
  await assert.rejects(pending,e=>e.code==='session_changed');assert.equal(f.service.retryPending,false);
});
test('server conflicts remain errors and are not mistaken for successful progress',async()=>{
  const f=fixture(async()=>reply({ok:false,error:'version_conflict'}));
  await assert.rejects(f.service.command({p_action:'line'}),e=>e.code==='version_conflict');assert.equal(f.service.retryPending,false);
});
test('progress is clamped and accessible without making pills taller',()=>{
  assert.match(progressHtml({percent:30,total_hours:10,completed_hours:3}),/aria-valuenow="30"/);
  assert.match(progressHtml({percent:1000},true),/width:100%/);
  assert.match(progressHtml(null,true),/aria-valuenow="0"/);
  assert.match(progressHtml({percent:30},true),/is-compact/);
  assert.equal(esc('<img src=x onerror=alert(1)>'),'&lt;img src=x onerror=alert(1)&gt;');
});
test('timeout keeps a retry receipt rather than guessing whether the write committed',async()=>{
  const f=fixture(()=>new Promise(()=>{}));
  await assert.rejects(f.service.command({p_action:'start'}),e=>e.code==='unconfirmed');assert.equal(f.service.retryPending,true);
  f.service.invalidate();assert.equal(f.service.retryPending,false);
});
