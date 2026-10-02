'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
require('./sales/dashboard-tools.js');
const customer=require('./sales/customer-emails.js'),email=require('./sales/email-actions.js');
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
