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

test('settlement filters distinguish actual saved dates, legacy undated contracts and pending applications', () => {
  const records=[...rows,{...rows[0],id:'undated',settlement:'Yes',settlement_date:''},{...rows[0],id:'invalid-date',settlement:'Yes',settlement_date:'2024-02-30'},{...rows[0],id:'old-date',settlement:'Yes',settlement_date:'2024-02-29'},{...rows[0],id:'stale-pending-date',settlement:'No',settlement_date:month+'-01'}],before=JSON.stringify(records);
  assert.equal(finance.financeFilterValue(records[2],'settlement'),month+'-01');assert.equal(finance.financeFilterValue(records[5],'settlement'),'undated');assert.equal(finance.financeFilterValue(records[6],'settlement'),'undated');assert.equal(finance.financeFilterValue(records[8],'settlement'),'');
  assert.deepEqual(new Set(finance.financeFilterOptions(records,'settlement',false)),new Set(['',month+'-01','2024-02-29','undated']));
  assert.deepEqual(ids(finance.filterFinanceEntries(records,{settlement:rule({mode:'value',value:month+'-01'})},false)),['gamma','epsilon']);
  assert.deepEqual(ids(finance.filterFinanceEntries(records,{settlement:rule({mode:'value',value:'undated'})},true)),['undated','invalid-date']);
  assert.deepEqual(ids(finance.filterFinanceEntries(records,{settlement:rule({mode:'blank'})},true)),['alpha','beta','delta','stale-pending-date']);assert.equal(JSON.stringify(records),before);
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
  const window={setTimeout:()=>1,clearTimeout(){},document:{getElementById:el,activeElement:null},crypto:{randomUUID:()=> 'finance-filter-created'},PDC_AUTH_CONTEXT:{userId:token},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  class FormData {constructor(form){this.form=form;}get(key){return this.form.values?.[key]??this.form.querySelector?.('[name="'+key+'"]')?.value??'';}}
  vm.runInNewContext(source,{window,globalThis:window,module:undefined,console,Map,Set,FormData});
  const api=window.BROOME_SALES_FINANCE;
  api.init({getToken:()=>token,getContext:()=>({role:'administrator'}),getSalesperson:()=>scope,getView:()=>view});
  const button=(dataset={},attrs=[])=>({dataset,hasAttribute:name=>attrs.includes(name)||Object.keys(dataset).some(k=>'data-'+k.replace(/[A-Z]/g,c=>'-'+c.toLowerCase())===name),getAttribute:name=>dataset[name.replace(/^data-/,'').replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]??'',closest(){return this;}});
  async function refresh(records=rows,canEdit=true) {const pending=api.refresh();calls.at(-1).resolve({data:{context:{role:canEdit?'administrator':'salesperson',can_edit_finance:canEdit},entries:copy(records),vehicle_options:[],salespeople:[]}});await pending;}
  function click(dataset={},attrs=[]) {return el('sales-finance').events.click({target:button(dataset,attrs)});}
  function filter(key,value,mobile=false) {
    return el('sales-finance').events.change({target:{value,dataset:{financeFilter:key,...(mobile?{financeFilterMobile:key}:{})},hasAttribute:name=>name==='data-finance-filter'||(mobile&&name==='data-finance-filter-mobile')}});
  }
  function edit(id,key,value) {
    const tr={controls:new Map(),querySelector(selector){if(!this.controls.has(selector))this.controls.set(selector,{hidden:true,disabled:false,textContent:'',title:'',querySelector(){return null;}});return this.controls.get(selector);}};
    return el('sales-finance').events.input({target:{dataset:{financeId:id,financeKey:key},value,closest:()=>tr}});
  }
  return {el,calls,api,window,refresh,click,filter,edit,html:()=>el('sales-finance').innerHTML,
    setScope:value=>scope=value,setToken:value=>{token=value;window.PDC_AUTH_CONTEXT={userId:value};},setView:value=>view=value};
}
const tbody=h=>h.html().match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1]||'';
function filterSelect(h,key,mobile=false) {
  const tag=Array.from(h.html().matchAll(/<select\b([^>]*)>([\s\S]*?)<\/select>/g)).find(match=>
    mobile ? match[1].includes('data-finance-filter-mobile')&&(match[1].includes('data-finance-filter="'+key+'"')||match[1].includes('data-finance-filter-mobile="'+key+'"'))
      : !match[1].includes('data-finance-filter-mobile')&&match[1].includes('data-finance-filter="'+key+'"'));
  assert.ok(tag,'native '+(mobile?'mobile ':'header ')+'select for '+key);
  return {attributes:tag[1],options:tag[2],html:tag[0]};
}
const optionValues=control=>Array.from(control.options.matchAll(/<option\b[^>]*value="([^"]*)"/g),match=>match[1]);
const selectedValue=control=>control.options.match(/<option\b[^>]*value="([^"]*)"[^>]*\bselected\b/)?.[1];

