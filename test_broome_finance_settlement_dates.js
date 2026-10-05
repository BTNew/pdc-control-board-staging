'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const finance=require('./sales/finance-pipeline.js');
const source=fs.readFileSync(require.resolve('./sales/finance-pipeline.js'),'utf8');
const today=finance.perthDay(),month=today.slice(0,7),monthDate=month+'-01';
const earlier=new Date(monthDate+'T00:00:00Z');earlier.setUTCMonth(earlier.getUTCMonth()-1);const previous=earlier.toISOString().slice(0,7),previousDate=previous+'-01';
const nextDay=new Date(today+'T00:00:00Z');nextDay.setUTCDate(nextDay.getUTCDate()+1);const future=nextDay.toISOString().slice(0,10);
const entries=[
 {id:'pending',customer:'Example Pending',settlement:'No',settlement_date:'',approval:'Yes',group_name:'Broome',new_used:'New',naf:1000,salesperson_code:'BG',version:1},
 {id:'dated',customer:'Example Dated',settlement:'Yes',settlement_date:monthDate,group_name:'Broome',new_used:'New',naf:2000,salesperson_code:'BG',version:4},
 {id:'legacy',customer:'Example Legacy',settlement:'Yes',settlement_date:'',group_name:'Broome',new_used:'Used',naf:3000,salesperson_code:'CW',version:2}
];
const clone=value=>JSON.parse(JSON.stringify(value)),tick=()=>new Promise(resolve=>setImmediate(resolve));

