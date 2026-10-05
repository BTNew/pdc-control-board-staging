'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require.resolve('./sales/finance-pipeline.js'),'utf8');
const copy=v=>v===undefined?undefined:JSON.parse(JSON.stringify(v)),tick=()=>new Promise(r=>setImmediate(r));
const initial=[{id:'one',customer:'Fictional One',new_used:'New',group_name:'Broome',notes:'',settlement:'No',settlement_date:'',version:1,salesperson_code:'BG'},
 {id:'two',customer:'Fictional Two',new_used:'Used',group_name:'Port Hedland',notes:'',settlement:'No',version:1,salesperson_code:'AW'}];
function harness(){
 const elements=new Map(),rows=new Map(),timers=new Map(),calls=[],events={},records=copy(initial);let now=0,timerId=0,token='account-one',scope='',view='finance',writes=0;
 function el(id){
  if(!elements.has(id)){
   const e={events:{},fields:new Map(),dataset:{},attrs:{},textContent:'',value:'',hidden:false,disabled:false,addEventListener(k,h){this.events[k]=h;},close(){},focus(){window.document.activeElement=this;},
    setAttribute(k,v){this.attrs[k]=v;},querySelector(selector){
     const field=selector.match(/data-finance-id="([^"]+)"/);if(field)return control(field[1],selector.match(/data-finance-key="([^"]+)"/)?.[1]||'customer');
     const status=selector.match(/data-finance-status="([^"]+)"/);if(status)return row(status[1]).status;
     if(!this.fields.has(selector))this.fields.set(selector,{textContent:'',dataset:{},hidden:false,disabled:false,focus(){}});return this.fields.get(selector);
    }};
   let html='';Object.defineProperty(e,'innerHTML',{get:()=>html,set(value){html=value;if(id==='sales-finance'){writes++;for(const state of rows.values())for(const [key,field] of state.fields){const tag=(html.match(/<(?:input|select)\b[^>]+>/g)||[]).find(t=>t.includes('data-finance-id="'+state.id+'"')&&t.includes('data-finance-key="'+key+'"'));if(tag){field.dataset.financeVersion=tag.match(/data-finance-version="([^"]+)"/)?.[1];if(field.tagName==='INPUT')field.value=tag.match(/\bvalue="([^"]*)"/)?.[1]||'';}}}}});elements.set(id,e);
  }return elements.get(id);
 }
 function row(id){if(!rows.has(id)){
  const state={id,fields:new Map(),status:{textContent:'',attrs:{},setAttribute(k,v){this.attrs[k]=v;}},actions:new Map()};
  state.tr={querySelector(selector){if(selector.includes('Total Comm')||selector.includes('Settlement'))return null;if(!state.actions.has(selector))state.actions.set(selector,{hidden:true,disabled:false,textContent:''});return state.actions.get(selector);},querySelectorAll(){return [...state.fields.values()];}};rows.set(id,state);
 }return rows.get(id);}
 function control(id,key){const state=row(id);if(!state.fields.has(key))state.fields.set(key,{dataset:{financeId:id,financeKey:key,financeVersion:String(records.find(r=>r.id===id)?.version||1)},tagName:['new_used','approval','access'].includes(key)?'SELECT':'INPUT',type:key==='settlement_date'?'date':'text',value:'',disabled:false,validity:{badInput:false},attrs:{},closest:()=>state.tr,focus(){window.document.activeElement=this;},setAttribute(k,v){this.attrs[k]=v;},setSelectionRange(){}});return state.fields.get(key);}
 const window={document:{getElementById:el,activeElement:null},setTimeout(fn,delay=0){const id=++timerId;timers.set(id,{fn,at:now+delay});return id;},clearTimeout:id=>timers.delete(id),addEventListener:(k,h)=>events[k]=h,PDC_AUTH_CONTEXT:{userId:token},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args:copy(args),resolve}));}}};
 vm.runInNewContext(source,{window,globalThis:window,module:undefined,Map,Set,console});const api=window.BROOME_SALES_FINANCE;
 api.init({getToken:()=>token,getContext:()=>window.PDC_AUTH_CONTEXT?{role:'administrator'}:null,getSalesperson:()=>scope,getView:()=>view});
 async function refresh(next=records,canEdit=true,error=null){const task=api.refresh();calls.at(-1).resolve(error?{error}:{data:{context:{role:canEdit?'administrator':'salesperson',can_edit_finance:canEdit},entries:copy(next)}});await task;}
 function input(id,key,value,badInput=false){const t=control(id,key);t.value=value;t.validity.badInput=badInput;el('sales-finance').events.input({target:t});return t;}
 function change(id,key){el('sales-finance').events.change({target:control(id,key)});}
 function action(key,id){el('sales-finance').events.click({target:{closest:()=>({dataset:{[key]:id},hasAttribute:()=>false})}});}
 async function advance(ms){const end=now+ms;for(let loops=0;loops<100;loops++){const due=[...timers].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!due)break;now=due[1].at;timers.delete(due[0]);due[1].fn();await tick();}now=end;}
 async function finish(index,error=null){const call=calls[index];if(error)call.resolve({error});else{const i=records.findIndex(r=>r.id===call.args.p_id);records[i]={...records[i],...call.args.p_data,version:records[i].version+1};call.resolve({data:{record:copy(records[i])}});}await tick();}
 return {api,window,calls,events,records,refresh,input,change,action,advance,finish,control,row,writes:()=>writes,html:()=>el('sales-finance').innerHTML,
  setToken(value){token=value;window.PDC_AUTH_CONTEXT=value?{userId:value}:null;api.syncScope();},setScope(value){scope=value;api.syncScope();},setView:value=>view=value};
}
test('typing batches one row patch, automatically persists cents and does not replace the focused cell',async()=>{
 const h=harness();await h.refresh();const notes=h.input('one','notes','First');notes.focus();h.input('one','finance_comm','12.30');await h.advance(400);h.input('one','notes','Finished note');await h.advance(699);assert.equal(h.calls.length,1);await h.advance(1);
 assert.deepEqual(h.calls[1].args.p_data,{notes:'Finished note',finance_comm:12.3});assert.equal(h.calls[1].args.p_expected_version,1);assert.equal(h.row('one').status.textContent,'Saving…');const before=h.writes();await h.finish(1);
 assert.equal(h.row('one').status.textContent,'Saved');assert.equal(h.writes(),before);assert.strictEqual(h.window.document.activeElement,notes);assert.equal(notes.dataset.financeVersion,'2');
});
test('edits made during a slow save are queued with the returned version and never erased',async()=>{
 const h=harness();await h.refresh();h.input('one','notes','First save').focus();await h.advance(700);assert.equal(h.calls.length,2);
 h.input('one','notes','Newer typing');h.input('one','naf','40000');await h.advance(800);assert.equal(h.calls.length,2,'one request per row at a time');await h.finish(1);assert.equal(h.control('one','notes').value,'Newer typing');
 await h.advance(700);assert.equal(h.calls.length,3);assert.deepEqual(h.calls[2].args.p_data,{notes:'Newer typing',naf:40000});assert.equal(h.calls[2].args.p_expected_version,2);await h.finish(2);assert.equal(h.records[0].notes,'Newer typing');assert.equal(h.records[0].naf,40000);assert.equal(h.row('one').status.textContent,'Saved');
});
test('different rows save independently, duplicate change events coalesce and unchanged values do not write',async()=>{
 const h=harness();await h.refresh();h.input('one','access','Yes');h.change('one','access');h.change('one','access');h.input('two','notes','Another row');await h.advance(20);assert.equal(h.calls.length,2);await h.advance(680);assert.equal(h.calls.length,3);await h.finish(2);await h.finish(1);
 h.input('one','access','Yes');h.change('one','access');await h.advance(20);assert.equal(h.calls.length,3);assert.equal(h.row('one').status.textContent,'Saved');
});
test('partial dates and invalid numeric input never save; committing a complete date saves its paired status',async()=>{
 const h=harness();await h.refresh();h.input('one','settlement_date','',true);h.change('one','settlement_date');await h.advance(1000);assert.equal(h.calls.length,1);h.input('one','settlement_date','2024-02-30');h.change('one','settlement_date');await h.advance(1000);assert.equal(h.calls.length,1);
 h.input('one','settlement_date','2024-02-29');await h.advance(1000);assert.equal(h.calls.length,1,'do not save partly edited native date segments');h.change('one','settlement_date');await h.advance(20);assert.deepEqual(h.calls[1].args.p_data,{settlement:'Yes',settlement_date:'2024-02-29'});await h.finish(1);
 h.input('one','finance_comm','',true);await h.advance(1000);assert.equal(h.calls.length,2);assert.match(h.row('one').status.textContent,/valid amount/);
});
test('failed saves keep the newest edits, show Retry and do not retry silently in a loop',async()=>{
 const h=harness();await h.refresh();h.input('one','notes','Save this').focus();await h.advance(700);h.input('one','notes','Keep latest');await h.finish(1,{message:'Connection lost'});assert.match(h.row('one').status.textContent,/Connection lost.*edits remain/);assert.equal(h.row('one').tr.querySelector('[data-finance-save]').textContent,'Retry');await h.advance(5000);assert.equal(h.calls.length,2);
 h.action('financeSave','one');assert.equal(h.calls[2].args.p_expected_version,1);assert.deepEqual(h.calls[2].args.p_data,{notes:'Keep latest'});await h.finish(2);assert.equal(h.records[0].notes,'Keep latest');
});
test('a failed background refresh retains unsaved data, while newer saved versions cannot be overwritten',async()=>{
 const h=harness();await h.refresh();h.input('one','notes','Retained');await h.refresh(h.records,true,{message:'Network unavailable'});assert.match(h.html(),/Retained/);await h.advance(2000);assert.equal(h.calls.length,2);h.action('financeSave','one');await h.finish(2);
 h.input('one','notes','Stale edit');await h.refresh([{...h.records[0],notes:'Another editor',version:3},h.records[1]]);await h.advance(700);assert.equal(h.calls.length,4,'stale edit is blocked before RPC');assert.match(h.row('one').status.textContent,/changed/i);
});
test('sign-out, account replacement, salesperson changes and permission loss cancel queued saves and delayed results',async()=>{
 for(const change of [h=>h.setToken(''),h=>h.setToken('other'),h=>h.setScope('BG'),async h=>h.refresh(h.records,false)]){
  const h=harness();await h.refresh();h.input('one','notes','Do not leak');await change(h);await h.advance(1000);assert.equal(h.calls.filter(c=>c.name==='save_broome_finance_application').length,0);
 }
 const h=harness();await h.refresh();h.input('one','notes','Delayed');await h.advance(700);h.setToken('other');await h.finish(1);assert.equal(h.html(),'');await h.advance(1000);assert.equal(h.calls.length,2);
});
test('pending saves continue across local page navigation and warn before leaving the browser',async()=>{
 const h=harness();await h.refresh();h.input('one','notes','Keep after navigation');const event={preventDefault(){this.prevented=true;}};h.events.beforeunload(event);assert.equal(event.prevented,true);
 h.setView('dashboard');await h.advance(700);await h.finish(1);h.setView('finance');h.api.render();assert.match(h.html(),/Keep after navigation/);const clean={preventDefault(){this.prevented=true;}};h.events.beforeunload(clean);assert.equal(clean.prevented,undefined);
});
test('a committed save with a lost response is reconciled by refresh without a duplicate or stale overwrite',async()=>{
 const h=harness();await h.refresh();h.input('one','notes','Already committed').focus();await h.advance(700);h.records[0]={...h.records[0],notes:'Already committed',version:2};await h.finish(1,{message:'Response lost'});await h.refresh();h.action('financeSave','one');assert.equal(h.calls.length,3);assert.equal(h.row('one').status.textContent,'Saved');
});