test('headers have accessible native dropdowns and view buttons without a filter modal or view select', async () => {
  const h=harness();await h.refresh();
  for(const [key,label] of finance.columns) {
    const control=filterSelect(h,key);
    assert.match(control.attributes,/class="[^"]*\bfinance-header-filter\b/);
    assert.match(control.attributes,/aria-label="[^"]+"/);
    assert.match(control.options,/value="all"/);assert.match(control.options,/value="blank"/);
    const header=h.html().match(new RegExp('<th\\b[^>]*>(?:(?!<\\/th>)[\\s\\S])*?data-finance-filter="'+key+'"(?:(?!<\\/th>)[\\s\\S])*?<\\/th>'))?.[0];
    assert.ok(header,key+' dropdown belongs to its table header');assert.match(header,/<span class="finance-header-label">/);assert.ok(header.includes(label));
  }
  for(const key of ['pipeline','statistics','all'])assert.match(h.html(),new RegExp('<button\\b[^>]*type="button"[^>]*data-finance-view="'+key+'"[^>]*aria-pressed="'+(key==='pipeline'?'true':'false')+'"'));
  assert.doesNotMatch(h.html(),/<select\b[^>]*data-finance-view|data-finance-filters|aria-haspopup="dialog"|finance-filter-form|finance-filter-dialog/);
  const index=fs.readFileSync(path.join(__dirname,'sales/index.html'),'utf8');assert.doesNotMatch(index,/id="finance-filter-dialog"|id="finance-filter-content"/);
  h.click({financeView:'all'});assert.match(tbody(h),/Example Casey|Example Emery/);
  assert.match(h.html(),/<button\b[^>]*data-finance-view="all"[^>]*aria-pressed="true"/);assert.equal(h.calls.length,1);
});

test('mobile dropdowns expose the same saved choices and apply immediately without saving', async () => {
  const h=harness();await h.refresh();
  for(const [key] of finance.columns) {
    const header=filterSelect(h,key),mobile=filterSelect(h,key,true);
    assert.match(mobile.attributes,/aria-label="[^"]+"/);assert.deepEqual(optionValues(mobile),optionValues(header),key);
  }
  h.filter('approval','value:Yes',true);
  assert.match(tbody(h),/Example Avery|Example Devon/);assert.doesNotMatch(tbody(h),/Example Bailey/);
  assert.equal(selectedValue(filterSelect(h,'approval')),'value:Yes');assert.equal(selectedValue(filterSelect(h,'approval',true)),'value:Yes');
  assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'get_broome_finance_pipeline');
});

test('exact column dropdowns combine with AND and clear recovers from no matching saved rows', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});
  h.filter('approval','value:Yes');assert.match(tbody(h),/Example Avery|Example Devon/);assert.doesNotMatch(tbody(h),/Example Bailey|Example Casey|Example Emery/);
  h.filter('customer','value:Example Avery');assert.match(tbody(h),/Example Avery/);assert.doesNotMatch(tbody(h),/Example Devon/);
  h.filter('finance_comm','value:10');assert.match(tbody(h),/Example Avery/);
  h.filter('approval','value:No');assert.equal(tbody(h),'');assert.match(h.html(),/No .*match|No .*entries|No .*applications/i);
  h.click({},['data-finance-clear-filters']);for(const row of rows)assert.match(tbody(h),new RegExp(row.customer));
  assert.equal(h.calls.length,1,'view and filters must not save finance or alter PDC records');
});

