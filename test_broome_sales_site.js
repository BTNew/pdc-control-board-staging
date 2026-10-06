const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const sales=require('./sales/sales.js');
test('tracker keeps yard hold and consignment categories and unknown flags distinct',()=>{
 assert.equal(sales.category({cosi:'Yes',salesperson_code:'BG',stock:'130',location_status:'YH',toyota_status:'In Transit'}),'yardhold');
 assert.equal(sales.category({cosi:'Yes',salesperson_code:'BG',stock:'130',toyota_status:'Vehicle Out on Consignment'}),'released');
 assert.equal(sales.category({cosi:'Yes',salesperson_code:'BG',stock:'',toyota_status:'Yard Hold'}),'unconfirmed');
 for(const v of [null,undefined,'', 'Unknown'])assert.equal(sales.flag(v),'unknown');
 assert.equal(sales.flag(false),'no');assert.equal(sales.flag(true),'yes');
});
test('search and sorting retain missing-last order and source records',()=>{
 const records=[{cosi:'Yes',salesperson_code:'BG',stock:'100',client:'Amy'},{cosi:'Yes',salesperson_code:'BG',stock:'20',client:'Bryce'},{cosi:'Yes',salesperson_code:'BG',stock:'',client:'Bryce'}];
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
const teamContext={role:'salesperson',display_name:'Bryce fixture',salesperson_code:'BG',can_view_all_salespeople:true};
const teamRows=[{cosi:true,salesperson_code:'BG',tracking_id:'own-team',stock:'QA-BG',client:'Own team fixture'},
 {cosi:true,salesperson_code:'AW',tracking_id:'other-team',stock:'QA-AW',client:'Other team fixture'}];
async function openTeam(h){
 h.calls[0].resolve({data:{context:teamContext,items:[teamRows[0]]}});await tick();
 assert.equal(h.calls[1].name,'get_broome_sales_board_snapshot');
 h.calls[1].resolve({data:{context:teamContext,items:teamRows}});await tick();
}
test('approved team viewer gets a salesperson dropdown, starts on own vehicles and switches to others or all',async()=>{
 const h=harness();await openTeam(h);
 assert.equal(h.el('salesperson-filter-label').hidden,false);assert.equal(h.el('salesperson-filter').value,'BG');
 assert.match(h.el('vehicle-table').innerHTML,/Own team fixture/);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Other team fixture/);
 h.el('salesperson-filter').events.change({target:{value:'AW'}});
 assert.match(h.el('vehicle-table').innerHTML,/Other team fixture/);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Own team fixture/);
 assert.match(h.el('vehicle-table').innerHTML,/View only/);assert.match(h.el('vehicle-table').innerHTML,/data-ordering-id="other-team"[^>]+disabled/);
 h.el('salesperson-filter').events.change({target:{value:''}});
 assert.match(h.el('vehicle-table').innerHTML,/Own team fixture/);assert.match(h.el('vehicle-table').innerHTML,/Other team fixture/);
});
test('team viewer cannot trigger another salesperson ordering, visibility or dispatch writes through forged controls',async()=>{
 const h=harness();await openTeam(h);h.el('salesperson-filter').events.change({target:{value:'AW'}});
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'other-team',orderingFlag:'tint'},value:'completed'}});
 h.el('vehicle-table').events.change({target:{dataset:{emailId:'other-team'},value:'hide'}});
 h.el('vehicle-table').events.change({target:{dataset:{emailId:'other-team'},value:'autocare-dispatch'}});
 await tick();assert.equal(h.calls.length,2);assert.match(h.el('sales-dispatch-status').textContent,/view only/);
 h.el('vehicle-table').events.change({target:{dataset:{select:'other-team'},checked:true}});
 assert.equal(h.el('sales-dispatch-selected').disabled,true);
});
test('revoking team viewing clears other-owner rows, closes details and removes the dropdown',async()=>{
 const h=harness();await openTeam(h);h.el('salesperson-filter').events.change({target:{value:'AW'}});
 h.el('vehicle-table').events.change({target:{dataset:{emailId:'other-team'},value:'details'}});
 assert.match(h.el('sales-detail-content').innerHTML,/Other team fixture/);
 h.el('sales-refresh').events.click();assert.equal(h.calls[2].name,'get_broome_sales_board_snapshot');h.calls[2].resolve({data:{context:{...teamContext,can_view_all_salespeople:false},items:[teamRows[0]]}});await tick();
 assert.equal(h.calls.length,3);assert.equal(h.el('salesperson-filter-label').hidden,true);assert.equal(h.el('salesperson-filter').value,'');
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Other team fixture/);assert.equal(h.el('sales-detail-content').innerHTML,'');
});
test('late team-board response cannot refill a signed-out account',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:teamContext,items:[teamRows[0]]}});await tick();
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[1].resolve({data:{context:teamContext,items:teamRows}});await tick();
 assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('salesperson-filter-label').hidden,true);
});
test('Andy administrator view retains all-salesperson dropdown without the extra team-view request',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'administrator',display_name:'Andy fixture',can_view_all_salespeople:true},items:teamRows}});await tick();
 assert.equal(h.calls.length,1);assert.equal(h.el('salesperson-filter-label').hidden,false);assert.equal(h.el('salesperson-filter').value,'');
 assert.match(h.el('vehicle-table').innerHTML,/Own team fixture/);assert.match(h.el('vehicle-table').innerHTML,/Other team fixture/);
});
test('sign-out clears data and a delayed read cannot refill the previous account',async()=>{
 const h=harness();assert.equal(h.calls.length,1);
 h.el('sales-detail-content').innerHTML='Private customer';
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'old',stock:'123',client:'Private customer'}]}});
 await tick();
 assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-detail-content').innerHTML,'');
 assert.equal(h.el('sales-refresh').disabled,false);
});
test('month and Toyota status filters ignore the removed legacy JITA preference',()=>{
 const rows=[{cosi:'Yes',salesperson_code:'BG',stock:'1',production_month:'06/26',toyota_status:'Yard Hold',jita:true},
 {cosi:'Yes',salesperson_code:'BG',stock:'2',production_month:'06/26',toyota_status:'Yard Hold',jita:null},
 {cosi:'Yes',salesperson_code:'BG',stock:'3',production_month:'07/26',toyota_status:'In Transit',jita:true}];
 assert.deepEqual(sales.selectRows(rows,{category:'all',month:'06/26',status:'Yard Hold',jita:'yes',sort:'stock',direction:1}).map(r=>r.stock),['1','2']);
 assert.deepEqual(sales.selectRows(rows,{category:'all',jita:'unknown',sort:'stock',direction:1}).map(r=>r.stock),['1','2','3']);
});
test('labels and pipeline retain authorised identities and clear on access revocation',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson',display_name:'Example'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'own-id',stock:'13001',order:'2026001',client:'Private customer',toyota_status:'Yard Hold'}]}});
 await tick();assert.equal(h.el('sales-pipeline').innerHTML,'');h.el('nav-pipeline').events.click();assert.match(h.el('sales-pipeline').innerHTML,/Private customer/);h.el('nav-dashboard').events.click();
 h.el('vehicle-table').events.change({target:{dataset:{select:'own-id'},checked:true}});
 h.el('sales-view-labels').events.click();assert.match(h.el('sales-labels').innerHTML,/Private customer/);
 assert.equal(h.el('sales-print-labels').disabled,false);
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 assert.equal(h.el('sales-pipeline').innerHTML,'');assert.equal(h.el('sales-labels').innerHTML,'');
 assert.equal(h.el('sales-print-labels').disabled,true);
});
test('Finance opens its placeholder without issuing a finance request; stale selected labels are removed on refresh',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson',display_name:'Example'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'old-id',stock:'13001',client:'Old assignment'}]}});
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
 h.calls[0].resolve({data:{context:{role:'salesperson',display_name:'Bryce'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'1',stock:'123'}]}});
 await tick();assert.match(h.el('vehicle-table').innerHTML,/123/);
 h.el('sales-refresh').events.click();h.calls[1].resolve({error:{message:'Access revoked'}});
 await tick();assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-refresh').disabled,false);
 h.el('sales-refresh').events.click();assert.equal(h.calls.length,3);
});
test('account replacement suppresses stale data and salesperson sees no admin selector',async()=>{
 const h=harness();h.window.PDC_AUTH_CONTEXT={role:'salesperson',userId:'B'};h.events['pdc-auth-ready']();
 h.calls[0].resolve({data:{context:{role:'administrator'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'private',stock:'999'}]}});
 h.calls[1].resolve({data:{context:{role:'salesperson',display_name:'Other'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'own',stock:'111'}]}});
 await tick();assert.doesNotMatch(h.el('vehicle-table').innerHTML,/999/);
 assert.match(h.el('vehicle-table').innerHTML,/111/);
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
 assert.doesNotMatch(js,/sessionStorage|\.from\(['"]vehicles|update_pdc_vehicle/);
 // Only the selected local printer name may persist. Vehicle/customer records
 // remain in the authenticated snapshot and are never cached in browser storage.
 const storageCalls=[...js.matchAll(/root\.localStorage\?\.([a-zA-Z]+)\(([^)]*)\)/g)];
 assert.equal((js.match(/localStorage/g)||[]).length,3);assert.equal(storageCalls.length,3);
 assert.deepEqual(storageCalls.map(match=>[match[1],match[2]]),[
  ['getItem',"'broome-sales-qz-printer-v1'"],['setItem',"'broome-sales-qz-printer-v1',state.printerName"],['removeItem',"'broome-sales-qz-printer-v1'"]]);
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
test('sales has no upload or account editor for either role',async()=>{
 for(const role of ['administrator','salesperson']){const h=harness();h.calls[0].resolve({data:{context:{role},items:[]}});await tick();assert.equal(h.calls.length,1);assert.equal(h.el('sales-order-preview').events.click,undefined);assert.equal(h.el('sales-access-form').events.submit,undefined);}
 const page=fs.readFileSync(require.resolve('./sales/index.html'),'utf8');assert.doesNotMatch(page,/sales-order-intake|sales-accounts|sales-open-order-intake/);
 const code=fs.readFileSync(require.resolve('./sales/sales.js'),'utf8');assert.doesNotMatch(code,/import_broome_sales_orders|assign_broome_sales_access/);
});
test('order-only detail shows bookings safely and disappears when access changes on refresh',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'order-id',canonical_vehicle_id:'canonical-test',order:'000123',stock:'',client:'Example',bay_bookings:[{stage:'Fitting',bay:'<unsafe>',status:'planned',scheduled_start_at:'2026-10-05T01:00:00Z'}]}]}});
 await tick();assert.match(h.el('vehicle-table').innerHTML,/Awaiting stock number/);assert.match(h.el('vehicle-table').innerHTML,/000123/);
 h.el('vehicle-table').events.click({target:{closest(selector){return selector==='[data-open]'?{dataset:{open:'order-id'}}:null;}}});
 assert.match(h.el('sales-detail-content').innerHTML,/Bay bookings/);assert.match(h.el('sales-detail-content').innerHTML,/&lt;unsafe&gt;/);
 assert.equal(h.calls.length,1);
 h.el('sales-refresh').events.click();h.calls[1].resolve({data:{context:{role:'salesperson'},items:[]}});await tick();
 assert.equal(h.el('sales-detail-content').innerHTML,'');assert.equal(h.el('sales-detail').closed,true);
});
const orderingRow={cosi:'Yes',salesperson_code:'BG',tracking_id:'own-order',stock:'13001',order:'000123',tint:false,tint_complete:false,tint_not_required:false,build_po:false,build_complete:false,build_not_required:false,tray_ordered:false,tray_complete:false,tray_not_required:false,ordering_version:0,jita:true};
const orderingItems=[['tint','tint_complete','tint_not_required','tint'],['build_po','build_complete','build_not_required','build'],['tray_ordered','tray_complete','tray_not_required','tray']];
test('three sales ordering tick boxes save through only the isolated RPC and JITA is absent',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 assert.equal((h.el('vehicle-table').innerHTML.match(/data-ordering-flag=/g)||[]).length,3);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/data-ordering-flag="jita"/);
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tint'},value:'orders_raised'}});
 assert.equal(h.calls[1].name,'set_broome_sales_ordering_status');
 assert.deepEqual(JSON.parse(JSON.stringify(h.calls[1].args)),{p_tracking_id:'own-order',p_item:'tint',p_status:'orders_raised',p_expected_version:0});
 assert.match(h.el('vehicle-table').innerHTML,/ordering-status orders_raised[^>]*data-ordering-flag="tint"[^>]*disabled/);
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'build_po'},value:'completed'}});assert.equal(h.calls.length,2);
 h.calls[1].resolve({data:{...orderingRow,tint:true,ordering_version:1}});await tick();
 assert.match(h.el('vehicle-table').innerHTML,/ordering-status orders_raised[^>]*data-ordering-flag="tint"/);
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/data-ordering-flag="tint"[^>]*disabled/);
 assert.match(h.el('sales-checklist-status').textContent,/TINT saved/);
});
test('failed status saves restore the last confirmed value and keep the error visible',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tray_ordered'},value:'orders_raised'}});
 h.calls[1].resolve({error:{message:'Checklist changed elsewhere. Refresh and try again.'}});await tick();
 assert.match(h.el('vehicle-table').innerHTML,/ordering-status not_decided[^>]*data-ordering-flag="tray_ordered"/);
 assert.match(h.el('sales-error').textContent,/changed elsewhere/);assert.match(h.el('sales-checklist-status').textContent,/could not be confirmed/);
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'other-order',orderingFlag:'tint'},value:'orders_raised'}});
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'jita'},value:'not_needed'}});
 assert.equal(h.calls.length,2);
});
test('a stale background snapshot cannot undo newer completed or explicit not-required statuses',async()=>{
 for(const [status,fields] of [['completed',{build_complete:true}],['not_needed',{build_not_required:true}]]){
  const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
  h.el('sales-refresh').events.click();
  h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'build_po'},value:status}});
  h.calls[2].resolve({data:{...orderingRow,...fields,ordering_version:1}});await tick();
  h.calls[1].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
  assert.match(h.el('vehicle-table').innerHTML,new RegExp('ordering-status '+status+'[^>]*data-ordering-flag="build_po"'));
 }
});
test('sign-out suppresses a delayed status response and clears its pending status',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tray_ordered'},value:'orders_raised'}});
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
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'v',canonical_vehicle_id:'c',stock:'123',
 pmb_location:'PMB',parts:{status:'Parts outstanding',eta:'2026-10-07',stoppage:true,stoppage_reason:'<script>test</script>',jobs:[{job_number:'001',status:'PO recorded'}]},
 bay_bookings:[{status:'started',stage:'Fitting',bay:'Bay 2',actual_start_at:'2026-10-01T01:00:00Z',progress:{completed_lines:2,total_lines:4,percent:50}}]}]}});await tick();
 h.el('vehicle-table').events.click({target:{closest:sel=>sel==='[data-open]'?{dataset:{open:'v'}}:null}});
 const html=h.el('sales-detail-content').innerHTML;
 for(const text of ['Work started','Bay 2','Parts outstanding','2026-10-07','PO recorded','2 of 4 items complete','50%','read-only'])assert.ok(html.includes(text),text);
 assert.ok(html.indexOf('PMB status')<html.indexOf('Vehicle and delivery details'));
 assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>/);
 assert.doesNotMatch(html,/type="checkbox"/);
});

