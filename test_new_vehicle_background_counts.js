'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(require.resolve('./pdc-new-vehicles.js'),'utf8');
function fixture() {
  const calls=[],badge={},nav={querySelector:()=>badge,setAttribute(name,value){this[name]=value;}},app={currentView:'dashboard'},document={visibilityState:'visible'};
  let allowed=true,release=null,reject=false;
  const context=vm.createContext({...require('./pdc-new-vehicles.js'),app,document,nav,Promise,Number,
    readable:()=>allowed,message:e=>e.message,render:()=>{},
    rpc:async(name)=>{calls.push(name);if(release)await new Promise(resolve=>release=resolve);if(reject)throw Error('offline');
      return name==='get_pdc_review_counts'?{ok:true,data:{new_vehicles:12,operation_changes:4}}:{ok:true,data:{items:[],total:name==='list_pdc_new_vehicle_reviews'?3:2}};}});
  vm.runInContext(source.slice(source.indexOf('  let items='),source.indexOf('  const readable='))
    +source.slice(source.indexOf('  async function load('),source.indexOf('  function choose('))
    +'\nglobalThis.api={refreshBackground,load,loadCounts,state:()=>({items,total,updateTotal,badgeCounts,loading}),reset:()=>{generation++;sessionGeneration++;badgeCounts=null;countRequest=null;},busy:value=>{saving=value;}};',context);
  return {api:context.api,calls,badge,nav,app,document,setAllowed:value=>allowed=value,fail:()=>{reject=true;},hold:()=>{release=true;return ()=>release();}};
}
test('background routes fetch badge counts without expanding either review list',async()=>{
  const f=fixture();for(let i=0;i<6;i++)await f.api.refreshBackground();
  assert.equal(f.calls.length,6);assert.ok(f.calls.every(n=>n==='get_pdc_review_counts'));
  assert.equal(f.badge.textContent,'16');assert.equal(f.badge.hidden,false);
  assert.equal(f.api.state().total,0,'badge reads must not pretend the full queue was loaded');
});
test('review route retains both full queue refreshes with their current counts',async()=>{
  const f=fixture();await f.api.refreshBackground();f.app.currentView='newvehicles';await f.api.refreshBackground();
  assert.deepEqual(f.calls,['get_pdc_review_counts','list_pdc_new_vehicle_reviews','list_pdc_tune_operation_changes']);
  assert.equal(f.api.state().badgeCounts,null);assert.equal(f.api.state().total,3);assert.equal(f.api.state().updateTotal,2);
});
test('hidden documents, unapproved users and an active save do not poll the review queues',async()=>{
  const f=fixture();f.document.visibilityState='hidden';await f.api.refreshBackground();
  f.document.visibilityState='visible';f.setAllowed(false);await f.api.refreshBackground();
  f.setAllowed(true);f.api.busy(true);await f.api.refreshBackground();assert.equal(f.calls.length,0);
});
test('badge checks coalesce and a late response cannot overwrite active review counts',async()=>{
  const f=fixture(),release=f.hold();const pending=f.api.refreshBackground();await f.api.refreshBackground();
  assert.equal(f.calls.length,1);f.app.currentView='newvehicles';release();await pending;
  assert.equal(f.api.state().badgeCounts,null);
});
test('sign-out discards pending badge counts and transient failures retain last confirmed badge',async()=>{
  const f=fixture(),release=f.hold();const pending=f.api.refreshBackground();f.api.reset();release();await pending;
  assert.equal(f.api.state().badgeCounts,null);
  const healthy=fixture();await healthy.api.refreshBackground();healthy.fail();await healthy.api.refreshBackground();
  assert.equal(healthy.badge.textContent,'16');assert.equal(healthy.api.state().total,0);
});
