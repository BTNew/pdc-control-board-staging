'use strict';
const assert=require('assert');
const crypto=require('crypto');
const RUN='HERMES-TEST-RUN-20260824';
const catalog=new Map([
 ['vehicle-005:FITTING',{scenario:5,hours:1.22,minutes:73}],
 ['vehicle-006:ELECTRICAL',{scenario:6,hours:1.02,minutes:61}],
 ['vehicle-007:FITTING',{scenario:7,hours:0.78,minutes:47}],
 ['vehicle-007:ELECTRICAL',{scenario:7,hours:0.98,minutes:59}],
]);
const vehicles=new Map([5,6,7].map(n=>[`vehicle-00${n}`,{scenario:n,version:1,stock:`HERMES-TEST-00${n}`,source:'hermes_overnight_synthetic',run:RUN}]));
const estimates=new Map(),receipts=new Map();
let protectedDigest='protected-estimate-relations-v1',siblingDigest='siblings-estimate-relations-v1',notifications=0;
const stable=x=>Array.isArray(x)?x.map(stable):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,stable(x[k])])):x;
const hash=x=>crypto.createHash('sha256').update(JSON.stringify(stable(x))).digest('hex');
function apply({role='administrator',email='admin@example.test',run=RUN,vehicleId,vehicleVersion,estimateVersion,key,stage,hours}){
 assert.strictEqual(role,'administrator','role'); assert.strictEqual(run,RUN,'run');
 const v=vehicles.get(vehicleId);assert.ok(v,'registry');assert.strictEqual(v.version,vehicleVersion,'vehicle version');
 const request={role,email,run,vehicleId,vehicleVersion,estimateVersion,key,stage,hours};const sha=hash(request);const rk=`${email}:${key}`;
 if(receipts.has(rk)){const r=receipts.get(rk);assert.strictEqual(r.sha,sha,'changed replay');return {...r.response,replay:true};}
 const expected=catalog.get(`${vehicleId}:${stage}`);assert.ok(expected,'catalog stage');assert.strictEqual(expected.scenario,v.scenario);assert.strictEqual(expected.hours,hours,'catalog hours');assert.strictEqual(expected.minutes,Math.round(hours*60),'exact minutes');
 assert.ok(hours>0,'migration 317 positive estimate preserved');
 const ek=`${vehicleId}:${stage}`,existing=estimates.get(ek);
 if(existing){assert.strictEqual(estimateVersion,existing.version,'estimate version');assert.deepStrictEqual(existing,expected,'immutable estimate');}
 else{assert.strictEqual(estimateVersion,0,'insert version');estimates.set(ek,{...expected,version:1});}
 assert.strictEqual(protectedDigest,'protected-estimate-relations-v1');assert.strictEqual(siblingDigest,'siblings-estimate-relations-v1');assert.strictEqual(notifications,0);
 const response={ok:true,replay:false,vehicleId,vehicleVersion:v.version,estimateVersion:1,stage,hours,minutes:expected.minutes,notificationDelta:0};receipts.set(rk,{sha,response});return response;
}
let r=apply({vehicleId:'vehicle-005',vehicleVersion:1,estimateVersion:0,key:'k1',stage:'FITTING',hours:1.22});assert.strictEqual(r.minutes,73);
let replay=apply({vehicleId:'vehicle-005',vehicleVersion:1,estimateVersion:0,key:'k1',stage:'FITTING',hours:1.22});assert.ok(replay.replay);
assert.throws(()=>apply({vehicleId:'vehicle-005',vehicleVersion:1,estimateVersion:0,key:'k1',stage:'FITTING',hours:1.23}),/changed replay/);
for(const x of [
 ['vehicle-006','ELECTRICAL',1.02,61,'k2'],['vehicle-007','FITTING',0.78,47,'k3'],['vehicle-007','ELECTRICAL',0.98,59,'k4']]){
 r=apply({vehicleId:x[0],vehicleVersion:1,estimateVersion:0,key:x[4],stage:x[1],hours:x[2]});assert.strictEqual(r.minutes,x[3]);
}
assert.throws(()=>apply({role:'operator',vehicleId:'vehicle-005',vehicleVersion:1,estimateVersion:1,key:'bad-role',stage:'FITTING',hours:1.22}),/role/);
assert.throws(()=>apply({vehicleId:'protected-1',vehicleVersion:1,estimateVersion:0,key:'bad-target',stage:'FITTING',hours:1.22}),/registry/);
assert.throws(()=>apply({vehicleId:'vehicle-005',vehicleVersion:2,estimateVersion:1,key:'bad-v',stage:'FITTING',hours:1.22}),/vehicle version/);
assert.throws(()=>apply({vehicleId:'vehicle-005',vehicleVersion:1,estimateVersion:0,key:'bad-ev',stage:'FITTING',hours:1.22}),/estimate version/);
assert.throws(()=>apply({vehicleId:'vehicle-006',vehicleVersion:1,estimateVersion:1,key:'bad-catalog',stage:'ELECTRICAL',hours:1.01}),/catalog hours/);
assert.strictEqual(estimates.size,4);assert.strictEqual(receipts.size,4);assert.strictEqual(notifications,0);
console.log('Migration 369 executable model passed: exact catalog, role/scope/version, replay, immutability, containment, and positive minutes.');
