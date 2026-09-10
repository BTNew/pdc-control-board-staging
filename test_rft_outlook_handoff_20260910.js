'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {openOutlook,outlookBody}=require('./pdc-rft-actions.js');
const prepared={recipient_email:'sales+test@example.invalid',subject:'RFT & ready – TEST',
 text:'Ready for transport.\n- Tow bar (2.33 h)\n\nThe QC completion photo is attached.\n\nKind regards,\nPMB',
 photo:new Uint8Array([1,2,3]),photoType:'image/png'};
test('Outlook handoff encodes recipient, subject and complete body without extra headers',()=>{
 const requests=[];
 const url=openOutlook(prepared,x=>requests.push(x));
 assert.deepEqual(requests,[url]);
 const parsed=new URL(url);
 assert.equal(parsed.protocol,'mailto:');
 assert.equal(decodeURIComponent(parsed.pathname),prepared.recipient_email);
 assert.equal(parsed.searchParams.get('subject'),prepared.subject);
 assert.equal(parsed.searchParams.get('body'),outlookBody(prepared));
 assert.deepEqual([...parsed.searchParams.keys()],['subject','body']);
 assert.match(parsed.searchParams.get('body'),/Tow bar \(2.33 h\)/);
 assert.doesNotMatch(parsed.searchParams.get('body'),/photo is attached/);
 assert.match(prepared.text,/photo is attached/); // saved receipt remains untouched
});
test('missing or multiline recipient never opens a compose window',()=>{
 for(const recipient_email of ['', 'sales@example.invalid\r\nbcc:other@example.invalid']){
  assert.throws(()=>openOutlook({...prepared,recipient_email},()=>assert.fail('must not launch')),/email is required/);
 }
});
function harness(){
 const source=fs.readFileSync('pdc-rft-actions.js','utf8');
 const elements=new Map(['pre','img','.rft-email-copy-photo','.rft-email-open-file','.rft-email-open-note'].map(x=>[x,{}]));
 const content={innerHTML:'',removeAttribute(){},querySelector:x=>elements.get(x)};
 const dialog={open:true,querySelector:()=>content};
 const requests=[];
 const ctx={dialog,currentView:null,outlookBody,esc:x=>x,icon:()=>'',btoa:x=>Buffer.from(x,'binary').toString('base64'),
  openOutlook:p=>requests.push(p),copyPhoto:()=>{ctx.copied=true;}};
 vm.createContext(ctx);
 vm.runInContext(source.slice(source.indexOf('  function showPrepared('),source.indexOf('  function message(')),ctx);
 return {ctx,dialog,content,elements,requests};
}
test('verified preview requests Outlook automatically and can reopen it without downloading',()=>{
 const h=harness();
 assert.equal(h.ctx.showPrepared(h.dialog,prepared),true);
 assert.equal(h.requests.length,1);
 assert.equal(h.requests[0],prepared);
 assert.doesNotMatch(h.content.innerHTML,/\.eml|Downloads|photo attached/);
 assert.match(h.content.innerHTML,/Copy QC photo/);
 h.elements.get('.rft-email-open-file').onclick();
 assert.equal(h.requests.length,2);
 h.elements.get('.rft-email-copy-photo').onclick();
 assert.equal(h.ctx.copied,true);
 h.ctx.currentView=null;
 h.elements.get('.rft-email-open-file').onclick();
 assert.equal(h.requests.length,2);
});
test('dismissed or replaced preview never launches Outlook',()=>{
 const h=harness();
 h.dialog.open=false;
 assert.equal(h.ctx.showPrepared(h.dialog,prepared),false);
 assert.equal(h.ctx.showPrepared({open:true},prepared),false);
 assert.equal(h.requests.length,0);
});
test('copy photo writes PNG to clipboard only on request and reports paste instruction',async()=>{
 const source=fs.readFileSync('pdc-rft-actions.js','utf8');
 let writes=0;
 const ctx={navigator:{clipboard:{write:async items=>{writes++;assert.equal(await items[0].data['image/png'],'png-fixture');}}},
  ClipboardItem:class{constructor(data){this.data=data;}},
  document:{createElement:()=>({getContext:()=>({drawImage(){}}),toBlob:fn=>fn('png-fixture')})}};
 vm.createContext(ctx);
 vm.runInContext(source.slice(source.indexOf('  async function copyPhoto('),source.indexOf('  function showPrepared(')),ctx);
 assert.equal(writes,0);
 const notice={};
 await ctx.copyPhoto({complete:true,naturalWidth:4,naturalHeight:3},notice);
 assert.equal(writes,1);
 assert.match(notice.textContent,/Photo copied.*Ctrl\+V/);
});
test('clipboard denial offers a manual copy fallback without claiming success',async()=>{
 const source=fs.readFileSync('pdc-rft-actions.js','utf8');
 const ctx={navigator:{}};
 vm.createContext(ctx);
 vm.runInContext(source.slice(source.indexOf('  async function copyPhoto('),source.indexOf('  function showPrepared(')),ctx);
 const notice={};
 await ctx.copyPhoto({},notice);
 assert.match(notice.textContent,/Right-click the photo/);
 assert.doesNotMatch(notice.textContent,/Photo copied/);
});
