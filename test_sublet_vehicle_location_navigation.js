'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'app.js'),'utf8');
const guard=require('./vehicle-requirements-guard.js');
function section(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);assert(a>=0&&b>a);return source.slice(a,b);}
const clean=value=>String(value??'').trim();
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function routingFixture(rows=[]){
  const calls=[];
  const nodes={'sublet-search':{value:'old search',focus(){calls.push('focus');},select(){calls.push('select');}},'sublet-provider-filter':{value:'Old provider'}};
  const context={app:{subletViewMode:'calendar',subletOperationalFilter:'returned'},cleanNavisionText:clean,displayStockNumber:v=>v.stock,
    $:selector=>nodes[selector.slice(1)],subletRows:()=>rows,plainDateValue:value=>/^\d{4}-\d{2}-\d{2}/.exec(String(value||''))?.[0]||'',
    showView:view=>calls.push({view,query:nodes['sublet-search'].value,mode:context.app.subletViewMode,status:context.app.subletOperationalFilter,provider:nodes['sublet-provider-filter'].value})};
  vm.createContext(context);vm.runInContext(section('function subletBookingState','function compareSubletBookingDate')+section('function openSubletForStock','function bindIncomingCardSelection'),context);
  return {context,nodes,calls};
}
test('jump uses exact stock, resets stale filters and preserves leading zeroes',()=>{
  const rows=[{stock:'123',pmbSubletBookingDate:''},{stock:'00123',pmbSubletBookingDate:'2026-09-16',pdcRequiresSublet:true}];
  const before=JSON.stringify(rows),f=routingFixture(rows);
  assert.equal(f.context.openSubletForStock(' 00123 '),true);
  assert.deepEqual(f.calls,[{view:'sublet',query:'00123',mode:'list',status:'booked',provider:'all'},'focus','select']);
  assert.equal(JSON.stringify(rows),before,'navigation does not change work status or booking data');
});
test('pending takes priority, then booked, then returned; no rows still allows creation',()=>{
  for(const [rows,expected] of [
    [[{stock:'A',pmbSubletBookingDate:'2026-09-14'},{stock:'A'}],'to-book'],
    [[{stock:'A',__subletBookingStatus:'returned'},{stock:'A',pmbSubletBookingDate:'2026-09-14'}],'booked'],
    [[{stock:'A',__subletBookingStatus:'returned'}],'returned'],
    [[{stock:'A',__subletBookingStatus:'cancelled',pmbSubletBookingDate:'2026-09-14'}],'to-book'],
    [[],'to-book']]){
    const f=routingFixture(rows);f.context.openSubletForStock('A');assert.equal(f.context.app.subletOperationalFilter,expected);assert.equal(f.nodes['sublet-search'].value,'A');
  }
});
test('empty stock or unavailable search does not navigate or alter filters',()=>{
  const f=routingFixture();assert.equal(f.context.openSubletForStock('  '),false);delete f.nodes['sublet-search'];assert.equal(f.context.openSubletForStock('123'),false);assert.equal(f.calls.length,0);assert.equal(f.context.app.subletViewMode,'calendar');
});
test('pill click cancels row disclosure and triggers one navigation',()=>{
  const f=routingFixture();let handler;const root={};f.context.$$=(selector,host)=>{assert.equal(selector,'[data-open-sublet-stock]');assert.equal(host,root);return [{dataset:{openSubletStock:'00123'},addEventListener(type,fn){assert.equal(type,'click');handler=fn;}}];};
  f.context.bindIncomingSubletLinks(root);let prevented=0,stopped=0;handler({preventDefault(){prevented++;},stopPropagation(){stopped++;}});assert.equal(prevented,1);assert.equal(stopped,1);assert.equal(f.calls.filter(x=>x.view).length,1);
});
function rendererFixture(){
  const def={key:'sublet',label:'Sublet',requireKey:'pdcRequiresSublet',completeKey:'pdcCompleteSublet'};
  const context={vehicleKey:v=>v.stock||'',cleanNavisionText:clean,displayStockNumber:v=>v.stock||'',normalizePmbStage:clean,inferredPmbStage:()=>'',
    vehicleWorkshopBookingProjection:()=>({bookingRequired:false,activeBookings:[]}),pdcJobDefsPartsFirst:()=>[def],pdcJobRequired:(v,d)=>v[d.requireKey]===true,pdcJobComplete:(v,d)=>v[d.completeKey]===true,
    pmbStageForPdcJob:()=>'',PMB_STAGE_TO_JOB_KEY:{},isActivePartsStoppage:()=>false,isPdcBlocked:()=>false,partsOrdered:()=>false,
    canonicalVehicleWorkState:(v,d,o)=>guard.projectWorkState({workKey:d.key,required:v[d.requireKey]===true,completed:v[d.completeKey]===true,bookings:o.bookings,subletBookings:v.pdcSubletBookings||[]}),
    pdcGridJobLabel:()=> 'Sublet',pdcJobCompletionTitle:()=> 'Sublet required',escapeHtml:esc};
  vm.createContext(context);vm.runInContext(section('function canonicalActiveSubletBooking','function pdcWorkDestination')+section('function incomingWorkChecklistHtml','function workStatusLegendHtml'),context);return context;
}
test('only opted-in Vehicle Locations pills become buttons, in every work state',()=>{
  const c=rendererFixture();
  for(const state of [{},{pdcRequiresSublet:true},{pdcRequiresSublet:true,pdcCompleteSublet:true},{pdcRequiresSublet:true,pdcSubletBookings:[{status:'active',outDate:'2026-09-14'}]}]){
    const vehicle={stock:'00123',...state},before=JSON.stringify(vehicle);
    const inert=c.incomingWorkChecklistHtml(vehicle),linked=c.incomingWorkChecklistHtml(vehicle,{subletNavigation:true});
    assert.doesNotMatch(inert,/<button|data-open-sublet-stock/);assert.match(linked,/<button type="button"[^>]*data-open-sublet-stock="00123"/);assert.match(linked,/aria-label="Open Sublet for stock 00123;/);
    assert.equal(linked.match(/class="(incoming-work-check [^"]+)"/)[1],inert.match(/class="(incoming-work-check [^"]+)"/)[1],'work state colours retain original classes');assert.equal(JSON.stringify(vehicle),before);
  }
  assert.doesNotMatch(c.incomingWorkChecklistHtml({stock:''},{subletNavigation:true}),/data-open-sublet-stock/);
  assert.match(c.incomingWorkChecklistHtml({stock:'A"<&'},{subletNavigation:true}),/data-open-sublet-stock="A&quot;&lt;&amp;"/);
});
test('create form inherits search, shows matches and still requires explicit canonical selection',()=>{
  const nodes={};for(const id of ['sublet-search','sublet-create-vehicle-id','sublet-create-error','sublet-create-vehicle-results','sublet-create-provider','sublet-create-out-date','sublet-create-return-date','sublet-create-vehicle-search'])nodes[id]={value:'',innerHTML:'',textContent:'',focus(){}};
  nodes['sublet-search'].value='00123';nodes['sublet-create-dialog']={showModal(){this.open=true;}};nodes['sublet-create-form']={reset(){nodes['sublet-create-vehicle-search'].value='';}};
  const vehicle={stock:'00123',__emailVehicleServerAuthoritative:true,__emailVehicleId:'canonical-id',__emailVehicleVersion:4};
  const context={$:selector=>nodes[selector.slice(1)],resetSubletCreateSession:()=>{},cleanNavisionText:clean,escapeHtml:esc,vehicleLocationBoardRows:()=>[vehicle],displayStockNumber:v=>v.stock,vehicleCustomerName:()=> 'Synthetic customer',displayVehicle:()=> 'Synthetic vehicle',loadSubletProviderRecords:()=>[],subletTodayDateKey:()=> '2026-09-14',window:{setTimeout:fn=>fn()}};
  vm.createContext(context);vm.runInContext(section('function subletCreateCanonicalVehicles','function closeSubletCreateDialog'),context);context.openSubletCreateDialog();
  assert.equal(nodes['sublet-create-vehicle-search'].value,'00123');assert.match(nodes['sublet-create-vehicle-results'].innerHTML,/data-sublet-create-vehicle="canonical-id"/);assert.equal(nodes['sublet-create-vehicle-id'].value,'');assert.equal(nodes['sublet-create-dialog'].open,true);
});
