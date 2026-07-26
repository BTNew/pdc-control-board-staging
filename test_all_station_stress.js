'use strict';
const assert=require('assert');
const {performance}=require('perf_hooks');
const E=require('./workshop-eligibility.js');
const stationCodes=E.workshopPlannerStageCodes();
const vehicles=Array.from({length:500},(_,i)=>({id:`v${i}`,stock_number:`STRESS${String(i).padStart(4,'0')}`,lifecycle_state:'active',current_location:i%3===0?'PMB':i%3===1?'YH':'IT',eta_to_kewdale:'2026-08-01'}));
const workItems=[];
for(let i=0;i<500;i++){
  workItems.push({vehicle_id:`v${i}`,work_key:stationCodes[i%stationCodes.length],required:true,completed:false});
  workItems.push({vehicle_id:`v${i}`,work_key:stationCodes[(i+1)%stationCodes.length],required:true,completed:false});
}
const bookings=vehicles.map((v,i)=>({vehicle_id:v.id,stage_code:stationCodes[i%stationCodes.length],status:'planned'}));
const heapBefore=process.memoryUsage().heapUsed;
const t0=performance.now();
let evaluations=0,candidates=0;
for(let round=0;round<100;round++) for(const stage of stationCodes){
 const result=E.workshopCanonicalEligibility({stage,vehicles,workItems,bookings});
 assert.strictEqual(result.stage,stage);
 candidates+=result.availableCount; evaluations++;
}
const elapsed=performance.now()-t0;
const heapDelta=Math.max(0,process.memoryUsage().heapUsed-heapBefore);
assert.strictEqual(vehicles.length,500);
assert.strictEqual(workItems.length,1000);
assert.strictEqual(bookings.length,500);
assert.strictEqual(evaluations,100*stationCodes.length);
assert(candidates>0);
assert(elapsed<5000,`eligibility stress exceeded 5s: ${elapsed.toFixed(2)}ms`);
assert(heapDelta<64*1024*1024,`eligibility stress retained >64MiB: ${heapDelta}`);
assert.throws(()=>E.workshopCanonicalEligibility({stage:'SUBLET',vehicles,workItems,bookings}),/not a schedulable planner station/i);
assert.throws(()=>E.workshopCanonicalEligibility({stage:'PIT_INSPECTION',vehicles,workItems,bookings}),/not a schedulable planner station/i);
console.log(JSON.stringify({vehicles:500,work_items:1000,bookings:500,planners:stationCodes.length,evaluations,elapsed_ms:Number(elapsed.toFixed(2)),heap_delta_bytes:heapDelta,sublet_rejected:true,pit_inspection_rejected:true}));
