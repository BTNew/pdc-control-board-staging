/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
require('./sales/dashboard-tools.js');
const customer=require('./sales/customer-emails.js'),email=require('./sales/email-actions.js');
function uiHarness(){
 const elements=new Map(),calls=[],clicks=[];
 const el=id=>{if(!elements.has(id))elements.set(id,{id,innerHTML:'',textContent:'',value:'',hidden:false,disabled:false,readOnly:false,events:{},addEventListener(type,fn){this.events[type]=fn;},close(){},showModal(){}});return elements.get(id);};
 const h={context:{role:'salesperson'},token:'session-one',rows:[{tracking_id:'own-order',stock:'13001',client:'Example customer',vehicle:'Example Hilux'}],el,calls,clicks};
 h.host={document:{getElementById:el,createElement(tag){const node={tagName:tag,href:'',rel:'',style:{},click(){clicks.push({href:this.href});},remove(){}};return node;},body:{appendChild(){}}},BROOME_SALES_EMAIL:email,BROOME_SALES_TOOLS:globalThis.BROOME_SALES_TOOLS,PDC_AUTH_CONTEXT:{role:'salesperson'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
 vm.runInNewContext(fs.readFileSync(require.resolve('./sales/customer-emails.js'),'utf8'),{window:h.host},{filename:'customer-emails.js'});
 h.api=h.host.BROOME_CUSTOMER_EMAILS;
 h.api.init({getContext:()=>h.context,getToken:()=>h.token,getRows:()=>h.rows});
 h.reply=async data=>{const pending=h.api.refresh();calls.at(-1).resolve({data:{drafts:[],context:{role:'salesperson'},...data}});await pending;};
 return h;
}
test('customer updates describe closed-page import capture and review without promising old emails',()=>{
 const h=uiHarness();h.api.render();const html=h.el('sales-customeremails').innerHTML;
 assert.match(html,/Navision status updates prepare drafts for your review, even while this page is closed/);
 assert.match(html,/first import establishes its starting point/);
 assert.match(html,/Review and send each email yourself/);
 assert.match(html,/A downloaded draft is not recorded as sent/);
 assert.match(html,/Dismiss removes an update from the awaiting list without deleting its history/);
 assert.doesNotMatch(html,/sales page is open|first check|waiting for a retry/);
 assert.equal(h.calls.length,0);
});
test('pending capture renders a safe retry notice and clears after recovery or omitted status',async()=>{
 const h=uiHarness(),draft={id:'draft-one',tracking_id:'own-order',template_kind:'vehicle_built',status:'draft',version:1,facts:{vehicle_model:'Example Hilux'}};
 await h.reply({capture_pending:2,drafts:[draft]});let html=h.el('sales-customeremails').innerHTML;
 assert.match(html,/role="status">Some vehicle updates are waiting for a retry/);
 assert.match(html,/Refresh customer emails to try again/);assert.match(html,/Ready for review/);
 await h.reply({capture_pending:0,drafts:[draft]});html=h.el('sales-customeremails').innerHTML;
 assert.doesNotMatch(html,/waiting for a retry/);assert.match(html,/Ready for review/);
 await h.reply({capture_pending:1});assert.match(h.el('sales-customeremails').innerHTML,/waiting for a retry/);
 await h.reply({});assert.doesNotMatch(h.el('sales-customeremails').innerHTML,/waiting for a retry/);
 await h.reply({capture_pending:'<img src=x onerror="alert(1)">'});
 assert.doesNotMatch(h.el('sales-customeremails').innerHTML,/<img|onerror|waiting for a retry/);
 assert.ok(h.calls.every(call=>call.name==='get_broome_customer_emails'));
});
test('capture notices clear on refresh error and cannot return after sign-out or account replacement',async()=>{
 const h=uiHarness();await h.reply({capture_pending:1});
 const failed=h.api.refresh();h.calls.at(-1).resolve({error:{message:'<img src=x> Retry failed'}});await failed;
 assert.doesNotMatch(h.el('sales-customeremails').innerHTML,/waiting for a retry|<img/);
 assert.match(h.el('sales-customeremails').innerHTML,/&lt;img src=x&gt; Retry failed/);
 await h.reply({capture_pending:1});h.token='session-two';h.api.render();
 assert.doesNotMatch(h.el('sales-customeremails').innerHTML,/waiting for a retry|Retry failed/);
 const delayed=h.api.refresh();h.context=null;h.token=null;delete h.host.PDC_AUTH_CONTEXT;h.api.clear();
 h.calls.at(-1).resolve({data:{drafts:[],context:{role:'salesperson'},capture_pending:5}});await delayed;
 assert.equal(h.el('sales-customeremails').innerHTML,'');
});
test('three customer templates use placeholders without salesperson signature or long dashes',()=>{
 assert.equal(customer.types.length,3);
 for(const [kind] of customer.types){
  const t=customer.template(kind);assert.match(t.subject,/\{\{vehicle_model\}\}/);
  assert.ok(t.body.includes('{{customer_first_name}}'));
  assert.ok(t.body.includes('{{vehicle_model}}'));
  assert.doesNotMatch(t.body,/salesperson_phone|salesperson_email|salesperson_name|Kind Regards|Broome Toyota/);
  assert.doesNotMatch(t.subject+t.body,/[—–−]/);
  assert.doesNotMatch(t.body,/guarantee|definitely|will arrive on/i);
 }
 assert.match(customer.template('production_planned').body,/\{\{production_month\}\}/);
 assert.match(customer.template('production_planned').body,/Timing can change/);
 assert.match(customer.template('production_planned').body,/confirmation that your vehicle has been built/);
 assert.match(customer.template('vehicle_built').body,/waiting on shipping and tracking details/);
 const perth=customer.template('perth_eta').body;
 for(const phrase of ['Kewdale, Perth','{{perth_eta_date}}','shipping','port clearances','customs','not your handover date','closer to arrival','myToyota Connect','create or activate','add your vehicle'])assert.ok(perth.includes(phrase),phrase);
});
test('firstNameFromClient reads Navision CLIENT and leaves companies blank',()=>{
 assert.equal(customer.firstNameFromClient('Watson, Craig'),'Craig');
 assert.equal(customer.firstNameFromClient('SMITH, JANE ANN'),'Jane');
 assert.equal(customer.firstNameFromClient('CRAIG WATSON'),'Craig');
 assert.equal(customer.firstNameFromClient('EXAMPLE COMPANY'),'');
 assert.equal(customer.firstNameFromClient('Acme Pty Ltd'),'');
 assert.equal(customer.firstNameFromClient(''),'');
});
test('event facts fill known information and auto-fill a person first name from CLIENT',()=>{
 const company=customer.draftText({template_kind:'production_planned',facts:{vehicle_model:'Example Hilux',production_month:'11/2026'}},{client:'EXAMPLE COMPANY',crm_contact:{email:'customer@example.invalid'}});
 assert.equal(company.recipient,'');assert.match(company.body,/November 2026/);
 assert.match(company.body,/\{\{customer_first_name\}\}/);assert.doesNotMatch(company.body,/EXAMPLE COMPANY|Kind Regards|salesperson|customer@example.invalid/);
 assert.throws(()=>customer.validate({...company,recipient:'customer@example.invalid'}),/placeholders/);
 const person=customer.draftText({template_kind:'vehicle_built',facts:{vehicle_model:'Example Hilux – SR5'}},{client:'Watson, Craig',crm_contact:{email:'craig@example.invalid'}});
 assert.equal(person.recipient,'');
 assert.equal(person.customer_first_name,'Craig');assert.match(person.body,/Hi Craig,/);assert.match(person.body,/Example Hilux - SR5/);assert.doesNotMatch(person.body,/\{\{|—|–|craig@example/);
});
test('reviewed text persists exactly and source values cannot inject another placeholder',()=>{
 const d={template_kind:'vehicle_built',recipient:'saved@example.invalid',subject:'Reviewed subject',body:'Hi Example, reviewed text.'};
 const out=customer.draftText(d,{client:'Watson, Craig',crm_contact:{email:'changed@example.invalid'}});
 assert.equal(out.recipient,d.recipient);assert.equal(out.subject,d.subject);assert.equal(out.body,d.body);
 assert.equal(out.customer_first_name,'Craig');
 assert.equal(customer.fill('{{vehicle_model}}', {vehicle_model:'Example {{customer_first_name}}',customer_first_name:'Secret'}),'Example {{customer_first_name}}');
 assert.equal(customer.fill('{{vehicle_model}}',{vehicle_model:'HiLux \u2013 SR5'}),'HiLux - SR5');
 assert.equal(customer.fill('{{unknown}}',{unknown:'ignored'}),'{{unknown}}');
 assert.equal(customer.monthLabel('13/26'),'');
});
test('Perth dates use calendar dates and invalid dates stay unresolved',()=>{
 const t=customer.draftText({template_kind:'perth_eta',facts:{vehicle_model:'Example Prado',perth_eta_date:'2026-11-04'}});
 assert.match(t.body,/04\/11\/2026/);
 assert.match(customer.draftText({template_kind:'perth_eta',facts:{perth_eta_date:'2026-02-30'}}).body,/\{\{perth_eta_date\}\}/);
});
test('customer export requires completed fields and safely creates a draft email',()=>{
 const t=customer.template('perth_eta');const values={customer_first_name:'Alex',vehicle_model:'Example Hilux',perth_eta_date:'4 November 2026'};
 const d=customer.validate({recipient:'alex@example.invalid',subject:customer.fill(t.subject,values),body:customer.fill(t.body,values)});
 const message=email.eml({to:d.recipient,cc:'',subject:d.subject,body:d.body});assert.match(message,/X-Unsent: 1/);assert.doesNotMatch(message,/SMTP|Authorization/);
 assert.doesNotMatch(d.body,/Kind Regards|salesperson_phone|—|–/);
 assert.throws(()=>customer.validate({...d,recipient:'alex@example.invalid\r\nBcc: other@example.invalid'}),/address/);
 assert.throws(()=>customer.validate({...d,subject:'subject\r\nBcc: other@example.invalid'}),/subject/);
 assert.throws(()=>customer.validate({...d,body:'Hi {{customer_first_name}},'}),/placeholders/);
 assert.throws(()=>customer.validate({...d,body:''}),/Complete/);
});
test('draft dialog auto-fills first name and hides signature fields',async()=>{
 const h=uiHarness();h.rows[0].client='Watson, Craig';h.rows[0].crm_contact={email:'crm@example.invalid'};
 const draft={id:'draft-one',tracking_id:'own-order',template_kind:'vehicle_built',status:'draft',version:1,facts:{vehicle_model:'Example Hilux'}};
 const click=()=>h.el('sales-customeremails').events.click({target:{dataset:{customerReview:draft.id},hasAttribute(){return false;},closest(){return this;}}});
 await h.reply({drafts:[draft]});click();
 assert.equal(h.el('customer-email-to').value,'');
 assert.equal(h.el('customer-email-first-name').value,'Craig');
 assert.match(h.el('customer-email-body').value,/Hi Craig,/);
 assert.doesNotMatch(h.el('customer-email-body').value,/Kind Regards|salesperson/);
 assert.equal(h.el('customer-email-fill-fields').hidden,false);
 assert.equal(h.el('customer-email-dismiss').hidden,false);
 assert.equal(h.el('customer-email-open').hidden,false);
 const savedBody='Hi Craig, reviewed message.';
 await h.reply({drafts:[{...draft,version:2,recipient:'reviewed@example.invalid',subject:'Reviewed subject',body:savedBody}]});click();
 assert.equal(h.el('customer-email-body').value,savedBody);
 for(const [index,status]of ['prepared','sent'].entries()){
  await h.reply({drafts:[{...draft,status,version:3+index,recipient:'reviewed@example.invalid',subject:'Reviewed subject',body:savedBody,can_manage_prepared:status==='prepared'}]});click();
  assert.equal(h.el('customer-email-to').value,'reviewed@example.invalid');assert.equal(h.el('customer-email-subject').value,'Reviewed subject');
  assert.equal(h.el('customer-email-body').value,savedBody);assert.equal(h.el('customer-email-body').readOnly,true);
  assert.equal(h.el('customer-email-fill-fields').hidden,true);
  assert.equal(h.el('customer-email-dismiss').hidden,true);
 }
});
test('Dismiss uses skip RPC and keeps history status',async()=>{
 const h=uiHarness();
 const draft={id:'draft-dismiss',tracking_id:'own-order',template_kind:'vehicle_built',status:'draft',version:1,facts:{vehicle_model:'Example Hilux'}};
 await h.reply({drafts:[draft]});
 h.el('sales-customeremails').events.click({target:{dataset:{customerReview:draft.id},hasAttribute(){return false;},closest(){return this;}}});
 const pending=h.el('customer-email-dismiss').events.click();
 const call=h.calls.at(-1);
 assert.equal(call.name,'save_broome_customer_email');
 assert.equal(call.args.p_action,'skip');
 call.resolve({data:{record:{...draft,status:'skipped',version:2}}});
 await pending;
 assert.match(h.el('sales-customeremails').innerHTML,/Dismissed|Earlier updates/);
});
test('Open email app opens mailto before the prepare RPC resolves',async()=>{
 const h=uiHarness();
 const draft={id:'draft-open',tracking_id:'own-order',template_kind:'vehicle_built',status:'draft',version:1,facts:{vehicle_model:'Example Hilux'},recipient:'craig@example.invalid'};
 await h.reply({drafts:[draft]});
 h.el('sales-customeremails').events.click({target:{dataset:{customerReview:draft.id},hasAttribute(){return false;},closest(){return this;}}});
 h.el('customer-email-to').value='craig@example.invalid';
 h.el('customer-email-subject').value='Your Example Hilux has been built';
 h.el('customer-email-body').value='Hi Craig,\n\nJust letting you know your Example Hilux has been built.';
 const pending=h.el('customer-email-open').events.click();
 assert.equal(h.clicks.length,1);
 assert.match(h.clicks[0].href,/^mailto:/);
 const call=h.calls.at(-1);
 assert.equal(call.name,'save_broome_customer_email');
 assert.equal(call.args.p_action,'prepare');
 call.resolve({data:{record:{...draft,status:'prepared',version:2,can_manage_prepared:true}}});
 await pending;
});
test('index dialog has Dismiss at top and no salesperson signature fields',()=>{
 const html=fs.readFileSync(require.resolve('./sales/index.html'),'utf8');
 const start=html.indexOf('id="customer-email-dialog"'),end=html.indexOf('</dialog>',start);
 const dialog=html.slice(start,end);
 assert.match(dialog,/id="customer-email-dismiss"/);
 assert.ok(dialog.indexOf('customer-email-dismiss')<dialog.indexOf('customer-email-to'));
 assert.doesNotMatch(dialog,/customer-email-signature-name|customer-email-signature-phone|customer-email-signature-email|Salesperson phone|Salesperson email|Salesperson name/);
 assert.doesNotMatch(dialog,/[—–−]/);
 assert.match(html,/customer-emails\.js\?v=2026\.10\.02\.19&amp;r495=2026\.10\.23\.r495&amp;r520=2026\.10\.24\.r520/);
});
