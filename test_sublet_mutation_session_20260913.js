'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {createPdcEmailVehicleLocationService}=require('./pdc-email-vehicle-location-service');
const source=fs.readFileSync(path.join(__dirname,'app.js'),'utf8');
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function extract(name){const start=source.search(new RegExp('(?:async )?function '+name+'\\(')),tail=source.slice(start),end=tail.slice(1).search(/\n(?:async )?function /);return tail.slice(0,end+1);}
function fixture(){
  const state={token:'operator-token',calls:[],pending:[],alerts:[],renders:0,refreshes:0};
  const vehicle={__subletBookingId:'booking-1',__emailVehicleServerAuthoritative:true,__subletBookingStatus:'active',__subletBookingVersion:1,pmbSubletBookingDate:'2026-09-14',pmbSubletExpectedReturnDate:'2026-09-15',pmbSubletNotes:'Original'};
  const service={updateSubletBooking(...args){state.calls.push(args);const pending=deferred();state.pending.push(pending);return pending.promise;},returnSubletBooking(...args){state.calls.push(args);const pending=deferred();state.pending.push(pending);return pending.promise;}};
  const ctx={console,window:{PDC_AUTH_CONTEXT:{userId:'operator-1',role:'operator'},alert:message=>state.alerts.push(message)},
    app:{subletMutationQueues:new Map(),emailVehicleLocationService:service},getPdcSupabaseAccessToken:()=>state.token,cleanNavisionText:value=>String(value??'').trim(),plainDateValue:value=>value,
    subletVehicleByKey:()=>vehicle,subletDateChangeError:()=>'',subletTodayDateKey:()=> '2026-09-14',renderSubletHome:()=>state.renders++,
    refreshEmailVehicleLocations:async()=>{state.refreshes++;vehicle.__subletBookingVersion++;}};
  vm.createContext(ctx);vm.runInContext(['queueSubletVehicleMutation','updateSubletField','setSubletReturned'].map(extract).join('\n'),ctx);
  return {ctx,state,vehicle};
}

test('Sublet edits serialize with the latest booking version while retaining each intended value',async()=>{
  const f=fixture(),first=f.ctx.updateSubletField('booking-1','pmbSubletNotes','First'),second=f.ctx.updateSubletField('booking-1','pmbSubletNotes','Second');
  await tick();assert.equal(f.state.calls.length,1);assert.equal(f.state.calls[0][1],1);assert.equal(f.state.calls[0][4],'First');
  f.state.pending[0].resolve({ok:true});assert.equal(await first,true);await tick();assert.equal(f.state.calls.length,2);assert.equal(f.state.calls[1][1],2);assert.equal(f.state.calls[1][4],'Second');
  f.state.pending[1].resolve({ok:true});assert.equal(await second,true);assert.equal(f.ctx.app.subletMutationQueues.size,0);
});

test('queued Sublet edits never execute with a replacement operator, token, service, or lost edit permission',async()=>{
  for(const mode of ['operator','token','service','role']){
    const f=fixture(),first=f.ctx.updateSubletField('booking-1','pmbSubletNotes','First'),second=f.ctx.updateSubletField('booking-1','pmbSubletNotes','Second');await tick();
    if(mode==='operator')f.ctx.window.PDC_AUTH_CONTEXT.userId='operator-2';
    if(mode==='token')f.state.token='new-token';
    if(mode==='service')f.ctx.app.emailVehicleLocationService={};
    if(mode==='role')f.ctx.window.PDC_AUTH_CONTEXT.role='viewer';
    f.state.pending[0].resolve({ok:true});assert.equal(await first,false,mode);assert.equal(await second,false,mode);
    assert.equal(f.state.calls.length,1,mode);assert.equal(f.state.refreshes,0,mode);assert.equal(f.state.renders,0,mode);assert.equal(f.state.alerts.length,0,mode);
  }
});

