const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const sales=require('./sales/sales.js');
test('tracker keeps yard hold and consignment categories and unknown flags distinct',()=>{
 assert.equal(sales.category({stock:'130',location_status:'YH',toyota_status:'In Transit'}),'yardhold');
 assert.equal(sales.category({stock:'130',toyota_status:'Vehicle Out on Consignment'}),'released');
 assert.equal(sales.category({stock:'',toyota_status:'Yard Hold'}),'unconfirmed');
 for(const v of [null,undefined,'', 'Unknown'])assert.equal(sales.flag(v),'unknown');
 assert.equal(sales.flag(false),'no');assert.equal(sales.flag(true),'yes');
});
test('search and sorting retain missing-last order and source records',()=>{
 const records=[{stock:'100',client:'Amy'},{stock:'20',client:'Bryce'},{stock:'',client:'Bryce'}];
 const filters={category:'all',search:'',sort:'stock',direction:-1};
 assert.deepEqual(sales.selectRows(records,filters).map(r=>r.stock),['100','20','']);
 assert.equal(sales.selectRows(records,{...filters,search:'bryce'}).length,2);
 assert.deepEqual(records.map(r=>r.stock),['100','20','']);
 assert.equal(sales.escapeHtml('<script>'),'&lt;script&gt;');
});
function harness(){
 const elements=new Map(),events={},calls=[];
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',
  dataset:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},
  events:{},addEventListener(name,fn){this.events[name]=fn;},close(){this.closed=true;},showModal(){this.closed=false;}});
  return elements.get(id);}
 const nav=['dashboard','pipeline','labels','finance'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},
  PDC_AUTH_CONTEXT:{role:'salesperson',userId:'A'},PDC_SUPABASE:{rpc(name,args){
   return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(name,fn){events[name]=fn;},setInterval(){}};
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Date,console});
 return{window,events,calls,el};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