test('blank numeric selections exclude a stored zero and customer-controlled options are escaped', async () => {
  const records=[...rows,{...rows[0],id:'unsafe',customer:'<img src=x onerror=alert(1)> & Example',notes:'<script>fictional</script>'}];
  const h=harness();await h.refresh(records);h.click({financeView:'all'});
  h.filter('finance_comm','blank');assert.match(tbody(h),/Example Devon/);assert.doesNotMatch(tbody(h),/Example Casey/);
  h.filter('finance_comm','value:0');assert.match(tbody(h),/Example Casey/);assert.doesNotMatch(tbody(h),/Example Devon/);
  const control=filterSelect(h,'customer');assert.match(control.options,/&lt;img/);assert.match(control.options,/&amp;/);assert.doesNotMatch(control.options,/<img|<script>/);
  assert.equal(h.calls.length,1);
});

test('dropdown choices come from scoped saved base rows rather than other filters or unsaved drafts', async () => {
  const h=harness();h.setScope('BG');await h.refresh();h.click({financeView:'all'});
  h.edit('alpha','customer','Pending customer draft');
  const before=optionValues(filterSelect(h,'customer'));assert.ok(before.includes('value:Example Avery'));assert.ok(!before.some(value=>value.includes('Pending customer draft')));
  assert.ok(!before.includes('value:Example Bailey'),'a different salesperson customer must not enter filter choices');
  h.filter('approval','value:No');assert.match(tbody(h),/Example Emery/);
  assert.deepEqual(optionValues(filterSelect(h,'customer')),before,'one column filter must not narrow another column choices');
  h.filter('approval','all');h.filter('customer','value:Example Avery');assert.match(tbody(h),/value="Pending customer draft"/);
  assert.equal(h.calls.length,1);
});

test('an active exact value survives refresh and view changes when it disappears from saved choices', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});h.filter('customer','value:Example Avery');
  await h.refresh(rows.filter(row=>row.id!=='alpha'));assert.equal(tbody(h),'');
  assert.equal(selectedValue(filterSelect(h,'customer')),'value:Example Avery');assert.ok(optionValues(filterSelect(h,'customer')).includes('value:Example Avery'));
  assert.equal(selectedValue(filterSelect(h,'customer',true)),'value:Example Avery');
  h.click({financeView:'statistics'});h.click({financeView:'pipeline'});
  assert.equal(selectedValue(filterSelect(h,'customer')),'value:Example Avery');assert.equal(tbody(h),'');
  h.filter('customer','all');assert.match(tbody(h),/Example Bailey|Example Devon/);assert.equal(h.calls.length,2);
});

test('saved-value filters preserve unsaved edits through hide, clear, poll and view changes', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});h.edit('alpha','customer','Pending customer draft');
  h.filter('customer','value:Example Avery');assert.match(tbody(h),/value="Pending customer draft"/);
  h.click({},['data-finance-clear-filters']);h.filter('approval','value:No');assert.doesNotMatch(tbody(h),/Pending customer draft/);
  await h.refresh();assert.doesNotMatch(tbody(h),/Pending customer draft/);
  h.click({financeView:'statistics'});h.click({financeView:'all'});assert.doesNotMatch(tbody(h),/Pending customer draft/);
  h.click({},['data-finance-clear-filters']);assert.match(tbody(h),/value="Pending customer draft"/);
  assert.equal(h.calls.length,2);assert.ok(h.calls.every(call=>call.name==='get_broome_finance_pipeline'));
  const save=h.click({financeSave:'alpha'});assert.equal(h.calls[2].name,'save_broome_finance_application');assert.equal(h.calls[2].args.p_data.customer,'Pending customer draft');assert.equal(h.calls[2].args.p_expected_version,1);
  h.calls[2].resolve({data:{record:{...rows[0],customer:'Pending customer draft',version:2}}});await save;
});

