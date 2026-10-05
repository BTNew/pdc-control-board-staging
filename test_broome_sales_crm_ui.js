const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const crm=require('./sales/crm-workspace.js');
const today=crm.perthToday();
function element(id) {
  return {id,innerHTML:'',textContent:'',dataset:{},events:{},addEventListener(type,fn){this.events[type]=fn;},querySelector(){return null;},scrollIntoView(){}};
}
function harness({admin=false,finance=false}={}) {
  const elements=new Map(),calls=[],events={},changes=[],opens=[];
  const el=id=>{if(!elements.has(id))elements.set(id,element(id));return elements.get(id);};
  const h={rows:[{tracking_id:'BG-order',cosi:true,salesperson_code:'BG',stock:'13001',order:'000001',client:'Bryce customer',vehicle:'HiLux'},
    {tracking_id:'PM-order',cosi:'Yes',salesperson_code:'PM',order:'000002',client:'Other customer',vehicle:'Prado'},
    {tracking_id:'unsold',cosi:'No',salesperson_code:'BG',stock:'13003',client:'Unsold customer'}],person:'BG',context:{role:admin?'administrator':'salesperson'}};
  h.host={crypto:require('node:crypto'),PDC_AUTH_CONTEXT:{userId:'approved-user',role:admin?'administrator':'salesperson'},document:{getElementById:el},addEventListener(type,fn){events[type]=fn;},
    PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  h.api=crm.createWorkspace(h.host);h.api.init({getRows:()=>h.rows,getContext:()=>h.context,getSalesperson:()=>h.person,openVehicle:id=>opens.push(id),showView:view=>{h.view=view;},onChanged:(...args)=>changes.push(args)});
  h.workspace={context:{can_edit_finance:finance},contacts:[{id:'c-bg',tracking_id:'BG-order',version:1,next_contact_date:today,next_action:'Call Bryce customer'},
    {id:'c-pm',tracking_id:'PM-order',version:1,next_contact_date:today,next_action:'Other private call'},
    {id:'c-unsold',tracking_id:'unsold',version:1,next_contact_date:today,next_action:'Unsold private call'}],
    tasks:[{id:'t-bg',tracking_id:'BG-order',version:2,title:'Own follow-up',due_date:today,completed:false},{id:'t-pm',tracking_id:'PM-order',version:1,title:'Other private task',due_date:today,completed:false}],
    delivery:[{id:'d-bg',tracking_id:'BG-order',version:1,promised_delivery_date:today,documents:true},{id:'d-pm',tracking_id:'PM-order',version:1,promised_delivery_date:today}],
    activities:[{id:'a-bg',tracking_id:'BG-order',activity_type:'note',body:'Own contact history',occurred_at:today+'T01:00:00Z'}],
    finance:[{id:'f-bg',tracking_id:'BG-order',version:2,current_application:true,approval_status:'approved',approval_date:today,settlement_status:'pending',shared_update:'Shared update',lender:'Private lender',amount:50000,commission:2000,internal_notes:'Manager-only note'},
      {id:'f-pm',tracking_id:'PM-order',version:1,current_application:true,approval_status:'pending',shared_update:'Other finance private'}],
    order_refs:h.rows.filter(crm.isSold).map(row=>({...row})),finance_accounts:[{id:'exact-role-id',name:'Approved editor',email:'editor@example.invalid',enabled:false,version:0}],
    alerts:[{id:'alert-bg',tracking_id:'BG-order',version:1,title:'Own ETA changed',details:'An observed update',occurred_at:today+'T02:00:00Z'},
      {id:'alert-pm',tracking_id:'PM-order',version:1,title:'Other private alert',occurred_at:today+'T02:00:00Z'}],
    timeline:[{id:'event-bg',tracking_id:'BG-order',title:'Stock allocated',details:'Observed stock update',occurred_at:today+'T03:00:00Z'}],history:[]};
  h.api.setWorkspace(h.workspace);Object.assign(h,{el,calls,events,changes,opens});return h;
}
function button(dataset){return {dataset,disabled:false,closest(){return this;}};}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
test('My Day and alerts use COSI rows and the selected salesperson without a first-load request',()=>{
  const h=harness({admin:true});assert.equal(h.calls.length,0);h.api.render('myday');
  const html=h.el('sales-myday').innerHTML;assert.match(html,/Own follow-up/);assert.match(html,/Call Bryce customer/);
  assert.doesNotMatch(html,/Other private|Other customer|Unsold private|Unsold customer/);
  h.api.render('alerts');assert.match(h.el('sales-alerts').innerHTML,/Own ETA changed/);assert.doesNotMatch(h.el('sales-alerts').innerHTML,/Other private alert/);
  h.person='PM';h.api.render('myday');assert.match(h.el('sales-myday').innerHTML,/Other private task/);assert.doesNotMatch(h.el('sales-myday').innerHTML,/Own follow-up|Bryce customer/);
});
test('Finance strips private amounts and notes from ordinary sales data and DOM',()=>{
  const h=harness();h.api.render('finance');const html=h.el('sales-finance').innerHTML;
  assert.match(html,/Approved|Shared update/);assert.doesNotMatch(html,/Manager-only note|Private lender|50000|2000|crm-new-finance|Finance staff only|finance-access/);
  assert.doesNotMatch(JSON.stringify(h.api.getWorkspace().finance),/Manager-only note|Private lender|50000/);
  assert.equal(h.api.getWorkspace().finance_accounts.length,0);
  h.person='';h.rows=h.rows.filter(row=>row.salesperson_code==='BG');h.api.render('finance');assert.doesNotMatch(h.el('sales-finance').innerHTML,/Other finance private|Other customer/);
});
test('manager Finance renders only capability-approved controls and exact order links',async()=>{
  const h=harness({admin:true,finance:true});h.api.render('finance');
  assert.match(h.el('sales-finance').innerHTML,/New finance entry|Finance editor access/);
  await h.el('sales-finance').events.click({target:button({crmEditFinance:'f-bg'})});
  const html=h.el('sales-finance').innerHTML;assert.match(html,/Finance staff only|Manager-only note|Private lender/);assert.match(html,/data-crm-tracking="BG-order"/);
  assert.doesNotMatch(html,/Other finance private/);
  h.person='PM';h.api.render('finance');assert.doesNotMatch(h.el('sales-finance').innerHTML,/Manager-only note|Bryce customer/);
});
test('Finance cannot use an auth role to bypass the workspace editing capability',async()=>{
  const h=harness({admin:true,finance:false});h.api.render('finance');assert.doesNotMatch(h.el('sales-finance').innerHTML,/data-crm-new-finance|Finance staff only/);
  await assert.rejects(h.api.save('finance','f-bg','BG-order',{approval_status:'pending'},2),/Finance editor access/);assert.equal(h.calls.length,0);
});
test('date and finance validation preserve independent finance and payout statuses',()=>{
  assert.equal(crm.perthToday(new Date('2026-10-01T17:30:00Z')),'2026-10-02');
  assert.equal(crm.dateValue('2024-02-29'),'2024-02-29');assert.throws(()=>crm.dateValue('2026-02-29'),/calendar/);
  assert.throws(()=>crm.dateValue('1999-12-31'),/2000/);assert.equal(crm.dateValue(''),null);
  for(const [key,status] of [['approval','approved'],['documents','complete'],['settlement','settled'],['access','active'],['payout','complete']])assert.throws(()=>crm.validate('finance',{[key+'_status']:status}),/date/);
  const data=crm.validate('finance',{approval_status:'approved',approval_date:today,settlement_status:'pending',payout_status:'complete',payout_date:today});
  assert.equal(data.settlement_status,'pending');assert.equal(data.payout_status,'complete');
  assert.throws(()=>crm.validate('finance',{settlement_status:'delivered'}),/valid/);
  assert.throws(()=>crm.validate('task',{title:'Call',due_date:''}),/due date/);assert.throws(()=>crm.validate('contact',{email:'invalid'}),/email/);
  assert.throws(()=>crm.validate('contact',{stock_number:'fake'}),/cannot be changed/);assert.throws(()=>crm.validate('note',{body:'',activity_type:'note'}),/Enter/);
});
test('record identity and cross-person writes are checked before submitting',async()=>{
  const h=harness();await assert.rejects(h.api.save('contact',null,'PM-order',{next_action:'No'},0),/no longer/);
  await assert.rejects(h.api.save('delivery',null,'unsold',{handover:true},0),/no longer/);
  assert.equal(h.calls.length,0);
  const pending=h.api.save('contact','c-bg','BG-order',{next_contact_date:today,next_action:'Call'},1);
  assert.equal(h.calls[0].name,'save_broome_sales_crm');assert.equal(h.calls[0].args.p_tracking_id,'BG-order');assert.equal(h.calls[0].args.p_expected_version,1);
  h.calls[0].resolve({data:{record:{id:'c-bg',tracking_id:'BG-order',next_contact_date:today,next_action:'Call',version:2}}});assert.equal((await pending).version,2);assert.equal(h.changes.length,1);
});
test('duplicate writes are suppressed and replay conflicts preserve the latest saved record',async()=>{
  const h=harness();const fields={title:'Follow up',due_date:today,completed:true};
  const pending=h.api.save('task','t-bg','BG-order',fields,2);
  await assert.rejects(h.api.save('task','t-bg','BG-order',fields,2),/already saving/);assert.equal(h.calls.length,1);
  h.calls[0].resolve({error:{message:'record version conflict'}});await assert.rejects(pending,/version conflict/);
  assert.equal(h.api.getWorkspace().tasks.find(t=>t.id==='t-bg').completed,false);
  const next=h.api.save('task','t-bg','BG-order',fields,2);assert.equal(h.calls.length,2);
  h.calls[1].resolve({data:{record:{id:'t-bg',tracking_id:'BG-order',...fields,version:3}}});assert.equal((await next).completed,true);
});
test('a delayed save cannot restore records or messages after sign-out',async()=>{
  const h=harness();const pending=h.api.save('contact','c-bg','BG-order',{next_action:'Private draft'},1);
  delete h.host.PDC_AUTH_CONTEXT;h.context=null;h.events['pdc-auth-locked']();
  h.calls[0].resolve({data:{record:{id:'c-bg',tracking_id:'BG-order',next_action:'Private saved response',version:2}}});
  assert.equal(await pending,null);assert.equal(h.changes.length,0);assert.equal(h.api.getWorkspace(),null);
  for(const id of ['sales-myday','sales-alerts','sales-finance','sales-history'])assert.equal(h.el(id).innerHTML,'');
});
test('selected-person changes invalidate delayed saves and remove old details',async()=>{
  const h=harness();h.el('sales-crm-detail').innerHTML=h.api.detailHtml(h.rows[0]);
  const pending=h.api.save('contact','c-bg','BG-order',{next_action:'Private draft'},1);h.person='PM';h.api.render('myday');
  h.calls[0].resolve({data:{record:{id:'c-bg',tracking_id:'BG-order',next_action:'Late private response',version:2}}});
  assert.equal(await pending,null);assert.equal(h.changes.length,0);assert.equal(h.api.detailHtml(h.rows[0]),'');assert.equal(h.el('sales-crm-detail').innerHTML,'');assert.doesNotMatch(h.el('sales-myday').innerHTML,/Late private response|Bryce customer/);
});
test('a delayed workspace refresh cannot leak into a replacement account',async()=>{
  const h=harness();const pending=h.api.refresh();h.host.PDC_AUTH_CONTEXT={userId:'replacement',role:'salesperson'};h.events['pdc-auth-ready']();
  h.calls[0].resolve({data:h.workspace});await pending;assert.equal(h.api.getWorkspace(),null);assert.equal(h.el('sales-myday').innerHTML,'');
});
test('details escape customer notes and workshop timeline and never expose Finance private fields',()=>{
  const h=harness();h.workspace.activities[0].body='<img src=x onerror=alert(1)>';h.workspace.timeline[0].title='<unsafe event>';
  h.api.setWorkspace(h.workspace);const row={...h.rows[0],pmb_arrival_date:today,bay_bookings:[{booking_id:'booking',stage:'Tint',bay:'<unsafe bay>',scheduled_start_at:today+'T04:00:00Z',actual_start_at:today+'T04:05:00Z'}]};
  const html=h.api.detailHtml(row);assert.match(html,/&lt;img|&lt;unsafe event&gt;|&lt;unsafe bay&gt;|Bay booking|Work started/);
  assert.doesNotMatch(html,/<img src=x|Manager-only note|Private lender|Other private/);assert.match(html,/does not mark RDR/);
  h.api.render('history');assert.match(h.el('sales-history').innerHTML,/RDR confirmation is awaiting/);
});
test('unsaved inputs survive polling and are cleared when scope changes',()=>{
  const h=harness();h.el('sales-crm-detail').innerHTML=h.api.detailHtml(h.rows[0]);h.api.bindDetail('BG-order');
  const form={dataset:{crmForm:'contact',crmId:'c-bg',crmTracking:'BG-order',crmVersion:'1'},elements:[{name:'next_action',type:'text',value:'Unsaved follow-up draft'}]};
  h.el('sales-crm-detail').events.input({target:{closest:()=>form}});h.workspace.contacts[0].next_action='New server version';h.workspace.contacts[0].version=2;
  h.api.setWorkspace(h.workspace);let html=h.api.detailHtml(h.rows[0]);assert.match(html,/Unsaved follow-up draft/);assert.match(html,/data-crm-version="1"/);
  h.person='PM';h.api.render('myday');h.person='BG';h.api.render('myday');html=h.api.detailHtml(h.rows[0]);assert.doesNotMatch(html,/Unsaved follow-up draft/);assert.match(html,/New server version/);
});
test('finance access is an exact account grant and never changes operational roles',async()=>{
  const h=harness({admin:true,finance:true});h.api.render('finance');const action=h.el('sales-finance').events.click({target:button({crmFinanceAccess:'exact-role-id'})});
  assert.equal(h.calls[0].args.p_kind,'finance_access');assert.equal(h.calls[0].args.p_id,'exact-role-id');assert.equal(h.calls[0].args.p_tracking_id,null);assert.deepEqual(h.calls[0].args.p_data,{enabled:true});
  h.calls[0].resolve({data:{record:{id:'exact-role-id',enabled:true,version:1}}});await action;assert.equal(h.api.getWorkspace().finance_accounts[0].enabled,true);
  const sales=harness();await assert.rejects(sales.api.save('finance_access','exact-role-id',null,{enabled:true},0),/Administrator/);assert.equal(sales.calls.length,0);
});
test('CRM source uses isolated sales RPCs without a browser record cache or operational writes',()=>{
  const source=fs.readFileSync('sales/crm-workspace.js','utf8');
  assert.doesNotMatch(source,/localStorage|sessionStorage|PDC_SUPABASE\.from\(|update_pdc|set_pdc|save_workshop|requestNotificationPermission|Notification\(/);
  assert.match(source,/save_broome_sales_crm/);assert.match(source,/get_broome_sales_workspace/);
});
test('structured alerts show changed facts and dated bay states without object placeholders',()=>{
  const details={before:{kewdale_eta:'2026-10-01',dealer_eta:null},after:{kewdale_eta:'2026-10-04',dealer_eta:null}};
  assert.match(crm.eventDetails(details,'eta_changed'),/Kewdale ETA: .*1 Oct 2026.*→.*4 Oct 2026/);
  assert.doesNotMatch(crm.eventDetails(details,'eta_changed'),/Dealer ETA|\[object Object\]/);
  assert.match(crm.eventDetails({before:'',after:'13001'},'stock_allocated'),/Awaiting allocation → 13001/);
  const bookings={before:[],after:[{booking_id:'private-booking-id',stage:'Tint',bay:'Bay A',status:'started',scheduled_start_at:'2026-10-03T01:00:00Z',actual_start_at:'2026-10-03T01:05:00Z'}]};
  const rendered=crm.eventDetails(bookings,'workshop_changed');assert.match(rendered,/No bay bookings → Tint · Bay A · Work started · Booked .*Started/);assert.doesNotMatch(rendered,/private-booking-id|\[object Object\]/);
  const h=harness();h.workspace.alerts[0].event_type='eta_changed';h.workspace.alerts[0].details=details;h.api.setWorkspace(h.workspace);h.api.render('alerts');assert.match(h.el('sales-alerts').innerHTML,/Kewdale ETA/);assert.doesNotMatch(h.el('sales-alerts').innerHTML,/\[object Object\]/);
});
test('Navision calendar dates keep Australian day/month order and timestamp times use Perth',()=>{
  assert.match(crm.dateLabel('03/08/2026'),/^3 Aug 2026$/);
  assert.match(crm.dateLabel('24/08/2026'),/^24 Aug 2026$/);
  assert.equal(crm.dateLabel('2026-08-03'),crm.dateLabel('03/08/2026'));
  assert.match(crm.dateLabel('29/02/2024'),/^29 Feb 2024$/);
  const timestamp=crm.dateLabel('2026-08-02T17:30:00Z',true);
  assert.match(timestamp,/3 Aug 2026/);assert.match(timestamp,/1:30 am/);
  for(const value of ['31/02/2026','2026-02-30','not-a-date','',null])assert.equal(crm.dateLabel(value),'Not recorded');
});
test('CRM resolves the shared date parser with the actual browser script load order',()=>{
  const window={document:{getElementById(){return null;}}},context=vm.createContext({window,module:undefined});
  vm.runInContext(fs.readFileSync('sales/crm-workspace.js','utf8'),context);
  vm.runInContext(fs.readFileSync('sales/dashboard-tools.js','utf8'),context);
  assert.equal(window.BROOME_SALES_CRM.dateLabel('03/08/2026'),'3 Aug 2026');
  assert.equal(window.BROOME_SALES_CRM.dateLabel('24/08/2026'),'24 Aug 2026');
});
test('Australian ETA changes show correct dates in alerts and the vehicle timeline',()=>{
  const details={before:{kewdale_eta:'03/08/2026'},after:{kewdale_eta:'24/08/2026'}};
  assert.equal(crm.eventDetails(details,'eta_changed'),'Kewdale ETA: 3 Aug 2026 → 24 Aug 2026');
  const h=harness();h.workspace.alerts[0].event_type='eta_changed';h.workspace.alerts[0].details=details;
  h.workspace.timeline[0].event_type='eta_changed';h.workspace.timeline[0].details=details;
  h.api.setWorkspace(h.workspace);h.api.render('alerts');
  for(const html of [h.el('sales-alerts').innerHTML,h.api.detailHtml(h.rows[0])]){
    assert.match(html,/Kewdale ETA: 3 Aug 2026 → 24 Aug 2026/);assert.doesNotMatch(html,/8 Mar 2026|Kewdale ETA: Not recorded/);
  }
});
test('an uncertain note submission retains its unique ID and occurrence time for a safe retry',async()=>{
  const h=harness();h.el('sales-crm-detail').innerHTML=h.api.detailHtml(h.rows[0]);h.api.bindDetail('BG-order');
  const submit=element('submit'),status=element('status'),form={dataset:{crmForm:'note',crmId:'',crmTracking:'BG-order',crmVersion:'0'},elements:[{name:'activity_type',type:'select-one',value:'call'},{name:'body',type:'textarea',value:'Customer called'}],querySelector:selector=>selector==='[type="submit"]'?submit:status};
  const event={target:{closest:()=>form},preventDefault(){}};
  const first=h.el('sales-crm-detail').events.submit(event);assert.equal(submit.disabled,true);assert.match(h.calls[0].args.p_id,/^[a-f0-9-]{36}$/);const firstArgs=h.calls[0].args;
  h.calls[0].resolve({error:{message:'Connection interrupted'}});await first;assert.equal(submit.disabled,false);assert.match(status.textContent,/Connection interrupted/);
  const retry=h.el('sales-crm-detail').events.submit(event);assert.equal(h.calls[1].args.p_id,firstArgs.p_id);assert.equal(h.calls[1].args.p_data.occurred_at,firstArgs.p_data.occurred_at);
  h.calls[1].resolve({data:{record:{id:firstArgs.p_id,tracking_id:'BG-order',...firstArgs.p_data,version:1}}});await retry;
  assert.equal(h.api.getWorkspace().activities.filter(note=>note.id===firstArgs.p_id).length,1);
});
test('revoking Finance editing removes hidden private forms and invalidates pending finance responses',async()=>{
  const h=harness({finance:true});h.api.render('finance');await h.el('sales-finance').events.click({target:button({crmEditFinance:'f-bg'})});assert.match(h.el('sales-finance').innerHTML,/Manager-only note/);
  const pending=h.api.save('finance','f-bg','BG-order',{shared_update:'Pending finance update'},2);
  h.workspace.context.can_edit_finance=false;h.api.setWorkspace(h.workspace);assert.doesNotMatch(h.el('sales-finance').innerHTML,/Manager-only note|Private lender|Finance staff only|data-crm-new-finance/);
  h.calls[0].resolve({data:{record:{id:'f-bg',tracking_id:'BG-order',internal_notes:'Late private response',version:3}}});assert.equal(await pending,null);assert.equal(h.changes.length,0);
  assert.doesNotMatch(JSON.stringify(h.api.getWorkspace().finance),/Late private response|Manager-only note/);
});
test('workspace polling renders only the active CRM view',()=>{
  const h=harness();h.api.clear();h.api.init({getRows:()=>h.rows,getContext:()=>h.context,getSalesperson:()=>h.person,getView:()=> 'alerts'});h.api.setWorkspace(h.workspace);
  assert.match(h.el('sales-alerts').innerHTML,/Own ETA changed/);assert.equal(h.el('sales-myday').innerHTML,'');assert.equal(h.el('sales-finance').innerHTML,'');
});
test('a vehicle reassignment during a save suppresses its response within the same account',async()=>{
  const h=harness();const pending=h.api.save('contact','c-bg','BG-order',{next_action:'Pending own update'},1);
  h.rows=h.rows.filter(row=>row.tracking_id!=='BG-order');
  h.calls[0].resolve({data:{record:{id:'c-bg',tracking_id:'BG-order',next_action:'Late assigned vehicle update',version:2}}});assert.equal(await pending,null);assert.equal(h.changes.length,0);
  h.api.setWorkspace(h.workspace);assert.equal(h.api.getWorkspace().contacts.length,0);assert.equal(h.api.getWorkspace().finance.length,0);assert.equal(h.api.getWorkspace().order_refs.length,0);
  h.api.render('myday');assert.doesNotMatch(h.el('sales-myday').innerHTML,/Late assigned vehicle update|Bryce customer/);
});
test('Finance mobile cards retain labelled statuses, dates, updates and actions without private fields',()=>{
  const h=harness();h.api.render('finance');const html=h.el('sales-finance').innerHTML;
  for(const label of ['Approval','Documents','Settlement','Access product','Existing loan payout','Shared update','Action'])assert.match(html,new RegExp('data-label="'+label+'"'));
  assert.match(html,/crm-finance-cell/);assert.match(html,/crm-finance-actions/);assert.match(html,/Shared update/);assert.match(html,/Updated/);assert.match(html,/data-crm-open="BG-order"/);
  assert.doesNotMatch(html,/Manager-only note|Private lender|50000|2000|Other customer/);
});
test('vehicle finance detail shows the saved settlement date and leaves blank Access unrecorded',()=>{
  const h=harness(),finance=require('./sales/finance-pipeline.js');
  h.workspace.finance=finance.projection([{id:'saved-finance',tracking_id:'BG-order',version:1,created_at:'2026-10-01',approval:'Yes',settlement:'Yes',settlement_date:'2026-09-30',access:'',finance_comm:272,naf:38919}]);
  h.api.setWorkspace(h.workspace);const html=h.api.detailHtml(h.rows[0]);
  const financeHtml=html.match(/<details><summary>Finance status<\/summary>[\s\S]*?<\/details>/)?.[0];
  assert.ok(financeHtml,'the vehicle detail must include its Finance status section');
  assert.match(financeHtml,/<dt>Settlement<\/dt><dd><span[^>]*>Settled<\/span><small>30 Sept 2026<\/small>/);
  assert.match(financeHtml,/<dt>Access product<\/dt><dd><span[^>]*>Not recorded<\/span>/);
  assert.match(financeHtml,/<dt>Existing loan payout<\/dt><dd><span[^>]*>Not recorded<\/span>/);
  assert.doesNotMatch(financeHtml,/38919|272|>Requested<\/span>/);
});

test('My Day ignores leads and keeps ordered vehicle reminders only',()=>{
  const h=harness({admin:true});h.workspace.leads=[{id:'ignored',customer_name:'Private enquiry',salesperson_code:'BG',next_contact_date:today,stage:'enquiry'}];
  h.api.setWorkspace(h.workspace);h.api.render('myday');
  assert.match(h.el('sales-myday').innerHTML,/crm-calendar-grid|Call Bryce customer|Own follow-up/);
  assert.doesNotMatch(h.el('sales-myday').innerHTML,/Private enquiry|Lead follow-ups|Open Leads/);
  assert.equal(h.api.getWorkspace().leads,undefined);
});
test('calendar weeks start on Monday and handle leap dates and year changes',()=>{
  assert.equal(crm.calendarDays('2026-10')[0],'2026-09-28');
  assert.equal(crm.calendarDays('2026-10').at(-1),'2026-11-01');
  assert.equal(crm.calendarDays('2024-02').includes('2024-02-29'),true);
  assert.equal(crm.calendarDays('2026-02').includes('2026-02-29'),false);
  assert.equal(crm.shiftMonth('2026-12',1),'2027-01');assert.equal(crm.shiftMonth('2026-01',-1),'2025-12');
  assert.throws(()=>crm.calendarDays('2026-13'),/valid/);
});
test('My Day places Australian and ISO Kewdale ETAs on their actual days, read-only and in scope',async()=>{
  const h=harness({admin:true});h.rows=[
    {...h.rows[0],tracking_id:'eta-ambiguous',kewdale_eta:'03/10/2026'},
    {...h.rows[0],tracking_id:'eta-high-day',kewdale_eta:'24/10/2026'},
    {...h.rows[0],tracking_id:'eta-iso',kewdale_eta:'2026-10-09'},
    {...h.rows[0],tracking_id:'eta-invalid',kewdale_eta:'31/02/2026'},
    {...h.rows[0],tracking_id:'eta-blank',kewdale_eta:''},
    {...h.rows[1],tracking_id:'eta-other-person',kewdale_eta:'03/10/2026'}
  ];
  h.api.setWorkspace(h.workspace);h.api.render('myday');
  const [year,month]=today.split('-').map(Number),steps=(2026-year)*12+10-month;
  if(steps)await h.el('sales-myday').events.click({target:button({calendarMonth:String(steps)})});
  const html=h.el('sales-myday').innerHTML;
  for(const [date,id] of [['2026-10-03','eta-ambiguous'],['2026-10-24','eta-high-day'],['2026-10-09','eta-iso']]){
    const cell=html.match(new RegExp('<section[^>]*data-calendar-day="'+date+'"[^>]*>([\\s\\S]*?)</section>'))?.[1];
    assert.ok(cell,date);assert.ok(cell.includes('data-calendar-id="'+id+'"'),id+' is on '+date);
    assert.match(cell,/data-calendar-kind="eta"/);assert.doesNotMatch(cell,/draggable="true"/);
    assert.equal(h.api.beginCalendarDrag('eta',id),null);
  }
  assert.doesNotMatch(html,/data-calendar-id="eta-(?:invalid|blank|other-person)"/);
  assert.equal(h.calls.length,0);
  await h.el('sales-myday').events.click({target:button({calendarKind:'eta',calendarId:'eta-high-day'})});
  assert.deepEqual(h.opens,['eta-high-day']);assert.equal(h.calls.length,0);
});
test('task drag saves the exact source identity, due date and version, preserving completion',async()=>{
  const h=harness();const drag=h.api.beginCalendarDrag('task','t-bg');assert.ok(drag);
  const pending=h.api.moveCalendarEntry(drag,'2026-11-04');assert.equal(h.calls.length,1);
  const args=h.calls[0].args;assert.equal(args.p_tracking_id,'BG-order');assert.equal(args.p_id,'t-bg');assert.equal(args.p_expected_version,2);
  assert.deepEqual(args.p_data,{title:'Own follow-up',due_date:'2026-11-04',completed:false});
  h.calls[0].resolve({data:{record:{id:'t-bg',tracking_id:'BG-order',...args.p_data,version:3}}});await pending;
  assert.equal(h.api.getWorkspace().tasks[0].due_date,'2026-11-04');assert.match(h.el('sales-myday').innerHTML,/Moved to/);
});
test('customer reminder drag changes only the reminder date and never contacts or PDC dates',async()=>{
  const h=harness();h.workspace.contacts[0].email='customer@example.invalid';h.api.setWorkspace(h.workspace);
  const drag=h.api.beginCalendarDrag('contact','c-bg'),pending=h.api.moveCalendarEntry(drag,'2026-10-09');
  assert.deepEqual(h.calls[0].args.p_data,{next_contact_date:'2026-10-09'});
  h.calls[0].resolve({data:{record:{id:'c-bg',tracking_id:'BG-order',next_contact_date:'2026-10-09',version:2}}});await pending;
  assert.equal(h.api.getWorkspace().contacts[0].email,'customer@example.invalid');
  assert.equal(h.api.getWorkspace().contacts[0].next_action,'Call Bryce customer');
  assert.equal(h.api.beginCalendarDrag('delivery','d-bg'),null);assert.equal(h.api.beginCalendarDrag('eta','BG-order'),null);
});
test('drag fails closed on reassignment, stale versions and salesperson change',async()=>{
  const h=harness();assert.equal(h.api.beginCalendarDrag('task','t-pm'),null);
  let drag=h.api.beginCalendarDrag('task','t-bg');h.workspace.tasks[0].version=3;h.api.setWorkspace(h.workspace);
  await assert.rejects(h.api.moveCalendarEntry(drag,'2026-10-05'),/changed/);assert.equal(h.calls.length,0);
  drag=h.api.beginCalendarDrag('task','t-bg');h.person='PM';h.api.render('myday');assert.equal(await h.api.moveCalendarEntry(drag,'2026-10-05'),null);assert.equal(h.calls.length,0);
  h.person='BG';h.api.render('myday');drag=h.api.beginCalendarDrag('task','t-bg');h.rows=[];assert.equal(await h.api.moveCalendarEntry(drag,'2026-10-05'),null);
});
test('failed reschedule keeps the saved date and delayed sign-out cannot restore data',async()=>{
  const h=harness(),savedDate='2026-10-01';
  // Keep both moves distinct from the saved date even when the test runs on 5/6 October.
  h.workspace.tasks[0].due_date=savedDate;h.api.setWorkspace(h.workspace);
  let drag=h.api.beginCalendarDrag('task','t-bg'),pending=h.api.moveCalendarEntry(drag,'2026-10-05');
  h.calls[0].resolve({error:{message:'Record version conflict'}});await assert.rejects(pending,/conflict/);assert.equal(h.api.getWorkspace().tasks[0].due_date,savedDate);
  drag=h.api.beginCalendarDrag('task','t-bg');pending=h.api.moveCalendarEntry(drag,'2026-10-06');delete h.host.PDC_AUTH_CONTEXT;h.context=null;h.events['pdc-auth-locked']();
  h.calls[1].resolve({data:{record:{id:'t-bg',tracking_id:'BG-order',due_date:'2026-10-06',version:3}}});
  assert.equal(await pending,null);assert.equal(h.api.getWorkspace(),null);assert.equal(h.el('sales-myday').innerHTML,'');
});
test('calendar click edits a task with its current version and polling preserves dirty input',async()=>{
  const h=harness();await h.el('sales-myday').events.click({target:button({calendarKind:'task',calendarId:'t-bg'})});
  let html=h.el('sales-myday').innerHTML;assert.match(html,/Edit task|name="due_date"|data-crm-version="2"/);
  const form={dataset:{crmForm:'task',crmId:'t-bg',crmTracking:'BG-order',crmVersion:'2'},elements:[{name:'title',type:'text',value:'Unsaved task'},{name:'due_date',type:'date',value:'2026-11-07'},{name:'completed',type:'checkbox',checked:false}]};
  h.el('sales-myday').events.input({target:{closest:()=>form}});h.workspace.tasks[0].title='Newer server task';h.workspace.tasks[0].version=3;h.api.setWorkspace(h.workspace);
  html=h.el('sales-myday').innerHTML;assert.match(html,/value="Unsaved task"|value="2026-11-07"|data-crm-version="2"/);
  assert.equal(h.api.beginCalendarDrag('task','t-bg'),null);
  await h.el('sales-myday').events.click({target:button({calendarClose:''})});assert.ok(h.api.beginCalendarDrag('task','t-bg'));
});
test('calendar drop event routes a genuine drag to the day, ignoring external drags',async()=>{
  const h=harness(),events=h.el('sales-myday').events;let prevented=0;
  const transfer={setData(){}};
  events.dragstart({target:button({calendarKind:'task',calendarId:'t-bg'}),dataTransfer:transfer,preventDefault(){prevented++;}});
  assert.equal(transfer.effectAllowed,'move');
  const target={dataset:{calendarDay:'2026-10-09'},closest(){return this;}};
  const pending=events.drop({target,preventDefault(){prevented++;}});assert.equal(h.calls[0].args.p_data.due_date,'2026-10-09');
  h.calls[0].resolve({data:{record:{id:'t-bg',tracking_id:'BG-order',title:'Own follow-up',due_date:'2026-10-09',completed:false,version:3}}});await pending;
  await events.drop({target,preventDefault(){throw new Error('External drop should not be consumed');}});
  assert.equal(h.calls.length,1);assert.equal(prevented,1);
});
