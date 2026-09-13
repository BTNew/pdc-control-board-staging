'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createPdcOperationalRefreshCoordinator:create}=require('./vehicle-locations-refresh');
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};};

test('a queued vehicle revision still reloads its supported board route when the user opens New Vehicles or setup',async()=>{
  for(const nextRoute of ['newvehicles','admin']){
    const gate=deferred(),calls=[],finishes=[];let route='dashboard';
    const coordinator=create({getRoute:()=>route,routeAdapters:{dashboard:{snapshot:()=>{calls.push('dashboard');return calls.length===1?gate.promise:{ok:true,revision:2};}}},onFinish:result=>finishes.push(result)});
    const first=coordinator.refresh({route:'dashboard'});
    const queued=coordinator.refresh({route:'dashboard',supersede:true,deferSupersede:true});
    route=nextRoute;gate.resolve({ok:true,revision:1});await first;const result=await queued;
    assert.equal(result.route,'dashboard',nextRoute);assert.equal(result.results.length,1,nextRoute);assert.equal(result.results[0].value.revision,2,nextRoute);
    assert.deepEqual(calls,['dashboard','dashboard']);assert.equal(finishes.length,2);assert.equal(coordinator.isRefreshing(),false);
  }
});

test('an invalidated queued refresh cannot restart after a new operator already began a fresh route read',async()=>{
  const gates=[deferred(),deferred()],calls=[],finishes=[];
  const coordinator=create({routeAdapters:{dashboard:{snapshot:()=>{calls.push('dashboard');return gates[0].promise;}},sublet:{snapshot:()=>{calls.push('sublet');return gates[1].promise;}}},onFinish:result=>finishes.push(result.route)});
  const old=coordinator.refresh({route:'dashboard'}),queued=coordinator.refresh({route:'dashboard',supersede:true,deferSupersede:true});
  coordinator.invalidate();const fresh=coordinator.refresh({route:'sublet'});gates[0].resolve({ok:true});
  assert.equal((await old).stale,true);assert.equal((await queued).stale,true);assert.equal(coordinator.isRefreshing(),true);
  gates[1].resolve({ok:true});assert.equal((await fresh).ok,true);assert.deepEqual(calls,['dashboard','sublet']);assert.deepEqual(finishes,['sublet']);
});
