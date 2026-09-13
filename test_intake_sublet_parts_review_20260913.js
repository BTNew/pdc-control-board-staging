'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'app.js'),'utf8');
const intake=require('./pdc-new-vehicles.js');

function extract(name){
  const start=source.search(new RegExp('(?:async )?function '+name+'\\('));
  assert(start>=0,`Missing function ${name}`);
  const tail=source.slice(start),end=tail.slice(1).search(/\n(?:async )?function /);
  return end<0?tail:tail.slice(0,end+1);
}
const clean=value=>String(value??'').trim();
const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};

test('Parts STOPPAGE retains its reason and clear action alongside imported evidence',()=>{
  const ctx={cleanNavisionText:clean,escapeHtml:escape,partsJobDef:()=>({key:'parts'}),canonicalVehicleWorkState:v=>({state:v.pdcPartsStoppage?'stoppage':'booked'}),partsMiscAcc:()=>false,pdcJobRequired:()=>true,
    PDC_JOB_BY_KEY:new Map([['parts',{key:'parts'}]]),partsStateComplete:v=>v.pdcPartsFlags?.parts_complete===true,vehicleKey:v=>v.stock,partsHasValidAuthoritativeEta:()=>true,
    vehicleCustomerName:()=> 'Synthetic customer',displayVehicle:()=> 'Hilux',partsStoppageReason:v=>v.pdcPartsStoppageReason,vehicleNavisionJitaNumber:()=>'',partsWorstEtaInputValue:()=>'',partsWorstEtaCountdownLabel:()=>'',partsWorstEtaCountdownClass:()=>'',vehicleKeyNumber:()=>'',displayStockNumber:v=>v.stock,vehicleJobcardNumber:()=> 'JC1'};
  vm.createContext(ctx);vm.runInContext(['importedPartsStatus','importedPartsTitle','isActivePartsStoppage','partsDepartmentStatus','partsDepartmentStatusLabel','partsDepartmentStatusClass','partsQueueActionsHtml','partsQueueRowHtml'].map(extract).join('\n'),ctx);
  const vehicle={stock:'00123',pdcPartsStoppage:true,pdcPartsStoppageReason:'Missing safety fitting',pdcRequiresParts:true,pdcPartsFlags:{feed:'separate_parts_status',colour:'orange',parts_complete:false,label:'Parts outstanding — see job cards'}};
  const before=JSON.stringify(vehicle),html=ctx.partsQueueRowHtml(vehicle);
  assert.equal(ctx.partsDepartmentStatus(vehicle),'stoppage');
  assert.match(html,/data-parts-clear-stoppage="00123"/);
  assert.match(html,/Missing safety fitting/);
  assert.match(html,/Parts outstanding — see job cards/);
  assert.doesNotMatch(html,/data-parts-stoppage="00123"/);
  assert.equal(JSON.stringify(vehicle),before);
  assert.equal(ctx.partsDepartmentStatus({...vehicle,pdcPartsStoppage:false,pdcPartsStoppageReason:''}),'import:Parts outstanding — see job cards');
});

function subletFixture(){
  const nodes={},listeners={},state={token:'fixture-token',calls:[],refreshes:0,renders:0,closes:0,pending:[]};
  for(const id of ['sublet-search','sublet-create-vehicle-id','sublet-create-error','sublet-create-vehicle-results','sublet-create-provider','sublet-create-out-date','sublet-create-return-date','sublet-create-vehicle-search','sublet-create-provider-email','sublet-create-notes','sublet-create-operation'])nodes[id]={value:'',textContent:'',innerHTML:'',disabled:false,isConnected:true,focus(){}};
  const submit={textContent:'Create booking',disabled:false,isConnected:true};
  const controls=Object.entries(nodes).filter(([id])=>!['sublet-search','sublet-create-error','sublet-create-vehicle-results'].includes(id)).map(([,node])=>node).concat(submit);
  const form={attributes:{},reset(){controls.forEach(node=>{if('value' in node)node.value='';});},querySelector:()=>submit,querySelectorAll:()=>controls,setAttribute(name,value){this.attributes[name]=value;},removeAttribute(name){delete this.attributes[name];}};
  const dialog={open:true,showModal(){this.open=true;},close(){state.closes++;this.open=false;}};
  nodes['sublet-create-form']=form;nodes['sublet-create-dialog']=dialog;nodes['sublet-create-form button[type="submit"]']=submit;
  const vehicle={__emailVehicleId:'fixture-vehicle',__emailVehicleVersion:3};
  const service={createSubletBooking(...args){state.calls.push(args);const pending=deferred();state.pending.push(pending);return pending.promise;}};
  const ctx={window:{PDC_AUTH_CONTEXT:{role:'administrator',userId:'fixture-user'},PDC_SUBLET_INTAKE:{jobs:()=>[{lineIdentity:'operation1'}],pending:()=>[{lineIdentity:'operation1'}]},addEventListener:(name,fn)=>{listeners[name]=fn;},setTimeout:fn=>fn()},
    app:{emailVehicleLocationService:service,subletOperationalFilter:'to-book'},$:selector=>nodes[selector.slice(1)],cleanNavisionText:clean,escapeHtml:escape,plainDateValue:clean,getPdcSupabaseAccessToken:()=>state.token,
    subletCreateCanonicalVehicles:()=>[vehicle],subletTodayDateKey:()=> '2026-09-14',loadSubletProviderRecords:()=>[{id:'provider1',name:'Synthetic provider'}],refreshEmailVehicleLocations:async()=>{state.refreshes++;},renderSubletHome:()=>{state.renders++;},renderSubletCreateVehicleMatches:()=>{}};
  vm.createContext(ctx);
  vm.runInContext(source.slice(source.indexOf('const subletCreateSession ='),source.indexOf('function subletCreateCanonicalVehicles'))+['openSubletCreateDialog','closeSubletCreateDialog','submitSubletCreate'].map(extract).join('\n'),ctx);
  function fill(){nodes['sublet-create-vehicle-id'].value='fixture-vehicle:3';nodes['sublet-create-provider'].value='provider1';nodes['sublet-create-out-date'].value='2026-09-14';nodes['sublet-create-return-date'].value='2026-09-15';nodes['sublet-create-operation'].value='operation1';nodes['sublet-create-notes'].value='Synthetic tint';}
  fill();return {ctx,nodes,state,listeners,dialog,form,submit,fill};
}

