'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {create}=require('./sales/vehicle-notes.js');
const {vehicleReference,selectRows}=require('./sales/sales.js');
function harness(){
 const elements=new Map(),events={},calls=[];let renders=0,scope='',hidden=false;
 const rows=[{tracking_id:'own',cosi:true,salesperson_code:'BG',order:'250026008',stock:''},{tracking_id:'second',cosi:true,salesperson_code:'BG',order:'000025001',stock:'1301'}];
 let visible=[rows[0]];
 const el=id=>{if(!elements.has(id))elements.set(id,{events:{},addEventListener(k,fn){this.events[k]=fn;}});return elements.get(id);};
 const host={PDC_AUTH_CONTEXT:{userId:'A'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},document:{getElementById:el},addEventListener(k,fn){events[k]=fn;}};
 const api=create(host).init({getRows:()=>rows,getVisibleRows:()=>visible,getScope:()=>scope,isHidden:()=>hidden,reference:vehicleReference,onChanged:()=>renders++});
 const click=(selector,data)=>el('vehicle-table').events.click({target:{closest:s=>s===selector?{dataset:data}:null}});
 const form=(notes='Working notes',custom='Customer requires morning handover')=>({dataset:{notesForm:'own'},elements:{namedItem:name=>({value:name==='notes'?notes:custom})},querySelector:()=>({textContent:''}),closest(){return this;}});
 const input=f=>el('vehicle-table').events.input({target:{closest:()=>f}});
 const save=f=>el('vehicle-table').events.submit({target:f,preventDefault(){}});
 return {api,host,el,events,calls,rows,click,form,input,save,setScope:v=>scope=v,setVisible:v=>visible=v,setHidden:v=>hidden=v,renders:()=>renders};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const saved=(version=1,notes='Working notes',custom='Customer requires morning handover')=>({tracking_id:'own',notes,custom_information:custom,version,updated_at:'2026-10-05T03:00:00Z'});
async function ready(h,data=[]){const p=h.api.load();h.calls[0].resolve({data});await p;}
test('Toyota Order Number remains an exact reference and searchable until Batch arrives',()=>{
 const row={stock:'',order:'250026008',cosi:true,salesperson_code:'BG'};
 assert.equal(vehicleReference(row),'Toyota Order 250026008');
 assert.equal(selectRows([row],{category:'all',search:'250026008',sort:'stock',direction:1})[0],row);
 assert.equal(vehicleReference({...row,stock:'1309001'}),'Stock 1309001');
 assert.equal(vehicleReference({...row,order:'000250026008'}),'Toyota Order 000250026008');
 assert.equal(row.stock,'');
});
test('Expand all opens only the currently filtered rows and Collapse all preserves drafts',async()=>{
 const h=harness();await ready(h);h.el('sales-expand-notes').events.click();
 assert.match(h.api.rowHtml(h.rows[0]),/Vehicle notes/);assert.equal(h.api.rowHtml(h.rows[1]),'');
 h.input(h.form('Draft before collapsing'));h.el('sales-collapse-notes').events.click();assert.equal(h.api.rowHtml(h.rows[0]),'');
 h.click('[data-notes-toggle]',{notesToggle:'own'});assert.match(h.api.rowHtml(h.rows[0]),/Draft before collapsing/);
});
test('clicking row or using keyboard opens notes, while other controls keep their actions',async()=>{
 const h=harness();await ready(h);h.click('[data-note-row]',{noteRow:'own'});assert.match(h.api.rowHtml(h.rows[0]),/Toyota Order 250026008/);
 h.el('vehicle-table').events.click({target:{closest:s=>s==='button,input,select,textarea,a,label,[data-resize]'?{}:null}});assert.match(h.api.rowHtml(h.rows[0]),/Vehicle notes/);
 h.el('vehicle-table').events.keydown({key:'Enter',target:{matches:()=>true,dataset:{noteRow:'own'}},preventDefault(){}});assert.equal(h.api.rowHtml(h.rows[0]),'');
});
test('save persists both fields through the scoped RPC and disables duplicate submissions',async()=>{
 const h=harness();await ready(h);h.click('[data-notes-toggle]',{notesToggle:'own'});const f=h.form();h.save(f);h.save(f);
 assert.equal(h.calls.length,2);assert.deepEqual(h.calls[1].args,{p_tracking_id:'own',p_notes:'Working notes',p_custom_information:'Customer requires morning handover',p_expected_version:0});
 assert.match(h.api.rowHtml(h.rows[0]),/Saving…/);h.calls[1].resolve({data:saved()});await tick();assert.match(h.api.rowHtml(h.rows[0]),/Notes saved\./);
});
test('save conflict keeps the typed draft and requires an explicit reload',async()=>{
 const h=harness();await ready(h,[saved()]);h.click('[data-notes-toggle]',{notesToggle:'own'});h.save(h.form('My unsaved edit'));
 h.calls[1].resolve({error:{message:'Notes changed elsewhere'}});await tick();assert.match(h.api.rowHtml(h.rows[0]),/My unsaved edit/);assert.match(h.api.rowHtml(h.rows[0]),/draft is kept/);
 h.click('[data-notes-reload]',{notesReload:'own'});h.calls[2].resolve({data:[saved(2,'Other user edit')]});await tick();assert.match(h.api.rowHtml(h.rows[0]),/Other user edit/);assert.doesNotMatch(h.api.rowHtml(h.rows[0]),/My unsaved edit/);
});
test('failed or malformed saves preserve draft and retries carry the same expected version',async()=>{
 const h=harness();await ready(h);h.click('[data-notes-toggle]',{notesToggle:'own'});h.save(h.form());h.calls[1].resolve({data:{...saved(),tracking_id:'other'}});await tick();
 assert.match(h.api.rowHtml(h.rows[0]),/could not be confirmed/);h.save(h.form());assert.equal(h.calls[2].args.p_expected_version,0);h.calls[2].resolve({data:saved()});await tick();assert.match(h.api.rowHtml(h.rows[0]),/Notes saved\./);
});
test('background load preserves drafts, expansion and newer confirmed save versions',async()=>{
 const h=harness();await ready(h,[saved()]);h.click('[data-notes-toggle]',{notesToggle:'own'});h.input(h.form('Typing during refresh'));
 const p=h.api.load();h.calls[1].resolve({data:[saved(2,'New saved text')]});await p;assert.match(h.api.rowHtml(h.rows[0]),/Typing during refresh/);
 h.save(h.form('Typing during refresh'));assert.equal(h.calls[2].args.p_expected_version,1);h.calls[2].resolve({error:{message:'Version conflict'}});await tick();
});
test('Batch allocation keeps the same note editor and exact order identity',async()=>{
 const h=harness();await ready(h,[saved()]);h.click('[data-notes-toggle]',{notesToggle:'own'});h.rows[0].stock='1309001';h.api.syncScope();
 assert.match(h.api.rowHtml(h.rows[0]),/Stock 1309001/);assert.match(h.api.rowHtml(h.rows[0]),/Working notes/);assert.equal(h.rows[0].order,'250026008');
});
test('sign-out and salesperson changes clear customer notes and ignore delayed saves',async()=>{
 const h=harness();await ready(h);h.click('[data-notes-toggle]',{notesToggle:'own'});h.save(h.form('Private draft'));
 delete h.host.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();h.calls[1].resolve({data:saved(1,'Private draft')});await tick();assert.equal(h.api.rowHtml(h.rows[0]),'');
 h.host.PDC_AUTH_CONTEXT={userId:'A'};await h.api.syncScope();h.click('[data-notes-toggle]',{notesToggle:'own'});h.setScope('PM');h.api.syncScope();assert.equal(h.api.rowHtml(h.rows[0]),'');
});
test('note text is escaped and hidden/conflicting rows cannot be expanded',async()=>{
 const h=harness();await ready(h,[saved(1,'<script>alert(1)</script>','<img onerror=bad>')]);h.click('[data-notes-toggle]',{notesToggle:'own'});
 const html=h.api.rowHtml(h.rows[0]);assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>|<img/);
 h.el('sales-collapse-notes').events.click();h.rows[0].identity_conflict=true;h.click('[data-notes-toggle]',{notesToggle:'own'});assert.equal(h.api.rowHtml(h.rows[0]),'');h.rows[0].identity_conflict=false;h.setHidden(true);h.el('sales-expand-notes').events.click();assert.equal(h.api.rowHtml(h.rows[0]),'');
});
