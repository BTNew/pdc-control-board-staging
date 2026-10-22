/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r486 (F99): no 'Raise PO · at yard hold' flag under the stock number on the Sales list; the red BUILD / TINT / TRAY tick stays.
// Made-up keys, POs and stock only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const acc=require('./sales/sales-accessories.js');
const K=n=>String(n).padStart(64,'0');
const line=(item,extra={})=>({group:'build',line:'1',item,type:'special',sublet:'',po:'',po_state:'blank',notes:'',in_house:false,line_key:'',delay:'none',...extra});
const raw=(lines,extra={})=>({tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',quote:'',source_file:'Sales.xlsx',snapshot_at:null,
  derived:{build:{state:'review',reason:'delayed_until_yard_hold'},tint:{state:'review',reason:'delayed_until_yard_hold'},tray:{state:'grey',reason:'not_on_quote'}},lines,...extra});
function harness(row){
  const calls=[];
  const host={PDC_AUTH_CONTEXT:{userId:'u'},addEventListener(){},document:{addEventListener(){}},
    PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  const full={tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',cosi:true,source_current:true,salesperson_code:'BG',...row};
  const api=acc.createSalesAccessories(host);
  api.init({getRows:()=>[full],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getToken:()=>'t',onUpdate(){}});
  return {api,calls,row:full};
}
const ready=async(h,record)=>{const p=h.api.refresh();h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[record]}});await p;};
const lifted=[line('Telematics',{line_key:K(1),delay:'delayed'}),line('Tint',{group:'tint',line_key:K(2),delay:'delayed'})];

test('past yard hold with no PO: no row flag anywhere, but BUILD and TINT ticks turn red',async()=>{
  const h=harness({location_status:'OD',toyota_status:'Delivered - At Body Builder',pmb_location:null});
  await ready(h,raw(lifted,{delay_lifted_lines:2,at_or_past_yard_hold:true}));
  assert.equal(h.api.rowFlagHtml,undefined,'the row flag API is gone');
  assert.equal(Object.values(h.api).some(fn=>typeof fn==='function'&&/sales-yard-hold-flag|Raise PO · at yard hold/.test(String(fn))),false);
  assert.deepEqual(h.api.tickFor(h.row,'build_po'),{state:'red',reason:'po_not_raised'});
  assert.deepEqual(h.api.tickFor(h.row,'tint'),{state:'red',reason:'po_not_raised'});
  assert.deepEqual(h.api.tickFor(h.row,'tray_ordered'),{state:'grey',reason:'not_on_quote'});
});

test('before yard hold the delay logic is unchanged: amber tick, delay still sent to the server',async()=>{
  const h=harness({location_status:'IT',toyota_status:'In Transit To WA',pmb_location:'IT'});
  await ready(h,raw([line('Telematics',{line_key:K(1),delay:'delayed'}),line('Mats',{line_key:K(3)})]));
  assert.deepEqual(h.api.tickFor(h.row,'build_po'),{state:'review',reason:'delayed_until_yard_hold'});
  void h.api.setDelay('t1',K(3),true);
  assert.equal(h.calls.at(-1).name,'set_broome_sales_accessory_delay');
});

test('the Sales list renders the red tick, and neither desktop nor phone rows call a row flag',()=>{
  const src=fs.readFileSync('sales/sales.js','utf8');
  assert.doesNotMatch(src,/rowFlagHtml|sales-yard-hold-flag|Raise PO · at yard hold/);
  const sales=require('./sales/sales.js');
  global.BROOME_SALES_ACCESSORIES={tickFor:()=>({state:'red',reason:'po_not_raised'})};
  try{
    const html=sales.orderingControl({tracking_id:'t1',stock:'13000001'},'build_po');
    assert.match(html,/derived-red/);assert.doesNotMatch(html,/sales-yard-hold-flag/);
  }finally{delete global.BROOME_SALES_ACCESSORIES;}
});

test('dead CSS removed, notes panel message kept, cache bust and FAULT_LOG row',()=>{
  const css=fs.readFileSync('sales/sales-accessories.css','utf8'),js=fs.readFileSync('sales/sales-accessories.js','utf8');
  assert.doesNotMatch(css+js,/sales-yard-hold-flag|Raise PO · at yard hold/);
  assert.match(css,/\.sales-notes-delay-lifted/,'per-line notes panel message styling stays');
  assert.match(js,/sales-notes-delay-lifted/,'per-line notes panel message stays');
  const html=fs.readFileSync('sales/index.html','utf8');
  assert.match(html,/sales-accessories\.css\?[^"]*no-yard-flag=2026\.10\.22\.r486"/);
  assert.match(html,/sales-accessories\.js\?[^"]*no-yard-flag=2026\.10\.22\.r486"/);
  assert.match(html,/src="sales\.js\?[^"]*no-yard-flag=2026\.10\.22\.r486"/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md','utf8'),/^\| F99 \| 22 Oct 15:22 \|[^\n]*r486[^\n]*test_r486_no_yard_hold_flag\.js/m);
});
