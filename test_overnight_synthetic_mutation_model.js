'use strict';
const assert = require('assert');
const crypto = require('crypto');

const RUN = 'HERMES-TEST-RUN-20260824';
const registry = new Map(Array.from({length:20},(_,i)=>{
  const n=String(i+1).padStart(3,'0');
  return [`vehicle-${n}`,{vehicleId:`vehicle-${n}`,stock:`HERMES-TEST-${n}`,version:1,location:i===1?'IT':i===2?'YH':'PMB',qc:false,lifecycle:'active',keyTag:'',parts:{required:true,ordered:false,received:false,stoppage:false},bookings:new Map(),sublets:new Map()}];
}));
const protectedDigest = 'protected-153-immutable';
const receipts = new Map();
let notifications = 0;

function stable(value){
  if(Array.isArray(value)) return value.map(stable);
  if(value&&typeof value==='object') return Object.fromEntries(Object.keys(value).sort().map(k=>[k,stable(value[k])]));
  return value;
}
function hash(value){return crypto.createHash('sha256').update(JSON.stringify(stable(value))).digest('hex');}
function exactKeys(payload,keys){assert.deepStrictEqual(Object.keys(payload).sort(),keys.slice().sort());}
function apply({actor='admin',email='admin@example.test',run=RUN,vehicleId,expectedVersion,subjectId=null,subjectVersion=null,key,action,payload={}}){
  assert.strictEqual(run,RUN,'wrong run fails closed');
  assert.ok(['admin','operator'].includes(actor),'role fails closed');
  const vehicle=registry.get(vehicleId); assert.ok(vehicle,'outside registry fails closed');
  const request={actor,email,run,vehicleId,expectedVersion,subjectId,subjectVersion,key,action,payload};
  const requestHash=hash(request); const receiptKey=`${actor}:${key}`;
  if(receipts.has(receiptKey)){
    const receipt=receipts.get(receiptKey); assert.strictEqual(receipt.requestHash,requestHash,'changed replay rejects');
    assert.strictEqual(receipt.email,email,'actor email drift rejects');
    assert.strictEqual(protectedDigest,'protected-153-immutable'); assert.strictEqual(notifications,0);
    return {...receipt.response,replay:true,replayContainmentVerified:true,currentVehicleVersion:vehicle.version};
  }
  assert.strictEqual(vehicle.version,expectedVersion,'stale vehicle version rejects');
  const before=JSON.stringify(stable(vehicle)); let ok=true,error='';
  try{
    switch(action){
      case 'vehicle_edit': exactKeys(payload,['pmb_key_tag']); assert.match(payload.pmb_key_tag,/^HERMES-TEST/); vehicle.keyTag=payload.pmb_key_tag; vehicle.version++; break;
      case 'parts_stoppage': exactKeys(payload,['reason']); assert.match(payload.reason,/^HERMES-TEST/); vehicle.parts.stoppage=true; vehicle.parts.reason=payload.reason; vehicle.version++; break;
      case 'parts_recover': exactKeys(payload,[]); vehicle.parts.stoppage=false; delete vehicle.parts.reason; vehicle.version++; break;
      case 'parts_ordered': exactKeys(payload,[]); vehicle.parts.ordered=true; vehicle.version++; break;
      case 'lifecycle_ready_qc': exactKeys(payload,[]); if(vehicle.location!=='PMB') throw new Error('qc_gate_blocked'); vehicle.location='QC'; vehicle.version++; break;
      case 'lifecycle_qc_to_rft': exactKeys(payload,[]); if(vehicle.location!=='QC') throw new Error('qc_gate_blocked'); vehicle.qc=true; vehicle.location='RFT'; vehicle.lifecycle='rft'; vehicle.version+=2; break;
      case 'workshop_move': {
        exactKeys(payload,['start']); const b=vehicle.bookings.get(subjectId); assert.ok(b,'cross-registry subject rejects'); assert.strictEqual(b.version,subjectVersion,'stale subject rejects'); b.start=payload.start;b.version++;break;
      }
      default: throw new Error('action_not_allowed');
    }
  }catch(err){ok=false;error=err.message;Object.assign(vehicle,JSON.parse(before));}
  assert.strictEqual(protectedDigest,'protected-153-immutable');
  assert.strictEqual(notifications,0,'QC/RFT must never enqueue');
  if(!ok) assert.strictEqual(JSON.stringify(stable(vehicle)),before,'failure is no-change');
  const response={ok,code:ok?'synthetic_action_applied':'synthetic_action_rejected',error,replay:false,vehicleId,vehicleVersionBefore:expectedVersion,vehicleVersionAfter:vehicle.version,subjectId,subjectVersionBefore:subjectVersion,notificationDelta:0};
  receipts.set(receiptKey,{requestHash,email,response});
  return response;
}

