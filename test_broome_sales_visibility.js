const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const sales=require('./sales/sales.js');
function harness(){
 const elements=new Map(),events={},calls=[];
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',
  dataset:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},
  events:{},addEventListener(name,fn){this.events[name]=fn;},close(){this.closed=true;},showModal(){this.closed=false;},scrollIntoView(){this.scrolled=true;},focus(){this.focused=true;}});
  return elements.get(id);}
 const nav=['dashboard','pipeline','labels','finance'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},
  BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),PDC_AUTH_CONTEXT:{role:'salesperson',userId:'A'},PDC_SUPABASE:{rpc(name,args){
   return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(name,fn){events[name]=fn;},setInterval(){}};
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Date,console});
 return{window,events,calls,el};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));

const row={cosi:true,tracking_id:'demo',stock:'130001',order:'TOYOTA001',client:'Fictional demo',salesperson_code:'BG',source_current:true,sales_hidden:false,sales_visibility_version:0};
const snapshot=items=>({data:{context:{role:'salesperson'},items}});
const action=(h,id,value)=>h.el('vehicle-table').events.change({target:{dataset:{emailId:id},value}});
test('active and hidden scopes exclude absent, unsold and other salesperson rows',()=>{
 const rows=[row,{...row,tracking_id:'hidden',sales_hidden:true},{...row,tracking_id:'missing',source_current:false},{...row,tracking_id:'unsold',cosi:false},{...row,tracking_id:'other',salesperson_code:'CW'}];
 assert.deepEqual(sales.scopeRows(rows,'BG').map(r=>r.tracking_id),['demo']);
 assert.deepEqual(sales.scopeRows(rows,'BG','hidden').map(r=>r.tracking_id),['hidden']);
 assert.equal(sales.selectRows(rows,{category:'all',sort:'stock',direction:1,salesperson:'BG'}).length,1);
});
test('hide waits for confirmation, removes selected labels and survives stale poll',async()=>{
 const h=harness();h.calls[0].resolve(snapshot([{...row}]));await tick();
 assert.match(h.el('vehicle-table').innerHTML,/Hide from sales planner/);
 assert.match(h.el('sales-mobile-vehicles').innerHTML,/Hide from sales planner/);
 h.el('vehicle-table').events.change({target:{dataset:{select:'demo'},checked:true}});
 h.el('sales-refresh').events.click();
 action(h,'demo','hide');
 assert.equal(h.calls[2].name,'set_broome_sales_vehicle_visibility');
 assert.deepEqual(JSON.parse(JSON.stringify(h.calls[2].args)),{p_tracking_id:'demo',p_hidden:true,p_expected_version:0});
 assert.match(h.el('vehicle-table').innerHTML,/Fictional demo/);
 h.calls[2].resolve({data:{tracking_id:'demo',sales_hidden:true,sales_visibility_version:1}});await tick();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Fictional demo/);
 assert.match(h.el('sales-summary').innerHTML,/0 selected/);
 h.calls[1].resolve(snapshot([{...row}]));await tick();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Fictional demo/);
 assert.equal(h.calls[3].name,'get_broome_sales_snapshot');
 h.calls[3].resolve(snapshot([]));await tick();
 h.el('sales-view-labels').events.click();
 assert.doesNotMatch(h.el('sales-labels').innerHTML,/Fictional demo/);
 assert.equal(h.el('sales-print-labels').disabled,true);
 h.el('nav-pipeline').events.click();assert.doesNotMatch(h.el('sales-pipeline').innerHTML,/Fictional demo/);
});
test('failed or malformed hide keeps vehicle visible without issuing PDC writes',async()=>{
 for(const result of [{error:{message:'Visibility changed'}},{data:{tracking_id:'demo',sales_hidden:true,sales_visibility_version:9}}]){
 const h=harness();h.calls[0].resolve(snapshot([{...row}]));await tick();
 action(h,'demo','hide');h.calls[1].resolve(result);await tick();
 assert.match(h.el('vehicle-table').innerHTML,/Fictional demo/);
 assert.match(h.el('sales-visibility-status').textContent,/not changed/);
 assert.equal(h.calls.length,2);
 }
});
test('hidden view offers restore only and missing hidden orders disappear',async()=>{
 const h=harness();h.calls[0].resolve(snapshot([]));await tick();
 h.el('sales-hidden-toggle').events.click();assert.equal(h.calls[1].name,'get_broome_hidden_sales_vehicles');
 h.calls[1].resolve(snapshot([{...row,sales_hidden:true,sales_visibility_version:1},{...row,tracking_id:'missing',client:'Missing demo',sales_hidden:true,source_current:false}]));await tick();
 assert.match(h.el('vehicle-table').innerHTML,/Show on sales planner/);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/View details|Hide from sales planner|Missing demo/);
 assert.match(h.el('vehicle-table').innerHTML,/data-ordering-flag="tint"[^>]*disabled/);
 action(h,'demo','show');assert.equal(h.calls[2].args.p_expected_version,1);
 h.calls[2].resolve({data:{tracking_id:'demo',sales_hidden:false,sales_visibility_version:2}});await tick();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Fictional demo/);
 h.calls[3].resolve(snapshot([{...row,sales_visibility_version:2}]));await tick();
 assert.equal(h.calls[4].name,'get_broome_hidden_sales_vehicles');
 h.calls[4].resolve(snapshot([]));await tick();
 h.el('sales-hidden-toggle').events.click();
 assert.match(h.el('vehicle-table').innerHTML,/Fictional demo/);
});
test('account change suppresses delayed visibility or hidden responses',async()=>{
 for(const mode of ['hide','hidden']){
 const h=harness();h.calls[0].resolve(snapshot([{...row}]));await tick();
 if(mode==='hide')action(h,'demo','hide');else h.el('sales-hidden-toggle').events.click();
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[1].resolve(mode==='hide'?{data:{tracking_id:'demo',sales_hidden:true,sales_visibility_version:1}}:snapshot([{...row,sales_hidden:true}]));await tick();
 assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-visibility-status').textContent,'');
 }
});
test('unknown, missing, conflicting and filtered vehicles cannot change visibility',async()=>{
 const h=harness();h.calls[0].resolve(snapshot([{...row,identity_conflict:true}]));await tick();
 for(const id of ['demo','missing'])action(h,id,'hide');
 assert.equal(h.calls.length,1);
});
test('refresh removes absent orders from all planner selections and details',async()=>{
 const h=harness();h.calls[0].resolve(snapshot([{...row}]));await tick();
 h.el('vehicle-table').events.change({target:{dataset:{select:'demo'},checked:true}});
 h.el('vehicle-table').events.click({target:{closest:s=>s==='[data-open]'?{dataset:{open:'demo'}}:null}});
 h.el('sales-refresh').events.click();h.calls[1].resolve(snapshot([{...row,source_current:false}]));await tick();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Fictional demo/);assert.equal(h.el('sales-detail-content').innerHTML,'');
 h.el('sales-show-all').events.click();h.el('sales-clear-filters').events.click();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Fictional demo/);
});