function harness(){
 const elements=new Map(),calls=[],rows=new Map(),deferred=[];let token='settlement-fixture',scope='',context={role:'administrator'},htmlWrites=0;
 function classes(){const values=new Set();return {add(...names){names.forEach(name=>values.add(name));},remove(...names){names.forEach(name=>values.delete(name));},toggle(name,on){if(on===undefined)on=!values.has(name);on?values.add(name):values.delete(name);return on;},contains:name=>values.has(name),toString:()=>[...values].join(' ')};}
 function renderedDate(id,html){return (html.match(/<input\b[^>]*>/g)||[]).find(tag=>tag.includes('data-finance-id="'+id+'"')&&tag.includes('data-finance-key="settlement_date"'));}
 function el(id){
  if(!elements.has(id)){
   const element={id,value:'',textContent:'',hidden:false,disabled:false,dataset:{},attrs:{},events:{},fields:new Map(),classList:classes(),closed:true,
    addEventListener(name,handler){this.events[name]=handler;},setAttribute(name,value){this.attrs[name]=value;},getAttribute(name){return this.attrs[name];},removeAttribute(name){delete this.attrs[name];},
    close(){this.closed=true;},showModal(){this.closed=false;},focus(){window.document.activeElement=this;},scrollIntoView(){},querySelectorAll(){return [];},
    querySelector(selector){
     if(id==='sales-finance'&&selector.includes('data-finance-id')){const found=selector.match(/data-finance-id="([^"]+)"/);if(found)return row(found[1]).date;}
     if(!this.fields.has(selector))this.fields.set(selector,{value:'',textContent:'',hidden:false,disabled:false,focus(){window.document.activeElement=this;},querySelector(){return null;}});return this.fields.get(selector);
    }};
   let html='';Object.defineProperty(element,'innerHTML',{get:()=>html,set(value){html=String(value);if(id==='sales-finance'){htmlWrites++;for(const [rowId,state] of rows){const tag=renderedDate(rowId,html);state.date.isConnected=Boolean(tag);if(tag){state.date.dataset.financeVersion=tag.match(/data-finance-version="([^"]+)"/)?.[1];state.date.value=tag.match(/value="([^"]*)"/)?.[1]||'';state.date.validity={badInput:false,valid:true};}}}}});elements.set(id,element);
  }return elements.get(id);
 }
 function row(id){
  if(!rows.has(id)){
   const controls=new Map(),cell={dataset:{label:'Settlement'},classList:classes(),attrs:{},textContent:'',setAttribute(name,value){this.attrs[name]=value;},removeAttribute(name){delete this.attrs[name];},querySelector(){return null;}};
   const tr={querySelector(selector){if(selector.includes('Settlement'))return cell;if(!controls.has(selector))controls.set(selector,{hidden:true,disabled:false,textContent:'',title:'',querySelector(){return null;}});return controls.get(selector);}};
   const tag=renderedDate(id,el('sales-finance').innerHTML),date={type:'date',tagName:'INPUT',value:tag?.match(/value="([^"]*)"/)?.[1]||'',dataset:{financeId:id,financeKey:'settlement_date',financeVersion:tag?.match(/data-finance-version="([^"]+)"/)?.[1]||String(entries.find(entry=>entry.id===id)?.version||0)},validity:{badInput:false,valid:true},disabled:false,isConnected:true,attrs:{},
    closest(selector){return selector==='td'||selector.includes('data-label')?cell:tr;},focus(){window.document.activeElement=this;},setCustomValidity(value){this.validationMessage=value;},setAttribute(name,value){this.attrs[name]=value;},removeAttribute(name){delete this.attrs[name];},getAttribute(name){return this.attrs[name];}};
   rows.set(id,{tr,date,cell,save:tr.querySelector('[data-finance-save]'),discard:tr.querySelector('[data-finance-discard]')});
  }return rows.get(id);
 }
 const window={document:{getElementById:el,activeElement:null},setTimeout(handler,delay=0){if(delay===0)deferred.push(handler);return deferred.length;},clearTimeout(){},crypto:{randomUUID:()=> 'settlement-created'},PDC_AUTH_CONTEXT:{userId:token},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
 vm.runInNewContext(source,{window,globalThis:window,module:undefined,console,Map,Set,FormData:class{constructor(form){this.form=form;}get(key){return this.form.values?.[key]||'';}}});
 const api=window.BROOME_SALES_FINANCE;api.init({getToken:()=>token,getContext:()=>context,getSalesperson:()=>scope,getView:()=> 'finance'});
 async function refresh(records=entries,canEdit=true){const pending=api.refresh();calls.at(-1).resolve({data:{context:{role:canEdit?'administrator':'salesperson',can_edit_finance:canEdit},entries:clone(records),vehicle_options:[],salespeople:[]}});await pending;}
 function change(attribute,value){el('sales-finance').events.change({target:{value,hasAttribute:name=>name===attribute}});}
 function action(key,id){el('sales-finance').events.click({target:{closest:()=>({hasAttribute:name=>key==='financeView'&&name==='data-finance-view',dataset:{[key]:id}})}});}
 function edit(id,value,badInput=false){const date=row(id).date;date.value=value;date.validity={badInput,valid:!badInput};el('sales-finance').events.input({target:date});return row(id);}
 function blur(){const target=window.document.activeElement;window.document.activeElement=null;el('sales-finance').events.focusout?.({target});for(const callback of deferred.splice(0))callback();}
 function focusoutTo(relatedTarget){const target=window.document.activeElement;window.document.activeElement=relatedTarget;el('sales-finance').events.focusout?.({target,relatedTarget});}
 function setToken(value){token=value;window.PDC_AUTH_CONTEXT=value?{userId:value}:null;context=value?{role:'administrator'}:null;}
 return {api,window,el,calls,row,edit,change,action,refresh,blur,focusoutTo,deferredCount:()=>deferred.length,setToken,setScope:value=>scope=value,html:()=>el('sales-finance').innerHTML,writes:()=>htmlWrites};
}
function contractCount(h,count){assert.match(h.html(),new RegExp('Settled applications \\/ contracts<\\/span><strong>'+count+'<\\/strong>'));}
function rowHtml(h,id){return h.html().split('<tr>').find(text=>text.includes('data-finance-id="'+id+'"'))?.split('</tr>')[0]||'';}

test('valid native settlement dates and clear patches pair the status without inventing a date',()=>{
 assert.deepEqual(finance.patch('settlement_date',monthDate),{settlement:'Yes',settlement_date:monthDate});
 assert.deepEqual(finance.patch('settlement_date',''),{settlement:'No',settlement_date:''});
 for(const value of [future,'2023-02-29','2024-02-30','2024-2-29','1899-12-31','partial','2024-01'])assert.throws(()=>finance.patch('settlement_date',value),/date/i,value);
 const records=[...entries,{...entries[2],id:'invalid',settlement_date:'2024-02-30'},{...entries[2],id:'future',settlement_date:future}],before=JSON.stringify(records);
 const current=finance.financeStatistics(records,month);assert.equal(current.contractCount,1);assert.equal(current.undated,3);assert.deepEqual(finance.financeStatistics(records,'undated').settled.map(row=>row.id),['legacy','invalid','future']);assert.equal(JSON.stringify(records),before);
});

