const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const sales=require('./sales/sales.js');
const fixture=(stock,eta,extra={})=>({tracking_id:stock,stock,cosi:'Yes',kewdale_eta:eta,...extra});
const filters={category:'all',sort:'kewdale_eta',direction:1};
test('Kewdale ETA sorts the reported day/month dates chronologically in both directions',()=>{
 const rows=[fixture('september','01/09/2026'),fixture('august','03/08/2026'),fixture('april','01/04/2025'),fixture('september3','03/09/2026')];
 const before=JSON.stringify(rows);
 assert.deepEqual(sales.selectRows(rows,filters).map(r=>r.stock),['april','august','september','september3']);
 assert.deepEqual(sales.selectRows(rows,{...filters,direction:-1}).map(r=>r.stock),['september3','september','august','april']);
 assert.equal(JSON.stringify(rows),before);
});
test('mixed ISO and Australian dates cross months and years correctly, keeping absent and invalid dates last',()=>{
 const rows=[fixture('blank',''),fixture('iso','2026-01-01'),fixture('null',null),fixture('old','31/12/2025'),fixture('invalid','31/02/2026'),fixture('leap','29/2/2024'),fixture('unpadded','3/8/2026'),fixture('timestamp','2026-09-01T00:00:00Z'),fixture('invalidLeap','29/02/2025')];
 assert.deepEqual(sales.selectRows(rows,filters).map(r=>r.stock),['leap','old','iso','unpadded','timestamp','blank','null','invalid','invalidLeap']);
 assert.deepEqual(sales.selectRows(rows,{...filters,direction:-1}).map(r=>r.stock),['timestamp','unpadded','iso','old','leap','blank','null','invalid','invalidLeap']);
});
test('equal ETA dates keep stable order and sorting retains the authorised COSI visibility filters',()=>{
 const rows=[fixture('first','03/08/2026',{salesperson_code:'BG'}),fixture('second','2026-08-03',{salesperson_code:'BG'}),fixture('other','01/01/2024',{salesperson_code:'CW'}),fixture('unsold','01/01/2024',{salesperson_code:'BG',cosi:'No'}),fixture('hidden','01/01/2024',{salesperson_code:'BG',sales_hidden:true}),fixture('missing','01/01/2024',{salesperson_code:'BG',source_current:false})];
 for(const direction of [1,-1])assert.deepEqual(sales.selectRows(rows,{...filters,salesperson:'BG',direction}).map(r=>r.stock),['first','second']);
});
function harness(){
 const elements=new Map(),events={},calls=[];
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',
  dataset:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},
  events:{},addEventListener(name,fn){this.events[name]=fn;},close(){this.closed=true;},showModal(){this.closed=false;},scrollIntoView(){this.scrolled=true;},focus(){this.focused=true;}});
  return elements.get(id);}
 const nav=['dashboard','pipeline','labels','finance'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},
  BROOME_SALES_TOOLS:require('./sales/dashboard-tools.js'),BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),PDC_AUTH_CONTEXT:{role:'salesperson',userId:'A'},PDC_SUPABASE:{rpc(name,args){
   return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(name,fn){events[name]=fn;},setInterval(){}};
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Date,console});
 return{window,events,calls,el};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));

function sortedStocks(h){return [...h.el('vehicle-table').innerHTML.matchAll(/data-open="(early|late|middle|blank)"/g)].map(m=>m[1]);}
function clickEta(h){h.el('vehicle-table').events.click({target:{closest:s=>s==='[data-sort]'?{dataset:{sort:'kewdale_eta'}}:null}});}
test('dashboard header click toggles earliest/latest and refresh retains chronological order without writes',async()=>{
 const h=harness();const rows=[fixture('late','01/09/2026'),fixture('early','03/08/2026'),fixture('middle','2026-08-27'),fixture('blank','')];
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:rows}});await tick();
 clickEta(h);assert.deepEqual(sortedStocks(h),['early','middle','late','blank']);assert.match(h.el('vehicle-table').innerHTML,/aria-sort="ascending"[^>]*><button type="button" data-sort="kewdale_eta">Kewdale ETA ↑/);
 clickEta(h);assert.deepEqual(sortedStocks(h),['late','middle','early','blank']);assert.match(h.el('vehicle-table').innerHTML,/aria-sort="descending"[^>]*><button type="button" data-sort="kewdale_eta">Kewdale ETA ↓/);
 h.el('sales-refresh').events.click();h.calls[1].resolve({data:{context:{role:'salesperson'},items:rows.slice().reverse()}});await tick();assert.deepEqual(sortedStocks(h),['late','middle','early','blank']);
 assert.deepEqual(h.calls.map(c=>c.name),['get_broome_sales_snapshot','get_broome_sales_snapshot']);
});
