'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),sales=require('./sales/sales.js');
const tick=()=>new Promise(r=>setImmediate(r)),copy=v=>JSON.parse(JSON.stringify(v));
const base={tracking_id:'one',stock:'QA-1',order:'250000001',client:'Fictional dispatch',salesperson_code:'BG',cosi:true,source_current:true,transport_number:'001234',toyota_status:'Despatched - From TWA',autocare_dispatch_version:0};
const snap=items=>({data:{context:{role:'administrator'},items:copy(items)}});
function harness(){
 const elements=new Map(),events={},calls=[];function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',value:'',hidden:false,disabled:false,dataset:{},classList:{toggle(){}},events:{},setAttribute(){},removeAttribute(){},addEventListener(n,f){this.events[n]=f;},close(){},showModal(){},focus(){}});return elements.get(id);}
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>[],addEventListener(){}},PDC_AUTH_CONTEXT:{userId:'A',role:'administrator'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener:(n,f)=>events[n]=f,setInterval(){},setTimeout(fn){fn();return 1;},clearTimeout(){}};
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Map,Date,console});
 return {el,window,calls,events,select(id){el('vehicle-table').events.change({target:{dataset:{select:id},checked:true}});},action(id,value){el('vehicle-table').events.change({target:{dataset:{emailId:id},value}});}};
}
test('Autocare is separate from Released and Navision dealer delivery always takes precedence',()=>{
 assert.equal(sales.category(base),'released');assert.equal(sales.category({...base,autocare_dispatched:true}),'autocare');assert.equal(sales.salesStatus({...base,autocare_dispatched:true}),'Dispatched Autocare');
 for(const stock of ['QA-1','',null])assert.equal(sales.category({...base,stock,autocare_dispatched:true,toyota_status:'Delivered - At Dealer'}),'dealer');
 for(const invalid of [{source_current:false},{sales_hidden:true},{identity_conflict:true},{order:''},{toyota_status:'Delivered - At Dealer'}])assert.equal(sales.dispatchEligible({...base,...invalid}),false);
});
test('transport-number search keeps leading zero references and existing approved scope',()=>{
 const rows=[base,{...base,tracking_id:'two',transport_number:'001234',salesperson_code:'AW'},{...base,tracking_id:'no',transport_number:'009999'},{...base,tracking_id:'absent',source_current:false},{...base,tracking_id:'hidden',sales_hidden:true}];
 assert.deepEqual(sales.selectRows(rows,{category:'all',search:'001234',salesperson:'BG',sort:'stock',direction:1}).map(r=>r.tracking_id),['one']);
 assert.equal(sales.selectRows(rows,{category:'all',search:'001234',sort:'stock',direction:1}).length,2);
});
test('batch dispatch includes checked vehicles outside the current search and waits for server confirmation',async()=>{
 const h=harness();h.calls[0].resolve(snap([base,{...base,tracking_id:'two',stock:'QA-2'},{...base,tracking_id:'other',transport_number:'009999'}]));await tick();h.select('other');h.el('search').events.input({target:{value:'001234'}});h.select('one');h.select('two');h.el('sales-dispatch-selected').events.click();
 assert.equal(h.calls[1].name,'set_broome_sales_autocare_dispatch');assert.deepEqual(copy(h.calls[1].args),{p_entries:[{tracking_id:'one',expected_version:0},{tracking_id:'two',expected_version:0},{tracking_id:'other',expected_version:0}],p_dispatched:true});assert.equal(h.el('sales-dispatch-selected').disabled,true);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/class="status-pill autocare/);
 h.calls[1].resolve({data:{items:['one','two','other'].map(tracking_id=>({tracking_id,autocare_dispatched:true,autocare_dispatch_version:1}))}});await tick();assert.match(h.el('vehicle-table').innerHTML,/status-pill autocare/);assert.match(h.el('sales-dispatch-status').textContent,/3 vehicles marked/);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/data-select="other"/);
});
test('failed or malformed dispatch does not update tiles and remains retryable',async()=>{
 for(const response of [{error:{message:'Conflict'}},{data:{items:[{tracking_id:'other',autocare_dispatched:true,autocare_dispatch_version:1}]}},{data:{items:[{tracking_id:'one',autocare_dispatched:true,autocare_dispatch_version:0}]}}]){
  const h=harness();h.calls[0].resolve(snap([base]));await tick();h.select('one');h.el('sales-dispatch-selected').events.click();h.calls[1].resolve(response);await tick();assert.doesNotMatch(h.el('vehicle-table').innerHTML,/status-pill autocare/);assert.match(h.el('sales-dispatch-status').textContent,/Conflict|not saved/);assert.equal(h.el('sales-dispatch-selected').disabled,false);
 }
});
test('stale polls cannot remove a confirmed mark, but fresh dealer status still wins; undo uses current version',async()=>{
 const h=harness();h.calls[0].resolve(snap([base]));await tick();h.el('sales-refresh').events.click();h.action('one','autocare-dispatch');h.calls[2].resolve({data:{items:[{tracking_id:'one',autocare_dispatched:true,autocare_dispatch_version:1}]}});await tick();h.calls[1].resolve(snap([base]));await tick();assert.match(h.el('vehicle-table').innerHTML,/status-pill autocare/);
 h.action('one','autocare-clear');assert.equal(h.calls[3].args.p_entries[0].expected_version,1);h.calls[3].resolve({data:{items:[{tracking_id:'one',autocare_dispatched:false,autocare_dispatch_version:2}]}});await tick();h.el('sales-clear-filters').events.click();assert.match(h.el('vehicle-table').innerHTML,/status-pill released/);
 h.el('sales-refresh').events.click();h.calls[4].resolve(snap([{...base,toyota_status:'Delivered - At Dealer',autocare_dispatched:true,autocare_dispatch_version:3}]));await tick();assert.match(h.el('vehicle-table').innerHTML,/status-pill dealer/);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/status-pill autocare/);
});
test('scope changes and sign-out suppress delayed responses and inaccessible vehicles cannot start requests',async()=>{
 for(const invalid of [{identity_conflict:true},{source_current:false},{sales_hidden:true},{toyota_status:'Delivered - At Dealer'}]){const h=harness();h.calls[0].resolve(snap([{...base,...invalid}]));await tick();h.action('one','autocare-dispatch');assert.equal(h.calls.length,1);}
 const h=harness();h.calls[0].resolve(snap([base]));await tick();h.action('one','autocare-dispatch');delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();h.calls[1].resolve({data:{items:[{tracking_id:'one',autocare_dispatched:true,autocare_dispatch_version:1}]}});await tick();assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-dispatch-status').textContent,'');
});

