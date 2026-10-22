/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm');
const {createWorkshopDataService} = require('./workshop-data-service');
const {createWorkshopRealtimeManager} = require('./workshop-realtime');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return {promise,resolve}; };
function fixture() {
  const reads=[], probes=[], sockets=[], timers=new Map(); let nextTimer=0, token='session', role='operator', revision=1;
  const rows=(stage,rev=revision)=>({ok:true,status:200,body:{revision:rev,scope:{stage_code:stage},bookings:[{id:stage,version:rev}]}});
  let response=stage=>Promise.resolve(rows(stage));
  const client={rpc:async(t,name,params,options)=>{
    reads.push({token:t,name,stage:params.p_stage_code,date:params.p_date_from,signal:options?.signal});
    return response(params.p_stage_code);
  },readRevision:async(t,scope)=>{probes.push(scope.stageCode);return {ok:true,body:[{revision}]};}};
  const config={workshop:{sharedData:true}}, root={replaceChildren(){},querySelector(){return {innerHTML:''};}};
  const context={window:{PDC_SUPABASE_CONFIG:config,PDC_AUTH_CONTEXT:{get role(){return role;}}},
    app:{currentView:'workshop',activeWorkshopPlannerStage:'HOIST'},OPERATIONAL_REFRESH_ROUTES:['workshop'],
    document:{getElementById:()=>root},workshopSharedModeEnabled:()=>true,
    workshopApplyOpenDateDefault(){},workshopState:()=>({date:'2026-10-19'}),
    normalizePmbStage:v=>v,cleanNavisionText:v=>String(v),getPdcSupabaseAccessToken:()=>token,
    createWorkshopSupabaseClient:()=>client,
    createWorkshopDataService:options=>createWorkshopDataService({...options,
      scheduleTimeout:(fn,ms)=>{const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearScheduledTimeout:id=>timers.delete(id)}),
    createWorkshopRealtimeManager:options=>createWorkshopRealtimeManager({...options,
      scheduleTimeout:(fn,ms)=>{const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearScheduledTimeout:id=>timers.delete(id)}),
    createPdcSupabaseRealtimeSubscription:(_config,handlers,scope)=>{const socket={handlers,scope,closed:false};sockets.push(socket);return {requiresSubscribedStatus:true,unsubscribe(){socket.closed=true;}};},
    scheduleWorkshopPlannerRender(){},cancelWorkshopPlannerRender(){},installWorkshopRecoveryListeners(){},removeWorkshopRecoveryListeners(){},buildWorkshopSharedActions:service=>({service})};
  const source=fs.readFileSync(require.resolve('./app.js'),'utf8');vm.createContext(context);
  for(const [start,end] of [['function initWorkshopSharedServicesIfEnabled()', '// Lazily constructs the vehicle-lifecycle'],['function teardownWorkshopPlannerScope(options)', 'function showView(view, options)']])
    vm.runInContext(source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start))),context);
  const init=()=>context.initWorkshopSharedServicesIfEnabled();
  return {context,reads,probes,sockets,timers,rows,init,service:()=>context.window.__workshopDataService,
    async open(){init();sockets[0].handlers.onSubscribed();await tick();await tick();},
    switch(stage){context.teardownWorkshopPlannerScope({preserveShell:true,preserveConnection:true});context.app.activeWorkshopPlannerStage=stage;init();},
    setResponse:fn=>{response=fn;},setToken:v=>{token=v;},setRole:v=>{role=v;},setRevision:v=>{revision=v;},
    close(){context.teardownWorkshopPlannerScope();},
    fire(ms){const entry=[...timers].find(([,timer])=>timer.ms===ms);assert.ok(entry);timers.delete(entry[0]);entry[1].fn();}};
}

test('three planners share one connection and use one fresh snapshot per destination',async()=>{
  const f=fixture();await f.open();const service=f.service();
  assert.equal(service.getState(),'connected_editable');
  for(const stage of ['FITTING','TINT']) {
    const gate=deferred();f.setResponse(()=>gate.promise);f.switch(stage);
    assert.equal(f.service(),service);assert.equal(service.getLastSnapshot(),null);
    assert.equal(service.getTrustedSnapshot(),null);assert.equal(service.isEnabled(),true);
    assert.equal(service.getState(),'connecting');
    gate.resolve(f.rows(stage));await tick();
    assert.equal(service.getTrustedSnapshot().scope.stage_code,stage);
  }
  assert.equal(f.sockets.length,1);assert.equal(f.sockets[0].scope.allStations,true);
  assert.deepEqual(f.probes,['HOIST']);assert.deepEqual(f.reads.map(r=>r.stage),['HOIST','FITTING','TINT']);
  f.init();await tick();assert.equal(f.reads.length,3,'rerender/category changes do not redownload');
  f.close();assert.equal(f.sockets[0].closed,true);assert.equal(service.getTrustedSnapshot(),null);assert.equal(f.timers.size,0);
});

test('late station responses cannot overwrite a rapid second switch',async()=>{
  const f=fixture();await f.open();const old=deferred();f.setResponse(()=>old.promise);f.switch('FITTING');
  f.setResponse(stage=>Promise.resolve(f.rows(stage,3)));f.switch('TINT');await tick();
  old.resolve(f.rows('FITTING',2));await tick();
  assert.equal(f.reads[1].signal.aborted,true);assert.equal(f.service().getTrustedSnapshot().scope.stage_code,'TINT');
  assert.equal(f.service().getLastRevision(),3);f.close();
});

test('revision events reload only the currently selected station',async()=>{
  const f=fixture();await f.open();f.switch('TINT');await tick();
  const count=f.reads.length;
  f.sockets[0].handlers.onChange({new:{stage_code:'HOIST',revision:9}});await tick();assert.equal(f.reads.length,count);assert.equal(f.timers.size,0);
  f.setRevision(2);f.sockets[0].handlers.onChange({new:{stage_code:'TINT',revision:2}});
  assert.equal(f.service().getTrustedSnapshot(),null);f.fire(250);await tick();
  assert.equal(f.reads.length,count+1);assert.equal(f.service().getLastRevision(),2);f.close();
});

test('switching during a lost connection stays locked until subscription and revision reconciliation',async()=>{
  const f=fixture();await f.open();f.sockets[0].handlers.onError();f.switch('TINT');await tick();
  assert.equal(f.service().getTrustedSnapshot(),null);assert.equal(f.service().getLastSnapshot(),null);
  assert.notEqual(f.service().getState(),'connected_editable');f.fire(1000);f.sockets[1].handlers.onSubscribed();await tick();await tick();
  assert.equal(f.service().getTrustedSnapshot().scope.stage_code,'TINT');assert.equal(f.service().getState(),'connected_editable');f.close();
});

for(const failure of ['logout','role','denied','network']) test('station switch fails closed after '+failure,async()=>{
  const f=fixture();await f.open();const gate=deferred();f.setResponse(()=>gate.promise);f.switch('TINT');
  if(failure==='logout') f.setToken(null);
  if(failure==='role') f.setRole('viewer');
  gate.resolve(failure==='denied'?{ok:false,status:403}:failure==='network'?{ok:false,status:503}:f.rows('TINT'));
  await tick();assert.equal(f.service().getTrustedSnapshot(),null);assert.notEqual(f.service().getState(),'connected_editable');f.close();
});
