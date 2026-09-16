'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const {createWorkshopDataService, createWorkshopSupabaseClient, WORKSHOP_CONNECTION_STATE: STATES} = require('./workshop-data-service.js');
const slim = require('./pdc-planner-slim.js');
const scope = {stageCode: 'FITTING', dateFrom: '2026-09-16', dateTo: '2026-09-16'};
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => {resolve=a;reject=b;}); return {promise,resolve,reject}; };
function harness() {
  let token='session-one', role='operator', revision=1, status='planned';
  const rpcCalls=[], probes=[], snapshots=[], states=[], timers=new Map(); let nextTimer=0;
  let read = async () => ({ok:true,status:200,body:[{revision}]});
  let rpc = async () => ({ok:true,status:200,body:{revision,bookings:[{booking_id:'booking-one',status,actual_start_at:status==='started'?'2026-09-16T00:10:00Z':null}]}});
  const service=createWorkshopDataService({config:{workshop:{sharedData:true}},scope,
    getAccessToken:()=>token,getRole:()=>role,onStateChange:value=>states.push(value),onSnapshot:value=>snapshots.push(value),
    scheduleTimeout:(fn,ms)=>{const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearScheduledTimeout:id=>timers.delete(id),
    client:{rpc:async(...args)=>{rpcCalls.push(args);return rpc(...args);},readRevision:async(...args)=>{probes.push(args);return read(...args);}}
  });
  return {service,rpcCalls,probes,snapshots,states,timers,setToken:v=>{token=v;},setRole:v=>{role=v;},
    setRead:v=>{read=v;},setRpc:v=>{rpc=v;},advance:()=>{revision++;status='started';}};
}

test('missing Realtime event is repaired from the scoped revision and canonical started booking',async()=>{
  const h=harness();await h.service.loadSnapshot('initial');h.advance();
  await h.service.reconcileRevision('visible_planner_revision');
  assert.equal(h.rpcCalls.length,2);assert.equal(h.probes.length,1);
  assert.deepEqual(h.probes[0].slice(0,2),['session-one',scope]);
  assert.equal(h.service.getTrustedSnapshot().bookings[0].status,'started');
  assert.equal(h.service.getTrustedSnapshot().bookings[0].actual_start_at,'2026-09-16T00:10:00Z');
  assert.equal(h.service.getLastRevision(),2);
});

test('unchanged revision checks neither fetch snapshots nor repaint nor interrupt editing',async()=>{
  const h=harness();await h.service.loadSnapshot('initial');const before=h.states.length;
  for(let i=0;i<12;i++) await h.service.reconcileRevision();
  assert.equal(h.probes.length,12);assert.equal(h.rpcCalls.length,1);assert.equal(h.snapshots.length,1);
  assert.equal(h.states.length,before);assert.equal(h.service.getState(),STATES.CONNECTED_EDITABLE);
  assert.equal(h.timers.size,0);
});

test('simultaneous focus and timer probes coalesce into one request',async()=>{
  const h=harness();await h.service.loadSnapshot();const pending=deferred();h.setRead(()=>pending.promise);
  const first=h.service.reconcileRevision(),second=h.service.reconcileRevision();
  assert.equal(first,second);assert.equal(h.probes.length,1);
  pending.resolve({ok:true,status:200,body:[{revision:'1'}]});await first;
  assert.equal(h.rpcCalls.length,1);assert.equal(h.timers.size,0);
});

test('routine probe does not schedule another full load during an in-flight snapshot',async()=>{
  const h=harness(), pending=deferred();h.setRpc(()=>pending.promise);
  const first=h.service.loadSnapshot();await h.service.reconcileRevision();
  assert.equal(h.probes.length,0);pending.resolve({ok:true,body:{revision:1,bookings:[]}});await first;
  assert.equal(h.rpcCalls.length,1);
});

test('Realtime change arriving during a probe uses its existing debounce, without a duplicate fetch',async()=>{
  const h=harness();await h.service.loadSnapshot();const pending=deferred();h.setRead(()=>pending.promise);
  const first=h.service.reconcileRevision();h.service.onRevisionSignal(2);
  pending.resolve({ok:true,status:200,body:[{revision:2}]});await first;
  assert.equal(h.rpcCalls.length,1);assert.equal(h.timers.size,1);
  h.advance();[...h.timers.values()][0].fn();await new Promise(resolve=>setImmediate(resolve));
  assert.equal(h.rpcCalls.length,2);assert.equal(h.service.getLastSnapshot().bookings[0].status,'started');
});

test('permission denial purges retained booking authority',async()=>{
  for(const status of [401,403]) {
    const h=harness();await h.service.loadSnapshot();h.setRead(async()=>({ok:false,status}));
    await h.service.reconcileRevision();assert.equal(h.service.getLastSnapshot(),null);
    assert.equal(h.service.getTrustedSnapshot(),null);assert.equal(h.service.getState(),STATES.PERMISSION_DENIED);
  }
});

test('empty RLS and malformed revision results are not accepted as freshness',async()=>{
  for(const body of [[],null,[{revision:null}],[{revision:'bad'}],[{revision:1},{revision:2}]]) {
    const h=harness();await h.service.loadSnapshot();h.setRead(async()=>({ok:true,status:200,body}));
    await h.service.reconcileRevision();assert.equal(h.service.getTrustedSnapshot(),null);
    assert.equal(h.service.getState(),STATES.OFFLINE_READ_ONLY);assert.equal(h.rpcCalls.length,1);
  }
});

test('network failure fails closed and a successful probe restores trust with a fresh snapshot',async()=>{
  const h=harness();await h.service.loadSnapshot();h.setRead(async()=>{throw Error('offline');});
  await h.service.reconcileRevision();assert.equal(h.service.getTrustedSnapshot(),null);
  assert.equal(h.service.getState(),STATES.OFFLINE_READ_ONLY);
  h.setRead(async()=>({ok:true,status:200,body:[{revision:1}]}));await h.service.reconcileRevision();
  assert.equal(h.rpcCalls.length,2);assert.ok(h.service.getTrustedSnapshot());
});

test('sign-out, changed token and changed role cannot accept a late revision probe',async()=>{
  for(const change of [h=>h.setToken(null),h=>h.setToken('new-session'),h=>h.setRole('viewer')]) {
    const h=harness();await h.service.loadSnapshot();const pending=deferred();h.setRead(()=>pending.promise);
    const first=h.service.reconcileRevision();change(h);pending.resolve({ok:true,status:200,body:[{revision:2}]});
    assert.equal(await first,null);assert.equal(h.service.getLastSnapshot(),null);assert.equal(h.rpcCalls.length,1);
  }
});

test('scope replacement and destruction abort and discard earlier revision probes',async()=>{
  for(const mode of ['scope','destroy','authority']) {
    const h=harness();await h.service.loadSnapshot();const pending=deferred();h.setRead(()=>pending.promise);
    const first=h.service.reconcileRevision(), signal=h.probes[0][2].signal;
    if(mode==='scope')await h.service.setScope({...scope,stageCode:'HOIST'});
    else if(mode==='destroy')h.service.destroy();else h.service.onAuthorityLost();
    assert.equal(signal.aborted,true);pending.resolve({ok:true,status:200,body:[{revision:99}]});
    assert.equal(await first,null);assert.notEqual(h.service.getLastRevision(),99);assert.equal(h.timers.size,0);
  }
});

test('revision requests have a bounded timeout and recover on the next probe',async()=>{
  const h=harness();await h.service.loadSnapshot();
  h.setRead((_token,_scope,{signal})=>new Promise((_resolve,reject)=>signal.addEventListener('abort',()=>reject(Error('aborted')))));
  const first=h.service.reconcileRevision();const timer=[...h.timers.values()][0];assert.equal(timer.ms,8000);timer.fn();
  await first;assert.equal(h.service.getState(),STATES.OFFLINE_READ_ONLY);assert.equal(h.timers.size,0);
  h.setRead(async()=>({ok:true,body:[{revision:1}]}));await h.service.reconcileRevision();assert.ok(h.service.getTrustedSnapshot());
});

test('late full snapshot cannot switch back to a previous login session',async()=>{
  const h=harness(), pending=deferred();h.setRpc(()=>pending.promise);
  const first=h.service.loadSnapshot();h.setToken('new-session');pending.resolve({ok:true,body:{revision:1,bookings:[]}});
  assert.equal(await first,null);assert.equal(h.service.getLastSnapshot(),null);assert.equal(h.snapshots.length,0);
});

test('revision client uses authenticated no-store stage/global reads and rejects missing identity',async()=>{
  const calls=[],client=createWorkshopSupabaseClient({url:'https://example.test',publishableKey:'public-key'},async(...args)=>{
    calls.push(args);return {ok:true,status:200,json:async()=>[{revision:12}]};
  });
  const controller=new AbortController();await client.readRevision('user-token',scope,{signal:controller.signal});
  await client.readRevision('user-token',null);await client.readRevision(null,scope);
  await client.readRevision('user-token',{stageCode:'FITTING&select=*'});
  assert.equal(calls.length,2);
  assert.equal(calls[0][0],'https://example.test/rest/v1/workshop_station_revision?select=revision&stage_code=eq.FITTING&limit=1');
  assert.match(calls[1][0],/workshop_revision\?select=revision&id=eq\.1&limit=1$/);
  assert.equal(calls[0][1].headers.Authorization,'Bearer user-token');assert.equal(calls[0][1].cache,'no-store');
  assert.equal(calls[0][1].signal,controller.signal);
});

function eventTarget() {
  const listeners=new Map();
  return {listeners,addEventListener:(name,fn)=>{if(!listeners.has(name))listeners.set(name,new Set());listeners.get(name).add(fn);},
    removeEventListener:(name,fn)=>listeners.get(name)?.delete(fn),emit:(name,data={})=>[...(listeners.get(name)||[])].forEach(fn=>fn(data))};
}
function appHarness() {
  const source=fs.readFileSync('./app.js','utf8'),window=eventTarget(),document=eventTarget(),timers=new Map(),channels=[];
  let token='signed-in',sequence=0;const refreshes=[],probes=[],overview=[];
  window.setTimeout=(fn,ms)=>{const id=++sequence;timers.set(id,{fn,ms,interval:false});return id;};
  window.setInterval=(fn,ms)=>{const id=++sequence;timers.set(id,{fn,ms,interval:true});return id;};
  window.clearTimeout=window.clearInterval=id=>timers.delete(id);
  window.PDC_SUPABASE_CONFIG={url:'https://staging.example.test'};document.visibilityState='visible';
  window.__workshopDataService={onRevisionSignal:()=>refreshes.push('signal'),reconcileRevision:reason=>probes.push(reason),onVisibilityReturn:()=>refreshes.push('visibility')};
  window.BroadcastChannel=class {constructor(name){this.name=name;this.sent=[];channels.push(this);}postMessage(data){this.sent.push(data);}close(){this.closed=true;}};
  const app={currentView:'workshop',workshopEligibilityState:'connected'};
  const context=vm.createContext({window,document,app,getPdcSupabaseAccessToken:()=>token,loadWorkshopEligibilitySnapshot:reason=>overview.push(reason)});
  for(const name of ['installWorkshopRecoveryListeners','removeWorkshopRecoveryListeners','installFitterWorkshopRefreshBridge']) {
    const start=source.indexOf(`function ${name}(`),end=source.indexOf('\nfunction ',start+1);
    vm.runInContext(source.slice(start,end),context);
  }
  return {window,document,app,timers,channels,refreshes,probes,overview,context,setToken:value=>{token=value;},
    flush:()=>{for(const[id,timer]of [...timers])if(!timer.interval){timers.delete(id);timer.fn();}}};
}

test('visible planner has one lightweight recovery timer; hidden/other routes do no work and teardown removes it',()=>{
  const h=appHarness();h.context.installWorkshopRecoveryListeners();h.context.installWorkshopRecoveryListeners();
  assert.equal(h.timers.size,1);const timer=[...h.timers.values()][0];assert.equal(timer.ms,10000);
  timer.fn();assert.equal(h.probes.length,1);assert.equal(h.refreshes.length,0);
  h.document.visibilityState='hidden';timer.fn();h.window.emit('focus');assert.equal(h.probes.length,1);
  h.document.visibilityState='visible';h.app.currentView='fitters';timer.fn();assert.equal(h.probes.length,1);
  h.app.currentView='workshop';h.window.emit('focus');assert.equal(h.probes.length,2);
  h.context.removeWorkshopRecoveryListeners();assert.equal(h.timers.size,0);
  h.window.emit('focus');assert.equal(h.probes.length,2);assert.equal(h.document.listeners.get('visibilitychange').size,0);
});

test('confirmed fitter writes coalesce and broadcast only an invalidation signal, without trusting payload rows',()=>{
  const h=appHarness();h.context.installFitterWorkshopRefreshBridge();h.context.installFitterWorkshopRefreshBridge();
  assert.equal(h.channels.length,1);
  for(let i=0;i<3;i++)h.window.emit('pdc-fitter-workshop-saved',{detail:{bookingId:'foreign',stageCode:'TYRE',status:'completed'}});
  h.flush();assert.deepEqual(h.refreshes,['signal']);
  assert.equal(h.channels[0].name,'pdc-workshop-saved:https://staging.example.test');
  assert.equal(JSON.stringify(h.channels[0].sent[0]),JSON.stringify({type:'fitter-workshop-saved'}));
});

test('cross-tab invalidation refreshes only the visible authorized board and never rebroadcasts',()=>{
  const h=appHarness();h.context.installFitterWorkshopRefreshBridge();const channel=h.channels[0];
  channel.onmessage({data:{type:'fitter-workshop-saved'}});h.flush();assert.equal(h.refreshes.length,1);assert.equal(channel.sent.length,0);
  h.document.visibilityState='hidden';channel.onmessage({data:{type:'fitter-workshop-saved'}});h.flush();assert.equal(h.refreshes.length,1);
  h.document.visibilityState='visible';h.setToken(null);channel.onmessage({data:{type:'fitter-workshop-saved'}});h.flush();
  h.window.emit('pdc-fitter-workshop-saved');h.flush();assert.equal(h.refreshes.length,1);assert.equal(channel.sent.length,0);
});

test('confirmed fitter event refreshes the all-bay overview and preserves its in-flight coalescing',()=>{
  const h=appHarness();h.context.installFitterWorkshopRefreshBridge();h.app.currentView='workflow';
  h.window.emit('pdc-fitter-workshop-saved');h.flush();assert.deepEqual(h.overview,['confirmed_fitter_write']);
  h.app.workshopEligibilityState='loading';h.window.emit('pdc-fitter-workshop-saved');h.flush();
  assert.equal(h.overview.length,1);assert.equal(h.app.workshopEligibilityRevisionPending,true);
});

test('page lifecycle closes and restores the cross-tab bridge and cleanup removes listeners/timers',()=>{
  const h=appHarness();h.context.installFitterWorkshopRefreshBridge();h.window.emit('pdc-fitter-workshop-saved');
  h.window.emit('pagehide');assert.equal(h.channels[0].closed,true);assert.equal(h.timers.size,0);
  h.window.emit('pageshow');assert.equal(h.channels.length,2);
  h.window.__fitterWorkshopRefreshBridgeCleanup();assert.equal(h.channels[1].closed,true);
  h.window.emit('pdc-fitter-workshop-saved');assert.equal(h.timers.size,0);
  assert.equal(h.window.listeners.get('pdc-fitter-workshop-saved').size,0);
});

test('compact running and stopped labels stay in the existing first line and preserve planner controls/progress',()=>{
  const html='<article class="workshop-plan is-started" title="Old" style="height:84px"><button class="workshop-plan-main">Old summary</button><span class="workshop-fitter-progress">10%</span><button data-stop>STOPPAGE</button></article>';
  for(const [status,label]of [['started','Running'],['stoppage','Stopped']]) {
    const output=slim.compactPlan(html,{key:'12',stock:'123',jc:'J123',customer:'Test',model:'Hilux',status});
    assert.match(output,new RegExp(`<strong><span class="planner-work-state">${label} · </span>Key 12`));
    assert.match(output,/height:84px/);assert.match(output,/<span class="workshop-fitter-progress">10%<\/span><button data-stop>STOPPAGE<\/button>/);
    assert.match(output,new RegExp(`title="${label} · Key 12`));
  }
  assert.doesNotMatch(slim.summaryHtml({status:'planned'}),/planner-work-state/);
  assert.match(slim.compactWeek('<article class="week" title="Old">Old</article>',{status:'started'}),/Running ·/);
});
