'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
require('./sales/dashboard-tools.js');
const customer=require('./sales/customer-emails.js'),email=require('./sales/email-actions.js');
function uiHarness(){
 const elements=new Map(),calls=[];
 const el=id=>{if(!elements.has(id))elements.set(id,{id,innerHTML:'',textContent:'',value:'',events:{},addEventListener(type,fn){this.events[type]=fn;},close(){},showModal(){}});return elements.get(id);};
 const h={context:{role:'salesperson'},token:'session-one',rows:[{tracking_id:'own-order',stock:'13001',client:'Example customer',vehicle:'Example Hilux'}],el,calls};
 h.host={document:{getElementById:el},PDC_AUTH_CONTEXT:{role:'salesperson'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
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
test('three customer templates use placeholders and salesperson contact signature',()=>{
 assert.equal(customer.types.length,3);
 for(const [kind] of customer.types){
  const t=customer.template(kind);assert.match(t.subject,/\{\{vehicle_model\}\}/);
  for(const key of ['customer_first_name','vehicle_model','salesperson_name','salesperson_phone','salesperson_email'])assert.ok(t.body.includes('{{'+key+'}}'));
  assert.doesNotMatch(t.body,/guarantee|definitely|will arrive on/i);
 }
 assert.match(customer.template('production_planned').body,/\{\{production_month\}\}/);
 assert.match(customer.template('production_planned').body,/timing may change/);
 assert.match(customer.template('production_planned').body,/confirmation.*built/);
 assert.match(customer.template('vehicle_built').body,/awaiting shipping and tracking information/);
 const perth=customer.template('perth_eta').body;
 for(const phrase of ['Kewdale, Perth','{{perth_eta_date}}','shipping arrangements','port clearances','customs','not your handover date','closer to arrival','myToyota Connect','create or activate','arrange to add your vehicle'])assert.ok(perth.includes(phrase),phrase);
});
test('event facts fill known information without guessing a customer first name',()=>{
 const t=customer.draftText({template_kind:'production_planned',facts:{vehicle_model:'Example Hilux',production_month:'11/2026',salesperson_name:'Example Salesperson'}},{client:'EXAMPLE COMPANY',crm_contact:{email:'customer@example.invalid'}});
 assert.equal(t.recipient,'customer@example.invalid');assert.match(t.body,/November 2026/);assert.match(t.body,/Example Salesperson/);
 assert.match(t.body,/\{\{customer_first_name\}\}/);assert.match(t.body,/\{\{salesperson_phone\}\}/);assert.doesNotMatch(t.body,/EXAMPLE COMPANY/);
 assert.throws(()=>customer.validate(t),/placeholders/);
});
test('editable draft signatures follow current ownership without replacing saved reviews or customer contacts',()=>{
 const facts=Object.freeze({vehicle_model:'Example Hilux',salesperson_name:'Original salesperson'});
 const draft=Object.freeze({template_kind:'vehicle_built',status:'draft',facts});
 const row=Object.freeze({salesperson_name:'Current salesperson',crm_contact:Object.freeze({email:'customer@example.invalid'})});
 const generated=customer.draftText(draft,row);
 assert.match(generated.body,/Kind Regards,\nCurrent salesperson\nBroome Toyota/);
 assert.doesNotMatch(generated.body,/Original salesperson/);assert.equal(generated.recipient,'customer@example.invalid');
 assert.match(generated.body,/\{\{salesperson_phone\}\} \| \{\{salesperson_email\}\}/);
 const saved={...draft,recipient:'reviewed@example.invalid',subject:'Reviewed subject',body:'Reviewed wording.\nKind Regards,\nChosen signer\n0400 000 000 | chosen@example.invalid'};
 assert.deepEqual(customer.draftText(saved,row),{recipient:saved.recipient,subject:saved.subject,body:saved.body});
 for(const status of ['prepared','sent'])assert.deepEqual(customer.draftText({...saved,status},row),{recipient:saved.recipient,subject:saved.subject,body:saved.body});
 assert.equal(facts.salesperson_name,'Original salesperson');assert.equal(row.crm_contact.email,'customer@example.invalid');
});
test('reassigned draft dialog defaults the current signature while prepared and sent messages stay exact',async()=>{
 const h=uiHarness();h.rows[0].salesperson_name='Current salesperson';
 const facts={vehicle_model:'Example Hilux',salesperson_name:'Original salesperson'};
 const draft={id:'reassigned-draft',tracking_id:'own-order',template_kind:'vehicle_built',status:'draft',version:1,facts};
 const click=()=>h.el('sales-customeremails').events.click({target:{dataset:{customerReview:draft.id},hasAttribute(){return false;},closest(){return this;}}});
 await h.reply({drafts:[draft]});click();
 assert.equal(h.el('customer-email-signature-name').value,'Current salesperson');
 assert.match(h.el('customer-email-body').value,/Kind Regards,\nCurrent salesperson\nBroome Toyota/);
 assert.equal(h.el('customer-email-fill-fields').hidden,false);
 const savedBody='Hi Example, reviewed message.\nKind Regards,\nChosen historical signer\n0400 000 000 | chosen@example.invalid';
 await h.reply({drafts:[{...draft,version:2,recipient:'reviewed@example.invalid',subject:'Reviewed subject',body:savedBody}]});click();
 assert.equal(h.el('customer-email-signature-name').value,'Current salesperson');
 assert.equal(h.el('customer-email-body').value,savedBody);
 for(const [index,status]of ['prepared','sent'].entries()){
  await h.reply({drafts:[{...draft,status,version:3+index,recipient:'reviewed@example.invalid',subject:'Reviewed subject',body:savedBody}]});click();
  assert.equal(h.el('customer-email-to').value,'reviewed@example.invalid');assert.equal(h.el('customer-email-subject').value,'Reviewed subject');
  assert.equal(h.el('customer-email-body').value,savedBody);assert.equal(h.el('customer-email-body').readOnly,true);
  assert.equal(h.el('customer-email-signature-name').value,'Original salesperson');assert.equal(h.el('customer-email-fill-fields').hidden,true);
 }
});
test('reviewed text persists exactly and source values cannot inject another placeholder',()=>{
 const d={template_kind:'vehicle_built',recipient:'saved@example.invalid',subject:'Reviewed subject',body:'Hi Example, reviewed text.'};
 assert.deepEqual(customer.draftText(d,{crm_contact:{email:'changed@example.invalid'}}),{recipient:d.recipient,subject:d.subject,body:d.body});
 assert.equal(customer.fill('{{vehicle_model}}', {vehicle_model:'Example {{customer_first_name}}',customer_first_name:'Secret'}),'Example {{customer_first_name}}');
 assert.equal(customer.fill('{{unknown}}',{unknown:'ignored'}),'{{unknown}}');
 assert.equal(customer.monthLabel('13/26'),'');
});
test('Perth dates use calendar dates and invalid dates stay unresolved',()=>{
 const t=customer.draftText({template_kind:'perth_eta',facts:{vehicle_model:'Example Prado',perth_eta_date:'2026-11-04'}});
 assert.match(t.body,/04\/11\/2026/);
 assert.match(customer.draftText({template_kind:'perth_eta',facts:{perth_eta_date:'2026-02-30'}}).body,/\{\{perth_eta_date\}\}/);
});
test('customer export requires completed fields and safely creates a draft email',()=>{
 const t=customer.template('perth_eta');const values={customer_first_name:'Alex',vehicle_model:'Example Hilux',perth_eta_date:'4 November 2026',salesperson_name:'Example Staff',salesperson_phone:'0400 000 000',salesperson_email:'staff@example.invalid'};
 const d=customer.validate({recipient:'alex@example.invalid',subject:customer.fill(t.subject,values),body:customer.fill(t.body,values)});
 const message=email.eml({to:d.recipient,cc:'',subject:d.subject,body:d.body});assert.match(message,/X-Unsent: 1/);assert.doesNotMatch(message,/SMTP|Authorization/);
 assert.throws(()=>customer.validate({...d,recipient:'alex@example.invalid\r\nBcc: other@example.invalid'}),/address/);
 assert.throws(()=>customer.validate({...d,subject:'subject\r\nBcc: other@example.invalid'}),/subject/);
 assert.throws(()=>customer.validate({...d,body:'Hi {{customer_first_name}},'}),/placeholders/);
 assert.throws(()=>customer.validate({...d,body:''}),/Complete/);
});
