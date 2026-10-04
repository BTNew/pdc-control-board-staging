'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const freshness = require('./karratha/pd135-navigation.js');
const navision = require('./karratha/navision-backend-service.js');
const transport = require('./karratha/pd135-transport.js');
const source = fs.readFileSync(path.join(__dirname, 'karratha/pd135-navigation.js'), 'utf8');
const flush = async () => { for (let i=0;i<20;i++) await Promise.resolve(); };
function deferred() { let resolve, reject; const promise = new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject}; }
function clock() {
  let time=0, sequence=0; const timers=new Map();
  return {now:()=>time,setTimeout:(callback,delay)=>{const id=++sequence;timers.set(id,{at:time+delay,callback});return id;},clearTimeout:id=>timers.delete(id),
    advance:async duration=>{const end=time+duration;for(;;){const due=[...timers].filter(([,entry])=>entry.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!due)break;time=due[1].at;timers.delete(due[0]);due[1].callback();await flush();}time=end;await flush();},size:()=>timers.size};
}
function fixture(overrides={}) {
  const time=clock(),state={authority:'own-user:administrator:1',token:'own-session',visible:true,allowed:true,busy:false,known:5,route:'workshop'},calls=[],statuses=[];
  const options={getAuthority:()=>state.authority,getToken:()=>state.token,isVisible:()=>state.visible,canRead:()=>state.allowed,isBusy:()=>state.busy,getKnownRevision:()=>state.known,getRoute:()=>state.route,
    probe:async signal=>{calls.push(['probe',signal]);return {ok:true,data:{revision:5}};},refresh:async route=>{calls.push(['refresh',route]);return {ok:true};},onStatus:(...args)=>statuses.push(args),...time,...overrides};
  const controller=freshness.create(options);return {time,state,calls,statuses,options,controller};
}
test('unchanged source runs one bounded check every30seconds and no full refresh',async()=>{
  const f=fixture();f.controller.ready();await f.time.advance(0);assert.equal(f.calls.length,1);await f.time.advance(29999);assert.equal(f.calls.length,1);await f.time.advance(1);assert.equal(f.calls.length,2);assert.ok(f.calls.every(call=>call[0]==='probe'));assert.deepEqual(f.statuses.at(-1),['checked',5]);
});
test('hidden or unapproved sessions do not poll; visible return resumes',async()=>{
  const f=fixture();f.state.visible=false;f.controller.ready();await f.time.advance(60000);assert.equal(f.calls.length,0);f.state.visible=true;f.controller.wake();await f.time.advance(0);assert.equal(f.calls.length,1);f.state.allowed=false;f.controller.wake();await f.time.advance(60000);assert.equal(f.calls.length,1);
});
test('changed projection completes before a full refresh of the current native route',async()=>{
  const order=[],wait=deferred();const f=fixture({probe:async()=>{order.push('probe');await wait.promise;order.push('projected');return {ok:true,data:{data:{revision:6}}};},refresh:async route=>{order.push('refresh:'+route);return {ok:true};}});
  f.controller.ready();await f.time.advance(0);assert.deepEqual(order,['probe']);wait.resolve();await flush();assert.deepEqual(order,['probe','projected','refresh:workshop']);
});
test('busy native coordinator queues a single trailing read without duplicate projection',async()=>{
  const wait=deferred();const f=fixture({probe:async()=>{f.calls.push(['probe']);return wait.promise;}});f.controller.ready();await f.time.advance(0);f.state.busy=true;wait.resolve({ok:true,data:{revision:6}});await flush();await f.time.advance(2000);assert.equal(f.calls.length,1);f.state.busy=false;await f.time.advance(1000);assert.deepEqual(f.calls,[['probe'],['refresh','workshop']]);
});
test('manual source loading prevents a parallel probe',async()=>{
  const f=fixture();f.state.busy=true;f.controller.ready();await f.time.advance(5000);assert.equal(f.calls.length,0);f.state.busy=false;await f.time.advance(1000);assert.equal(f.calls.length,1);
});
test('focus and online bursts coalesce while a check or full read is running',async()=>{
  const wait=deferred();const f=fixture({probe:async()=>{f.calls.push(['probe']);return wait.promise;}});f.controller.ready();await f.time.advance(0);for(let i=0;i<10;i++)f.controller.wake();await f.time.advance(0);assert.equal(f.calls.length,1);wait.resolve({ok:true,data:{revision:5}});await flush();await f.time.advance(1000);assert.ok(f.calls.length<=2);
});
test('lock drops delayed source response and stops subsequent timer work',async()=>{
  const wait=deferred();const f=fixture({probe:()=>wait.promise});f.controller.ready();await f.time.advance(0);f.controller.locked();wait.resolve({ok:true,data:{revision:6}});await flush();await f.time.advance(60000);assert.equal(f.calls.length,0);assert.equal(f.statuses.some(([state])=>state==='checked'),false);assert.equal(f.statuses.some(([state])=>state==='locked'),true);
});
test('membership or token replacement never refreshes from the former authority',async()=>{
  for(const field of ['authority','token']){const wait=deferred();const f=fixture({probe:()=>wait.promise});f.controller.ready();await f.time.advance(0);f.state[field]='replacement';wait.resolve({ok:true,data:{revision:6}});await flush();assert.equal(f.calls.length,0);assert.equal(f.statuses.some(([state])=>state==='checked'),false);}
});
test('bounded aborted probe recovers after a hung connection and new authority',async()=>{
  let attempts=0;const f=fixture({probe:signal=>{attempts++;if(attempts>1)return Promise.resolve({ok:true,data:{revision:5}});return new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(new Error('aborted')),{once:true}));}});
  f.controller.ready();await f.time.advance(0);await f.time.advance(15000);assert.equal(attempts,1);assert.deepEqual(f.statuses.at(-1),['error',null]);f.state.authority='new-approved-user';f.controller.ready();await f.time.advance(0);assert.equal(attempts,2);assert.deepEqual(f.statuses.at(-1),['checked',5]);
});
test('lost visibility and route changes cannot start a stale full read',async()=>{
  const wait=deferred();const f=fixture({probe:()=>wait.promise});f.controller.ready();await f.time.advance(0);f.state.visible=false;f.controller.wake();wait.resolve({ok:true,data:{revision:6}});await flush();assert.equal(f.calls.length,0);
  const next=fixture({probe:async()=>({ok:true,data:{revision:6}})});next.state.route='parts';next.controller.ready();await next.time.advance(0);assert.deepEqual(next.calls,[['refresh','parts']]);
});
test('errors and malformed revision responses never adopt source records',async()=>{
  for(const response of [{ok:false,data:{revision:6}},{ok:true,data:{revision:null}},{ok:true,data:{revision:'unsafe'}},{ok:true,data:{revision:Infinity}}]){const f=fixture({probe:async()=>response});f.controller.ready();await f.time.advance(0);assert.equal(f.calls.length,0);assert.deepEqual(f.statuses.at(-1),['error',null]);}
});
test('destroy aborts the active check and clears its timer ownership',async()=>{
  let aborted=false;const f=fixture({probe:signal=>new Promise((yes,no)=>signal.addEventListener('abort',()=>{aborted=true;no(new Error('aborted'));}))});f.controller.ready();await f.time.advance(0);f.controller.destroy();await flush();assert.equal(aborted,true);assert.equal(f.time.size(),0);
});
test('actual own addon uses the protected native page-one getter and native coordinator only',async()=>{
  const time=clock(),events={},documentEvents={},requests=[],refreshes=[],body={dataset:{}};
  const mapContext={window:{}};vm.runInNewContext(fs.readFileSync(path.join(__dirname,'karratha/pd135-api-map.js'),'utf8'),mapContext);const map=mapContext.window.K135_API_MAP;
  const boundary=transport.create({map,pageUrl:'https://btnew.github.io/pdc-control-board-staging/karratha/',getEpoch:()=>0,fetch:async(url,init)=>{requests.push({url:String(url),init});return new Response(JSON.stringify({ok:true,revision:6,items:[],has_more:false}),{status:200});}});
  const document={readyState:'loading',visibilityState:'visible',body,addEventListener:(name,callback)=>{documentEvents[name]=callback;}};
  const window={document,PDC_AUTH_CONTEXT:{userId:'own-user',centreCode:'135',role:'administrator',membership_version:1,engine_version:'native135'},PDC135_CONNECTION:{ready:true},PDC_AUTH:{getAccessToken:()=> 'own-test-session'},PDC_SUPABASE_CONFIG:{url:transport.PROJECT_URL,publishableKey:'public-fictional-key'},PDC_NAVISION_BACKEND_SERVICE:navision,fetch:boundary.fetch,AbortController,setTimeout:time.setTimeout,clearTimeout:time.clearTimeout,addEventListener:(name,callback)=>{events[name]=callback;}};
  const nativeApp={currentView:'workshop',sharedNavisionVisibleRevision:5,sharedNavisionVisibleState:'ready',vehicleLocationsRefreshCoordinator:{isRefreshing:()=>false}};
  const context={window,document,app:nativeApp,OPERATIONAL_REFRESH_ROUTES:['workshop','parts'],navisionSharedBackendService:()=>{},vehicleLocationsRefreshRoleCanRead:()=>true,refreshOperationalPage:async(route,options)=>{refreshes.push({route,options});return {ok:true};},setTimeout,clearTimeout,AbortController,Date};
  vm.runInNewContext(source,context);window.PDC135_NAVISION_FRESHNESS.install(window);await time.advance(0);
  assert.equal(requests.length,1);assert.equal(new URL(requests[0].url).pathname,'/rest/v1/rpc/k135_get_navision_visible_snapshot');assert.deepEqual(JSON.parse(requests[0].init.body),{p_source_system:'microsoft_navision',p_dealer_code:'14450',p_after_record_id:null,p_page_size:1,p_expected_revision:null});assert.ok(requests[0].init.signal instanceof AbortSignal);assert.equal(requests[0].init.redirect,'error');
  assert.equal(refreshes.length,1);assert.equal(refreshes[0].route,'workshop');assert.equal(refreshes[0].options.source,'navision_freshness');assert.equal(body.dataset.pd135NavisionRevision,'6');assert.equal(body.dataset.pd135NavisionStatus,'checked');assert.ok(body.dataset.pd135NavisionChecked);assert.doesNotMatch(JSON.stringify(body.dataset),/session|public-fictional|own-user/);
  window.PDC_AUTH_CONTEXT=null;events['pdc-auth-locked']();assert.equal(body.dataset.pd135NavisionStatus,'locked');assert.equal(body.dataset.pd135NavisionRevision,undefined);
  assert.doesNotMatch(source,/localStorage|sessionStorage|apply_navision|activate_navision|link_navision|preview_navision|public\.navision|\.rpc\(|\.from\(/);
});
