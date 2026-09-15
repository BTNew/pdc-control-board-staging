'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {createController,summaryHtml,stockKey}=require('./pdc-emergency-priority');
function fixture(fetchImpl,timeoutMs){
 const config={projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}};
 let owner={actor:'user-a',token:'token-a',role:'operator',config};
 const calls=[];const preview={ok:true,can_apply:true,applied:false,plan_hash:'1.hash',bookings:[],changes:[],stock_number:'ABC'};
 const controller=createController({context:()=>owner,uuid:()=> 'fixed-key',timeoutMs,
  fetch:async(url,options)=>{const body=JSON.parse(options.body);calls.push(body);return fetchImpl?fetchImpl(body,options):{ok:true,json:async()=>body.p_apply?{...preview,applied:true}:preview};}});
 return {controller,calls,owner(v){owner=v;},getOwner:()=>owner,preview};
}
test('preview first, then apply binds stock/hash/idempotency key',async()=>{
 const f=fixture();await assert.rejects(f.controller.apply(),/Preview/);
 await f.controller.preview('ab-c');assert.equal(f.calls[0].p_stock_number,'ABC');assert.equal(f.calls[0].p_apply,false);
 await f.controller.apply();assert.deepEqual(f.calls[1],{p_stock_number:'ABC',p_apply:true,p_plan_hash:'1.hash',p_idempotency_key:'fixed-key'});
 assert.equal(f.controller.canApply,false);
});
test('stale preview requires a fresh preview',async()=>{
 const f=fixture(async b=>({ok:true,json:async()=>b.p_apply?{ok:false,error:'stale_preview',message:'Bookings changed'}:{ok:true,can_apply:true,plan_hash:'hash',bookings:[],changes:[]}}));
 await f.controller.preview('123');await assert.rejects(f.controller.apply(),/Bookings changed/);assert.equal(f.controller.canApply,false);
});
test('uncertain apply retains same key for retry and blocks a new preview',async()=>{
 let applying=0;const f=fixture(async b=>{
  if(b.p_apply&&++applying===1)throw Error('lost connection');
  return {ok:true,json:async()=>({ok:true,can_apply:true,applied:b.p_apply,plan_hash:'hash',bookings:[],changes:[]})};
 });
 await f.controller.preview('123');await assert.rejects(f.controller.apply(),/not confirmed/);
 assert.equal(f.controller.uncertain,true);await assert.rejects(f.controller.preview('456'),/Check/);
 await f.controller.apply();assert.equal(f.calls[1].p_idempotency_key,f.calls[2].p_idempotency_key);assert.equal(f.controller.uncertain,false);
});
test('sign-out during preview discards the response',async()=>{
 let release;const f=fixture(()=>new Promise(resolve=>{release=resolve;}));
 const pending=f.controller.preview('123');f.owner({...f.getOwner(),actor:'user-b',token:'token-b'});f.controller.invalidate();
 release({ok:true,json:async()=>f.preview});await assert.rejects(pending,/session changed/);assert.equal(f.controller.canApply,false);
});
test('viewer and wrong project cannot send a request',async()=>{
 const f=fixture();f.owner({...f.getOwner(),role:'viewer'});await assert.rejects(f.controller.preview('123'),/operator/);assert.equal(f.calls.length,0);
 f.owner({...f.getOwner(),role:'operator',config:{...f.getOwner().config,projectRef:'different'}});
 await assert.rejects(f.controller.preview('123'),/operator/);assert.equal(f.calls.length,0);
});
test('duplicate click cannot issue a second mutation',async()=>{
 let release;const f=fixture(()=>new Promise(resolve=>{release=resolve;}));
 const p=f.controller.preview('123');await assert.rejects(f.controller.preview('123'),/already running/);
 release({ok:true,json:async()=>f.preview});await p;assert.equal(f.calls.length,1);
});
test('timeout aborts a request and releases busy state',async()=>{
 let signal;const f=fixture((_,options)=>{signal=options.signal;return new Promise(()=>{});},5);
 await assert.rejects(f.controller.preview('123'),e=>e.code==='unconfirmed'&&/no schedule changes were saved/.test(e.message));assert.equal(signal.aborted,true);assert.equal(f.controller.busy,false);
});
test('malformed preview cannot enable apply',async()=>{
 const f=fixture(async()=>({ok:true,json:async()=>({ok:true,can_apply:true,bookings:[]})}));
 await assert.rejects(f.controller.preview('123'),/incomplete/);assert.equal(f.controller.canApply,false);
});
test('summary escapes customer data and shows affected before and after times',()=>{
 const html=summaryHtml({stock_number:'<stock>',customer:'<script>',bookings:[{stage_code:'FITTING',bay_number:1,start_at:'2026-09-16T00:00:00Z',end_at:'2026-09-16T01:00:00Z'}],
 changes:[{priority:false,stock_number:'&stock',stage_code:'HOIST',bay_number:2,old_start_at:'2026-09-16T01:00:00Z',new_start_at:'2026-09-16T02:00:00Z',new_end_at:'2026-09-16T03:00:00Z'}]});
 assert(!html.includes('<script>'));assert(html.includes('&lt;stock&gt;'));assert(html.includes('Previous start'));assert(html.includes('New finish'));
 assert.equal(stockKey(' IS-5001 '),'IS5001');
});
