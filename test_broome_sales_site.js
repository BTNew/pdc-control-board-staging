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
test('Navision sales parser preserves order identity, blank stock and quoted customer values',()=>{
 const parser=require('./sales/navision-orders.js');
 const rows=parser.parse('Report title\nOrder,COSI,Dealer,Salesperson,Batch,Customer Surname,Model Description\n000123,Yes,37047,BG,,"Example, Customer",HiLux\n000124,No,37047,CW,13002,Example,Prado');
 assert.equal(rows[0].order,'000123');assert.equal(rows[0].batch,'');assert.equal(rows[0].cosi,'Yes');assert.equal(rows[0].client,'Example, Customer');
 assert.equal(rows[1].batch,'13002');assert.throws(()=>parser.parse('Order,COSI,Dealer\n1,Yes,37047'),/Salesperson|salesperson/);
 assert.equal(parser.parse('Order,COSI,Dealer,Salesperson\n00123,Yes,037047,BG')[0].dealer_code,'37047');
 assert.equal(parser.parse('Order,COSI,Dealer,Salesperson\n00123,Yes,002345,BG')[0].dealer_code,'002345');
 assert.throws(()=>parser.parse('Order,COSI,Dealer,Salesperson\n1,Yes,37047,"BG'),/unclosed quote/);
});
test('order-only detail shows bookings safely and disappears when access changes on refresh',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{tracking_id:'order-id',canonical_vehicle_id:'canonical-test',order:'000123',stock:'',client:'Example',bay_bookings:[{stage:'Fitting',bay:'<unsafe>',status:'planned',scheduled_start_at:'2026-10-05T01:00:00Z'}]}]}});
 await tick();assert.match(h.el('vehicle-table').innerHTML,/Awaiting stock number/);assert.match(h.el('vehicle-table').innerHTML,/000123/);
 h.el('vehicle-table').events.click({target:{closest(selector){return selector==='[data-open]'?{dataset:{open:'order-id'}}:null;}}});
 assert.match(h.el('sales-detail-content').innerHTML,/Bay bookings/);assert.match(h.el('sales-detail-content').innerHTML,/&lt;unsafe&gt;/);
 assert.equal(h.el('sales-order-intake').hidden,true);h.el('sales-order-preview').events.click();assert.equal(h.calls.length,1);
 h.el('sales-refresh').events.click();h.calls[1].resolve({data:{context:{role:'salesperson'},items:[]}});await tick();
 assert.equal(h.el('sales-detail-content').innerHTML,'');assert.equal(h.el('sales-detail').closed,true);
});
test('administrator import requires a reviewed export and editing it invalidates approval',async()=>{
 const h=harness();h.window.BROOME_NAVISION_ORDERS=require('./sales/navision-orders.js');
 h.calls[0].resolve({data:{context:{role:'administrator'},items:[]}});await tick();
 h.el('sales-order-text').value='Order,COSI,Dealer,Salesperson\n000123,Yes,37047,BG';h.el('sales-order-preview').events.click();
 assert.equal(h.calls[1].name,'import_broome_sales_orders');assert.equal(h.calls[1].args.p_apply,false);
 h.calls[1].resolve({data:{accepted:1,without_stock:1,skipped_unsold:0}});await tick();assert.equal(h.el('sales-order-apply').disabled,false);
 h.el('sales-order-text').events.input();assert.equal(h.el('sales-order-apply').disabled,true);
 h.el('sales-order-apply').events.click();await tick();assert.equal(h.calls.length,2);
});
test('an edited export cannot regain approval from an earlier review response',async()=>{
 const h=harness();h.window.BROOME_NAVISION_ORDERS=require('./sales/navision-orders.js');
 h.calls[0].resolve({data:{context:{role:'administrator'},items:[]}});await tick();
 h.el('sales-order-text').value='Order,COSI,Dealer,Salesperson\n000123,Yes,37047,BG';h.el('sales-order-preview').events.click();
 h.el('sales-order-text').value='Order,COSI,Dealer,Salesperson\n000999,Yes,37047,CW';h.el('sales-order-text').events.input();
 h.calls[1].resolve({data:{accepted:1,without_stock:1,skipped_unsold:0}});await tick();
 assert.equal(h.el('sales-order-apply').disabled,true);assert.equal(h.el('sales-order-message').textContent,'');
});
const orderingRow={tracking_id:'own-order',stock:'13001',order:'000123',tint:false,build_po:false,build_complete:false,tray_ordered:false,tray_complete:false,ordering_version:0,jita:true};
test('five sales ordering checkboxes save through only the isolated RPC and JITA stays read-only',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 assert.equal((h.el('vehicle-table').innerHTML.match(/data-ordering-flag=/g)||[]).length,5);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/data-ordering-flag="jita"/);
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tint'},checked:true}});
 assert.equal(h.calls[1].name,'set_broome_sales_ordering_flag');
 assert.deepEqual(JSON.parse(JSON.stringify(h.calls[1].args)),{p_tracking_id:'own-order',p_flag:'tint',p_checked:true,p_expected_version:0});
 assert.match(h.el('vehicle-table').innerHTML,/data-ordering-flag="tint"[^>]*checked[^>]*disabled/);
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'build_po'},checked:true}});assert.equal(h.calls.length,2);
 h.calls[1].resolve({data:{...orderingRow,tint:true,ordering_version:1}});await tick();
 assert.match(h.el('vehicle-table').innerHTML,/data-ordering-flag="tint"[^>]*checked/);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/data-ordering-flag="tint"[^>]*disabled/);
 assert.match(h.el('sales-checklist-status').textContent,/Tint saved/);
});
test('failed checkbox saves restore the last confirmed value and keep the error visible',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tray_ordered'},checked:true}});
 h.calls[1].resolve({error:{message:'Checklist changed elsewhere. Refresh and try again.'}});await tick();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/data-ordering-flag="tray_ordered"[^>]*checked/);
 assert.match(h.el('sales-error').textContent,/changed elsewhere/);assert.match(h.el('sales-checklist-status').textContent,/not saved/);
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'other-order',orderingFlag:'tint'},checked:true}});
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'jita'},checked:false}});
 assert.equal(h.calls.length,2);
});
test('a stale background snapshot cannot undo a newer saved tick',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 h.el('sales-refresh').events.click();
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'build_complete'},checked:true}});
 h.calls[2].resolve({data:{...orderingRow,build_complete:true,ordering_version:1}});await tick();
 h.calls[1].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 assert.match(h.el('vehicle-table').innerHTML,/data-ordering-flag="build_complete"[^>]*checked/);
});
test('sign-out suppresses a delayed checkbox response and clears its pending status',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tray_complete'},checked:true}});
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[1].resolve({data:{...orderingRow,tray_complete:true,ordering_version:1}});await tick();
 assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-checklist-status').textContent,'');
});

