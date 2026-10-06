const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const tools=require('./sales/dashboard-tools.js'),email=require('./sales/email-actions.js');
test('Kewdale counters use Perth calendar days across midnight and month boundaries',()=>{
 assert.equal(tools.perthToday(new Date('2026-10-01T16:01:00Z')),'2026-10-02');
 assert.deepEqual(tools.etaInfo('2026-10-05','2026-10-02'),{date:'05/10/2026',label:'Due in 3 days',tone:'due',days:3});
 assert.equal(tools.etaInfo('30/09/2026','2026-10-02').label,'2 days past ETA');
 assert.equal(tools.etaInfo('2026-10-02','2026-10-02').label,'Due today');
 assert.equal(tools.etaInfo('2024-02-29','2024-03-01').days,-1);
});
test('invalid or missing ETA never becomes a false arrival or overdue claim',()=>{
 for(const value of ['',null,'2026-02-29','31/04/2026','TBA','<img>','2026-13-01']){
  const result=tools.etaInfo(value,'2026-10-02');assert.equal(result.days,null);assert.equal(result.label,'');
 }
 assert.equal(tools.etaInfo('2026-10-03','2026-10-02').label,'Due in 1 day');
 assert.equal(tools.etaInfo('2026-10-01','2026-10-02').label,'1 day past ETA');
});
test('column preferences admit only bounded numeric widths and discard customer data',()=>{
 assert.deepEqual(tools.readWidths('bad JSON'),tools.defaults);
 assert.deepEqual(tools.readWidths('{"customer":"PRIVATE"}'),tools.defaults);
 const out=tools.readWidths('[99999,-4,"PRIVATE",null,100.4]');
 assert.deepEqual(out.slice(0,5),[600,40,75,145,100]);assert.equal(out.length,13);
});
test('column pointer and keyboard changes preserve bounded widths and save only numbers',()=>{
 const events={},stored=[],cols=tools.defaults.map(()=>({style:{}}));
 const handles=tools.defaults.map((_,i)=>({dataset:{resize:String(i)},setAttribute(k,v){this[k]=v;},setPointerCapture(){}}));
 const table={style:{},addEventListener(k,fn){events[k]=fn;},querySelectorAll(s){return s==='col'?cols:handles;}};
 const window={localStorage:{getItem(){return '[120]';},setItem(k,v){stored.push([k,JSON.parse(v)]);}}};
 vm.runInNewContext(fs.readFileSync('sales/dashboard-tools.js','utf8'),{window,Date,Intl,JSON,Number,module:undefined});
 const controller=window.BROOME_SALES_TOOLS.initColumns(table);controller.apply();assert.equal(cols[0].style.width,(120/[120,...tools.defaults.slice(1)].reduce((a,b)=>a+b,0)*100)+'%');
 const target={closest:()=>handles[0]},base={target,preventDefault(){},stopPropagation(){}};
 events.pointerdown({...base,button:0,clientX:100,pointerId:7});events.pointermove({clientX:150,pointerId:7});events.pointerup();
 assert.equal(Number.parseFloat(cols[0].style.width),170/[120,...tools.defaults.slice(1)].reduce((a,b)=>a+b,0)*100);assert.equal(handles[0]['aria-valuenow'],'170');
 events.keydown({...base,key:'ArrowRight'});assert.equal(Number.parseFloat(cols[0].style.width),180/[120,...tools.defaults.slice(1)].reduce((a,b)=>a+b,0)*100);
 events.keydown({...base,key:'Home'});assert.equal(Number.parseFloat(cols[0].style.width),60/[120,...tools.defaults.slice(1)].reduce((a,b)=>a+b,0)*100);
 assert.ok(stored.every(([k,v])=>k==='broome-sales-column-widths-v3'&&v.every(x=>typeof x==='number')));
});
test('four templates match the examples without inventing equipment or recipients',()=>{
 const r={stock:'13032821',order:'0026001',client:'PARK',vehicle:'LC300 GR Sport',kewdale_eta:'2026-08-03'};
 assert.equal(email.template('tint',r).to,'jono@performancetinting.com.au');
 assert.equal(email.template('tint',r).subject,'Tint PO - 13032821');
 assert.equal(email.template('build',r).subject,'New vehicle order for 13032821 - PMG Build');
 for(const kind of ['released','update','build','tint'])assert.match(email.template(kind,r).body,/PARK/);
 assert.doesNotMatch(email.template('build',r).body,/Steel tray|tyre hangers/);
 assert.equal(email.template('released',r).to,'amy.elkington@broometoyota.com.au');assert.equal(email.template('update',r).to,'');
 assert.throws(()=>email.template('fake',r));
});
test('stockless email uses the exact Toyota order and does not fabricate a stock number',()=>{
 const d=email.template('update',{order:'0001234',client:'Example',vehicle:'HiLux'});
 assert.match(d.subject,/Toyota order 0001234/);assert.match(d.body,/Stock number: Awaiting allocation/);
 assert.match(d.body,/Toyota order: 0001234/);
});
test('email recipients reject header injection and mailto encodes editable content',()=>{
 assert.equal(email.addresses('a@example.invalid; b@example.invalid',true),'a@example.invalid, b@example.invalid');
 for(const bad of ['a@example.invalid\r\nBcc: stolen@example.invalid','Amy','a@example.invalid,','javascript:alert(1)'])assert.throws(()=>email.addresses(bad,true));
 assert.throws(()=>email.addresses('',true));
 const url=email.mailto({to:'a@example.invalid',cc:'b@example.invalid',subject:'A & B',body:'Customer: café\n?bcc=evil'});
 assert.equal(new URL(url).searchParams.get('body'),'Customer: café\n?bcc=evil');
 assert.equal(new URL(url).searchParams.get('subject'),'A & B');
});
test('draft MIME keeps unicode text, both body formats, binary attachment bytes and unsent header',()=>{
 const bytes=Uint8Array.from([0,1,2,128,255]),body='Customer: café & <unsafe>\nVehicle: HiLux';
 const msg=email.eml({to:'test@example.invalid',cc:'',subject:'é'.repeat(100)+'\nBcc: evil@example.invalid',body},[{name:'Parts été.pdf',bytes}],'test_boundary');
 assert.match(msg,/^X-Unsent: 1\r\n/);assert.doesNotMatch(msg,/\r\nBcc:/);assert.ok([...msg].every(c=>c.charCodeAt(0)<128));
 assert.match(msg,/multipart\/alternative/);assert.match(msg,/filename\*=UTF-8''Parts%20%C3%A9t%C3%A9.pdf/);
 const blocks=[...msg.matchAll(/Content-Transfer-Encoding: base64\r\n(?:Content-Disposition:[\s\S]*?)?\r\n([A-Za-z0-9+/=\r\n]*?)(?=\r\n--)/g)].map(m=>Buffer.from(m[1].replace(/\s/g,''),'base64'));
 assert.equal(blocks[0].toString('utf8'),body);assert.match(blocks[1].toString('utf8'),/&lt;unsafe&gt;/);assert.deepEqual(blocks[2],Buffer.from(bytes));
 const subjects=[...msg.matchAll(/=\?UTF-8\?B\?([^?]+)\?=/g)].map(m=>Buffer.from(m[1],'base64').toString('utf8')).join('');
 assert.equal(subjects,'é'.repeat(100)+' Bcc: evil@example.invalid');
});
test('attachment limits stop oversize batches before file reads',()=>{
 assert.throws(()=>email.attachmentLimits([{size:11*1024*1024}]));
 assert.throws(()=>email.attachmentLimits(Array(11).fill({size:1})));
 assert.throws(()=>email.attachmentLimits(Array(3).fill({size:8*1024*1024})));
 assert.doesNotThrow(()=>email.attachmentLimits([{size:10*1024*1024},{size:10*1024*1024}]));
});
function emailHarness(){
 const els=new Map(),downloads=[],errors=[];let token='A',rows=[{tracking_id:'own',stock:'1',client:'Private customer',vehicle:'HiLux'}],selected=[];
 function el(id){if(!els.has(id))els.set(id,{value:'',textContent:'',files:[],open:false,events:{},addEventListener(k,fn){this.events[k]=fn;},showModal(){this.open=true;},close(){this.open=false;}});return els.get(id);}
 const window={document:{getElementById:el,body:{appendChild(){}},createElement(){return {click(){downloads.push(this.download);},remove(){}};}},Blob,URL:{createObjectURL(){return 'blob:fixture';},revokeObjectURL(){}},setTimeout(){},location:{href:''},btoa:s=>Buffer.from(s,'binary').toString('base64')};
 vm.runInNewContext(fs.readFileSync('sales/email-actions.js','utf8'),{window,TextEncoder,Uint8Array,Date,module:undefined});
 const ui=window.BROOME_SALES_EMAIL;ui.init({getRows:()=>rows,getSelectedRows:()=>selected,getToken:()=>token,onError:message=>errors.push(message)});
 return {ui,el,window,downloads,errors,setToken(v){token=v;},setRows(v){rows=v;},setSelected(v){selected=v;}};
}
test('email dialog only opens for scoped rows and clears all private fields when scope changes',()=>{
 const h=emailHarness();h.ui.open('update','other');assert.equal(h.el('sales-email').open,false);
 h.ui.open('update','own');assert.match(h.el('sales-email-body').value,/Private customer/);
 h.setToken('B');h.ui.syncScope();assert.equal(h.el('sales-email').open,false);assert.equal(h.el('sales-email-body').value,'');
 h.ui.open('update','own');h.setRows([]);h.ui.syncScope();assert.equal(h.el('sales-email-subject').value,'');
});
test('pending attachment read loses download authority on sign-out or scope change',async()=>{
 const h=emailHarness();h.ui.open('update','own');h.el('sales-email-to').value='test@example.invalid';let resolve;
 h.el('sales-email-files').files=[{name:'parts.pdf',size:2,arrayBuffer:()=>new Promise(r=>resolve=r)}];
 const pending=h.el('sales-email-download').events.click();h.setToken('signed-out');h.ui.syncScope();resolve(Uint8Array.from([1,2]).buffer);await pending;
 assert.deepEqual(h.downloads,[]);assert.equal(h.el('sales-email-status').textContent,'');assert.equal(h.el('sales-email-files').value,'');
});
test('text-only email path refuses selected attachments rather than silently dropping them',()=>{
 const h=emailHarness();h.ui.open('update','own');h.el('sales-email-to').value='test@example.invalid';h.el('sales-email-files').files=[{name:'parts.pdf',size:2}];
 h.el('sales-email-open').events.click();assert.equal(h.window.location.href,'');assert.match(h.el('sales-email-status').textContent,/does not attach files/);
});
test('new sales tools contain no operational write, email send endpoint or customer record cache',()=>{
 for(const f of ['sales/dashboard-tools.js','sales/email-actions.js']){
  const code=fs.readFileSync(f,'utf8');assert.doesNotMatch(code,/PDC_SUPABASE|\.rpc\(|fetch\(|sendMail|access_token|service_role/);
 }
 assert.doesNotMatch(fs.readFileSync('sales/email-actions.js','utf8'),/localStorage|sessionStorage|indexedDB/);
 const html=fs.readFileSync('sales/index.html','utf8');assert.match(html,/email-actions\.js\?v=2026\.10\.06\.01/);assert.match(html,/dashboard-tools\.js\?v=2026\.10\.02\.18/);
});

test('resizing shares width with a neighbour and never grows the table',()=>{
 for(const index of [0,5,tools.defaults.length-1])for(const delta of [-10000,-20,20,10000]){
  const before=tools.defaults.slice(),after=tools.resizeWidths(before,index,delta);
  assert.equal(after.reduce((a,b)=>a+b,0),before.reduce((a,b)=>a+b,0));
  assert.ok(after.every(n=>n>=40&&n<=600));assert.deepEqual(before,tools.defaults);
 }
});

test('combined Broome release lists every exact stock or Toyota order in the subject and full details in the body',()=>{
 const rows=[{stock:'00123',order:'250000001',client:'Customer café',vehicle:'HiLux',transport_number:'000987'},{order:'0000456',client:'Second customer',vehicle:'Coaster'}];
 const draft=email.releaseTemplate(rows);assert.equal(draft.to,'amy.elkington@broometoyota.com.au');
 assert.equal(draft.subject,'Vehicles released to Broome - 00123, Toyota order 0000456');
 for(const text of ['00123','250000001','0000456','Customer café','Second customer','HiLux','Coaster','000987'])assert.ok(draft.body.includes(text),text);
 assert.match(draft.body,/Stock number: Awaiting allocation/);assert.throws(()=>email.releaseTemplate([]));
 const message=email.eml(draft,[],'release_fixture');assert.match(message,/^X-Unsent: 1\r\nTo: amy\.elkington@broometoyota\.com\.au\r\n/);
 const subject=[...message.matchAll(/=\?UTF-8\?B\?([^?]+)\?=/g)].map(m=>Buffer.from(m[1],'base64').toString('utf8')).join('');assert.equal(subject,draft.subject);
 const large=email.releaseTemplate(Array.from({length:40},(_,i)=>({stock:'QA-'+i,client:'Fictional',vehicle:'HiLux'})));
 const folded=email.eml(large,[],'large_release');assert.equal([...folded.matchAll(/=\?UTF-8\?B\?([^?]+)\?=/g)].map(m=>Buffer.from(m[1],'base64').toString('utf8')).join(''),large.subject);
});

test('release action uses all selected authorised rows once and resolves their real source details',()=>{
 const h=emailHarness(),rows=[{tracking_id:'own',stock:'1',client:'First',vehicle:'HiLux'},{tracking_id:'two',order:'002',client:'Second',vehicle:'Coaster'},{tracking_id:'other',stock:'3',client:'Not selected'}];
 h.setRows(rows);h.setSelected([{...rows[0],client:'Untrusted replacement'},rows[1],rows[0]]);h.ui.open('released','other');
 assert.equal(h.el('sales-email-to').value,'amy.elkington@broometoyota.com.au');assert.equal(h.el('sales-email-subject').value,'Vehicles released to Broome - 1, Toyota order 002');
 assert.match(h.el('sales-email-body').value,/First/);assert.match(h.el('sales-email-body').value,/Second/);assert.doesNotMatch(h.el('sales-email-body').value,/Not selected|Untrusted replacement/);
 assert.match(h.el('sales-email-title').textContent,/2 vehicles/);h.ui.open('update','other');assert.equal(h.el('sales-email-subject').value,'Request update - 3');assert.doesNotMatch(h.el('sales-email-body').value,/Second/);
 h.setSelected([]);h.ui.open('released','own');assert.equal(h.el('sales-email-subject').value,'Vehicle released to Broome - 1');
});

test('missing or ambiguous selected vehicles prevent a partial release email',()=>{
 const h=emailHarness(),own={tracking_id:'own',stock:'1'},two={tracking_id:'two',stock:'2'};
 h.setRows([own]);h.setSelected([own,two]);h.ui.open('released','own');assert.equal(h.el('sales-email').open,false);assert.match(h.errors[0],/no longer available/);
 h.setRows([own,{...two,identity_conflict:true}]);h.ui.open('released','own');assert.equal(h.el('sales-email-body').value,'');assert.equal(h.errors.length,2);
});

test('losing any batch vehicle or changing its source reference clears the entire release draft',()=>{
 const h=emailHarness(),rows=[{tracking_id:'own',stock:'1',order:'001'},{tracking_id:'two',stock:'2',order:'002'}];
 h.setRows(rows);h.setSelected(rows);h.ui.open('released','own');h.setRows([rows[0]]);h.ui.syncScope();assert.equal(h.el('sales-email').open,false);assert.equal(h.el('sales-email-subject').value,'');
 h.setRows(rows);h.ui.open('released','own');h.setRows([rows[0],{...rows[1],order:'003'}]);h.ui.syncScope();assert.equal(h.el('sales-email-body').value,'');
});

test('pending combined release download stops if a secondary vehicle loses access during attachment reads',async()=>{
 const h=emailHarness(),rows=[{tracking_id:'own',stock:'1'},{tracking_id:'two',stock:'2'}];h.setRows(rows);h.setSelected(rows);h.ui.open('released','own');let resolve;
 h.el('sales-email-files').files=[{name:'fixture.pdf',size:2,arrayBuffer:()=>new Promise(r=>resolve=r)}];
 const pending=h.el('sales-email-download').events.click();h.setRows([rows[0]]);h.ui.syncScope();resolve(Uint8Array.from([1,2]).buffer);await pending;
 assert.deepEqual(h.downloads,[]);assert.equal(h.el('sales-email-to').value,'');assert.equal(h.window.location.href,'');
});