test('sales print button uses scoped Zebra rows and clears delayed status on sign-out',async()=>{
 const h=harness(),printed=[];let finish;
 h.window.BROOME_ZEBRA_LABELS={...h.window.BROOME_ZEBRA_LABELS,print:(rows,authorised)=>{printed.push({rows,authorised});return new Promise(resolve=>finish=resolve);}};
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{cosi:'Yes',salesperson_code:'BG',tracking_id:'own',stock:'001',client:'Example customer'}]}});await tick();
 h.el('vehicle-table').events.change({target:{dataset:{select:'own'},checked:true}});h.el('sales-view-labels').events.click();
 h.el('sales-print-labels').events.click();assert.equal(printed.length,1);assert.equal(printed[0].rows[0].stock,'001');assert.equal(printed[0].authorised(),true);assert.equal(h.el('sales-print-labels').disabled,true);
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();assert.equal(printed[0].authorised(),false);finish('BT-Zebra-EricComp');await tick();
 assert.equal(h.el('sales-label-status').textContent,'');assert.equal(h.el('sales-labels').innerHTML,'');
});

test('TINT BUILD and TRAY preserve existing progress and distinguish undecided from explicit not required',()=>{
 for(const [key,complete,notRequired] of orderingItems){
 assert.equal(sales.orderingState({},key),'not_decided');assert.equal(sales.orderingState({[key]:false,[complete]:false},key),'not_decided');
 assert.equal(sales.orderingState({[notRequired]:true},key),'not_needed');assert.equal(sales.orderingState({[notRequired]:'true'},key),'not_decided');
 assert.equal(sales.orderingState({[key]:true},key),'orders_raised');assert.equal(sales.orderingState({[key]:true,[notRequired]:true},key),'orders_raised');
 assert.equal(sales.orderingState({[complete]:true},key),'completed');assert.equal(sales.orderingState({[key]:true,[complete]:true,[notRequired]:true},key),'completed');
 const html=sales.orderingControl({tracking_id:'example',order:'EXAMPLE',[complete]:true},key);assert.match(html,/ordering-status completed/);assert.match(html,/role="checkbox"/);assert.match(html,/aria-checked="true"/);assert.doesNotMatch(html,/<select/);
 }
});
test('all four checkbox states have distinct icons and accessible current and next labels',()=>{
 const states=[['not_decided',{},'',/not decided/i,/not required/i,'false'],['not_needed',{tint_not_required:true},'/',/not required/i,/orders raised/i,'mixed'],['orders_raised',{tint:true},'−',/orders raised/i,/completed/i,'mixed'],['completed',{tint_complete:true},'✓',/completed/i,/not decided/i,'true']];
 for(const [status,fields,icon,current,next,checked] of states){
  const html=sales.orderingControl({...orderingRow,...fields},'tint'),title=html.match(/title="([^"]*)"/)?.[1],aria=html.match(/aria-label="([^"]*)"/)?.[1];
  assert.match(html,new RegExp('ordering-status '+status));assert.match(html,new RegExp('data-ordering-status="'+status+'"'));assert.match(html,new RegExp('aria-checked="'+checked+'"'));
  assert.ok(html.includes('<span aria-hidden="true">'+icon+'</span>'));assert.match(title,current);assert.match(title,next);assert.match(aria,current);assert.match(aria,next);assert.match(aria,/TINT.*13001/);
  for(const guard of [{identity_conflict:true},{sales_hidden:true}])assert.match(sales.orderingControl({...orderingRow,...fields,...guard},'tint'),/ disabled /);
 }
});
test('sales status selectors reject arbitrary states and hidden completion fields',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 for(const [key,value] of [['tint','invented'],['build_complete','completed'],['tray_complete','completed'],['tint_not_required','not_needed'],['build_not_required','not_needed'],['tray_not_required','not_needed']])h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:key},value}});
 assert.equal(h.calls.length,1);
});
test('ordering status sort distinguishes undecided, not required, raised and completed for each item',()=>{
 for(const [key,complete,notRequired] of orderingItems){
  const rows=[{...orderingRow,stock:'4',[key]:true,[complete]:true},{...orderingRow,stock:'2',[notRequired]:true},{...orderingRow,stock:'1'},{...orderingRow,stock:'3',[key]:true}],before=JSON.stringify(rows);
  assert.deepEqual(sales.selectRows(rows,{category:'all',sort:key,direction:1}).map(r=>r.stock),['1','2','3','4']);
  assert.deepEqual(sales.selectRows(rows,{category:'all',sort:key,direction:-1}).map(r=>r.stock),['4','3','2','1']);assert.equal(JSON.stringify(rows),before);
 }
});