test('settlement cells use native dates, show legacy uncertainty and mark only valid dates green',async()=>{
 const h=harness();await h.refresh([...entries,{...entries[2],id:'invalid',customer:'Example Invalid',settlement_date:'2024-02-30'}]);h.action('financeView','all');
 const dated=rowHtml(h,'dated');assert.match(dated,/type="date"/);assert.match(dated,/data-finance-key="settlement_date"/);assert.match(dated,new RegExp('value="'+monthDate+'"'));assert.match(dated,/finance-yes[^>]*data-label="Settlement"/);
 for(const id of ['legacy','invalid']){const html=rowHtml(h,id);assert.match(html,/Date not recorded/i);assert.doesNotMatch(html,/finance-yes[^>]*data-label="Settlement"/);}
 assert.doesNotMatch(h.html(),/data-finance-key="settlement"|data-finance-date=|finance-date-button/);assert.equal(h.calls.length,1);
});

test('typing a date updates settlement styling in place and monthly totals only change after a confirmed save',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');const initial=h.writes(),row=h.edit('pending',previousDate);
 assert.equal(h.writes(),initial,'typing must retain native date controls');assert.equal(h.calls.length,1);assert.equal(row.save.hidden,false);assert.equal(row.save.disabled,false);assert.equal(row.cell.classList.contains('finance-yes'),true);
 h.action('financeView','statistics');h.change('data-finance-period',previous);contractCount(h,0);
 h.action('financeView','all');h.action('financeSave','pending');const call=h.calls[1];assert.equal(call.name,'save_broome_finance_application');assert.deepEqual(clone(call.args.p_data),{settlement:'Yes',settlement_date:previousDate});assert.equal(call.args.p_expected_version,1);assert.equal(call.args.p_vehicle,null);
 call.resolve({data:{record:{...entries[0],settlement:'Yes',settlement_date:previousDate,version:2}}});await tick();h.action('financeView','statistics');h.change('data-finance-period',previous);contractCount(h,1);assert.match(h.html(),/Example Pending/);
});

test('clearing then re-entering a settlement date moves only saved contracts between months',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.edit('dated','');h.action('financeView','statistics');contractCount(h,1);
 h.action('financeView','all');h.action('financeSave','dated');assert.deepEqual(clone(h.calls[1].args.p_data),{settlement:'No',settlement_date:''});assert.equal(h.calls[1].args.p_expected_version,4);
 h.calls[1].resolve({data:{record:{...entries[1],settlement:'No',settlement_date:'',version:5}}});await tick();h.action('financeView','statistics');contractCount(h,0);
 h.action('financeView','all');h.edit('dated',previousDate);h.action('financeSave','dated');assert.deepEqual(clone(h.calls[2].args.p_data),{settlement:'Yes',settlement_date:previousDate});assert.equal(h.calls[2].args.p_expected_version,5);
 h.calls[2].resolve({data:{record:{...entries[1],settlement:'Yes',settlement_date:previousDate,version:6}}});await tick();h.action('financeView','statistics');h.change('data-finance-period',previous);contractCount(h,1);h.change('data-finance-period',month);contractCount(h,0);
});

test('partial native badInput disables Save and cannot silently clear the saved date',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.row('dated').date.focus();const before=h.writes(),partial=h.edit('dated','',true);
 assert.equal(h.writes(),before);assert.equal(partial.save.disabled,true);h.action('financeSave','dated');assert.equal(h.calls.length,1,'partial empty native input is an error, not clearing');
 h.edit('dated',previousDate);assert.equal(partial.save.disabled,false);h.blur();h.action('financeSave','dated');assert.deepEqual(clone(h.calls[1].args.p_data),{settlement:'Yes',settlement_date:previousDate});
 h.calls[1].resolve({data:{record:{...entries[1],settlement_date:previousDate,version:5}}});await tick();
});

