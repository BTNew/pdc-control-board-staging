const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const sales=require('./sales/sales.js');
const filters={category:'all',search:'',salesperson:'',month:'',status:'',jita:'',sort:'stock',direction:1};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function records(){return [
 {tracking_id:'bg-yard',stock:'13030001',order:'000111',salesperson_code:'BG',salesperson_name:'Bryce example',client:'BG yard customer',vehicle:'Example HiLux',cosi:'Yes',production_month:'06/26',toyota_status:'Yard Hold',location_status:'YH',canonical_vehicle_id:'pmb-bg',ordering_version:0},
 {tracking_id:'bg-await',stock:'',order:'000112',salesperson_code:'BG',client:'BG awaiting customer',vehicle:'Example Prado',cosi:true,production_month:'07/26',toyota_status:'Planned for Production'},
 {tracking_id:'cw-production',stock:'13030003',order:'000113',salesperson_code:'CW',client:'CW production customer',vehicle:'Example HiAce',cosi:1,production_month:'09/26',toyota_status:'Planned for Production',canonical_vehicle_id:'pmb-cw'},
 {tracking_id:'cw-dealer',stock:'13030004',order:'000114',salesperson_code:'CW',client:'CW dealer customer',vehicle:'Example Corolla',cosi:' yes ',production_month:'10/26',toyota_status:'Delivered - At Dealer'},
 {tracking_id:'bg-unsold',stock:'13039901',order:'000115',salesperson_code:'BG',client:'UNSOLD PRIVATE CUSTOMER',cosi:'No',production_month:'11/26',toyota_status:'UNSOLD ONLY LOCATION',canonical_vehicle_id:'pmb-unsold'},
 {tracking_id:'cw-unknown',stock:'13039902',order:'000116',salesperson_code:'CW',client:'UNKNOWN PRIVATE CUSTOMER',cosi:null,production_month:'12/26',toyota_status:'UNKNOWN ONLY LOCATION',canonical_vehicle_id:'pmb-unknown'}
];}
function harness(){
 const elements=new Map(),events={},calls=[];
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',closed:true,
  dataset:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},events:{},
  addEventListener(name,fn){this.events[name]=fn;},close(){this.closed=true;},showModal(){this.closed=false;},scrollIntoView(){},focus(){}});return elements.get(id);}
 const nav=['dashboard','pipeline','labels','finance'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},
  BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),PDC_AUTH_CONTEXT:{role:'administrator',userId:'admin-example'},
  PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},
  addEventListener(name,fn){events[name]=fn;},setInterval(){}};
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Date,console});
 return {window,events,calls,el};
}
async function load(h,items=records()){
 h.calls.at(-1).resolve({data:{context:{role:'administrator',display_name:'Administrator example'},items}});await tick();
}
function choose(h,id,value){h.el(id).value=value;h.el(id).events.change({target:{value}});}
function select(h,id){h.el('vehicle-table').events.change({target:{dataset:{select:id},checked:true}});}
function open(h,id){h.el('vehicle-table').events.click({target:{closest:selector=>selector==='[data-open]'?{dataset:{open:id}}:null}});}
function cardCount(h,key){
 const match=h.el('status-tabs').innerHTML.match(new RegExp('data-category="'+key+'"[^>]*>[\\s\\S]*?<strong>(\\d+)</strong>'));
 assert.ok(match,'Expected status card '+key);return Number(match[1]);
}
test('COSI scope accepts only explicit yes values and excludes stocked unsold and unknown records',()=>{
 const rows=[true,'Yes',' YES ','true',' true ',1,' 1 ',false,'No','0','',null,undefined,'Unknown','y','yes please'].map((cosi,index)=>({cosi,stock:String(index),salesperson_code:index%2?'CW':'BG'}));
 const original=rows.slice();
 assert.deepEqual(sales.scopeRows(rows).map(r=>r.stock),['0','1','2','3','4','5','6']);
 assert.deepEqual(sales.scopeRows(rows,'BG').map(r=>r.stock),['0','2','4','6']);
 assert.deepEqual(sales.selectRows(rows,filters).map(r=>r.stock),['0','1','2','3','4','5','6']);
 assert.deepEqual(rows,original,'Filtering must not alter imported records');
});
test('dashboard, pipeline and dropdown options contain only COSI vehicles in the selected salesperson scope',async()=>{
 const h=harness();await load(h);
 assert.equal(cardCount(h,'all'),4);assert.match(h.el('sales-data-count').textContent,/\b4\b/);
 for(const id of ['vehicle-table','sales-pipeline','sales-month-filter','sales-status-filter']){
  assert.doesNotMatch(h.el(id).innerHTML,/UNSOLD|UNKNOWN|11\/26|12\/26/);
 }
 choose(h,'salesperson-filter','BG');
 assert.equal(cardCount(h,'all'),2);assert.equal(cardCount(h,'unconfirmed'),1);assert.equal(cardCount(h,'yardhold'),1);
 assert.equal(cardCount(h,'production'),0);assert.equal(cardCount(h,'dealer'),0);
 assert.match(h.el('sales-data-count').textContent,/\b2\b/);assert.match(h.el('sales-summary').innerHTML,/1 linked to PMB/);
 assert.match(h.el('vehicle-table').innerHTML,/BG yard customer/);assert.match(h.el('vehicle-table').innerHTML,/BG awaiting customer/);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/CW production customer|CW dealer customer/);
 h.el('nav-pipeline').events.click();assert.match(h.el('sales-pipeline').innerHTML,/BG yard customer/);assert.match(h.el('sales-pipeline').innerHTML,/BG awaiting customer/);
 assert.doesNotMatch(h.el('sales-pipeline').innerHTML,/CW production customer|CW dealer customer/);
 assert.match(h.el('sales-month-filter').innerHTML,/06\/26|07\/26/);assert.doesNotMatch(h.el('sales-month-filter').innerHTML,/09\/26|10\/26/);
 assert.match(h.el('sales-status-filter').innerHTML,/Yard Hold/);assert.doesNotMatch(h.el('sales-status-filter').innerHTML,/Delivered - At Dealer/);
 h.el('nav-dashboard').events.click();choose(h,'salesperson-filter','CW');
 assert.equal(cardCount(h,'all'),2);assert.equal(cardCount(h,'production'),1);assert.equal(cardCount(h,'dealer'),1);
 assert.equal(cardCount(h,'unconfirmed'),0);assert.equal(cardCount(h,'yardhold'),0);
 assert.doesNotMatch(h.el('sales-month-filter').innerHTML,/06\/26|07\/26/);assert.doesNotMatch(h.el('sales-pipeline').innerHTML,/BG yard customer|BG awaiting customer/);
});
test('changing salesperson resets unavailable month and status filters, closes details and clears labels',async()=>{
 const h=harness();await load(h);choose(h,'salesperson-filter','BG');
 choose(h,'sales-month-filter','06/26');choose(h,'sales-status-filter','Yard Hold');
 select(h,'bg-yard');h.el('sales-view-labels').events.click();assert.match(h.el('sales-labels').innerHTML,/BG yard customer/);
 h.el('nav-dashboard').events.click();open(h,'bg-yard');assert.equal(h.el('sales-detail').closed,false);
 choose(h,'salesperson-filter','CW');
 assert.equal(h.el('sales-month-filter').value,'');assert.equal(h.el('sales-status-filter').value,'');
 assert.equal(h.el('sales-detail').closed,true);assert.equal(h.el('sales-detail-content').innerHTML,'');
 assert.doesNotMatch(h.el('sales-labels').innerHTML,/BG yard customer/);assert.equal(h.el('sales-print-labels').disabled,true);
 assert.match(h.el('sales-summary').innerHTML,/0 selected<\/span>/);
 assert.match(h.el('vehicle-table').innerHTML,/CW production customer/);assert.match(h.el('vehicle-table').innerHTML,/CW dealer customer/);
 assert.equal(h.calls.length,1,'Changing dashboard scope must not write operational data');
});
test('a pending Zebra job loses submission authority if its salesperson scope changes',async()=>{
 const h=harness(),jobs=[];let fail;
 h.window.BROOME_ZEBRA_LABELS={...h.window.BROOME_ZEBRA_LABELS,print:(rows,authorised)=>{
  jobs.push({rows,authorised});return new Promise((resolve,reject)=>{fail=reject;});
 }};
 await load(h);choose(h,'salesperson-filter','BG');select(h,'bg-yard');h.el('sales-view-labels').events.click();
 h.el('sales-print-labels').events.click();assert.equal(jobs.length,1);assert.equal(jobs[0].rows[0].tracking_id,'bg-yard');assert.equal(jobs[0].authorised(),true);
 h.el('nav-dashboard').events.click();choose(h,'salesperson-filter','CW');assert.equal(jobs[0].authorised(),false);
 fail(new Error('Vehicle access changed. Refresh before printing.'));await tick();
 assert.doesNotMatch(h.el('sales-labels').innerHTML,/BG yard customer/);assert.equal(h.el('sales-print-labels').disabled,true);
});
test('refresh removes a vehicle whose COSI becomes No from detail, labels and ordering writes',async()=>{
 const h=harness();await load(h);choose(h,'salesperson-filter','BG');select(h,'bg-yard');open(h,'bg-yard');
 h.el('sales-refresh').events.click();await load(h,records().map(r=>r.tracking_id==='bg-yard'?{...r,cosi:'No'}:r));
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/BG yard customer/);assert.doesNotMatch(h.el('sales-pipeline').innerHTML,/BG yard customer/);
 assert.equal(h.el('sales-detail').closed,true);assert.equal(h.el('sales-detail-content').innerHTML,'');assert.equal(h.el('sales-print-labels').disabled,true);
 const before=h.calls.length;
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'bg-yard',orderingFlag:'tint'},checked:true}});
 select(h,'bg-yard');h.el('sales-view-labels').events.click();await tick();
 assert.equal(h.calls.length,before,'A hidden order cannot trigger an ordering write');assert.doesNotMatch(h.el('sales-labels').innerHTML,/BG yard customer/);
});
test('the fixed sales roster keeps a selected salesperson with no current orders',async()=>{
 const h=harness();await load(h);choose(h,'salesperson-filter','BG');
 h.el('sales-refresh').events.click();await load(h,records().filter(r=>r.salesperson_code==='CW'));
 assert.equal(h.el('salesperson-filter').value,'BG');assert.equal(cardCount(h,'all'),0);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/CW production customer|CW dealer customer/);
 assert.match(h.el('salesperson-filter').innerHTML,/value="BG"/);
 choose(h,'salesperson-filter','');assert.equal(cardCount(h,'all'),2);
});