test('sign-out clears data and a delayed read cannot refill the previous account',async()=>{
 const h=harness();assert.equal(h.calls.length,1);
 h.el('sales-detail-content').innerHTML='Private customer';
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{tracking_id:'old',stock:'123',client:'Private customer'}]}});
 await tick();
 assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-detail-content').innerHTML,'');
 assert.equal(h.el('sales-refresh').disabled,false);
});
test('combined month, Toyota status and JITA filters restrict the visible authorised set',()=>{
 const rows=[{stock:'1',production_month:'06/26',toyota_status:'Yard Hold',jita:true},
 {stock:'2',production_month:'06/26',toyota_status:'Yard Hold',jita:null},
 {stock:'3',production_month:'07/26',toyota_status:'In Transit',jita:true}];
 assert.deepEqual(sales.selectRows(rows,{category:'all',month:'06/26',status:'Yard Hold',jita:'yes',sort:'stock',direction:1}).map(r=>r.stock),['1']);
 assert.deepEqual(sales.selectRows(rows,{category:'all',jita:'unknown',sort:'stock',direction:1}).map(r=>r.stock),['2']);
});
test('labels and pipeline retain authorised identities and clear on access revocation',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson',display_name:'Example'},items:[{tracking_id:'own-id',stock:'13001',order:'2026001',client:'Private customer',toyota_status:'Yard Hold'}]}});
 await tick();assert.match(h.el('sales-pipeline').innerHTML,/Private customer/);
 h.el('vehicle-table').events.change({target:{dataset:{select:'own-id'},checked:true}});
 h.el('sales-view-labels').events.click();assert.match(h.el('sales-labels').innerHTML,/Private customer/);
 assert.equal(h.el('sales-print-labels').disabled,false);
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 assert.equal(h.el('sales-pipeline').innerHTML,'');assert.equal(h.el('sales-labels').innerHTML,'');
 assert.equal(h.el('sales-print-labels').disabled,true);
});
test('Finance opens its placeholder without issuing a finance request; stale selected labels are removed on refresh',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson',display_name:'Example'},items:[{tracking_id:'old-id',stock:'13001',client:'Old assignment'}]}});
 await tick();h.el('vehicle-table').events.change({target:{dataset:{select:'old-id'},checked:true}});
 h.el('nav-finance').events.click();assert.equal(h.el('sales-finance-view').hidden,false);
 assert.equal(h.el('sales-dashboard-view').hidden,true);assert.equal(h.el('sales-page-title').textContent,'Finance');
 assert.equal(h.calls.length,1);
 h.el('nav-dashboard').events.click();h.el('sales-refresh').events.click();
 h.calls[1].resolve({data:{context:{role:'salesperson',display_name:'Example'},items:[]}});
 await tick();assert.doesNotMatch(h.el('sales-labels').innerHTML,/Old assignment/);
 assert.equal(h.el('sales-print-labels').disabled,true);
});
test('failed refresh clears stale records and can be retried',async()=>{
 const h=harness();
 h.calls[0].resolve({data:{context:{role:'salesperson',display_name:'Bryce'},items:[{tracking_id:'1',stock:'123'}]}});
 await tick();assert.match(h.el('vehicle-table').innerHTML,/123/);
 h.el('sales-refresh').events.click();h.calls[1].resolve({error:{message:'Access revoked'}});
 await tick();assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-refresh').disabled,false);
 h.el('sales-refresh').events.click();assert.equal(h.calls.length,3);
});
test('account replacement suppresses stale data and salesperson sees no admin selector',async()=>{
 const h=harness();h.window.PDC_AUTH_CONTEXT={role:'salesperson',userId:'B'};h.events['pdc-auth-ready']();
 h.calls[0].resolve({data:{context:{role:'administrator'},items:[{tracking_id:'private',stock:'999'}]}});
 h.calls[1].resolve({data:{context:{role:'salesperson',display_name:'Other'},items:[{tracking_id:'own',stock:'111'}]}});
 await tick();assert.doesNotMatch(h.el('vehicle-table').innerHTML,/999/);
 assert.match(h.el('vehicle-table').innerHTML,/111/);assert.equal(h.el('sales-accounts').hidden,true);
 assert.equal(h.el('salesperson-filter-label').hidden,true);
});
test('site switcher cannot navigate a salesperson and exposes both sites to admin',()=>{
 const listeners={},navigation=[],holder={hidden:false};
 const select={value:'pmb',disabled:false,closest:()=>holder,addEventListener:(n,fn)=>listeners[n]=fn};
 const window={PDC_AUTH_CONTEXT:{role:'salesperson'},location:{href:'https://btnew.github.io/pdc-control-board-staging/',assign:url=>navigation.push(String(url))},addEventListener:(n,fn)=>listeners[n]=fn};
 const document={getElementById:()=>select,body:{dataset:{pdcSite:'pmb'}}};
 vm.runInNewContext(fs.readFileSync('site-switcher.js','utf8'),{window,document,URL});
 assert.equal(holder.hidden,true);select.value='broome';listeners.change();assert.equal(navigation.length,0);
 window.PDC_AUTH_CONTEXT.role='administrator';listeners['pdc-auth-ready']();
 assert.equal(holder.hidden,false);select.value='broome';listeners.change();
 assert.equal(navigation[0],'https://btnew.github.io/pdc-control-board-staging/sales/');
});
test('sales entry has no operational loaders, local record cache or static customer payload',()=>{
 const html=fs.readFileSync('sales/index.html','utf8'),js=fs.readFileSync('sales/sales.js','utf8');
 assert.doesNotMatch(html,/src="(?:\.\.\/)?(?:app|email-board-data|workshop-planner|data-staging-empty)\.js/);
 assert.doesNotMatch(js,/localStorage|sessionStorage|\.from\(['"]vehicles|update_pdc_vehicle/);
 assert.match(html,/data-pdc-site="broome"/);assert.match(html,/id="pdc-site-switcher"/);
});
