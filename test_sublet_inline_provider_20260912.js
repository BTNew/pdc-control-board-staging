'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'pdc-sublet-intake.js'),'utf8');
const helpers=source.slice(source.indexOf('  const writable='),source.indexOf('  function prepareProviderEntry()'));
function fixture(){
  const nodes={};
  const node=(id,value='')=>nodes[id]={value,hidden:false,disabled:false,dataset:{},style:{},textContent:'',innerHTML:'',focus(){},reportValidity(){return true;}};
  ['sublet-new-provider','sublet-new-provider-error','sublet-new-provider-name','sublet-new-provider-email','sublet-create-provider','sublet-create-provider-email','sublet-create-out-date','sublet-create-return-date','sublet-create-notes'].forEach(id=>node(id));
  const buttons=[node('save'),node('cancel')];
  const inputs=[nodes['sublet-new-provider-name'],nodes['sublet-new-provider-email']];
  nodes['sublet-new-provider'].querySelectorAll=selector=>selector==='input'?inputs:selector==='button'?buttons:[...inputs,...buttons];
  nodes['sublet-create-dialog']={open:true};
  nodes['sublet-new-provider-name'].value=' New  Provider ';
  nodes['sublet-new-provider-email'].value=' new@example.com ';
  nodes['sublet-create-out-date'].value='2026-09-14';nodes['sublet-create-return-date'].value='2026-09-15';nodes['sublet-create-notes'].value='Keep original job notes';
  const state={role:'administrator',token:'synthetic-token',rows:[],calls:[],cacheError:null};
  const service={
    listSubletProviders:async()=>state.rows,
    getCachedSubletProviders:()=>({rows:state.rows,error:state.cacheError}),
    addSubletProvider:async(name,email)=>{state.calls.push({name,email});const provider={id:'new-provider-id',name,email,active:true};state.rows.push(provider);return {ok:true,provider};}
  };
  const ctx={document:{getElementById:id=>nodes[id]},window:{__workshopReferenceDataService:service,PDC_AUTH_CONTEXT:{role:'administrator'}},
    workshopTechnicianAdminCanMutate:()=>state.role==='administrator',getPdcSupabaseAccessToken:()=>state.token,
    initWorkshopReferenceDataServiceIfAvailable:()=>service,loadSubletProviderRecords:(all=false)=>state.rows.filter(r=>all||r.active),
    subletProviderEmailValid:value=>!value||/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value),
    fillSubletCreateProviderEmail:()=>{nodes['sublet-create-provider-email'].value=state.rows.find(r=>r.id===nodes['sublet-create-provider'].value)?.email||'';},
    esc:value=>String(value).replace(/[&<>"']/g,'_')};
  vm.createContext(ctx);vm.runInContext(helpers,ctx);
  return {ctx,state,service,nodes,save:()=>ctx.saveNewProvider()};
}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
test('add once, choose canonical provider and keep dates and notes',async()=>{
  const f=fixture();const wait=deferred();f.service.listSubletProviders=()=>wait.promise;
  const first=f.save();const second=f.save();wait.resolve([]);await Promise.all([first,second]);
  assert.deepEqual(f.state.calls,[{name:'New Provider',email:'new@example.com'}]);
  assert.equal(f.nodes['sublet-create-provider'].value,'new-provider-id');assert.equal(f.nodes['sublet-create-provider-email'].value,'new@example.com');
  assert.equal(f.nodes['sublet-create-out-date'].value,'2026-09-14');assert.equal(f.nodes['sublet-create-return-date'].value,'2026-09-15');assert.equal(f.nodes['sublet-create-notes'].value,'Keep original job notes');
  assert.equal(f.nodes['sublet-new-provider'].hidden,true);
});
test('active duplicate reuses identity and directory email without add or overwrite',async()=>{
  const f=fixture();f.state.rows=[{id:'existing',name:'NEW PROVIDER',email:'directory@example.com',active:true}];await f.save();
  assert.equal(f.state.calls.length,0);assert.equal(f.nodes['sublet-create-provider'].value,'existing');assert.equal(f.nodes['sublet-create-provider-email'].value,'directory@example.com');
});
test('concurrent duplicate result selects only refreshed active canonical record',async()=>{
  const f=fixture();f.service.addSubletProvider=async()=>{f.state.rows=[{id:'concurrent',name:'New Provider',email:'original@example.com',active:true}];return {ok:false,error:'duplicate_name'};};await f.save();
  assert.equal(f.nodes['sublet-create-provider'].value,'concurrent');assert.equal(f.nodes['sublet-create-provider-email'].value,'original@example.com');
});
test('inactive duplicate remains unchanged and does not unblock booking',async()=>{
  const f=fixture();f.state.rows=[{id:'inactive',name:'New Provider',email:'original@example.com',active:false}];await f.save();
  assert.equal(f.state.calls.length,0);assert.match(f.nodes['sublet-new-provider-error'].textContent,/inactive/i);assert.equal(f.nodes['sublet-new-provider'].hidden,false);assert.equal(f.state.rows[0].active,false);
});
test('operator/viewer cannot add even when controls are invoked directly',async()=>{
  for(const role of ['operator','viewer','']){const f=fixture();f.state.role=role;await f.save();assert.equal(f.state.calls.length,0);assert.match(f.nodes['sublet-new-provider-error'].textContent,/Administrator/);}
});
test('invalid name/email never reaches reference mutation',async()=>{
  for(const [name,email] of [['   ',''],['Provider','broken-address']]){const f=fixture();f.nodes['sublet-new-provider-name'].value=name;f.nodes['sublet-new-provider-email'].value=email;await f.save();assert.equal(f.state.calls.length,0);assert.ok(f.nodes['sublet-new-provider-error'].textContent);}
});
test('directory read failure, mutation rejection and network error stay editable for retry',async()=>{
  for(const mode of ['cache','permission','network']){const f=fixture();if(mode==='cache')f.state.cacheError={message:'offline'};else f.service.addSubletProvider=async()=>{if(mode==='network')throw Error('offline');return {ok:false,error:'permission_denied'};};await f.save();assert.equal(f.nodes['sublet-new-provider'].hidden,false);assert.ok(f.nodes['sublet-new-provider-error'].textContent);assert.equal(f.nodes['sublet-create-provider'].disabled,false);assert.equal(f.nodes.save.disabled,false);}
});
test('failed refresh after successful add never guesses provider identity',async()=>{
  const f=fixture();f.service.addSubletProvider=async()=>({ok:true,provider:{id:'uncached',name:'New Provider',active:true}});await f.save();assert.equal(f.nodes['sublet-create-provider'].value,'');assert.match(f.nodes['sublet-new-provider-error'].textContent,/refreshed/);
});
test('close/reopen, auth token change, authority loss and service replacement discard stale response',async()=>{
  for(const mode of ['reopen','closed','token','role','service']){const f=fixture();const gate=deferred();f.service.listSubletProviders=()=>gate.promise;const request=f.save();
    if(mode==='reopen')vm.runInContext('providerGeneration++',f.ctx);if(mode==='closed')f.nodes['sublet-create-dialog'].open=false;if(mode==='token')f.state.token='another-token';if(mode==='role')f.state.role='viewer';if(mode==='service')f.ctx.window.__workshopReferenceDataService={};
    gate.resolve([]);await request;assert.equal(f.state.calls.length,0);assert.equal(f.nodes['sublet-create-provider'].value,'');}
});
test('provider entry capture handler blocks form submission and exposes no booking mutation',()=>{
  const block=source.slice(source.indexOf("form.addEventListener('submit'"),source.indexOf("    const entry=document.getElementById('sublet-new-provider');",source.indexOf("form.addEventListener('submit'")));
  assert.match(block,/preventDefault/);assert.match(block,/stopImmediatePropagation/);assert.match(block,/capture:true/);assert.doesNotMatch(helpers,/createSubletBooking|updateSubletBooking/);
});