test('invalid and future typed dates cannot save or count as a settlement',async()=>{
 for(const date of [future,'2024-02-30']){const h=harness();await h.refresh();h.action('financeView','all');const row=h.edit('pending',date);assert.equal(row.save.disabled,true);assert.equal(row.cell.classList.contains('finance-yes'),false);h.action('financeSave','pending');assert.equal(h.calls.length,1);h.action('financeView','statistics');contractCount(h,1);}
});

test('polling does not replace a focused native date or lose a partial edit',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');const date=h.row('dated').date;date.focus();h.edit('dated','',true);const before=h.writes();
 await h.refresh();assert.equal(h.writes(),before);assert.strictEqual(h.window.document.activeElement,date);assert.equal(date.value,'');assert.equal(date.validity.badInput,true);assert.equal(h.row('dated').save.disabled,true);
 h.edit('dated',previousDate);h.blur();assert.ok(h.writes()>before,'the deferred poll renders when the native date loses focus');assert.match(rowHtml(h,'dated'),new RegExp('value="'+previousDate+'"'));assert.equal(h.calls.length,2);
});

for(const kind of ['view button','header dropdown'])test('a deferred date poll preserves the first '+kind+' action and its unsaved date',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.row('pending').date.focus();h.edit('pending',previousDate);const before=h.writes();
 await h.refresh();assert.equal(h.writes(),before,'a focused date must defer the poll render');assert.equal(h.deferredCount(),0);
 const attribute=kind==='view button'?'data-finance-view':'data-finance-filter';
 const control={tagName:kind==='view button'?'BUTTON':'SELECT',value:'value:Example Pending',dataset:kind==='view button'?{financeView:'pipeline'}:{financeFilter:'customer'},
  hasAttribute:name=>name===attribute,closest(selector){return selector.split(',').includes('['+attribute+']')?this:null;}};
 assert.match(h.html(),kind==='view button'?/<button\b[^>]*data-finance-view="pipeline"/:/<select\b[^>]*data-finance-filter="customer"/);
 h.focusoutTo(control);
 assert.equal(h.deferredCount(),0,'leaving the date for this control must not queue a replacement before its action');assert.equal(h.writes(),before,'focusout must retain the clicked control');
 h.el('sales-finance').events[kind==='view button'?'click':'change']({target:control});
 assert.equal(h.writes(),before+1,'the first action must apply and consume the deferred render');
 assert.match(rowHtml(h,'pending'),new RegExp('value="'+previousDate+'"'));assert.match(rowHtml(h,'pending'),/data-finance-version="1"/);assert.doesNotMatch(h.html().match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1]||'',/Example Dated|Example Legacy/);
 if(kind==='view button')assert.match(h.html(),/<button\b[^>]*data-finance-view="pipeline"[^>]*aria-pressed="true"/);
 else assert.match(h.html(),/<option value="value:Example Pending" selected>/);
 assert.equal(h.calls.length,2,'view and filter actions must not save the draft');
 h.action('financeSave','pending');assert.equal(h.calls[2].name,'save_broome_finance_application');assert.deepEqual(clone(h.calls[2].args.p_data),{settlement:'Yes',settlement_date:previousDate});assert.equal(h.calls[2].args.p_expected_version,1);
 h.calls[2].resolve({data:{record:{...entries[0],settlement:'Yes',settlement_date:previousDate,version:2}}});await tick();
});

test('stale date drafts retain their original version and cannot replace a newer saved date',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.edit('dated',previousDate);const newer={...entries[1],settlement_date:monthDate,version:5};await h.refresh([entries[0],newer,entries[2]]);
 assert.match(rowHtml(h,'dated'),/Changed elsewhere|changed/i);assert.match(rowHtml(h,'dated'),/data-finance-save="dated"[^>]*disabled/);h.action('financeSave','dated');assert.equal(h.calls.length,2,'a conflicted draft must fail before issuing a save');
 h.action('financeView','statistics');h.change('data-finance-period',previous);contractCount(h,0);h.change('data-finance-period',month);contractCount(h,1);
});

