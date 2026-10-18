'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createWorkshopDataService}=require('./workshop-data-service');
const lock={ok:false,status:500,body:{code:'55P03',message:'canceling statement due to lock timeout'}};
const success={ok:true,status:200,body:{ok:true,booking_id:'saved'}};
function fixture(){
 let token='same-user',role='administrator',handler=async()=>success;const writes=[];
 const service=createWorkshopDataService({config:{workshop:{sharedData:true}},getAccessToken:()=>token,getRole:()=>role,
  client:{rpc:async(t,name,params)=>name.includes('snapshot')?{ok:true,status:200,body:{revision:1,bookings:[]}}:(writes.push({t,name,params}),handler())}});
 return {service,writes,handler:fn=>handler=fn,token:v=>token=v,role:v=>role=v,
  run:async(name='administrator_schedule_workshop_vehicle',params={p_request_id:'same-receipt',p_vehicle_expected_version:3})=>{await service.loadSnapshot('initial');return service.mutate(name,params);}};
}
test('known rolled-back lock failures can recover after six waits with the exact intent and receipt',async()=>{
 const f=fixture();let n=0;f.handler(async()=>++n<7?lock:success);assert.equal((await f.run()).ok,true);assert.equal(f.writes.length,7);
 for(const w of f.writes){assert.strictEqual(w.params,f.writes[0].params);assert.equal(w.t,'same-user');assert.equal(w.params.p_vehicle_expected_version,3);}
});
test('persistent contention stops after seven attempts with a known rollback',async()=>{const f=fixture();f.handler(async()=>lock);const r=await f.run();assert.equal(r.code,'55P03');assert.notEqual(r.outcomeUnknown,true);assert.equal(f.writes.length,7);});
test('move commands keep their booking version and receipt through a lock retry',async()=>{
 const f=fixture();let n=0;f.handler(async()=>++n===1?lock:success);assert.equal((await f.run('administrator_move_workshop_booking',{p_request_id:'move-receipt',p_expected_version:4})).ok,true);assert.equal(f.writes.length,2);assert.strictEqual(f.writes[0].params,f.writes[1].params);
});
for(const response of [{ok:false,status:503,body:{}},{ok:false,status:403,body:{code:'55P03'}},{ok:false,status:500,body:{code:'P0001',message:'conflict'}},{ok:true,status:200,body:{ok:false,error:'vehicle_version_conflict'}}]){
 test(`does not replay unknown or rejected outcome ${response.status}/${response.body.code||response.body.error||'unknown'}`,async()=>{const f=fixture();f.handler(async()=>response);await f.run();assert.equal(f.writes.length,1);});
}
for(const change of ['token','role','destroy'])test(`authority ${change} during lock failure cancels replay`,async()=>{
 const f=fixture();f.handler(async()=>{if(change==='destroy')f.service.destroy();else f[change](change==='token'?'another-user':'viewer');return lock;});
 assert.equal((await f.run()).ok,false);assert.equal(f.writes.length,1);
});
test('commands without receipt protection and other mutations are never retried',async()=>{
 for(const [name,params] of [['administrator_schedule_workshop_vehicle',{p_vehicle_expected_version:3}],['start_workshop_work',{p_expected_version:3,p_request_id:'irrelevant'}]]){
  const f=fixture();f.handler(async()=>lock);await f.run(name,params);assert.equal(f.writes.length,1);
 }
});
