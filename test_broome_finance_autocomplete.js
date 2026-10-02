'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const finance=require('./sales/finance-pipeline.js');
const rows=[
 {tracking_id:'a',stock:'13059110',order:'260011',client:'Example Amanda',vehicle:'Corolla Ascent',salesperson_code:'BG',new_used:'New',group_name:'Broome'},
 {tracking_id:'b',stock:'13059111',order:'260012',client:'Example Andrew',vehicle:'HiLux SR5',salesperson_code:'CW'},
 {tracking_id:'c',stock:'',order:'000260013',client:'Example Jordan',vehicle:'Prado GXL',salesperson_code:'BG'}
];
test('vehicle suggestions match partial stock, order, customer and model without mutating source',()=>{
 assert.deepEqual(finance.matchVehicles(rows,'13059110').map(r=>r.tracking_id),['a']);
 assert.deepEqual(finance.matchVehicles(rows,'amanda').map(r=>r.tracking_id),['a']);
 assert.deepEqual(finance.matchVehicles(rows,' EXAMPLE  AND ').map(r=>r.tracking_id),['b','a']);
 assert.deepEqual(finance.matchVehicles(rows,'000260').map(r=>r.tracking_id),['c']);
 assert.deepEqual(finance.matchVehicles(rows,'HiLux').map(r=>r.tracking_id),['b']);
 assert.deepEqual(finance.matchVehicles(rows,''),[]);assert.deepEqual(finance.matchVehicles(rows,'not found'),[]);
 assert.deepEqual(rows.map(r=>r.tracking_id),['a','b','c']);
});
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
test('typing opens bounded suggestions; clicking selects exact vehicle and fills customer without saving',async()=>{
 const h=harness();await open(h);h.input('130591');
 assert.equal(h.el('finance-vehicle-search').attrs['aria-expanded'],'true');
 assert.match(h.el('finance-vehicle-matches').innerHTML,/Example Amanda/);assert.match(h.el('finance-vehicle-matches').innerHTML,/Example Andrew/);
 h.click('a');assert.equal(h.el('finance-vehicle-picker').value,'a');
 assert.equal(h.el('finance-add-form').querySelector('[name="customer"]').value,'Example Amanda');
 assert.equal(h.el('finance-vehicle-search').value,'13059110');assert.equal(h.el('finance-vehicle-matches').hidden,true);
 assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'get_broome_finance_pipeline');
 h.input('Jordan');assert.equal(h.el('finance-vehicle-picker').value,'');assert.equal(h.el('finance-add-form').querySelector('[name="customer"]').value,'');
 h.click('c');assert.equal(h.el('finance-vehicle-picker').value,'c');assert.equal(h.el('finance-vehicle-search').value,'000260013');
});
test('arrow keys and Enter choose a match; Escape closes suggestions without submitting',async()=>{
 const h=harness();await open(h);h.input('Example');
 assert.equal(h.key('ArrowDown').prevented,true);assert.equal(h.el('finance-vehicle-search').attrs['aria-activedescendant'],'finance-match-0');
 h.key('ArrowDown');assert.equal(h.el('finance-vehicle-search').attrs['aria-activedescendant'],'finance-match-1');
 assert.equal(h.key('Enter').prevented,true);assert.equal(h.el('finance-vehicle-picker').value,'b');assert.equal(h.calls.length,1);
 h.input('Jordan');assert.equal(h.key('Escape').prevented,true);assert.equal(h.el('finance-vehicle-matches').hidden,true);
 assert.equal(h.el('finance-vehicle-search').attrs['aria-expanded'],'false');
});
test('no matches, escaping, manual customer edits and ten-result bound are safe',async()=>{
 const h=harness();await open(h,[...rows,...Array.from({length:12},(_,i)=>({...rows[0],tracking_id:'x'+i,stock:'14000'+i,client:'Extra customer '+i})),{...rows[0],tracking_id:'unsafe',client:'<img src=x onerror=alert(1)>',stock:'unsafe'}]);
 h.input('Extra');assert.equal((h.el('finance-vehicle-matches').innerHTML.match(/role="option"/g)||[]).length,10);assert.match(h.el('finance-vehicle-match-status').textContent,/10 of 12/);
 h.input('unsafe');assert.match(h.el('finance-vehicle-matches').innerHTML,/&lt;img/);assert.doesNotMatch(h.el('finance-vehicle-matches').innerHTML,/<img/);
 h.input('not found');assert.equal(h.el('finance-vehicle-matches').hidden,true);assert.match(h.el('finance-vehicle-match-status').textContent,/No matching/);
 h.input('Amanda');h.click('a');h.el('finance-add-form').querySelector('[name="customer"]').value='Manual finance customer';
 h.input('Jordan');assert.equal(h.el('finance-add-form').querySelector('[name="customer"]').value,'Manual finance customer');
});
test('suggestions respect salesperson filter and close when scope changes or access clears',async()=>{
 const h=harness();h.setScope('BG');await open(h);h.input('Example');
 assert.doesNotMatch(h.el('finance-vehicle-matches').innerHTML,/Example Andrew/);h.click('b');assert.equal(h.el('finance-vehicle-picker').value,'');
 h.setScope('CW');h.input('Andrew');assert.equal(h.el('finance-add-content').innerHTML,'');assert.equal(h.el('finance-add-dialog').closed,true);
 h.window.BROOME_SALES_FINANCE.clear();assert.equal(h.el('sales-finance').innerHTML,'');
});
test('autocomplete selection submits the exact existing identity only after Add finance entry',async()=>{
 const h=harness();await open(h);h.input('Amanda');h.click('a');
 const form={values:{mode:'existing',tracking_id:h.el('finance-vehicle-picker').value,customer:h.el('finance-add-form').querySelector('[name="customer"]').value,new_used:'New',group_name:'Broome'},querySelector:()=>({disabled:false})};
 const p=h.el('finance-add-content').events.submit({target:form,preventDefault(){}});
 assert.equal(h.calls[1].name,'save_broome_finance_application');assert.equal(h.calls[1].args.p_tracking_id,'a');assert.equal(h.calls[1].args.p_vehicle,null);assert.equal(h.calls[1].args.p_data.customer,'Example Amanda');
 h.calls[1].resolve({data:{record:{id:'finance-fixture',customer:'Example Amanda',tracking_id:'a',version:1}}});await p;await tick();
 assert.equal(h.el('finance-add-dialog').closed,true);
});
