'use strict';
// r427 (F40): yard hold follows the whole stage order, not only the board location. Made-up keys, POs and stock only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const acc=require('./sales/sales-accessories.js');
const K=n=>String(n).padStart(64,'0');
const line=(item,extra={})=>({group:'build',line:'1',item,type:'special',sublet:'',po:'',po_state:'blank',notes:'',in_house:false,line_key:'',delay:'none',...extra});
const raw=(lines,extra={})=>({tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',quote:'',source_file:'Sales.xlsx',snapshot_at:null,
  derived:{build:{state:'review',reason:'delayed_until_yard_hold'},tint:{state:'grey',reason:'not_on_quote'},tray:{state:'grey',reason:'not_on_quote'}},lines,...extra});
const view={editable:true,busy:new Set(),messages:new Map()};
const box=(html,key)=>(html.match(new RegExp('<input type="checkbox" data-accessory-delay="'+key+'"[^>]*>'))||[''])[0];
const migration=fs.readFileSync('supabase/migrations/20261021014735_r427_yard_hold_post_stages.sql','utf8');

test('the screen uses the same stage order as the server: every regression-check case agrees',()=>{
  const cases=[...migration.matchAll(/\('(\{[^']*\})'(?:::jsonb)?,(true|false)\)/g)].map(m=>[JSON.parse(m[1]),m[2]==='true']);
  assert.equal(cases.length,40);
  for(const [row,want] of cases)assert.equal(acc.atOrPastYardHold(row),want,JSON.stringify(row));
});

test('OD, OC and every Y? yard code are at or past yard hold even with no board location; production and transit are not',()=>{
  for(const code of ['YH','YN','YR','YW','OD','OC','od',' OD '])assert.equal(acc.atOrPastYardHold({location_status:code}),true,code);
  for(const code of ['','IT'])assert.equal(acc.atOrPastYardHold({location_status:code}),false,code);
  assert.deepEqual(['','IT','YN','OD'].map(code=>acc.yardHoldStageRank(code,'')),[0,1,2,3]);
  assert.equal(acc.atOrPastYardHold({location_status:'OD',toyota_status:'Delivered - At Body Builder',pmb_location:null}),true);
  assert.equal(acc.atOrPastYardHold({location_status:'OD',pmb_location:'IT'}),true,'Navision past the yard beats a stale board IT');
  assert.equal(acc.atOrPastYardHold(null),false);
});

test('a row past yard hold: no delay box, a stored delay reads lifted and red with the message',()=>{
  const rec=acc.normaliseRecord(raw([line('Telematics',{line_key:K(1),delay:'delayed'}),line('Transport',{group:'admin',line_key:K(2),delay:'delayed'}),line('Mats',{line_key:K(3)})]));
  const html=acc.notesLinesHtml(rec,{...view,row_past_yard_hold:true});
  for(const n of [1,2,3])assert.equal(box(html,K(n)),'',String(n));
  assert.doesNotMatch(html,/sales-notes-po-delayed|Delayed – yard hold/);
  assert.equal(html.match(/Vehicle is at yard hold, delay removed, please raise the PO/g).length,2);
  assert.match(html,/Telematics<\/span><small class="sales-notes-delay-lifted" role="alert">Vehicle is at yard hold, delay removed, please raise the PO<\/small><\/div><div class="sales-notes-accessory-po sales-notes-po-red">Not raised<\/div>/);
  // Before yard hold nothing changes: the box is offered and the delayed line stays amber.
  const before=acc.notesLinesHtml(rec,{...view,row_past_yard_hold:false});
  assert.match(box(before,K(1)),/ checked>$/);assert.match(box(before,K(3)),/^<input type="checkbox" data-accessory-delay="0+3" data-accessory-vehicle="t1">$/);
  assert.match(before,/sales-notes-po-delayed">Delayed – yard hold/);
  // The server's flag alone also hides the box on a delayed line (r418 only hid it on red lines).
  assert.equal(box(acc.notesLinesHtml(acc.normaliseRecord(raw([line('Tint',{group:'tint',line_key:K(4),delay:'delayed'})],{at_or_past_yard_hold:true})),view),K(4)),'');
});

function harness(row){
  const calls=[],listeners={};
  const host={PDC_AUTH_CONTEXT:{userId:'u'},addEventListener(){},document:{addEventListener(k,fn){listeners[k]=fn;}},
    PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  const full={tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',cosi:true,source_current:true,salesperson_code:'BG',...row};
  const api=acc.createSalesAccessories(host);
  api.init({getRows:()=>[full],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getToken:()=>'t',onUpdate(){}});
  return {api,calls,row:full};
}
const ready=async(h,record)=>{const p=h.api.refresh();h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[record]}});await p;};

test('past yard hold on the row: the panel, the tick and the order flag all show the PO is due, and no new delay is sent',async()=>{
  const h=harness({location_status:'OD',toyota_status:'Delivered - At Body Builder',pmb_location:null});
  await ready(h,raw([line('Telematics',{line_key:K(1),delay:'delayed'}),line('Mats',{line_key:K(3)})]));
  const html=h.api.notesPanelHtml(h.row);
  assert.equal(box(html,K(1)),'');assert.equal(box(html,K(3)),'');
  assert.match(html,/please raise the PO/);
  assert.deepEqual(h.api.tickFor(h.row,'build_po'),{state:'red',reason:'po_not_raised'});
  assert.deepEqual(h.api.tickFor(h.row,'tint'),{state:'grey',reason:'not_on_quote'});
  assert.match(h.api.rowFlagHtml(h.row),/Raise PO · at yard hold/);
  const sent=h.calls.length;await h.api.setDelay('t1',K(3),true);
  assert.equal(h.calls.length,sent,'no RPC for a new delay past yard hold');
  assert.match(h.api.notesPanelHtml(h.row),/please raise the PO/);
});

test('before yard hold the r418 behaviour is unchanged: amber tick, no order flag, the delay is sent to the server',async()=>{
  const h=harness({location_status:'IT',toyota_status:'In Transit To WA',pmb_location:'IT'});
  await ready(h,raw([line('Telematics',{line_key:K(1),delay:'delayed'}),line('Mats',{line_key:K(3)})]));
  assert.deepEqual(h.api.tickFor(h.row,'build_po'),{state:'review',reason:'delayed_until_yard_hold'});
  assert.equal(h.api.rowFlagHtml(h.row),'');
  const p=h.api.setDelay('t1',K(3),true);
  assert.equal(h.calls.at(-1).name,'set_broome_sales_accessory_delay');
  h.calls.at(-1).resolve({data:{tracking_id:'t1',line_key:K(3),delayed:true,delay:'delayed'}});
  await new Promise(r=>setImmediate(r));h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[raw([line('Mats',{line_key:K(3),delay:'delayed'})])]}});await p;
});

test('the release is wired: cache bust, migration and rollback pair, and the FAULT_LOG row',()=>{
  assert.match(fs.readFileSync('sales/index.html','utf8'),/sales-accessories\.js\?[^"]*yard-stage=2026\.10\.21\.04"/);
  assert.match(migration,/accessory_yard_hold_reached\(e\)/);
  assert.match(fs.readFileSync('supabase/rollbacks/20261021014735_r427_yard_hold_post_stages.down.sql','utf8'),/DROP FUNCTION pdc_sales_private\.accessory_yard_hold_reached\(jsonb\)/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md','utf8'),/^\| F40 \| 21 Oct 09:47 \|/m);
});