test('row-menu transfer moves all five checked vehicles and excludes an unchecked vehicle',async()=>{
 const h=harness(),rows=Array.from({length:6},(_,i)=>({...base,tracking_id:'vehicle-'+i,stock:'QA-'+i}));h.calls[0].resolve(snap(rows));await tick();
 for(let i=0;i<5;i++)h.select('vehicle-'+i);assert.match(h.el('vehicle-table').innerHTML,/Dispatched Autocare \(5 selected\)/);
 h.action('vehicle-2','autocare-dispatch');assert.deepEqual(copy(h.calls[1].args.p_entries).map(r=>r.tracking_id),rows.slice(0,5).map(r=>r.tracking_id));
 h.calls[1].resolve({data:{items:rows.slice(0,5).map(r=>({tracking_id:r.tracking_id,autocare_dispatched:true,autocare_dispatch_version:1}))}});await tick();
 assert.match(h.el('sales-dispatch-status').textContent,/5 vehicles marked/);assert.match(h.el('sales-summary').innerHTML,/0 selected/);
 h.el('sales-clear-filters').events.click();assert.match(h.el('status-tabs').innerHTML,/data-category="autocare"[^]*?<strong>5<\/strong>/);
 assert.match(h.el('vehicle-table').innerHTML,/status-pill released/);
});

test('row menu on an already dispatched vehicle transfers the rest of the selection once',async()=>{
 const h=harness(),rows=[{...base,autocare_dispatched:true,autocare_dispatch_version:1},{...base,tracking_id:'two',stock:'QA-2'},{...base,tracking_id:'three',stock:'QA-3'}];h.calls[0].resolve(snap(rows));await tick();rows.forEach(r=>h.select(r.tracking_id));
 h.action('one','autocare-dispatch');assert.deepEqual(copy(h.calls[1].args.p_entries),[{tracking_id:'two',expected_version:0},{tracking_id:'three',expected_version:0}]);
 h.calls[1].resolve({data:{items:['two','three'].map(tracking_id=>({tracking_id,autocare_dispatched:true,autocare_dispatch_version:1}))}});await tick();assert.equal(h.el('sales-dispatch-status').textContent,'3 vehicles marked Dispatched Autocare (1 already there).');assert.match(h.el('sales-summary').innerHTML,/0 selected/);
});

test('an ineligible checked vehicle prevents a partial batch and retains the selection for correction',async()=>{
 const h=harness();h.calls[0].resolve(snap([base,{...base,tracking_id:'dealer',toyota_status:'Delivered - At Dealer'}]));await tick();h.select('one');h.select('dealer');h.action('one','autocare-dispatch');
 assert.equal(h.calls.length,1);assert.match(h.el('sales-dispatch-status').textContent,/No vehicles were moved/);assert.match(h.el('sales-summary').innerHTML,/2 selected/);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/status-pill autocare/);
});