test('a stale Back action response cannot repaint or alert a later signed-in operator',async()=>{
  const f=fixture(),pending=f.ctx.setSubletReturned('booking-1',true);await tick();f.ctx.window.PDC_AUTH_CONTEXT.userId='operator-2';
  f.state.pending[0].resolve({ok:false,code:'version_conflict'});assert.equal(await pending,false);
  assert.equal(f.state.refreshes,0);assert.equal(f.state.alerts.length,0);assert.equal(f.state.renders,0);
});

test('Sublet network and refresh failures settle the queue and distinguish unconfirmed from saved changes',async()=>{
  for(const phase of ['network','refresh']){
    const f=fixture();if(phase==='refresh')f.ctx.refreshEmailVehicleLocations=async()=>{throw new Error('offline');};
    const pending=f.ctx.updateSubletField('booking-1','pmbSubletNotes','Draft');await tick();
    if(phase==='network')f.state.pending[0].reject(new Error('offline'));else f.state.pending[0].resolve({ok:true});
    assert.equal(await pending,phase==='refresh');assert.equal(f.ctx.app.subletMutationQueues.size,0);
    assert.match(f.state.alerts[0],phase==='refresh'?/booking was saved.*could not be refreshed/:/could not be confirmed/);assert.doesNotMatch(f.state.alerts[0],/No change was made/);
  }
});

test('a confirmed return followed by a false refresh warns about stale display while preserving success',async()=>{
  const f=fixture();f.ctx.refreshEmailVehicleLocations=async()=>false;
  const pending=f.ctx.setSubletReturned('booking-1',true);await tick();f.state.pending[0].resolve({ok:true});
  assert.equal(await pending,true);assert.match(f.state.alerts[0],/return was saved.*could not be refreshed/);assert.equal(f.state.renders,1);
});

test('a confirmed version conflict keeps its precise message and does not claim success',async()=>{
  const f=fixture(),pending=f.ctx.updateSubletField('booking-1','pmbSubletNotes','Draft');await tick();f.state.pending[0].resolve({ok:false,code:'version_conflict'});
  assert.equal(await pending,false);assert.match(f.state.alerts[0],/changed concurrently/);assert.equal(f.state.refreshes,1);
});

test('read-only users cannot start canonical Sublet edits or returns',async()=>{
  const f=fixture();f.ctx.window.PDC_AUTH_CONTEXT.role='viewer';
  assert.equal(await f.ctx.updateSubletField('booking-1','pmbSubletNotes','Draft'),false);assert.equal(await f.ctx.setSubletReturned('booking-1',true),false);assert.equal(f.state.calls.length,0);
});

test('Sublet service requires an explicit success response and rejects responses from an expired session',async()=>{
  for(const mode of ['missing-ok','false-ok','string-ok','session-changed','valid']){
    let token='current';const service=createPdcEmailVehicleLocationService({config:{url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'fixture-key'},getAccessToken:()=>token,
      fetchImpl:async()=>({ok:true,status:200,json:async()=>{if(mode==='session-changed')token='new';return mode==='missing-ok'?{}:{ok:mode==='false-ok'?false:mode==='string-ok'?'true':true};}})});
    const result=await service.updateSubletBooking('booking',1,'2026-09-14','2026-09-15');assert.equal(result.ok,mode==='valid',mode);
    if(mode==='session-changed')assert.equal(result.code,'session_changed');
  }
});

