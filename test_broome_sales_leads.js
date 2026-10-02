const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const leads=require('./sales/leads.js');
const leadA='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',leadB='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const orderA='cccccccc-cccc-4ccc-8ccc-cccccccccccc',orderB='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const own={id:leadA,version:1,customer_name:'Own customer',salesperson_code:'BG',stage:'enquiry',next_action:'Follow up',notes:'Private note'};
const other={id:leadB,version:1,customer_name:'Other customer',salesperson_code:'PM',stage:'quote'};
const refs=[{tracking_id:orderA,salesperson_code:'BG',order:'000123',stock:'',client:'Own customer',vehicle:'HiLux'},{tracking_id:orderB,salesperson_code:'PM',order:'000124',stock:'13001',client:'Other customer',vehicle:'Prado'}];
const people=[{code:'BG',name:'Bryce'},{code:'PM',name:'Other salesperson'}];
function harness(role='salesperson'){
 const elements=new Map(),events={},calls=[],changes=[],opened=[];
 const el=id=>{
  if(!elements.has(id)) elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',events:{},classList:{add(){}},
   addEventListener(event,fn){this.events[event]=fn;},focus(){this.focused=true;},reset(){}});
  return elements.get(id);
 };
 const window={document:{getElementById:el},PDC_AUTH_CONTEXT:{userId:'user-A',role},
  PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},
  addEventListener(event,fn){events[event]=fn;}};
 vm.runInNewContext(fs.readFileSync('sales/leads.js','utf8'),{window,module:undefined,Date,Set,console});
 const controller=window.BROOME_SALES_LEADS,ctx={role,salesperson_code:'BG',salesperson_id:'self'};
 let selected='';
 controller.init({getContext:()=>ctx,getSalesperson:()=>selected,onChanged:value=>changes.push(value),openVehicle:id=>opened.push(id)});
 const workspace={context:ctx,leads:[{...own},{...other}],order_refs:refs,salespeople:people};
 controller.setWorkspace(workspace);
 return{window,events,calls,changes,opened,controller,el:name=>el('sales-leads-'+name),setSelected:value=>{selected=value;controller.render();},setScopeOnly:value=>{selected=value;controller.syncScope();},workspace};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function clickEdit(h,id){h.el('list').events.click({target:{closest(selector){return selector==='[data-lead-edit]'?{dataset:{leadEdit:id}}:null;}}});}