test('Sublet create has one in-flight request and preserves canonical booking payload',async()=>{
  const f=subletFixture(),first=f.ctx.submitSubletCreate();
  assert.equal(await f.ctx.submitSubletCreate(),false);
  assert.equal(f.state.calls.length,1);assert.equal(f.submit.disabled,true);assert.equal(f.form.attributes['aria-busy'],'true');
  assert.deepEqual(f.state.calls[0],['fixture-vehicle',3,'provider1','2026-09-14','2026-09-15','','Synthetic tint','operation1']);
  f.state.pending[0].resolve({ok:true});assert.equal(await first,true);
  assert.equal(f.dialog.open,false);assert.equal(f.submit.disabled,false);assert.equal(f.ctx.app.subletOperationalFilter,'booked');assert.equal(f.state.refreshes,1);
});

test('old Sublet completion cannot dismiss a newly opened booking draft',async()=>{
  const f=subletFixture(),first=f.ctx.submitSubletCreate();
  f.ctx.closeSubletCreateDialog();f.ctx.openSubletCreateDialog();f.fill();f.nodes['sublet-create-notes'].value='Replacement draft';
  f.state.pending[0].resolve({ok:true});assert.equal(await first,false);
  assert.equal(f.dialog.open,true);assert.equal(f.nodes['sublet-create-notes'].value,'Replacement draft');assert.equal(f.state.closes,1);assert.equal(f.state.refreshes,0);assert.equal(f.submit.disabled,false);
});

test('auth lock or changed user/token/service invalidates a pending booking completion',async()=>{
  for(const mode of ['locked','user','token','service']){
    const f=subletFixture(),first=f.ctx.submitSubletCreate();
    if(mode==='locked'){f.listeners['pdc-auth-locked']();f.ctx.openSubletCreateDialog();f.fill();}
    if(mode==='user')f.ctx.window.PDC_AUTH_CONTEXT.userId='another-user';
    if(mode==='token')f.state.token='another-token';
    if(mode==='service')f.ctx.app.emailVehicleLocationService={};
    const closes=f.state.closes;f.state.pending[0].resolve({ok:true});assert.equal(await first,false,mode);
    assert.equal(f.dialog.open,true,mode);assert.equal(f.state.closes,closes,mode);assert.equal(f.state.refreshes,0,mode);
    assert.equal(f.ctx.app.subletOperationalFilter,'to-book',mode);
  }
});

test('uncertain Sublet save restores controls and retains the chosen requirement for review',async()=>{
  for(const thrown of [false,true]){
    const f=subletFixture(),request=f.ctx.submitSubletCreate();
    if(thrown)f.state.pending[0].reject(new Error('offline'));else f.state.pending[0].resolve({ok:false,code:'sublet_create_unavailable'});
    assert.equal(await request,false);assert.equal(f.dialog.open,true);assert.equal(f.submit.disabled,false);
    assert.equal(f.nodes['sublet-create-operation'].value,'operation1');assert.equal(f.nodes['sublet-create-notes'].value,'Synthetic tint');
    assert.match(f.nodes['sublet-create-error'].textContent,/could not be confirmed/);
  }
});

test('queue search matches stock, customer and any job card without modifying review data',()=>{
  const rows=[{stock_number:'00123',customer_name:'Busselton Toyota',job_cards:['J100','J200']},{stock_number:'999',customer_name:'Other customer',job_cards:['J300']}],before=JSON.stringify(rows);
  for(const query of ['00123','BUSSELTON',' j200 '])assert.deepEqual(intake.matchingReviewRows(rows,query),[rows[0]]);
  assert.deepEqual(intake.matchingReviewRows(rows,'missing'),[]);assert.deepEqual(intake.matchingReviewRows(rows,''),rows);assert.equal(JSON.stringify(rows),before);
});
