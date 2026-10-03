'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const finance = require('./sales/finance-pipeline.js');
const source = fs.readFileSync(path.join(__dirname, 'sales/finance-pipeline.js'), 'utf8');
const month = finance.perthDay().slice(0, 7);
const privateKeys = ['financier', 'finance_comm', 'dof_daf', 'mvi', 'rsa', 'naf', 'total_comm'];
const rows = [
  {id:'alpha',customer:'Example Avery',new_used:'New',financier:'TFS',group_name:'Broome',approval:'Yes',settlement:'No',notes:'Documents waiting on customer',access:'Yes',payout_complete:'',finance_comm:10,dof_daf:10,mvi:null,rsa:0,naf:5000,salesperson_code:'BG',version:1},
  {id:'beta',customer:'Example Bailey',new_used:'Used',financier:'TFM',group_name:'Port Hedland',approval:'No',settlement:'No',notes:'Documents not yet submitted',access:'No',payout_complete:'No',finance_comm:'20.10',dof_daf:0,mvi:5,rsa:0,naf:2000,salesperson_code:'CW',version:1},
  {id:'gamma',customer:'Example Casey',new_used:'Used',financier:'FARADAY',group_name:'Broome',approval:'',settlement:'Yes',settlement_date:month+'-01',notes:'',access:'',payout_complete:'Yes',finance_comm:0,dof_daf:0,mvi:0,rsa:0,naf:1000,salesperson_code:'BG',version:1},
  {id:'delta',customer:'Example Devon',new_used:'New',financier:'OTHER',group_name:'Port Hedland',approval:'Yes',settlement:'No',notes:'Unsubmitted application',access:'',payout_complete:'',finance_comm:null,dof_daf:null,mvi:null,rsa:null,naf:null,salesperson_code:'BG',version:1},
  {id:'epsilon',customer:'Example Emery',new_used:'New',financier:'TFS',group_name:'Broome',approval:'No',settlement:'Yes',settlement_date:month+'-01',notes:'Second settled application',access:'Yes',payout_complete:'No',finance_comm:5,dof_daf:0,mvi:0,rsa:0,naf:3000,salesperson_code:'BG',version:1}
];
const rule = fields => ({mode:'all',value:'',query:'',min:'',max:'',...fields});
const ids = records => Array.from(records, record => record.id);
const copy = value => JSON.parse(JSON.stringify(value));

test('text filters contain case-insensitively while exact values and columns combine with AND', () => {
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{customer:rule({query:'  aVeRy  '})},true)),['alpha']);
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{notes:rule({query:'DOCUMENTS'})},true)),['alpha','beta']);
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{approval:rule({mode:'value',value:'Yes'}),group_name:rule({mode:'value',value:'Broome'})},true)),['alpha']);
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{new_used:rule({mode:'value',value:'New'}),notes:rule({query:'application'})},true)),['delta','epsilon']);
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{financier:rule({mode:'value',value:'TF'})},true)),[],'an exact financier choice must not become a prefix match');
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{customer:rule({mode:'value',value:'Example Avery',query:'avery'})},true)),['alpha']);
});

test('blank numeric values remain different from zero and boundaries are inclusive', () => {
  const values=[{id:'null',finance_comm:null},{id:'missing'},{id:'empty',finance_comm:''},{id:'spaces',finance_comm:'  '},{id:'zero',finance_comm:0},{id:'string-zero',finance_comm:'0.00'},{id:'lower',finance_comm:'10.10'},{id:'upper',finance_comm:20.2},{id:'outside',finance_comm:20.21}];
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{finance_comm:rule({mode:'blank'})},true)),['null','missing','empty','spaces']);
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{finance_comm:rule({mode:'value',value:'0'})},true)),['zero','string-zero']);
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{finance_comm:rule({min:'0',max:'0'})},true)),['zero','string-zero']);
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{finance_comm:rule({min:'10.10',max:'20.20'})},true)),['lower','upper']);
  for(const key of ['finance_comm','dof_daf','mvi','rsa','naf']) {
    const list=[{id:'below',[key]:1},{id:'inside',[key]:'2.10'},{id:'boundary',[key]:3},{id:'blank',[key]:null}];
    assert.deepEqual(ids(finance.filterFinanceEntries(list,{[key]:rule({min:'2.10',max:'3'})},true)),['inside','boundary'],key);
  }
});

