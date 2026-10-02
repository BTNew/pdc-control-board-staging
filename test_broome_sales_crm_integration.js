const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const sales=require('./sales/sales.js');
const orderA='cccccccc-cccc-4ccc-8ccc-cccccccccccc',leadA='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',viewA='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const sold={cosi:'Yes',tracking_id:orderA,salesperson_code:'BG',stock:'13001',order:'000123',client:'Own customer',vehicle:'HiLux',toyota_status:'Delivered - At Dealer',dealer_eta:'2026-10-07',ordering_version:0};
const ctx=role=>({role,display_name:'Example',salesperson_code:'BG',salesperson_id:'self',can_edit_finance:false});
const workspace=role=>({context:ctx(role),leads:[{id:leadA,version:1,customer_name:'Lead without stock',salesperson_code:'CW',stage:'enquiry'}],salespeople:[{code:'BG',name:'Bryce'},{code:'CW',name:'Other salesperson'}],order_refs:[sold],contacts:[],activities:[],tasks:[],delivery:[],finance:[],views:[],timeline:[],alerts:[],history:[]});
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function harness(role='administrator') {
 const elements=new Map(),events={},listeners={},calls=[],crmCalls={init:[],setWorkspace:[],clear:0,syncScope:[]};
 function el(id){
  if(!elements.has(id)){
   let markup='';const node={textContent:'',hidden:false,disabled:false,value:'',open:false,dataset:{},writes:0,events:{},
    classList:{add(){},toggle(){}},setAttribute(){},removeAttribute(){},focus(){},reset(){},scrollIntoView(){},
    addEventListener(name,fn){this.events[name]=fn;},close(){this.open=false;this.events.close?.();},showModal(){this.open=true;}};
   Object.defineProperty(node,'innerHTML',{get(){return markup;},set(value){markup=value;this.writes++;}});elements.set(id,node);
  }
  return elements.get(id);
 }
 const nav=['myday','dashboard','pipeline','alerts','finance','leads','labels','history'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 let crmOptions,crmScope='';
 const window={document:{hidden:false,activeElement:null,getElementById:el,querySelectorAll:()=>nav,querySelector(){return null;},addEventListener(){}},
  PDC_AUTH_CONTEXT:{role,userId:'user-A'},BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),
  BROOME_SALES_CRM:{init(options){crmOptions=options;crmCalls.init.push(options);},setWorkspace(data){crmCalls.setWorkspace.push(data);},clear(){crmCalls.clear++;el('sales-crm-detail').innerHTML='';},
   syncScope(){const scope=crmOptions?.getSalesperson();crmCalls.syncScope.push(scope);if(scope!==crmScope){crmScope=scope;el('sales-crm-detail').innerHTML='';}},render(){},detailHtml(){return '';},bindDetail(){}},
  PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(name,fn){(listeners[name] ||= []).push(fn);events[name]=(...args)=>listeners[name].forEach(handler=>handler(...args));},setInterval(){}};
 vm.runInNewContext(fs.readFileSync('sales/leads.js','utf8'),{window,module:undefined,Date,Set,console});
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,module:undefined,Date,Set,Map,console});
 return{window,events,calls,el,crmCalls,getCrmOptions:()=>crmOptions};
}
async function initial(h,role='administrator',rows=[sold],work=workspace(role)){
 assert.equal(h.calls[0].name,'get_broome_sales_snapshot');
 h.calls[0].resolve({data:{context:ctx(role),items:rows,navision_updated_at:'2026-10-02T01:00:00Z',checked_at:'2026-10-02T01:00:00Z'}});await tick();
 assert.equal(h.calls[1].name,'get_broome_sales_workspace');h.calls[1].resolve({data:work});await tick();
}
function change(h,id,value){h.el(id).value=value;h.el(id).events.change({target:{value}});}
test('quick views use authoritative finance status fields, real dates and current incomplete tasks',()=>{
 assert.equal(sales.quickMatch({...sold,crm_finance:{approval_status:'pending'}},'waiting_finance','2026-10-02'),true);
 assert.equal(sales.quickMatch({...sold,crm_finance:{documents_status:'requested'}},'waiting_finance','2026-10-02'),true);
 assert.equal(sales.quickMatch({...sold,crm_finance:{settlement_status:'pending'}},'waiting_finance','2026-10-02'),true);
 assert.equal(sales.quickMatch({...sold,crm_finance:{approval_status:'approved',documents_status:'complete',settlement_status:'settled'}},'waiting_finance','2026-10-02'),false);
 assert.equal(sales.quickMatch({...sold,crm_finance:{approval_status:'declined'}},'needs_attention','2026-10-02'),true);
 assert.equal(sales.quickMatch({...sold,crm_tasks:[{completed:false,due_date:null}]},'needs_attention','2026-10-02'),false);
 assert.equal(sales.quickMatch({...sold,crm_tasks:[{completed:true,due_date:'2026-10-01'}]},'needs_attention','2026-10-02'),false);
 assert.equal(sales.quickMatch({...sold,crm_tasks:[{completed:false,due_date:'2026-10-02'}]},'needs_attention','2026-10-02'),true);
 assert.equal(sales.quickMatch({...sold,dealer_eta:null},'due_week','2026-10-02'),false);
 assert.equal(sales.quickMatch({...sold,dealer_eta:'2026-10-01'},'due_week','2026-10-02'),false);
 assert.equal(sales.quickMatch({...sold,dealer_eta:'2026-10-10'},'due_week','2026-10-02'),false);
 assert.equal(sales.quickMatch({...sold,dealer_eta:'2026-10-09'},'due_week','2026-10-02'),true);
 assert.equal(sales.quickMatch({...sold,dealer_eta:'2026-10-07',crm_delivery:{promised_delivery_date:'2026-10-20'}},'due_week','2026-10-02'),false);
});
test('loaded sales modules receive the separate workspace only after the scoped vehicle snapshot',async()=>{
 const h=harness();assert.equal(h.crmCalls.init.length,1);assert.equal(h.calls.length,1);assert.equal(h.crmCalls.setWorkspace.length,0);
 await initial(h);assert.equal(h.crmCalls.setWorkspace.length,1);assert.match(h.el('vehicle-table').innerHTML,/Own customer/);
 h.el('nav-leads').events.click();assert.match(h.el('sales-leads-list').innerHTML,/Lead without stock/);
 assert.equal(h.calls.length,2);assert.equal(h.el('sales-leads-form').hidden,true);
});
test('administrators can select an active salesperson with leads and no COSI orders, including after polling',async()=>{
 const h=harness();await initial(h);assert.match(h.el('salesperson-filter').innerHTML,/value="CW"/);
 change(h,'salesperson-filter','CW');assert.doesNotMatch(h.el('vehicle-table').innerHTML,/Own customer/);
 h.el('nav-leads').events.click();assert.match(h.el('sales-leads-list').innerHTML,/Lead without stock/);
 h.el('sales-refresh').events.click();h.calls[2].resolve({data:{context:ctx('administrator'),items:[sold]}});await tick();h.calls[3].resolve({data:workspace('administrator')});await tick();
 assert.equal(h.el('salesperson-filter').value,'CW');assert.match(h.el('sales-leads-list').innerHTML,/Lead without stock/);
});
test('an identical poll retains vehicle table and card DOM while still checking for workspace updates',async()=>{
 const h=harness();await initial(h);const tableWrites=h.el('vehicle-table').writes,mobileWrites=h.el('sales-mobile-vehicles').writes;
 h.el('sales-refresh').events.click();h.calls[2].resolve({data:{context:ctx('administrator'),items:[{...sold}],navision_updated_at:'2026-10-02T01:00:00Z',checked_at:'2026-10-02T01:00:30Z'}});await tick();h.calls[3].resolve({data:workspace('administrator')});await tick();
 assert.equal(h.el('vehicle-table').writes,tableWrites);assert.equal(h.el('sales-mobile-vehicles').writes,mobileWrites);assert.equal(h.crmCalls.setWorkspace.length,2);
});
test('the newest workspace response wins and an older request cannot restore older leads or saved views',async()=>{
 const h=harness();await initial(h);
 const oldRequest=h.getCrmOptions().onChanged();assert.equal(h.calls[2].name,'get_broome_sales_workspace');
 const newRequest=h.getCrmOptions().onChanged();assert.equal(h.calls[3].name,'get_broome_sales_workspace');
 const newer={...workspace('administrator'),views:[{id:viewA,name:'Newest view',version:2,filters:{}}],leads:[{...workspace('administrator').leads[0],customer_name:'Newest lead',version:2}]};
 h.calls[3].resolve({data:newer});await newRequest;
 h.calls[2].resolve({data:{...workspace('administrator'),views:[{id:viewA,name:'Older view',version:1,filters:{}}]}});await oldRequest;
 assert.match(h.el('sales-saved-view').innerHTML,/Newest view/);assert.doesNotMatch(h.el('sales-saved-view').innerHTML,/Older view/);
 h.el('nav-leads').events.click();assert.match(h.el('sales-leads-list').innerHTML,/Newest lead/);
 assert.equal(h.crmCalls.setWorkspace.length,2);
});
test('account replacement clears module DOM and suppresses a delayed workspace response',async()=>{
 const h=harness();await initial(h);h.el('nav-leads').events.click();
 const pending=h.getCrmOptions().onChanged();h.window.PDC_AUTH_CONTEXT={role:'salesperson',userId:'user-B'};h.events['pdc-auth-ready']();
 h.calls[2].resolve({data:workspace('administrator')});await pending;
 assert.equal(h.el('sales-leads-list').innerHTML,'');assert.equal(h.el('vehicle-table').innerHTML,'');assert.equal(h.el('sales-saved-view').innerHTML,'');
 assert.equal(h.crmCalls.setWorkspace.length,1);assert.equal(h.calls[3].name,'get_broome_sales_snapshot');
});
test('a pending workspace read uses the latest selected salesperson when it arrives',async()=>{
 const h=harness();await initial(h);h.el('nav-leads').events.click();
 const pending=h.getCrmOptions().onChanged();change(h,'salesperson-filter','CW');
 const incoming={...workspace('administrator'),leads:[{...workspace('administrator').leads[0],customer_name:'Current scope lead'},{id:viewA,version:1,customer_name:'Previous scope customer',salesperson_code:'BG',stage:'quote'}]};
 h.calls[2].resolve({data:incoming});await pending;
 assert.equal(h.el('salesperson-filter').value,'CW');assert.match(h.el('sales-leads-list').innerHTML,/Current scope lead/);assert.doesNotMatch(h.el('sales-leads-list').innerHTML,/Previous scope customer/);
});
test('a workspace failure clears CRM customer data while retaining the separately loaded scoped vehicle feed',async()=>{
 const h=harness();await initial(h);h.el('nav-leads').events.click();assert.match(h.el('sales-leads-list').innerHTML,/Lead without stock/);
 const pending=h.getCrmOptions().onChanged();h.calls[2].resolve({error:{message:'Workspace access unavailable'}});await pending;
 assert.equal(h.el('sales-leads-list').innerHTML,'');assert.match(h.el('sales-workspace-status').textContent,/Workspace access unavailable/);
 h.el('nav-dashboard').events.click();assert.match(h.el('vehicle-table').innerHTML,/Own customer/);
});
test('changing the dashboard salesperson immediately clears hidden Leads and CRM forms',async()=>{
 const h=harness();await initial(h);h.el('nav-leads').events.click();
 h.el('sales-leads-list').events.click({target:{closest(selector){return selector==='[data-lead-edit]'?{dataset:{leadEdit:leadA}}:null;}}});
 h.el('sales-leads-notes').value='Hidden draft';h.el('nav-dashboard').events.click();h.el('sales-crm-detail').innerHTML='Hidden CRM draft';
 change(h,'salesperson-filter','BG');
 assert.equal(h.el('sales-leads-form').hidden,true);assert.equal(h.el('sales-leads-notes').value,'');assert.equal(h.el('sales-leads-list').innerHTML,'');assert.equal(h.el('sales-crm-detail').innerHTML,'');
 assert.equal(h.crmCalls.syncScope.at(-1),'BG');
});
test('saved views contain personal filter choices rather than salesperson or operational identifiers',async()=>{
 const h=harness();await initial(h);change(h,'salesperson-filter','BG');change(h,'sales-saved-view','preset:waiting_finance');
 h.el('search').value='HiLux';h.el('search').events.input({target:{value:'HiLux'}});h.el('sales-view-name').value='Finance follow-up';h.el('sales-save-view').events.click();
 assert.equal(h.calls[2].name,'save_broome_sales_crm');const args=JSON.parse(JSON.stringify(h.calls[2].args));
 assert.equal(args.p_kind,'view');assert.equal(args.p_id,null);assert.equal(args.p_tracking_id,null);assert.equal(args.p_expected_version,0);
 assert.equal(args.p_data.filters.quick,'waiting_finance');assert.equal(args.p_data.filters.search,'HiLux');
 assert.deepEqual(Object.keys(args.p_data.filters).sort(),['category','direction','jita','month','quick','search','sort','status']);
 assert.doesNotMatch(JSON.stringify(args),/salesperson_code|salesperson_id|canonical_vehicle|dealer_code|user_role_id/);
});
test('a sign-out during the post-save refresh cannot restore saved-view success or private options',async()=>{
 const h=harness();await initial(h);h.el('sales-view-name').value='My follow-ups';h.el('sales-save-view').events.click();
 h.calls[2].resolve({data:{record:{id:viewA,version:1}}});await tick();assert.equal(h.calls[3].name,'get_broome_sales_workspace');
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[3].resolve({data:{...workspace('administrator'),views:[{id:viewA,name:'Private saved view',version:1,filters:{}}]}});await tick();
 assert.equal(h.el('sales-view-status').textContent,'');assert.equal(h.el('sales-saved-view').innerHTML,'');assert.equal(h.el('sales-view-name').value,'');assert.equal(h.el('sales-leads-list').innerHTML,'');
});