test('PMB distinguishes scheduled bay from actual work and preserves multiple active stages',()=>{
 const r={canonical_vehicle_id:'v',pmb_location:'PMB',bay_bookings:[{booking_id:'b',status:'planned',stage:'Fitting',bay:'Bay 2',scheduled_start_at:'2026-10-05T01:00:00Z'}]};
 assert.equal(sales.pmbSummary(r).status,'Booked · Fitting / Bay 2');
 r.bay_bookings.push({booking_id:'c',status:'started',stage:'Electrical',bay:'Bay 1'},{booking_id:'d',status:'stoppage',stage:'Fitting',bay:'Bay 3'});
 assert.ok(sales.pmbSummary(r).status.includes('Work started · Electrical / Bay 1; Work stopped'));
 assert.equal(sales.pmbSummary({...r,canonical_vehicle_id:null}).status,'Not linked to PMB');
 assert.equal(sales.pmbSummary({...r,bay_bookings:[],workshop_status:'completed',pmb_stoppage_started_at:'yesterday',pmb_stoppage_cleared_at:'today'}).status,'Completed');
});
test('parts source authority and unknown receipt stay distinct',()=>{
 assert.equal(sales.partsStatus(null),'Not recorded');
 assert.equal(sales.partsStatus({required:null,received:null}),'Not recorded');
 assert.equal(sales.partsStatus({required:false}),'No parts required');
 assert.equal(sales.partsStatus({required:true,ordered:true}),'Parts ordered · awaiting receipt');
 assert.equal(sales.partsStatus({status:'Parts outstanding — see job cards',received:true}),'Parts outstanding — see job cards');
});
test('stock detail shows read-only current PMB, parts and planned/actual progress; escapes source text',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{tracking_id:'v',canonical_vehicle_id:'c',stock:'123',
 pmb_location:'PMB',parts:{status:'Parts outstanding',eta:'2026-10-07',stoppage:true,stoppage_reason:'<script>test</script>',jobs:[{job_number:'001',status:'PO recorded'}]},
 bay_bookings:[{status:'started',stage:'Fitting',bay:'Bay 2',actual_start_at:'2026-10-01T01:00:00Z',progress:{completed_lines:2,total_lines:4,percent:50}}]}]}});await tick();
 h.el('vehicle-table').events.click({target:{closest:sel=>sel==='[data-open]'?{dataset:{open:'v'}}:null}});
 const html=h.el('sales-detail-content').innerHTML;
 for(const text of ['Work started','Bay 2','Parts outstanding','2026-10-07','PO recorded','2 of 4 items complete','50%','read-only'])assert.ok(html.includes(text),text);
 assert.ok(html.indexOf('PMB status')<html.indexOf('Vehicle and delivery details'));
 assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>/);
 assert.doesNotMatch(html,/type="checkbox"/);
});