test('settlement dropdowns show human dates and match exact saved dates or missing dates', async () => {
  const h=harness(),records=[...rows,{...rows[0],id:'undated',customer:'Example Undated',settlement:'Yes',settlement_date:''}];await h.refresh(records);h.click({financeView:'all'});
  const control=filterSelect(h,'settlement'),dateOption=control.options.match(new RegExp('<option value="value:'+month+'-01"[^>]*>([^<]*)<\\/option>'))?.[1];
  assert.ok(dateOption,'the ISO date remains the exact filter value');assert.notEqual(dateOption,month+'-01','the label formats the date for a person');assert.match(control.options,/value="value:undated"[^>]*>[^<]*date not recorded/i);assert.doesNotMatch(control.options,/value="value:Yes"|value="value:No"/);
  h.filter('settlement','value:'+month+'-01');assert.match(tbody(h),/Example Casey|Example Emery/);assert.doesNotMatch(tbody(h),/Example Avery|Example Undated/);
  h.filter('settlement','value:undated');assert.match(tbody(h),/Example Undated/);assert.doesNotMatch(tbody(h),/Example Casey|Example Emery/);
  h.filter('settlement','blank');assert.match(tbody(h),/Example Avery/);assert.doesNotMatch(tbody(h),/Example Casey|Example Emery|Example Undated/);assert.equal(h.calls.length,1);
});

test('header filters do not shrink settlement statistics and survive view-button changes', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});h.filter('approval','value:Yes');
  const before=h.calls.length;h.click({financeView:'statistics'});
  assert.match(h.html(),/Example Casey/);assert.match(h.html(),/Example Emery/);
  assert.match(h.html(),/Settled applications \/ contracts<\/span><strong>2<\/strong>/);
  assert.match(h.html(),/Settled NAF<\/span><strong>\$4,000\.00<\/strong>/);
  h.click({financeView:'all'});assert.doesNotMatch(tbody(h),/Example Casey|Example Emery/);assert.match(tbody(h),/Example Avery/);
  assert.equal(selectedValue(filterSelect(h,'approval')),'value:Yes');assert.equal(h.calls.length,before);
});

test('account and salesperson scope changes discard filters and hidden drafts', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});h.edit('alpha','notes','Private unsaved note');h.filter('approval','value:Yes');
  h.setScope('BG');h.api.syncScope();h.api.render();
  assert.match(tbody(h),/Example Emery/);assert.doesNotMatch(tbody(h),/Private unsaved note|Example Bailey/);assert.equal(selectedValue(filterSelect(h,'approval')),'all');
  h.filter('approval','value:Yes');h.setToken('replacement-finance-account');h.api.syncScope();assert.equal(h.html(),'');
  await h.refresh();h.click({financeView:'all'});assert.match(tbody(h),/Example Emery/);assert.doesNotMatch(tbody(h),/Private unsaved note/);assert.equal(selectedValue(filterSelect(h,'approval')),'all');
  assert.ok(h.calls.every(call=>call.name==='get_broome_finance_pipeline'));
});

test('permission downgrade removes private dropdowns and rejects forged private keys', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});h.filter('approval','value:Yes');
  assert.ok(optionValues(filterSelect(h,'financier')).includes('value:TFM'));
  await h.refresh(rows,false);
  for(const key of privateKeys)assert.doesNotMatch(h.html(),new RegExp('data-finance-filter(?:-mobile)?="'+key+'"'));
  assert.match(tbody(h),/Example Bailey/);assert.match(tbody(h),/Example Emery/);assert.equal(selectedValue(filterSelect(h,'approval')),'all');
  const before=tbody(h);
  for(const key of privateKeys)h.filter(key,'value:999999');
  assert.equal(tbody(h),before,'forged private filters cannot restrict public rows');assert.doesNotMatch(h.html(),/value:TFM|value:FARADAY|value:5000|value:20\.1/);
  h.filter('approval','value:No');assert.match(tbody(h),/Example Bailey|Example Emery/);assert.doesNotMatch(tbody(h),/Example Avery|Example Devon/);
  assert.equal(h.calls.length,2);assert.ok(h.calls.every(call=>call.name==='get_broome_finance_pipeline'));
});

test('forged keys and unsupported dropdown values leave the current exact filter unchanged', async () => {
  const h=harness();await h.refresh();h.click({financeView:'all'});h.filter('approval','value:Yes');
  const before=tbody(h);
  for(const key of ['unknown','current_location','constructor','__proto__'])h.filter(key,'blank');
  for(const value of ['value:unsupported','contains:Yes','value:','min:0','Yes',''])h.filter('approval',value);
  assert.equal(tbody(h),before);assert.equal(selectedValue(filterSelect(h,'approval')),'value:Yes');assert.equal(h.calls.length,1);
  h.filter('approval','all');assert.match(tbody(h),/Example Bailey/);assert.equal(selectedValue(filterSelect(h,'approval')),'all');
});