test('a poll before the first date input cannot pin the draft to a record version the user never saw',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');const date=h.row('pending').date;assert.equal(date.dataset.financeVersion,'1');date.focus();const before=h.writes();
 const newer={...entries[0],version:2,settlement:'Yes',settlement_date:monthDate};await h.refresh([newer,...entries.slice(1)]);assert.equal(h.writes(),before);assert.equal(date.dataset.financeVersion,'1');assert.equal(date.value,'');assert.equal(h.row('pending').save.disabled,true);
 h.edit('pending',previousDate);assert.equal(h.row('pending').save.disabled,true);h.action('financeSave','pending');assert.equal(h.calls.length,2,'a forged Save cannot turn the displayed v1 date into a v2 write');assert.match(rowHtml(h,'pending'),/Changed elsewhere|changed/i);
 h.action('financeView','statistics');h.change('data-finance-period',previous);contractCount(h,0);h.change('data-finance-period',month);contractCount(h,2);
});

test('changing All to BG while a BG date remains focused renders the new scope immediately',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.row('pending').date.focus();h.edit('pending',previousDate);const before=h.writes();assert.match(h.html(),/Example Legacy/);
 h.setScope('BG');h.api.render();assert.ok(h.writes()>before,'scope changes must bypass native-date poll deferral even if the focused row stays in scope');assert.doesNotMatch(h.html(),/Example Legacy/);assert.match(h.html(),/Example Pending|Example Dated/);assert.match(rowHtml(h,'pending'),/value=""/);assert.doesNotMatch(h.html(),new RegExp('value="'+previousDate+'"'));
 h.action('financeSave','pending');assert.equal(h.calls.length,1,'the previous All-scope draft must be discarded');
});

test('a focused date poll disables a newly stale draft in place but removes controls immediately when access is lost',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.row('dated').date.focus();h.edit('dated',previousDate);const before=h.writes();
 await h.refresh([entries[0],{...entries[1],version:5},entries[2]]);assert.equal(h.writes(),before);assert.equal(h.row('dated').save.disabled,true,'a focused stale draft must not retain an enabled Save');assert.equal(h.row('dated').date.value,previousDate);
 await h.refresh(entries,false);assert.ok(h.writes()>before);assert.doesNotMatch(h.html(),/data-finance-key="settlement_date"|data-finance-save=/);h.action('financeSave','dated');assert.equal(h.calls.length,3);
 const removed=harness();await removed.refresh();removed.action('financeView','all');removed.row('dated').date.focus();removed.edit('dated',previousDate);const visible=removed.writes();await removed.refresh([entries[0],entries[2]]);assert.ok(removed.writes()>visible);assert.doesNotMatch(removed.html(),/Example Dated/);removed.action('financeSave','dated');assert.equal(removed.calls.length,2);
});

test('permission downgrade and selected salesperson changes discard pending dates and reject forged edits',async()=>{
 const h=harness();await h.refresh();h.action('financeView','all');h.edit('pending',previousDate);h.setScope('CW');h.api.syncScope();h.api.render();assert.doesNotMatch(h.html(),/Example Pending/);h.action('financeSave','pending');assert.equal(h.calls.length,1);
 h.setScope('');h.api.syncScope();h.api.render();assert.match(rowHtml(h,'pending'),/value=""/);h.edit('pending',previousDate);await h.refresh(entries,false);assert.doesNotMatch(h.html(),/data-finance-key="settlement_date"|data-finance-save=/);
 h.edit('pending',previousDate);h.action('financeSave','pending');assert.equal(h.calls.length,2);h.action('financeView','statistics');h.change('data-finance-period',previous);contractCount(h,0);
});

test('sign-out or account replacement suppresses a delayed date save and its customer message',async()=>{
 for(const replacement of ['', 'replacement-account']){const h=harness();await h.refresh();h.action('financeView','all');h.edit('pending',previousDate);h.action('financeSave','pending');h.setToken(replacement);h.api.syncScope();assert.equal(h.html(),'');h.calls[1].resolve({data:{record:{...entries[0],settlement:'Yes',settlement_date:previousDate,version:2}}});await tick();assert.equal(h.html(),'');assert.equal(h.calls.length,2);}
});