test('sales tick boxes cycle all four states on desktop and mobile without PDC writes',async()=>{
 const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
 assert.doesNotMatch(h.el('vehicle-table').innerHTML,/JITA|class="sales-flag/);
 let row={...orderingRow};
 for(const [index,current,next] of [[1,'not_decided','not_needed'],[2,'not_needed','orders_raised'],[3,'orders_raised','completed'],[4,'completed','not_decided']]){
  assert.equal(sales.nextOrderingState(current),next);
  const control={dataset:{orderingId:'own-order',orderingFlag:'tint',orderingStatus:current}};
  h.el(index===2?'sales-mobile-vehicles':'vehicle-table').events.click({target:{closest:()=>control}});
  assert.deepEqual(JSON.parse(JSON.stringify(h.calls[index].args)),{p_tracking_id:'own-order',p_item:'tint',p_status:next,p_expected_version:index-1});assert.equal(h.calls[index].name,'set_broome_sales_ordering_status');
  row={...row,tint:['orders_raised','completed'].includes(next),tint_complete:next==='completed',tint_not_required:next==='not_needed',ordering_version:index};h.calls[index].resolve({data:row});await tick();
  for(const surface of ['vehicle-table','sales-mobile-vehicles'])assert.match(h.el(surface).innerHTML,new RegExp('ordering-status '+next+'[^>]*data-ordering-flag="tint"'));
 }
});

test('each explicit not-required flag saves independently and preserves the other confirmed items',async()=>{
 const h=harness();let row={...orderingRow,build_po:true,tray_ordered:true,tray_complete:true};h.calls[0].resolve({data:{context:{role:'salesperson'},items:[row]}});await tick();
 for(const [index,[key,complete,notRequired,item]] of orderingItems.entries()){
  h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:key},value:'not_needed'}});
  const call=h.calls[index+1];assert.equal(call.name,'set_broome_sales_ordering_status');assert.deepEqual(JSON.parse(JSON.stringify(call.args)),{p_tracking_id:'own-order',p_item:item,p_status:'not_needed',p_expected_version:index});
  row={...row,[key]:false,[complete]:false,[notRequired]:true,ordering_version:index+1};call.resolve({data:row});await tick();
  for(const [other] of orderingItems)assert.match(h.el('vehicle-table').innerHTML,new RegExp('ordering-status '+sales.orderingState(row,other)+'[^>]*data-ordering-flag="'+other+'"'));
 }
 assert.equal(h.calls.length,4);assert.ok(h.calls.slice(1).every(call=>call.name==='set_broome_sales_ordering_status'));
});

