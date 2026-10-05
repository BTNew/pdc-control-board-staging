'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const completed=require('./sales/completed-vehicles.js');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const row={tracking_id:'old',stock:'CMP-OLD',order:'250000001',client:'Fictional archive customer',vehicle:'HiLux',salesperson_code:'BG',source_current:false,completion_reason:'absent_from_navision',last_seen_at:'2026-10-01T01:00:00Z',completed_at:'2026-10-05T03:00:00Z',notes:'Saved <note>',custom_information:'Special instructions'};
function harness(integrated=false){
 const elements=new Map(),listeners={},calls=[];let view='dashboard',scope='';
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',value:'',hidden:false,disabled:false,dataset:{},events:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},focus(){},close(){},showModal(){},addEventListener(n,fn){this.events[n]=fn;},querySelector(selector){return this.innerHTML.includes('id="'+selector.slice(1)+'"')?el(selector.slice(1)):null;}});return elements.get(id);}
 const nav=['dashboard','history','labels','pipeline'].map(name=>{const node=el('nav-'+name);node.dataset.salesView=name;return node;});
 const host={PDC_AUTH_CONTEXT:{userId:'user-A',role:'administrator'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},
  document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},setInterval(){},
  BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),addEventListener(name,fn){(listeners[name]??=[]).push(fn);}};
 const api=completed.create(host);host.BROOME_COMPLETED_VEHICLES=api;
 if(integrated)vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window:host,module:undefined,console,Date,Set,Map});
 else api.init({getContext:()=>host.PDC_AUTH_CONTEXT,getView:()=>view,getSalesperson:()=>scope});
 return{host,api,el,calls,setView:x=>view=x,setScope:x=>scope=x,fire:name=>(listeners[name]||[]).forEach(fn=>fn())};
}
function response(items=[row],role='administrator'){return{data:{context:{role,salesperson_code:'BG'},items,navision_updated_at:'2026-10-05T03:16:51Z'}};}
test('Completed filters only omitted orders, searches Toyota references and retained notes, and escapes HTML',()=>{
 const rows=[row,{...row,tracking_id:'current',source_current:true},{...row,tracking_id:'wrong',completion_reason:'delivered_to_dealer'},{...row,tracking_id:'other',salesperson_code:'AW'},{...row,tracking_id:'stockless',stock:'',order:'250000002'}];
 assert.deepEqual(completed.selectRows(rows,'saved','BG').map(r=>r.tracking_id),['old','stockless']);
 assert.deepEqual(completed.selectRows(rows,'250000002').map(r=>r.tracking_id),['stockless']);
 const html=completed.tableHtml([row,rows[4]]);
 assert.match(html,/Saved &lt;note&gt;/);assert.match(html,/Toyota Order 250000002/);assert.doesNotMatch(html,/<textarea|data-open|data-ordering|data-select|<script/);
});
test('archive loads lazily, errors remove stale rows, and retry refreshes the read-only list',async()=>{
 const h=harness();h.api.render();assert.equal(h.calls.length,0);
 h.setView('history');h.api.render();assert.equal(h.calls[0].name,'get_broome_completed_sales_vehicles');
 h.calls[0].resolve(response());await tick();assert.match(h.el('completed-results').innerHTML,/Fictional archive customer/);
 h.api.refresh();assert.equal(h.el('completed-results').innerHTML.includes('Fictional archive customer'),false);
 h.calls[1].resolve({error:{message:'Access revoked'}});await tick();assert.equal(h.el('completed-results').innerHTML,'');assert.match(h.el('completed-status').textContent,/Access revoked/);
 h.el('completed-refresh').events.click();h.calls[2].resolve(response([]));await tick();assert.match(h.el('completed-results').innerHTML,/No completed vehicles/);
});
test('pending Completed response cannot repopulate a signed-out or switched account',async()=>{
 const h=harness();h.setView('history');h.api.render();delete h.host.PDC_AUTH_CONTEXT;h.fire('pdc-auth-locked');
 h.calls[0].resolve(response());await tick();assert.equal(h.el('sales-history').innerHTML,'');assert.equal(h.el('completed-results').innerHTML,'');
});
test('scope changes suppress old responses and salesperson reads only the assigned code',async()=>{
 const h=harness();h.setView('history');h.api.render();h.setScope('AW');h.api.render();
 h.calls[0].resolve(response());await tick();assert.doesNotMatch(h.el('completed-results').innerHTML,/Fictional archive customer/);
 h.calls[1].resolve(response([{...row,salesperson_code:'AW',client:'Other scoped fixture'},row]));await tick();
 assert.match(h.el('completed-results').innerHTML,/Other scoped fixture/);assert.doesNotMatch(h.el('completed-results').innerHTML,/Fictional archive customer/);
 const sp=harness();sp.host.PDC_AUTH_CONTEXT.role='salesperson';sp.setView('history');sp.api.render();sp.calls[0].resolve(response([row,{...row,tracking_id:'x',salesperson_code:'AW',client:'Unassigned fixture'}],'salesperson'));await tick();
 assert.match(sp.el('completed-results').innerHTML,/Fictional archive customer/);assert.doesNotMatch(sp.el('completed-results').innerHTML,/Unassigned fixture/);
});
test('a new active snapshot invalidates a closed archive and cancels an older pending archive response',async()=>{
 const h=harness();h.setView('history');h.api.render();h.api.currentSnapshot();
 h.calls[0].resolve(response());h.calls[1].resolve(response([]));await tick();assert.doesNotMatch(h.el('completed-results').innerHTML,/Fictional archive customer/);
 h.setView('dashboard');h.api.currentSnapshot();assert.equal(h.calls.length,2);
 h.setView('history');h.api.render();assert.equal(h.calls.length,3);h.calls[2].resolve(response([]));await tick();
});
test('Sales navigation separates current and Completed, removes stale label selection and refreshes archives',async()=>{
 const h=harness(true);
 h.calls[0].resolve({data:{context:{role:'administrator'},items:[{...row,source_current:true,cosi:true}],checked_at:'2026-10-05T03:00:00Z'}});await tick();
 h.el('vehicle-table').events.change({target:{dataset:{select:'old'},checked:true}});
 h.el('nav-history').events.click();assert.equal(h.el('sales-page-title').textContent,'Completed vehicles');assert.equal(h.calls[1].name,'get_broome_completed_sales_vehicles');
 h.calls[1].resolve(response([]));await tick();h.el('sales-refresh').events.click();
 h.calls[2].resolve({data:{context:{role:'administrator'},items:[]}});await tick();assert.equal(h.calls[3].name,'get_broome_completed_sales_vehicles');
 h.calls[3].resolve(response());await tick();assert.match(h.el('completed-results').innerHTML,/CMP-OLD/);
 h.el('nav-dashboard').events.click();assert.doesNotMatch(h.el('vehicle-table').innerHTML,/CMP-OLD/);
 h.el('sales-view-labels').events.click();assert.doesNotMatch(h.el('sales-labels').innerHTML,/CMP-OLD/);assert.equal(h.el('sales-print-labels').disabled,true);
});