test('only the four current salespeople enter visible and hidden planner scopes; shared rows are untouched',()=>{
 const rows=['BG','AW','PM','CW','ZZ','',null].flatMap((code,index)=>[
  {cosi:true,source_current:true,salesperson_code:code,tracking_id:'visible-'+index},
  {cosi:true,source_current:true,salesperson_code:code,tracking_id:'hidden-'+index,sales_hidden:true}
 ]);
 const before=JSON.stringify(rows);
 assert.deepEqual(sales.salespeople,['BG','AW','PM','CW']);
 assert.deepEqual(sales.scopeRows(rows).map(r=>r.salesperson_code),['BG','AW','PM','CW']);
 assert.deepEqual(sales.scopeRows(rows,'','hidden').map(r=>r.salesperson_code),['BG','AW','PM','CW']);
 assert.deepEqual(sales.scopeRows(rows,'ZZ'),[]);
 assert.equal(JSON.stringify(rows),before);
});

test('the fixed selector and every dashboard count exclude additional imported salesperson codes',async()=>{
 const h=harness(),excluded={...records()[0],tracking_id:'zz-yard',stock:'13990000',salesperson_code:'ZZ',client:'Excluded example customer',production_month:'01/27',toyota_status:'Other person location'};
 await load(h,[...records(),excluded]);
 const options=[...h.el('salesperson-filter').innerHTML.matchAll(/<option value="([^"]+)"/g)].map(m=>m[1]);
 assert.deepEqual(options,['BG','AW','PM','CW']);
 assert.equal(cardCount(h,'all'),4);
 for(const id of ['vehicle-table','sales-pipeline','sales-month-filter','sales-status-filter'])assert.doesNotMatch(h.el(id).innerHTML,/Excluded example|Other person location|01\/27/);
 for(const [code,count] of [['BG',2],['AW',0],['PM',0],['CW',2]]){
  choose(h,'salesperson-filter',code);assert.equal(cardCount(h,'all'),count);
 }
 assert.equal(h.calls.length,1,'Roster selection must not write shared PDC data');
});