test('total commission filters compute component cents and never use NAF or a stale stored total', () => {
  const values=[{id:'decimal',finance_comm:.1,dof_daf:.2,naf:90000,total_comm:99999},{id:'other',finance_comm:.31,total_comm:.3},{id:'none',naf:5000},{id:'zero',finance_comm:0}];
  assert.equal(finance.financeFilterValue(values[0],'total_comm'),'0.3');
  assert.equal(finance.financeFilterValue(values[2],'total_comm'),'0');
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{total_comm:rule({min:'0.30',max:'0.30'})},true)),['decimal']);
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{total_comm:rule({mode:'value',value:'0'})},true)),['none','zero']);
  assert.deepEqual(ids(finance.filterFinanceEntries(values,{total_comm:rule({mode:'blank'})},true)),[]);
});

test('filter choices normalize duplicates and blanks without altering saved rows or their order', () => {
  const values=[{id:'first',customer:'  Example Avery ',approval:'Yes',finance_comm:'10.00'},{id:'second',customer:'Example Avery',approval:'Yes',finance_comm:10},{id:'third',customer:'',approval:null,finance_comm:0},{id:'fourth',approval:'No',finance_comm:null}];
  const before=JSON.stringify(values);values.forEach(Object.freeze);Object.freeze(values);
  assert.equal(finance.financeFilterValue(values[0],'customer'),'Example Avery');
  assert.equal(finance.financeFilterValue(values[0],'finance_comm'),'10');
  assert.deepEqual(new Set(finance.financeFilterOptions(values,'customer',true)),new Set(['Example Avery','']));
  assert.deepEqual(new Set(finance.financeFilterOptions(values,'finance_comm',true)),new Set(['10','0','']));
  const filtered=finance.filterFinanceEntries(values,{approval:rule({mode:'value',value:'Yes'})},true);
  assert.deepEqual(ids(filtered),['first','second']);assert.strictEqual(filtered[0],values[0]);assert.strictEqual(filtered[1],values[1]);
  assert.equal(JSON.stringify(values),before);
});

test('ordinary salespeople cannot filter or discover private amounts and unknown keys are ignored', () => {
  const filters=Object.fromEntries(privateKeys.map(key=>[key,rule({mode:'value',value:'impossible',min:'999999999'})]));
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,filters,false)),ids(rows));
  for(const key of [...privateKeys,'current_location','constructor','__proto__'])assert.deepEqual(finance.financeFilterOptions(rows,key,false),[],key);
  assert.deepEqual(finance.financeFilterOptions(rows,'unknown',true),[]);
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{unknown:rule({mode:'blank'})},true)),ids(rows));
  assert.deepEqual(ids(finance.filterFinanceEntries(rows,{...filters,approval:rule({mode:'value',value:'Yes'})},false)),['alpha','delta']);
});