function submit(h){return h.el('form').events.submit({preventDefault(){}});}
test('lead scope fails closed without an approved owner and administrators can select a salesperson',()=>{
 assert.deepEqual(leads.scopeRows([own,other],{role:'salesperson',salesperson_code:'BG'},''),[own]);
 assert.deepEqual(leads.scopeRows([own,other],{role:'salesperson'},''),[]);
 assert.deepEqual(leads.scopeRows([own,other],{role:'driver',salesperson_code:'BG'},''),[]);
 assert.deepEqual(leads.scopeRows([own,other],{role:'administrator'},'PM'),[other]);
 assert.equal(leads.scopeRows([own,other],{role:'administrator'},'').length,2);
});
test('ordered leads require a scoped immutable order UUID and active owner; names never create a match',()=>{
 const data={customer_name:'Own customer',stage:'order',salesperson_code:'BG'};
 assert.throws(()=>leads.validateLead(data,refs,people,{role:'administrator'}),/existing COSI order/);
 assert.throws(()=>leads.validateLead({...data,tracking_id:orderB},refs,people,{role:'administrator'}),/assigned to this salesperson/);
 assert.throws(()=>leads.validateLead({...data,tracking_id:'13001'},refs,people,{role:'administrator'}),/current COSI/);
 assert.equal(leads.validateLead({...data,tracking_id:orderA},refs,people,{role:'administrator'}).tracking_id,orderA);
 assert.throws(()=>leads.validateLead({...data,salesperson_code:'ZZ',tracking_id:orderA},refs,people,{role:'administrator'}),/active salesperson/);
 const forced=leads.validateLead({...data,salesperson_code:'PM',tracking_id:orderA},refs,people,{role:'salesperson',salesperson_code:'BG'});
 assert.equal(forced.data.salesperson_code,'BG');
});
test('unknown stages, invalid dates and oversized or malformed inputs are refused',()=>{
 const data={customer_name:'Example',stage:'enquiry',salesperson_code:'BG'};
 const ctx={role:'administrator'};
 assert.throws(()=>leads.validateLead({...data,stage:'approved'},refs,people,ctx),/recognised lead stage/);
 assert.throws(()=>leads.validateLead({...data,next_contact_date:'2026-02-30'},refs,people,ctx),/valid next contact/);
 assert.throws(()=>leads.validateLead({...data,email:'not-an-email'},refs,people,ctx),/valid email/);
 assert.throws(()=>leads.validateLead({...data,notes:'x'.repeat(4001)},refs,people,ctx),/shorten notes/);
 assert.throws(()=>leads.validateLead({...data,last_contact_date:'2026-02-30'},refs,people,ctx),/valid last contact/);
 assert.throws(()=>leads.validateLead({...data,last_contact_date:'1999-12-31'},refs,people,ctx),/valid last contact/);
 assert.throws(()=>leads.validateLead({...data,customer_name:' '},refs,people,ctx),/customer name/);
 assert.equal(leads.validateLead({...data,next_contact_date:'2028-02-29'},refs,people,ctx).data.next_contact_date,'2028-02-29');
 assert.equal(leads.validateLead({...data,last_contact_date:'2026-10-01'},refs,people,ctx).data.last_contact_date,'2026-10-01');
});
test('a salesperson only sees their leads, cannot edit another owner and all displayed values are escaped',()=>{
 const h=harness();
 assert.match(h.el('list').innerHTML,/Own customer/);assert.doesNotMatch(h.el('list').innerHTML,/Other customer/);
 clickEdit(h,leadB);assert.equal(h.el('form').hidden,true);
 h.controller.setWorkspace({...h.workspace,leads:[{...own,customer_name:'<img src=x onerror=alert(1)>',notes:'<script>bad</script>'}]});
 assert.match(h.el('list').innerHTML,/&lt;img/);assert.doesNotMatch(h.el('list').innerHTML,/<script>|<img/);
 clickEdit(h,leadA);assert.equal(h.el('owner-label').hidden,true);
 assert.doesNotMatch(h.el('tracking_id').innerHTML,/000124|Other customer/);
});
test('search and stage filters operate within the salesperson scope',()=>{
 const h=harness();h.el('search').value='PRIVATE NOTE';h.el('search').events.input();assert.match(h.el('list').innerHTML,/Own customer/);
 h.el('filter-stage').value='quote';h.el('filter-stage').events.change();assert.doesNotMatch(h.el('list').innerHTML,/Own customer|Other customer/);
 assert.match(h.el('list').innerHTML,/No leads match/);
});
test('polling preserves an unsaved form, while changing the administrator salesperson discards it',()=>{
 const h=harness('administrator');h.setSelected('BG');clickEdit(h,leadA);
 h.el('notes').value='Unsaved conversation';h.controller.setWorkspace({...h.workspace,leads:[{...own},{...other}]});
 assert.equal(h.el('notes').value,'Unsaved conversation');assert.equal(h.el('form').hidden,false);
 h.setSelected('PM');assert.equal(h.el('form').hidden,true);assert.equal(h.el('notes').value,'');
 assert.match(h.el('list').innerHTML,/Other customer/);assert.doesNotMatch(h.el('list').innerHTML,/Own customer/);
});
test('a hidden Leads editor and customer cards clear immediately when only its scope is synchronised',()=>{
 const h=harness('administrator');h.setSelected('BG');clickEdit(h,leadA);h.el('notes').value='Hidden draft';
 h.setScopeOnly('PM');assert.equal(h.el('form').hidden,true);assert.equal(h.el('notes').value,'');assert.equal(h.el('list').innerHTML,'');
 h.controller.render();assert.match(h.el('list').innerHTML,/Other customer/);
});
test('new and edited leads save only through the separate CRM RPC and require version confirmation',async()=>{
 const h=harness();h.el('new').events.click();h.el('customer_name').value='New customer';h.el('stage').value='enquiry';submit(h);
 assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'save_broome_sales_crm');
 assert.equal(h.calls[0].args.p_kind,'lead');assert.equal(h.calls[0].args.p_expected_version,0);assert.equal(h.calls[0].args.p_id,null);
 assert.equal(h.calls[0].args.p_tracking_id,null);assert.equal(h.calls[0].args.p_data.salesperson_code,'BG');
 assert.equal(h.el('notes').disabled,true);
 h.calls[0].resolve({data:{record:{...own,id:leadB,version:1,customer_name:'New customer'}}});await tick();
 assert.equal(h.el('form').hidden,true);assert.match(h.el('list').innerHTML,/New customer/);assert.equal(h.changes.length,1);
 clickEdit(h,leadA);assert.equal(h.el('notes').disabled,false);submit(h);
 assert.equal(h.calls[1].args.p_expected_version,1);h.calls[1].resolve({error:{message:'Record changed elsewhere. Refresh and try again.'}});await tick();
 assert.match(h.el('message').textContent,/changed elsewhere/);assert.equal(h.el('form').hidden,false);assert.equal(h.el('save').disabled,false);
});
test('explicit linked order opens only a scoped vehicle, without editing PDC',()=>{
 const h=harness();h.controller.setWorkspace({...h.workspace,leads:[{...own,stage:'order',tracking_id:orderA}]});
 h.el('list').events.click({target:{closest(selector){return selector==='[data-lead-open]'?{dataset:{leadOpen:orderB}}:null;}}});assert.equal(h.opened.length,0);
 h.el('list').events.click({target:{closest(selector){return selector==='[data-lead-open]'?{dataset:{leadOpen:orderA}}:null;}}});assert.deepEqual(h.opened,[orderA]);assert.equal(h.calls.length,0);
});
test('sign-out clears contacts and drafts; a delayed save cannot refill the page',async()=>{
 const h=harness();clickEdit(h,leadA);h.el('notes').value='Unsaved secret';submit(h);assert.equal(h.calls.length,1);
 delete h.window.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
 h.calls[0].resolve({data:{record:{...own,version:2,notes:'Saved secret'}}});await tick();
 assert.equal(h.el('list').innerHTML,'');assert.equal(h.el('notes').value,'');assert.equal(h.el('tracking_id').innerHTML,'');assert.equal(h.el('message').textContent,'');assert.equal(h.changes.length,0);
});
test('scope and principal replacement suppress delayed save results',async()=>{
 const h=harness('administrator');h.setSelected('BG');clickEdit(h,leadA);submit(h);h.setSelected('PM');
 h.calls[0].resolve({data:{record:{...own,version:2,notes:'Previous scope'}}});await tick();
 assert.doesNotMatch(h.el('list').innerHTML,/Previous scope|Own customer/);assert.equal(h.changes.length,0);
 h.setSelected('BG');clickEdit(h,leadA);submit(h);h.window.PDC_AUTH_CONTEXT={role:'salesperson',userId:'user-B'};h.events['pdc-auth-ready']();
 h.calls[1].resolve({data:{record:{...own,version:2}}});await tick();assert.equal(h.el('list').innerHTML,'');assert.equal(h.changes.length,0);
});
test('older polling results cannot erase a newer confirmed save; malformed save confirmation stays visible',async()=>{
 const h=harness();clickEdit(h,leadA);h.el('notes').value='New confirmed note';submit(h);
 h.calls[0].resolve({data:{record:{...own,version:2,notes:'New confirmed note'}}});await tick();
 h.controller.setWorkspace({...h.workspace,leads:[{...own}]});assert.match(h.el('list').innerHTML,/New confirmed note/);
 clickEdit(h,leadA);submit(h);h.calls[1].resolve({data:{record:{...own,version:2}}});await tick();assert.match(h.el('message').textContent,/could not be confirmed/);assert.equal(h.el('save').disabled,false);
});
test('a save reply cannot erase a later version already received by background polling',async()=>{
 const h=harness();clickEdit(h,leadA);submit(h);
 h.controller.setWorkspace({...h.workspace,leads:[{...own,version:3,notes:'Later confirmed update'}]});
 h.calls[0].resolve({data:{record:{...own,version:2,notes:'Older save response'}}});await tick();
 assert.match(h.el('list').innerHTML,/Later confirmed update/);assert.doesNotMatch(h.el('list').innerHTML,/Older save response/);
});
test('module stores no customer data in browser storage and never invokes operational vehicle or messaging writes',()=>{
 const js=fs.readFileSync('sales/leads.js','utf8');
 assert.doesNotMatch(js,/localStorage|sessionStorage|\.from\(|update_pdc|send_email|send_sms|mailto:/);
 assert.match(js,/save_broome_sales_crm/);
});