test('a missing or non-boolean explicit flag cannot be accepted as a successful status save',async()=>{
 for(const [, ,notRequired] of orderingItems)for(const invalid of [undefined,null,'true']){
  const h=harness();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[{...orderingRow}]}});await tick();
  h.el('vehicle-table').events.change({target:{dataset:{orderingId:'own-order',orderingFlag:'tint'},value:'not_needed'}});
  const response={...orderingRow,tint_not_required:true,ordering_version:1};if(invalid===undefined)delete response[notRequired];else response[notRequired]=invalid;
  h.calls[1].resolve({data:response});await tick();assert.match(h.el('vehicle-table').innerHTML,/ordering-status not_decided[^>]*data-ordering-flag="tint"/);assert.match(h.el('sales-checklist-status').textContent,/could not be confirmed/);assert.doesNotMatch(h.el('sales-checklist-status').textContent,/saved/);
 }
});

test('new not-required requests retain hidden, source, conflict, salesperson and disabled guards',async()=>{
 const h=harness(),other={...orderingRow,tracking_id:'other-order',salesperson_code:'AW',stock:'13002'};
 h.calls[0].resolve({data:{context:{role:'administrator'},items:[{...orderingRow},other,{...orderingRow,tracking_id:'hidden',sales_hidden:true},{...orderingRow,tracking_id:'old-source',source_current:false},{...orderingRow,tracking_id:'conflict',identity_conflict:true}]}});await tick();
 h.el('salesperson-filter').events.change({target:{value:'AW'}});
 for(const id of ['own-order','hidden','old-source','conflict'])h.el('vehicle-table').events.change({target:{dataset:{orderingId:id,orderingFlag:'tint'},value:'not_needed'}});
 const disabled={disabled:true,dataset:{orderingId:'other-order',orderingFlag:'tint',orderingStatus:'not_decided'}};h.el('vehicle-table').events.click({target:{closest:()=>disabled}});assert.equal(h.calls.length,1);
 h.el('salesperson-filter').events.change({target:{value:''}});h.el('vehicle-table').events.change({target:{dataset:{orderingId:'conflict',orderingFlag:'tint'},value:'not_needed'}});assert.equal(h.calls.length,1);
 h.el('salesperson-filter').events.change({target:{value:'AW'}});h.el('vehicle-table').events.change({target:{dataset:{orderingId:'other-order',orderingFlag:'tint'},value:'not_needed'}});assert.equal(h.calls.length,2);
 h.calls[1].resolve({data:{...other,tint_not_required:true,ordering_version:1}});await tick();assert.match(h.el('vehicle-table').innerHTML,/ordering-status not_needed/);assert.doesNotMatch(h.el('vehicle-table').innerHTML,/13001/);
});
