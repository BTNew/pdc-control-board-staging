'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const finance=require('./sales/finance-pipeline.js');
const rows=[];
function harness(){
 const elements=new Map(),calls=[],fields=new Map();let settings,scope='';
 function el(id){if(!elements.has(id))elements.set(id,{id,value:'',innerHTML:'',textContent:'',hidden:false,disabled:false,dataset:{},events:{},attrs:{},
  addEventListener(n,f){this.events[n]=f;},setAttribute(n,v){this.attrs[n]=v;},removeAttribute(n){delete this.attrs[n];},focus(){this.focused=true;},scrollIntoView(){},
  close(){this.closed=true;},showModal(){this.closed=false;},querySelector(s){if(!fields.has(s))fields.set(s,{value:'',focus(){this.focused=true;}});return fields.get(s);}});
  return elements.get(id);
 }
 const window={document:{getElementById:el,activeElement:null},crypto:{randomUUID:()=> 'finance-fixture'},PDC_AUTH_CONTEXT:{userId:'fixture'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
 vm.runInNewContext(fs.readFileSync('sales/finance-pipeline.js','utf8'),{window,globalThis:window,module:undefined,console,Map,Set,FormData:class{constructor(form){this.form=form;}get(k){return this.form.values[k];}}});
 settings={getToken:()=> 'fixture',getContext:()=>({role:'administrator'}),getSalesperson:()=>scope,getView:()=> 'finance'};
 window.BROOME_SALES_FINANCE.init(settings);
 return {el,fields,calls,window,setScope:s=>scope=s,
  input(text){el('finance-vehicle-search').value=text;el('finance-add-content').events.input({target:el('finance-vehicle-search')});},
  click(id){el('finance-add-content').events.click({target:{closest:s=>s==='[data-finance-match]'?{dataset:{financeMatch:id}}:null}});},
  key(key){const event={target:el('finance-vehicle-search'),key,preventDefault(){this.prevented=true;},stopPropagation(){}};el('finance-add-content').events.keydown(event);return event;}
 };
}
const tick=()=>new Promise(r=>setImmediate(r));
async function open(h,refs=rows){
 const p=h.window.BROOME_SALES_FINANCE.refresh();
 h.calls[0].resolve({data:{context:{role:'administrator',can_edit_finance:true},entries:[],vehicle_options:refs,salespeople:[]}});await p;
 h.el('sales-finance').events.click({target:{closest:()=>({hasAttribute:n=>n==='data-finance-add'})}});
}

const month=finance.perthDay().slice(0,7),previousDate=new Date(month+'-01T00:00:00Z');previousDate.setUTCMonth(previousDate.getUTCMonth()-1);const previous=previousDate.toISOString().slice(0,7);
const applications=[
 {id:'active',customer:'Example Active',settlement:'No',approval:'Yes',financier:'TFS BM',naf:12345.67,finance_comm:100.10,dof_daf:20.20,salesperson_code:'BG',vehicle:{model:'MODEL SHOULD NOT APPEAR'},version:1},
 {id:'current',customer:'Example Current',settlement:'Yes',settlement_date:month+'-01',approval:'Yes',financier:'TFM',naf:25000,finance_comm:500,salesperson_code:'BG',version:1},
 {id:'past',customer:'Example Previous',settlement:'Yes',settlement_date:previous+'-01',financier:'FARADAY',naf:19000,finance_comm:200,salesperson_code:'CW',version:1,updated_at:month+'-01T00:00:00Z'},
 {id:'undated',customer:'Example Undated',settlement:'Yes',financier:'OTHER',naf:3000,finance_comm:0.10,dof_daf:0.20,salesperson_code:'BG',version:1,updated_at:month+'-01T00:00:00Z'}
];
async function loaded(h,editor=true,records=applications){const p=h.window.BROOME_SALES_FINANCE.refresh();h.calls[0].resolve({data:{context:{role:editor?'administrator':'salesperson',can_edit_finance:editor},entries:records,vehicle_options:[],salespeople:[]}});await p;}
function view(h,value){h.el('sales-finance').events.change({target:{value,hasAttribute:k=>k==='data-finance-view'}});}
function period(h,value){h.el('sales-finance').events.change({target:{value,hasAttribute:k=>k==='data-finance-period'}});}
function action(h,key,id){h.el('sales-finance').events.click({target:{closest:()=>({hasAttribute:()=>false,dataset:{[key]:id}})}});}
test('monthly settlement totals use real dates, retain legacy undated records and sum decimal cents',()=>{
 const report=finance.financeStatistics(applications,month);
 assert.equal(report.settledCount,1);assert.equal(report.naf,25000);assert.equal(report.commission,500);assert.equal(report.pipelineCount,1);assert.equal(report.approved,1);assert.equal(report.pipelineNaf,12345.67);assert.equal(report.undated,1);
 assert.equal(finance.financeStatistics(applications,previous).settledCount,1);assert.equal(finance.financeStatistics(applications,'undated').commission,0.30);assert.equal(finance.financeStatistics(applications,'all').settledCount,3);
 assert.deepEqual(report.months.map(r=>r.month),[month,previous]);assert.equal(report.financiers.find(r=>r.name==='TFS').pipeline,1);
});
test('settlement dates validate calendar days and use Perth day around UTC midnight',()=>{
 assert.equal(finance.perthDay(new Date('2026-10-01T17:00:00Z')),'2026-10-02');
 for(const value of ['2023-02-29','2024-02-30','2024-2-29','1899-12-31','2026-10-03',''])assert.equal(finance.validSettlementDate(value,'2026-10-02'),false,value);
 assert.equal(finance.validSettlementDate('2024-02-29','2026-10-02'),true);
 assert.deepEqual(finance.patch('financier','FARADAY'),{financier:'FARADAY'});assert.throws(()=>finance.patch('financier','invalid'));
});
test('pipeline is slim customer-only, retains legacy financier choice and all applications are accessible',async()=>{
 const h=harness();await loaded(h);let html=h.el('sales-finance').innerHTML;
 assert.match(html,/Example Active/);assert.doesNotMatch(html,/Example Current|MODEL SHOULD NOT APPEAR|finance-vehicle-label/);
 assert.match(html,/<option value="TFS BM" selected>/);for(const choice of ['TFS','TFM','FARADAY','OTHER'])assert.match(html,new RegExp('<option value="'+choice+'"'));
 view(h,'all');assert.match(h.el('sales-finance').innerHTML,/Example Current/);assert.match(h.el('sales-finance').innerHTML,/Example Undated/);
 view(h,'statistics');html=h.el('sales-finance').innerHTML;assert.match(html,/Settlement month/);assert.match(html,/Previous months/);assert.match(html,/Financier overview/);assert.match(html,/Example Current/);assert.doesNotMatch(html,/Example Previous|Example Undated/);
 period(h,'undated');assert.match(h.el('sales-finance').innerHTML,/Example Undated/);period(h,previous);assert.match(h.el('sales-finance').innerHTML,/Example Previous/);
});
test('statistics obey salesperson filter and do not disclose private finance figures to ordinary salespeople',async()=>{
 const h=harness();h.setScope('BG');await loaded(h);view(h,'statistics');period(h,previous);assert.doesNotMatch(h.el('sales-finance').innerHTML,/Example Previous/);
 const viewer=harness();await loaded(viewer,false);view(viewer,'statistics');const html=viewer.el('sales-finance').innerHTML;
 assert.doesNotMatch(html,/Financier overview|Settled NAF|Settled commission|Pipeline NAF|\$25,000|500\.00|data-finance-add/);assert.match(html,/Settled applications/);
});
test('customer-only creation submits no model, stock or order and requires explicit Add',async()=>{
 const h=harness();await loaded(h);h.el('sales-finance').events.click({target:{closest:()=>({hasAttribute:k=>k==='data-finance-add'})}});
 assert.doesNotMatch(h.el('finance-add-content').innerHTML,/name="model"|name="stock"|name="order"/);assert.match(h.el('finance-add-content').innerHTML,/Customer only/);assert.equal(h.calls.length,1);
 const form={values:{mode:'new',customer:'Example customer only',new_used:'Used',group_name:'Broome',financier:'OTHER'},querySelector:()=>({disabled:false})};
 const p=h.el('finance-add-content').events.submit({target:form,preventDefault(){}});assert.equal(JSON.stringify(h.calls[1].args.p_vehicle),'{}');assert.equal(h.calls[1].args.p_tracking_id,null);assert.equal(h.calls[1].args.p_data.financier,'OTHER');
 h.calls[1].resolve({data:{record:{id:'finance-fixture',customer:'Example customer only',settlement:'',version:1}}});await p;
});
test('settlement date is a draft until Save row and stale edits cannot overwrite a newer record',async()=>{
 const h=harness();await loaded(h);view(h,'statistics');action(h,'financeDate','current');assert.equal(h.el('finance-settlement-date-dialog').closed,false);assert.equal(h.calls.length,1);
 const form={values:{settlement_date:previous+'-02'}};h.el('finance-settlement-date-content').events.submit({target:form,preventDefault(){}});assert.equal(h.calls.length,1);assert.equal(h.el('finance-settlement-date-dialog').closed,true);
 action(h,'financeSave','current');assert.equal(h.calls[1].name,'save_broome_finance_application');assert.equal(h.calls[1].args.p_data.settlement_date,previous+'-02');assert.equal(h.calls[1].args.p_expected_version,1);
 h.calls[1].resolve({data:{record:{...applications[1],settlement_date:previous+'-02',version:2}}});await tick();assert.doesNotMatch(h.el('sales-finance').innerHTML,/Example Current/);
 period(h,previous);action(h,'financeDate','current');const refresh=h.window.BROOME_SALES_FINANCE.refresh();h.calls[2].resolve({data:{context:{role:'administrator',can_edit_finance:true},entries:[{...applications[1],settlement_date:previous+'-02',version:3}],vehicle_options:[],salespeople:[]}});await refresh;
 h.el('finance-settlement-date-content').events.submit({target:form,preventDefault(){}});assert.equal(h.calls.length,3);assert.match(h.el('sales-finance').innerHTML,/changed/);
});
test('switching salesperson or signing out clears settlement dialog and pending edits',async()=>{
 const h=harness();await loaded(h);view(h,'statistics');action(h,'financeDate','current');h.setScope('CW');h.window.BROOME_SALES_FINANCE.syncScope();assert.equal(h.el('finance-settlement-date-dialog').closed,true);assert.equal(h.el('finance-settlement-date-content').innerHTML,'');
 h.window.BROOME_SALES_FINANCE.clear();assert.equal(h.el('sales-finance').innerHTML,'');
});

const productApplications=[
 {...applications[1],id:'bn',customer:'Broome New Example',group_name:'Broome',new_used:'New',rsa:15.10,mvi:30.20,access:'Yes'},
 {...applications[1],id:'pu',customer:'Pilbara Used Example',group_name:'Port Hedland',new_used:'Used',rsa:0,mvi:40.30,access:'No'},
 {...applications[1],id:'pn',customer:'Pilbara New Example',group_name:'Pilbara',new_used:'New',rsa:25.20,mvi:null,access:'Yes'},
 {...applications[2],id:'old',customer:'Previous Month Example',group_name:'Broome',new_used:'New',rsa:9,mvi:8,access:'Yes'},
 {...applications[0],id:'pipe',customer:'Pipeline Example',group_name:'Port Hedland',new_used:'Used',rsa:100,mvi:100,access:'Yes'},
 {...applications[3],id:'unknown',customer:'Undated Example',group_name:'Broome',new_used:'Used',rsa:null,mvi:0,access:''}
];
test('monthly product totals count settled contracts and positive product amounts with precise cents',()=>{
 const report=finance.financeStatistics(productApplications,month);
 assert.equal(report.contractCount,3);assert.equal(report.accessCount,2);assert.equal(report.rsaCount,2);assert.equal(report.rsaTotal,40.30);assert.equal(report.mviCount,2);assert.equal(report.mviTotal,70.50);
 assert.equal(report.pipelineCount,1);assert.equal(report.undated,1);
 const past=report.months.find(r=>r.month===previous);assert.equal(past.count,1);assert.equal(past.rsaCount,1);assert.equal(past.accessCount,1);assert.equal(past.mviCount,1);
 assert.equal(finance.financeStatistics(productApplications,'all').contractCount,5);assert.equal(finance.financeStatistics(productApplications,'undated').mviCount,0);
});
test('location and New/Used filters apply to settlements, previous months and the pipeline together',()=>{
 assert.equal(finance.financeGroup(' PORT   HEDLAND '),'pilbara');assert.equal(finance.financeGroup('Pilbara'),'pilbara');assert.equal(finance.financeGroup('Broome'),'broome');assert.equal(finance.financeGroup('unknown'),'');
 const report=finance.financeStatistics(productApplications,month,{group:'pilbara',newUsed:'used'});
 assert.deepEqual(report.settled.map(r=>r.id),['pu']);assert.equal(report.contractCount,1);assert.equal(report.rsaCount,0);assert.equal(report.mviCount,1);assert.equal(report.accessCount,0);assert.equal(report.pipelineCount,1);assert.equal(report.undated,0);assert.deepEqual(report.months.map(r=>r.month),[month]);
 assert.equal(finance.financeStatistics(productApplications,month,{group:'broome',newUsed:'new'}).contractCount,1);
 assert.equal(finance.financeStatistics(productApplications,month,{group:'pilbara',newUsed:'new'}).contractCount,1);
 assert.equal(finance.financeStatistics([...productApplications,{...productApplications[0],group_name:'Unknown'}],month,{group:'broome'}).contractCount,1);
});
test('statistics dropdowns filter displayed customers without saving and reset on sign-out',async()=>{
 const h=harness();await loaded(h,true,productApplications);view(h,'statistics');
 function filter(key,value){h.el('sales-finance').events.change({target:{value,hasAttribute:k=>k===key}});}
 filter('data-finance-group','pilbara');filter('data-finance-new-used','used');
 let html=h.el('sales-finance').innerHTML;assert.match(html,/Pilbara Used Example/);assert.doesNotMatch(html,/Broome New Example|Pilbara New Example|Previous Month Example/);assert.match(html,/<option value="pilbara" selected>/);assert.match(html,/<option value="used" selected>/);assert.match(html,/RSI products \(RSA\)/);assert.match(html,/\$40\.30 total/);assert.equal(h.calls.length,1);
 period(h,'undated');html=h.el('sales-finance').innerHTML;assert.match(html,/<option value="undated" selected>/);assert.match(html,/No settlements in this period/);
 // Statistics filters must not restrict the editable pipeline when changing views.
 view(h,'pipeline');assert.match(h.el('sales-finance').innerHTML,/Pipeline Example/);
 h.window.BROOME_SALES_FINANCE.clear();const p=h.window.BROOME_SALES_FINANCE.refresh();h.calls[1].resolve({data:{context:{role:'administrator',can_edit_finance:true},entries:productApplications,vehicle_options:[],salespeople:[]}});await p;view(h,'statistics');html=h.el('sales-finance').innerHTML;assert.match(html,/<option value="all" selected>/);assert.match(html,/Broome New Example/);
});
test('filtered product statistics retain salesperson boundaries and private amount protections',async()=>{
 const h=harness();h.setScope('BG');await loaded(h,false,[...productApplications,{...productApplications[0],id:'other',customer:'Other Salesperson Example',salesperson_code:'CW'}]);view(h,'statistics');
 const html=h.el('sales-finance').innerHTML;assert.doesNotMatch(html,/Other Salesperson Example|RSI products \(RSA\)|MVI products|\$40\.30|\$70\.50/);assert.match(html,/Access products/);assert.match(html,/Finance location/);
});