let r=apply({vehicleId:'vehicle-001',expectedVersion:1,key:'00000000-0000-4000-8000-000000000001',action:'vehicle_edit',payload:{pmb_key_tag:'HERMES-TEST-KEY-001'}});
assert.ok(r.ok);assert.strictEqual(r.vehicleVersionAfter,2);
let replay=apply({vehicleId:'vehicle-001',expectedVersion:1,key:'00000000-0000-4000-8000-000000000001',action:'vehicle_edit',payload:{pmb_key_tag:'HERMES-TEST-KEY-001'}});
assert.ok(replay.replay);assert.strictEqual(replay.currentVehicleVersion,2);
assert.throws(()=>apply({vehicleId:'vehicle-001',expectedVersion:1,key:'00000000-0000-4000-8000-000000000001',action:'vehicle_edit',payload:{pmb_key_tag:'HERMES-TEST-CHANGED'}}),/changed replay rejects/);
assert.throws(()=>apply({vehicleId:'protected-001',expectedVersion:1,key:'x',action:'vehicle_edit',payload:{pmb_key_tag:'HERMES-TEST-X'}}),/outside registry/);

r=apply({vehicleId:'vehicle-009',expectedVersion:1,key:'00000000-0000-4000-8000-000000000009',action:'parts_stoppage',payload:{reason:'HERMES-TEST supplier delay'}});assert.ok(r.ok);assert.ok(registry.get('vehicle-009').parts.stoppage);
r=apply({vehicleId:'vehicle-009',expectedVersion:2,key:'00000000-0000-4000-8000-000000000019',action:'parts_recover',payload:{}});assert.ok(r.ok);assert.ok(!registry.get('vehicle-009').parts.stoppage);

r=apply({vehicleId:'vehicle-002',expectedVersion:1,key:'00000000-0000-4000-8000-000000000002',action:'lifecycle_ready_qc',payload:{}});assert.ok(!r.ok);assert.strictEqual(r.code,'synthetic_action_rejected');
replay=apply({vehicleId:'vehicle-002',expectedVersion:1,key:'00000000-0000-4000-8000-000000000002',action:'lifecycle_ready_qc',payload:{}});assert.ok(replay.replay);assert.ok(!replay.ok);

const qc=registry.get('vehicle-012');qc.location='QC';
r=apply({vehicleId:'vehicle-012',expectedVersion:1,key:'00000000-0000-4000-8000-000000000012',action:'lifecycle_qc_to_rft',payload:{}});assert.ok(r.ok);assert.strictEqual(notifications,0);assert.strictEqual(qc.lifecycle,'rft');

const race=registry.get('vehicle-017');race.bookings.set('booking-017',{vehicleId:'vehicle-017',version:1,start:'2026-08-25T08:00:00+08:00'});
r=apply({vehicleId:'vehicle-017',expectedVersion:1,subjectId:'booking-017',subjectVersion:1,key:'00000000-0000-4000-8000-000000000017',action:'workshop_move',payload:{start:'2026-08-25T08:01:00+08:00'}});assert.ok(r.ok);
r=apply({vehicleId:'vehicle-017',expectedVersion:1,subjectId:'booking-017',subjectVersion:1,key:'00000000-0000-4000-8000-000000000027',action:'workshop_move',payload:{start:'2026-08-25T08:02:00+08:00'}});assert.ok(!r.ok);assert.match(r.error,/stale subject/);

assert.strictEqual(receipts.size,7,'successful and rejected outcomes are durably idempotent');
assert.strictEqual(protectedDigest,'protected-153-immutable');
assert.strictEqual(notifications,0);
console.log('Overnight synthetic mutation executable model passed: registry, replay, failure receipt, Parts stoppage, QC no-notification, and stale race.');