function harness() {
  const elements=new Map(),calls=[];let token='finance-filter-fixture',scope='',view='finance';
  function el(id) {
    if(!elements.has(id))elements.set(id,{id,value:'',innerHTML:'',textContent:'',hidden:false,disabled:false,dataset:{},events:{},attrs:{},fields:new Map(),closed:true,
      addEventListener(name,handler){this.events[name]=handler;},setAttribute(name,value){this.attrs[name]=value;},getAttribute(name){return this.attrs[name];},removeAttribute(name){delete this.attrs[name];},
      focus(){this.focused=true;},scrollIntoView(){},close(){this.closed=true;},showModal(){this.closed=false;},
      querySelector(selector){if(!this.fields.has(selector)){const name=selector.match(/name=["']([^"']+)/)?.[1];this.fields.set(selector,{name,value:'',innerHTML:'',textContent:'',hidden:false,disabled:false,dataset:{},focus(){this.focused=true;},querySelector(){return null;}});}return this.fields.get(selector);},
      querySelectorAll(){return [];}
    });return elements.get(id);
  }
  const window={document:{getElementById:el,activeElement:null},crypto:{randomUUID:()=> 'finance-filter-created'},PDC_AUTH_CONTEXT:{userId:token},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  class FormData {constructor(form){this.form=form;}get(key){return this.form.values?.[key]??this.form.querySelector?.('[name="'+key+'"]')?.value??'';}}
  vm.runInNewContext(source,{window,globalThis:window,module:undefined,console,Map,Set,FormData});
  const api=window.BROOME_SALES_FINANCE;
  api.init({getToken:()=>token,getContext:()=>({role:'administrator'}),getSalesperson:()=>scope,getView:()=>view});
  const button=(dataset={},attrs=[])=>({dataset,hasAttribute:name=>attrs.includes(name)||Object.keys(dataset).some(k=>'data-'+k.replace(/[A-Z]/g,c=>'-'+c.toLowerCase())===name),getAttribute:name=>dataset[name.replace(/^data-/,'').replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]??'',closest(){return this;}});
  async function refresh(records=rows,canEdit=true) {const pending=api.refresh();calls.at(-1).resolve({data:{context:{role:canEdit?'administrator':'salesperson',can_edit_finance:canEdit},entries:copy(records),vehicle_options:[],salespeople:[]}});await pending;}
  function click(dataset={},attrs=[]) {return el('sales-finance').events.click({target:button(dataset,attrs)});}
  function change(attribute,value) {return el('sales-finance').events.change({target:{value,hasAttribute:name=>name===attribute}});}
  function apply(column,fields={}) {
    click({financeFilter:column});
    const form={id:'finance-filter-form',values:{column,value:'all',query:'',min:'',max:'',...fields},querySelector:selector=>el('finance-filter-form').querySelector(selector),closest(){return this;}};
    return el('finance-filter-content').events.submit({target:form,preventDefault(){this.prevented=true;}});
  }
  function edit(id,key,value) {
    const tr={controls:new Map(),querySelector(selector){if(!this.controls.has(selector))this.controls.set(selector,{hidden:true,disabled:false,textContent:'',title:'',querySelector(){return null;}});return this.controls.get(selector);}};
    return el('sales-finance').events.input({target:{dataset:{financeId:id,financeKey:key},value,closest:()=>tr}});
  }
  return {el,calls,api,window,refresh,click,change,apply,edit,html:()=>el('sales-finance').innerHTML,
    setScope:value=>scope=value,setToken:value=>{token=value;window.PDC_AUTH_CONTEXT={userId:value};},setView:value=>view=value};
}
const tbody=h=>h.html().match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1]||'';

test('every available finance header opens a filter and mobile toolbar exposes the same controls without saving', async () => {
  const h=harness();await h.refresh();
  for(const [key] of finance.columns)assert.match(h.html(),new RegExp('data-finance-filter="'+key+'"'));
  assert.match(h.html(),/data-finance-filters/);assert.doesNotMatch(h.html(),/data-finance-clear-filters/,'no recovery control is needed before filtering');
  h.click({financeFilter:'approval'});assert.equal(h.el('finance-filter-dialog').closed,false);assert.match(h.el('finance-filter-content').innerHTML,/id="finance-filter-form"/);
  assert.match(h.el('finance-filter-content').innerHTML,/name="column"/);assert.match(h.el('finance-filter-content').innerHTML,/name="value"/);
  assert.match(h.el('finance-filter-content').innerHTML,/value="value:Yes"/);assert.match(h.el('finance-filter-content').innerHTML,/value="blank"/);
  h.el('finance-filter-dialog').events.cancel();assert.equal(h.el('finance-filter-dialog').closed,true);
  h.click({},['data-finance-filters']);assert.equal(h.el('finance-filter-dialog').closed,false);assert.match(h.el('finance-filter-content').innerHTML,/name="column"/);
  h.apply('approval',{value:'value:Yes'});assert.match(h.html(),/data-finance-clear-filters/);assert.match(h.html(),/class="finance-header-filter active" data-finance-filter="approval"/);assert.match(h.html(),/<span aria-hidden="true">●<\/span>/);
  assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'get_broome_finance_pipeline');
});

test('header value, contains and amount filters combine, with a clear recovery from no matching rows', async () => {
  const h=harness();await h.refresh();h.change('data-finance-view','all');
  h.apply('approval',{value:'value:Yes'});assert.equal(h.el('finance-filter-dialog').closed,true);
  assert.match(tbody(h),/Example Avery|Example Devon/);assert.doesNotMatch(tbody(h),/Example Bailey|Example Casey|Example Emery/);
  h.apply('customer',{query:'AvErY'});assert.match(tbody(h),/Example Avery/);assert.doesNotMatch(tbody(h),/Example Devon/);
  h.apply('finance_comm',{min:'10',max:'10'});assert.match(tbody(h),/Example Avery/);
  h.apply('notes',{query:'not-a-matching-update'});assert.equal(tbody(h),'');assert.match(h.html(),/No .*match|No .*entries|No .*applications/i);
  h.click({},['data-finance-clear-filters']);for(const row of rows)assert.match(tbody(h),new RegExp(row.customer));
  assert.equal(h.calls.length,1,'view and filter changes must not save finance or change PDC records');
});

test('blank selections exclude a stored zero and filter options escape customer-controlled text', async () => {
  const records=[...rows,{...rows[0],id:'unsafe',customer:'<img src=x onerror=alert(1)> & Example',notes:'<script>fictional</script>'}];
  const h=harness();await h.refresh(records);h.change('data-finance-view','all');
  h.apply('finance_comm',{value:'blank'});assert.match(tbody(h),/Example Devon/);assert.doesNotMatch(tbody(h),/Example Casey/);
  h.click({},['data-finance-clear-filters']);h.click({financeFilter:'customer'});
  const dialog=h.el('finance-filter-content').innerHTML;assert.match(dialog,/&lt;img/);assert.doesNotMatch(dialog,/<img|onerror="|<script>/);
  assert.equal(h.calls.length,1);
});

test('filters use saved values while preserving unsaved edits through hide, clear, poll and view changes', async () => {
  const h=harness();await h.refresh();h.change('data-finance-view','all');h.edit('alpha','customer','Pending customer draft');
  h.apply('customer',{query:'Pending customer draft'});assert.equal(tbody(h),'','drafts must not alter saved matching values');
  h.click({},['data-finance-clear-filters']);assert.match(tbody(h),/value="Pending customer draft"/);
  h.apply('approval',{value:'value:No'});assert.doesNotMatch(tbody(h),/Pending customer draft/);
  await h.refresh();assert.doesNotMatch(tbody(h),/Pending customer draft/);
  h.change('data-finance-view','statistics');h.change('data-finance-view','all');assert.doesNotMatch(tbody(h),/Pending customer draft/,'view changes must preserve the approval filter');
  h.click({},['data-finance-clear-filters']);assert.match(tbody(h),/value="Pending customer draft"/);
  assert.equal(h.calls.length,2);assert.ok(h.calls.every(call=>call.name==='get_broome_finance_pipeline'));
  const save=h.click({financeSave:'alpha'});assert.equal(h.calls[2].name,'save_broome_finance_application');assert.equal(h.calls[2].args.p_data.customer,'Pending customer draft');assert.equal(h.calls[2].args.p_expected_version,1);
  h.calls[2].resolve({data:{record:{...rows[0],customer:'Pending customer draft',version:2}}});await save;
});

test('header filters never shrink settlement statistics or their period and location calculations', async () => {
  const h=harness();await h.refresh();h.change('data-finance-view','all');h.apply('approval',{value:'value:Yes'});
  const before=h.calls.length;h.change('data-finance-view','statistics');
  assert.match(h.html(),/Example Casey/);assert.match(h.html(),/Example Emery/);
  assert.match(h.html(),/Settled applications \/ contracts<\/span><strong>2<\/strong>/);
  assert.match(h.html(),/Settled NAF<\/span><strong>\$4,000\.00<\/strong>/);
  h.change('data-finance-view','all');assert.doesNotMatch(tbody(h),/Example Casey|Example Emery/);assert.match(tbody(h),/Example Avery/);
  assert.equal(h.calls.length,before);
});

test('account and salesperson scope changes reset filters and close the dialog rather than carrying hidden drafts', async () => {
  const h=harness();await h.refresh();h.change('data-finance-view','all');h.edit('alpha','notes','Private unsaved note');h.apply('approval',{value:'value:Yes'});h.click({financeFilter:'customer'});
  h.setScope('BG');h.api.syncScope();h.api.render();assert.equal(h.el('finance-filter-dialog').closed,true);assert.equal(h.el('finance-filter-content').innerHTML,'');
  assert.match(tbody(h),/Example Emery/);assert.doesNotMatch(tbody(h),/Private unsaved note|Example Bailey/);
  h.apply('approval',{value:'value:Yes'});h.click({financeFilter:'customer'});h.setToken('replacement-finance-account');h.api.syncScope();assert.equal(h.el('finance-filter-dialog').closed,true);assert.equal(h.html(),'');
  await h.refresh();h.change('data-finance-view','all');assert.match(tbody(h),/Example Emery/);assert.doesNotMatch(tbody(h),/Private unsaved note/);
  assert.ok(h.calls.every(call=>call.name==='get_broome_finance_pipeline'));
});

test('permission downgrade clears filters and private dialog content; forged private choices cannot restrict or expose rows', async () => {
  const h=harness();await h.refresh();h.change('data-finance-view','all');h.apply('approval',{value:'value:Yes'});h.click({financeFilter:'financier'});
  assert.match(h.el('finance-filter-content').innerHTML,/value:TFM|value:FARADAY/);
  await h.refresh(rows,false);assert.equal(h.el('finance-filter-dialog').closed,true);assert.equal(h.el('finance-filter-content').innerHTML,'');
  for(const key of privateKeys)assert.doesNotMatch(h.html(),new RegExp('data-finance-filter="'+key+'"'));
  assert.match(tbody(h),/Example Bailey|Example Emery/,'public filters must reset too');
  h.click({financeFilter:'financier'});assert.equal(h.el('finance-filter-dialog').closed,true);
  h.click({},['data-finance-filters']);const dialog=h.el('finance-filter-content').innerHTML;
  for(const key of privateKeys)assert.doesNotMatch(dialog,new RegExp('<option value="'+key+'"'));
  h.el('finance-filter-content').events.change({target:{name:'column',value:'financier'}});
  assert.equal(h.el('finance-filter-content').innerHTML,dialog,'a forged private column change must not replace the allowed public filter');
  h.el('finance-filter-dialog').events.cancel();h.click({financeFilter:'finance_comm'});assert.equal(h.el('finance-filter-dialog').closed,true);
  const form={id:'finance-filter-form',values:{column:'finance_comm',value:'value:999999',query:'',min:'999999',max:''},querySelector:selector=>h.el('finance-filter-form').querySelector(selector),closest(){return this;}};
  h.el('finance-filter-content').events.submit({target:form,preventDefault(){}});
  assert.match(tbody(h),/Example Bailey|Example Emery/);assert.doesNotMatch(h.el('finance-filter-content').innerHTML,/value:TFM|value:FARADAY/);
  assert.equal(h.calls.length,2);assert.ok(h.calls.every(call=>call.name==='get_broome_finance_pipeline'));
});