test('expanded canonical Sublet controls match the supported booking mutations and preserve returned history',()=>{
  for(const returned of [false,true]){
    const row={id:'vehicle',__emailVehicleServerAuthoritative:true,__subletBookingId:'booking',pmbSubletNotes:'Saved provider notes'};
    const host={innerHTML:''},clean=value=>String(value??'');
    const ctx={Set,app:{subletViewMode:'list',subletOperationalFilter:returned?'returned':'booked',subletExpandedRows:new Set(['booking'])},
      $:selector=>selector==='#sublet-home-content'?host:null,$$:()=>[],cleanNavisionText:clean,escapeHtml:clean,subletRows:()=>[row],renderSubletSummary(){},syncSubletProviderFilter:()=> 'all',syncSubletViewControls(){},
      subletMatchesOperationalFilter:()=>true,subletBookingState:()=>returned?'returned':'booked',normalizeSubletProviderName:clean,pmbBaySubletProvider:()=> 'Provider',plainDateValue:clean,
      vehicleKey:v=>v.id,displayStockNumber:()=> '00123',vehicleKeyNumber:()=> '1',vehicleJobcardNumber:()=> 'TEST',vehicleCustomerName:()=> 'Synthetic customer',displayVehicle:()=> 'Hilux',
      subletIsOverdue:()=>false,subletAwayOnDate:()=>false,subletTodayDateKey:()=> '2026-09-14',subletProviderOptionsHtml:()=> '',subletProviderContact:()=>({email:'provider@example.com'})};
    vm.createContext(ctx);vm.runInContext(extract('renderSubletHome'),ctx);ctx.renderSubletHome();
    const tag=attribute=>host.innerHTML.match(new RegExp('<(?:input|textarea)\\b[^>]*'+attribute+'[^>]*>'))?.[0]||'';
    assert.match(tag('data-sublet-field="pmbSubletActualReturnDate"'),/disabled/);
    assert.match(tag('data-sublet-email-sent='),/disabled/);
    for(const field of ['pmbSubletProviderEmail','pmbSubletNotes'])assert.equal(/disabled/.test(tag(`data-sublet-field="${field}"`)),returned,field);
    assert.equal(/disabled/.test(tag('data-sublet-returned=')),returned);
    assert.match(host.innerHTML,/Saved provider notes/);
  }
});

test('a hung Sublet request is bounded and reports an uncertain result without retrying',async()=>{
  const serviceSource=fs.readFileSync(path.join(__dirname,'pdc-email-vehicle-location-service.js'),'utf8');
  let expire,timeout,cleared=false,calls=0;
  const ctx={AbortController,url:'https://fixture.invalid',key:'fixture',getAccessToken:()=> 'token',
    setTimeout:(callback,ms)=>{expire=callback;timeout=ms;return 'timer';},clearTimeout:id=>{cleared=id==='timer';},
    request:(_url,options)=>{calls++;return new Promise((_resolve,reject)=>options.signal.addEventListener('abort',()=>reject(new Error('aborted'))));}};
  vm.createContext(ctx);vm.runInContext(serviceSource.slice(serviceSource.indexOf('  async function subletRpc('),serviceSource.indexOf('  function createSubletBooking(')),ctx);
  const result=ctx.subletRpc('create_pdc_sublet_booking',{},'sublet_create_unavailable');
  assert.equal(timeout,60000);expire();const response=await result;
  assert.equal(response.ok,false);assert.equal(response.code,'sublet_create_unavailable');assert.equal(calls,1);assert.equal(cleared,true);
});

test('clearing old-session Sublet queues lets the next operator save before a hung old reply resolves',async()=>{
  const f=fixture(),old=f.ctx.updateSubletField('booking-1','pmbSubletNotes','Old operator');await tick();
  const nextService={...f.ctx.app.emailVehicleLocationService};
  vm.runInContext(extract('resetEmailVehicleLocations'),f.ctx);f.ctx.resetEmailVehicleLocations();
  f.ctx.app.emailVehicleLocationService=nextService;
  f.ctx.window.PDC_AUTH_CONTEXT.userId='operator-2';f.state.token='new-session';
  const fresh=f.ctx.updateSubletField('booking-1','pmbSubletNotes','New operator');await tick();
  assert.equal(f.state.calls.length,2);assert.equal(f.state.calls[1][4],'New operator');
  f.state.pending[0].resolve({ok:true});assert.equal(await old,false);assert.equal(f.ctx.app.subletMutationQueues.size,1);
  f.state.pending[1].resolve({ok:true});assert.equal(await fresh,true);assert.equal(f.ctx.app.subletMutationQueues.size,0);
});
