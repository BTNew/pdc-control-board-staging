'use strict';
const assert=require('node:assert/strict');
const test=require('node:test');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const snapshot=(revision=1)=>({stages:[{code:'FITTING',revision},{code:'TINT',revision:3}],candidates:[],board:{bookings:[{booking_id:'b',status:revision>1?'started':'planned'}],bays:[]}});
const response=body=>({ok:true,status:200,json:async()=>body});
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function harness(){
  let token='session-one',fetcher,sequence=0,clock=Date.parse('2026-09-16T04:00:00Z'),blocked=null;
  const calls=[],renders=[],timers=new Map(),listeners=new Map();
  const app={currentView:'workflow',workshopEligibilityState:'connected',workshopEligibilitySnapshot:snapshot(),workshopEligibilityRequestGeneration:0,workshopEligibilityRevisionPending:false,
    workshopEligibilityRealtime:{subscribed:true,unsubscribe(){this.closed=true;}}};
  const win={PDC_SUPABASE_CONFIG:{url:'https://staging.example.test',publishableKey:'public-key',workshop:{sharedData:true}},PDC_AUTH_CONTEXT:{role:'operator'},
    setTimeout:(fn,ms)=>{const id=++sequence;timers.set(id,{fn,ms});return id;},clearTimeout:id=>timers.delete(id),
    setInterval:(fn,ms)=>{const id=++sequence;timers.set(id,{fn,ms,interval:true});return id;},clearInterval:id=>timers.delete(id),
    addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name)};
  const document={visibilityState:'visible',activeElement:null,querySelector:()=>blocked,addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name)};
  fetcher=async url=>response(url.endsWith('get_workshop_eligibility_snapshot')?snapshot():[{stage_code:'FITTING',revision:1},{stage_code:'TINT',revision:3}]);
  class FakeDate extends Date {static now(){return clock;}}
  const context=vm.createContext({window:win,document,app,AbortController,Date:FakeDate,Promise,Map,Set,
    setTimeout:win.setTimeout,clearTimeout:win.clearTimeout,
    getPdcSupabaseAccessToken:()=>token,renderWorkflowBoard:()=>renders.push(app.workshopEligibilityState),
    createPdcSupabaseRealtimeSubscription:(_cfg,handlers)=>{context.handlers=handlers;return{unsubscribe(){}};},
    fetch:async(...args)=>{calls.push(args);return fetcher(...args);}});
  for(const name of ['workshopEligibilitySharedAuthorityEnabled','teardownWorkshopEligibilityOverview','failWorkshopEligibilityOverviewSubscription','workshopEligibilityOverviewSubscribe','workshopEligibilityRequestIsCurrent','workshopEligibilityReadError','refreshWorkshopEligibilityClock','reconcileWorkshopEligibilityRevision','loadWorkshopEligibilitySnapshot','installWorkshopRecoveryListeners']){
    const start=source.indexOf(`function ${name}(`),end=source.indexOf('\nfunction ',start+10);assert(start>=0,name);vm.runInContext(source.slice(start,end),context);
  }
  return {app,window:win,document,context,calls,renders,timers,listeners,setFetch:fn=>{fetcher=fn;},setToken:value=>{token=value;},advance:ms=>{clock+=ms;},setBlocked:value=>{blocked=value;}};
}
test('unchanged all-station revisions do not refetch snapshots or repaint',async()=>{
  const h=harness();for(let i=0;i<12;i++)await h.context.reconcileWorkshopEligibilityRevision();
  assert.equal(h.calls.length,12);assert.equal(h.renders.length,0);assert.equal(h.app.workshopEligibilityState,'connected');
  assert.equal(h.calls[0][0],'https://staging.example.test/rest/v1/rpc/get_workshop_overview_revisions');
  assert.equal(h.calls[0][1].headers.Authorization,'Bearer session-one');assert.equal(h.calls[0][1].cache,'no-store');assert.equal(h.timers.size,0);
});
test('missed Realtime event fetches one changed canonical snapshot',async()=>{
  const h=harness();h.setFetch(async url=>response(url.endsWith('get_workshop_eligibility_snapshot')?snapshot(2):[{stage_code:'FITTING',revision:2},{stage_code:'TINT',revision:3}]));
  await h.context.reconcileWorkshopEligibilityRevision();assert.equal(h.calls.length,2);assert.deepEqual(h.renders,['connected']);
  assert.equal(h.app.workshopEligibilitySnapshot.board.bookings[0].status,'started');
});
test('manual refresh, route entry and a burst of subscriptions share one in-flight snapshot',async()=>{
  const h=harness(),pending=deferred();h.setFetch(()=>pending.promise);
  const first=h.context.loadWorkshopEligibilitySnapshot('manual');
  assert.equal(h.context.loadWorkshopEligibilitySnapshot('route_entry'),first);assert.equal(h.context.loadWorkshopEligibilitySnapshot('subscribed'),first);
  assert.equal(h.app.workshopEligibilityState,'connected');assert.equal(h.renders.length,0);assert.equal(h.calls.length,1);
  pending.resolve(response(snapshot(2)));await first;assert.deepEqual(h.renders,['connected']);assert.equal(h.timers.size,0);
});
test('Realtime arriving during a full snapshot checks revisions instead of repeating the same full fetch',async()=>{
  const h=harness(),pending=deferred();h.setFetch(url=>url.endsWith('get_workshop_eligibility_snapshot')?pending.promise:Promise.resolve(response([{stage_code:'FITTING',revision:2},{stage_code:'TINT',revision:3}])));
  const first=h.context.loadWorkshopEligibilitySnapshot();h.app.workshopEligibilityRevisionPending=true;
  await h.context.reconcileWorkshopEligibilityRevision('realtime');assert.equal(h.calls.length,1);
  pending.resolve(response(snapshot(2)));await first;await settle();assert.equal(h.calls.length,2);assert.equal(h.renders.length,1);
});
test('a changed revision during an older snapshot causes exactly one trailing full fetch',async()=>{
  const h=harness(),pending=deferred();let full=0;
  h.setFetch(url=>url.endsWith('get_workshop_eligibility_snapshot')?(++full===1?pending.promise:Promise.resolve(response(snapshot(2)))):Promise.resolve(response([{stage_code:'FITTING',revision:2},{stage_code:'TINT',revision:3}])));
  const first=h.context.loadWorkshopEligibilitySnapshot();h.app.workshopEligibilityRevisionPending=true;pending.resolve(response(snapshot(1)));await first;await settle();
  assert.equal(full,2);assert.equal(h.calls.length,3);assert.equal(h.app.workshopEligibilitySnapshot.stages[0].revision,2);
});
test('overlapping focus and timer probes coalesce',async()=>{
  const h=harness(),pending=deferred();h.setFetch(()=>pending.promise);
  const first=h.context.reconcileWorkshopEligibilityRevision();assert.equal(h.context.reconcileWorkshopEligibilityRevision(),first);assert.equal(h.calls.length,1);
  pending.resolve(response([{stage_code:'FITTING',revision:1},{stage_code:'TINT',revision:3}]));await first;assert.equal(h.timers.size,0);
});
test('hidden tabs and unrelated routes do no revision work',async()=>{
  const h=harness();h.document.visibilityState='hidden';await h.context.reconcileWorkshopEligibilityRevision();h.document.visibilityState='visible';h.app.currentView='fitters';await h.context.reconcileWorkshopEligibilityRevision();assert.equal(h.calls.length,0);
});
test('late snapshot or revision result from a previous account or role cannot restore data',async()=>{
  for(const mode of ['snapshot-token','probe-token','snapshot-role','probe-role']){
    const h=harness(),pending=deferred();h.setFetch(()=>pending.promise);
    const full=mode.startsWith('snapshot'),first=full?h.context.loadWorkshopEligibilitySnapshot():h.context.reconcileWorkshopEligibilityRevision();
    if(mode.endsWith('token'))h.setToken('new-session');else h.window.PDC_AUTH_CONTEXT.role='viewer';
    pending.resolve(response(full?snapshot(99):[{stage_code:'FITTING',revision:99},{stage_code:'TINT',revision:3}]));await first;
    assert.equal(h.app.workshopEligibilitySnapshot,null);assert.equal(h.app.workshopEligibilityRealtime,null);assert.equal(h.app.workshopEligibilityState,'permission_denied');
  }
});
test('teardown aborts both request types and discards late replies',async()=>{
  for(const full of [false,true]){const h=harness(),pending=deferred();h.setFetch(()=>pending.promise);
    const first=full?h.context.loadWorkshopEligibilitySnapshot():h.context.reconcileWorkshopEligibilityRevision();const signal=h.calls[0][1].signal;
    h.context.teardownWorkshopEligibilityOverview({clearSnapshot:true});assert.equal(signal.aborted,true);
    pending.resolve(response(full?snapshot(99):[{stage_code:'FITTING',revision:99}]));await first;assert.equal(h.app.workshopEligibilitySnapshot,null);assert.equal(h.app.workshopEligibilityState,'idle');}
});
test('empty RLS, malformed and duplicate revision rows fail closed',async()=>{
  for(const rows of [[],null,[{stage_code:'FITTING',revision:null}],[{stage_code:'FITTING',revision:'bad'}],[{stage_code:'FITTING',revision:1},{stage_code:'FITTING',revision:2}]]){
    const h=harness();h.setFetch(async()=>response(rows));await h.context.reconcileWorkshopEligibilityRevision();assert.equal(h.app.workshopEligibilitySnapshot,null);assert.equal(h.app.workshopEligibilityState,'offline_error');assert.equal(h.calls.length,1);
  }
});
test('permission failure does not retain previous rows; later recovery requires a full fresh read',async()=>{
  const h=harness();h.setFetch(async()=>({ok:false,status:403}));await h.context.reconcileWorkshopEligibilityRevision();assert.equal(h.app.workshopEligibilityState,'permission_denied');assert.equal(h.app.workshopEligibilitySnapshot,null);
  h.setFetch(async url=>response(url.endsWith('get_workshop_eligibility_snapshot')?snapshot(2):[{stage_code:'FITTING',revision:2},{stage_code:'TINT',revision:3}]));await h.context.reconcileWorkshopEligibilityRevision();assert.equal(h.app.workshopEligibilitySnapshot.stages[0].revision,2);
});
test('revision timeout is bounded and cleans up in-flight work',async()=>{
  const h=harness();h.setFetch((_url,{signal})=>new Promise((_resolve,reject)=>signal.addEventListener('abort',()=>reject(Error('timeout')))));
  const first=h.context.reconcileWorkshopEligibilityRevision();const timer=[...h.timers.values()][0];assert.equal(timer.ms,8000);timer.fn();await first;
  assert.equal(h.app.workshopEligibilityState,'offline_error');assert.equal(h.timers.size,0);assert.equal(h.app.workshopEligibilityRevisionRequest,null);
});
test('read waits for subscription establishment and only one initial snapshot is requested',async()=>{
  const h=harness();h.app.workshopEligibilityRealtime=null;h.app.workshopEligibilitySnapshot=null;h.app.workshopEligibilityState='idle';
  h.context.loadWorkshopEligibilitySnapshot();h.context.loadWorkshopEligibilitySnapshot('route_entry');assert.equal(h.calls.length,0);
  await h.context.handlers.onSubscribed();assert.equal(h.calls.length,1);assert.equal(h.app.workshopEligibilityState,'connected');
});
test('minute projection redraw requires no data fetch and defers during panning, typing or a dialog',()=>{
  const h=harness();h.context.refreshWorkshopEligibilityClock();h.context.refreshWorkshopEligibilityClock();assert.equal(h.renders.length,1);assert.equal(h.calls.length,0);
  h.advance(60000);h.setBlocked({});h.context.refreshWorkshopEligibilityClock();assert.equal(h.renders.length,1);
  h.setBlocked(null);h.document.activeElement={matches:()=>true};h.context.refreshWorkshopEligibilityClock();assert.equal(h.renders.length,1);
  h.document.activeElement=null;h.context.refreshWorkshopEligibilityClock();assert.equal(h.renders.length,2);assert.equal(h.calls.length,0);
});
test('permanently mounted hidden vehicle and customer dialogs do not block clock redraws',()=>{
  const h=harness();h.document.querySelector=selector=>selector.includes('.modal-overlay:not([hidden])')?null:{hidden:true};
  h.context.refreshWorkshopEligibilityClock();assert.equal(h.renders.length,1);
});
