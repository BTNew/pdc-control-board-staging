/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test'), assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require.resolve('./workshop-planner.js'),'utf8');
const start=source.indexOf('let workshopWeeklyLoadSequence = 0;');
const end=source.indexOf('async function openWorkshopWeeklyView',start);
function fixture() {
 let scope={stageCode:'FABRICATION',dateFrom:'2026-10-19',dateTo:'2026-10-19'}, snapshot=null, shared=true;
 const requests=[];let respond=async next=>{scope=next;snapshot={scope:{stage_code:next.stageCode,date_from:next.dateFrom,date_to:next.dateTo},bookings:[{id:'wednesday',scheduled_start_at:'2026-10-21T00:00:00Z'}]};};
 const service={getScope:()=>scope,getTrustedSnapshot:()=>snapshot,setScope:async next=>{requests.push(next);await respond(next);}};
 const context={window:{__workshopDataService:service},workshopSharedModeActive:()=>shared,workshopDateKey:d=>d};
 vm.createContext(context);vm.runInContext(source.slice(start,end),context);
 return {context,requests,service,load:(stage,dates)=>context.workshopLoadWeeklySnapshot(stage,dates),
  response:fn=>respond=fn,install:(next,value)=>{scope=next;snapshot=value;},shared:v=>shared=v};
}
test('weekly view waits for the full range including bookings outside the selected day',async()=>{
 const f=fixture();let finish;f.response(next=>new Promise(resolve=>{finish=()=>{f.install(next,{scope:{stage_code:next.stageCode,date_from:next.dateFrom,date_to:next.dateTo},bookings:[{id:'wednesday'}]});resolve();};}));
 let resolved=false;const result=f.load('FABRICATION',['2026-10-19','2026-10-20','2026-10-21','2026-10-22','2026-10-23']).then(value=>{resolved=true;return value;});
 await Promise.resolve();assert.equal(resolved,false);
 assert.equal(f.requests[0].dateFrom,'2026-10-19');assert.equal(f.requests[0].dateTo,'2026-10-23');
 finish();assert.equal(await result,true);assert.equal(f.service.getTrustedSnapshot().bookings[0].id,'wednesday');
});
test('a retained single-day snapshot cannot present an empty week as authoritative',async()=>{
 const f=fixture();f.response(async next=>f.install(next,{scope:{stage_code:'FABRICATION',date_from:'2026-10-19',date_to:'2026-10-19'},bookings:[]}));
 assert.equal(await f.load('FABRICATION',['2026-10-19','2026-10-23']),false);
});
test('permission loss and network failure do not open an editable empty week',async()=>{
 const f=fixture();f.response(async next=>f.install(next,null));assert.equal(await f.load('FABRICATION',['2026-10-19','2026-10-23']),false);
 f.response(async()=>{throw Error('network unavailable');});assert.equal(await f.load('FABRICATION',['2026-10-19','2026-10-23']),false);
});
test('late previous-week results cannot replace a newer requested week',async()=>{
 const f=fixture();const pending=[];
 f.response(next=>new Promise(resolve=>pending.push(()=>{f.install(next,{scope:{stage_code:next.stageCode,date_from:next.dateFrom,date_to:next.dateTo}});resolve();})));
 const first=f.load('FABRICATION',['2026-10-19','2026-10-23']);
 const second=f.load('FABRICATION',['2026-10-26','2026-10-30']);
 pending[1]();assert.equal(await second,true);pending[0]();assert.equal(await first,false);
});
test('replaced or torn-down services cannot reopen a pending weekly view',async()=>{
 const f=fixture();let finish;f.response(()=>new Promise(resolve=>finish=resolve));
 const result=f.load('FABRICATION',['2026-10-19','2026-10-23']);
 f.context.window.__workshopDataService=null;finish();assert.equal(await result,false);
});
test('local planners retain their existing week data source',async()=>{
 const f=fixture();f.shared(false);assert.equal(await f.load('FABRICATION',['2026-10-19','2026-10-23']),true);assert.equal(f.requests.length,0);
});
