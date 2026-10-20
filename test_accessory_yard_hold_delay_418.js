'use strict';
// r418 (F33): "Delay until yard hold" on Not raised Sales accessory lines. Made-up POs and keys only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const acc=require('./sales/sales-accessories.js');
const K=n=>String(n).padStart(64,'0');
const line=(item,po,extra={})=>({group:'build',line:'1',item,type:'special',sublet:'',po,po_state:!po?'blank':/^PO\d+$/.test(po)?'po':'other',notes:'',in_house:false,line_key:'',delay:'none',...extra});
const record=(lines,extra={})=>acc.normaliseRecord({tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',quote:'',source_file:'Sales.xlsx',snapshot_at:null,
  derived:{build:{state:'red',reason:'po_not_raised'},tint:{state:'review',reason:'delayed_until_yard_hold'},tray:{state:'grey',reason:'not_on_quote'}},lines,...extra});
const view={editable:true,busy:new Set(),messages:new Map()};
const items=html=>[...html.matchAll(/<div class="sales-notes-accessory-item"><span>([^<]*)<\/span>/g)].map(m=>m[1]);
const heads=html=>[...html.matchAll(/data-po-group="([^"]*)">([^<]*)</g)].map(m=>m[2]);
const box=(html,key)=>(html.match(new RegExp('<input type="checkbox" data-accessory-delay="'+key+'"[^>]*>'))||[''])[0];

test('a delayed Not raised line is amber "Delayed – yard hold", grouped after Not raised, never red',()=>{
  const html=acc.notesLinesHtml(record([line('Tint','',{group:'tint',line_key:K(1),delay:'delayed'}),line('Mats','',{line_key:K(2)}),line('Canopy','PO100001',{line_key:K(3)})]),view);
  assert.deepEqual(items(html),['Canopy','Mats','Tint']);
  assert.deepEqual(heads(html),['PO100001 · 1 line','Not raised · 1 line','Delayed – yard hold · 1 line']);
  assert.match(html,/Tint<\/span><label class="sales-notes-delay"><input type="checkbox" data-accessory-delay="0+1" data-accessory-vehicle="t1" checked><span>Delay until yard hold<\/span><\/label><\/div><div class="sales-notes-accessory-po sales-notes-po-delayed">Delayed – yard hold<\/div>/);
  assert.match(box(html,K(2)),/^<input type="checkbox" data-accessory-delay="0+2" data-accessory-vehicle="t1">$/);
  assert.equal(box(html,K(3)),'','a line with a PO never gets the box');
  const css=fs.readFileSync('sales/sales-accessories.css','utf8');
  assert.match(css,/\.sales-notes-po-delayed\{[^}]*#fff4d6/);assert.doesNotMatch(css.match(/\.sales-notes-po-delayed\{[^}]*\}/)[0],/animation|fde2e2/);
});

test('at or past yard hold: no box to delay, a lifted delay shows red with the message, and the order row is flagged',()=>{
  const rec=record([line('Tint','',{group:'tint',line_key:K(1),delay:'lifted'}),line('Mats','',{line_key:K(2)})],{at_or_past_yard_hold:true,delay_lifted_lines:1});
  const html=acc.notesLinesHtml(rec,view);
  assert.equal(box(html,K(1)),'');assert.equal(box(html,K(2)),'');
  assert.match(html,/Tint<\/span><small class="sales-notes-delay-lifted" role="alert">Vehicle is at yard hold, delay removed, please raise the PO<\/small><\/div><div class="sales-notes-accessory-po sales-notes-po-red">Not raised<\/div>/);
  assert.deepEqual(heads(html),['Not raised · 2 lines']);
  assert.equal(acc.liftedMessage,'Vehicle is at yard hold, delay removed, please raise the PO');
});

test('no box without a server line key, without a view, or when the user cannot edit (the server checks again)',()=>{
  assert.doesNotMatch(acc.notesLinesHtml(record([line('Mats','')]),view),/<input/);
  assert.doesNotMatch(acc.notesLinesHtml(record([line('Mats','',{line_key:K(2)})])),/<input/);
  assert.match(box(acc.notesLinesHtml(record([line('Mats','',{line_key:K(2)})]),{...view,editable:false}),K(2)),/ disabled>$/);
  const bad=record([line('Mats','',{line_key:'not-a-key',delay:'sometimes'})]);
  assert.equal(bad.lines[0].line_key,'');assert.equal(bad.lines[0].delay,'none');
  assert.equal(bad.at_or_past_yard_hold,false);assert.equal(bad.delay_lifted_lines,0);
});

function harness(item){
  const calls=[],updates=[],listeners={};
  const host={PDC_AUTH_CONTEXT:{userId:'u'},addEventListener(){},document:{addEventListener(k,fn){listeners[k]=fn;}},
    PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  const row={tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',cosi:true,source_current:true,salesperson_code:'BG'};
  const api=acc.createSalesAccessories(host);
  api.init({getRows:()=>[row],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getToken:()=>'t',onUpdate:()=>updates.push(1)});
  const raw={tracking_id:'t1',navision_record_id:'n1',order:'00001',stock:'13000001',derived:{build:{state:'red'},tint:{state:'grey'},tray:{state:'grey'}},
    lines:[line('Mats','',{line_key:K(2)})],...item};
  return {api,calls,updates,listeners,row,raw};
}
const ready=async h=>{const p=h.api.refresh();h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[h.raw]}});await p;};

test('ticking saves through the invoker RPC with exact arguments, shows Saving…, then re-reads the server state',async()=>{
  const h=harness();await ready(h);
  const p=h.api.setDelay('t1',K(2),true);
  assert.deepEqual(h.calls.at(-1),{name:'set_broome_sales_accessory_delay',args:{p_tracking_id:'t1',p_line_key:K(2),p_delayed:true},resolve:h.calls.at(-1).resolve});
  assert.match(box(h.api.notesPanelHtml(h.row),K(2)),/ disabled>$/);assert.match(h.api.notesPanelHtml(h.row),/Saving…/);
  h.raw.lines=[line('Mats','',{line_key:K(2),delay:'delayed'})];h.raw.derived={build:{state:'review',reason:'delayed_until_yard_hold'},tint:{state:'grey'},tray:{state:'grey'}};
  h.calls.at(-1).resolve({data:{tracking_id:'t1',line_key:K(2),delayed:true,delay:'delayed'}});
  await new Promise(r=>setImmediate(r));
  assert.equal(h.calls.at(-1).name,'get_broome_sales_accessories');
  h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[h.raw]}});await p;
  const html=h.api.notesPanelHtml(h.row);
  assert.match(box(html,K(2)),/ checked>$/);assert.match(html,/sales-notes-po-delayed">Delayed – yard hold</);
  assert.deepEqual(h.api.tickFor(h.row,'build_po'),{state:'review',reason:'delayed_until_yard_hold'});
});

test('a refused delay shows the server message and keeps the line as the server has it',async()=>{
  const h=harness();await ready(h);
  const p=h.api.setDelay('t1',K(2),true);
  h.calls.at(-1).resolve({error:{message:'Vehicle is at yard hold, delay removed, please raise the PO'}});
  await new Promise(r=>setImmediate(r));h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[h.raw]}});await p;
  const html=h.api.notesPanelHtml(h.row);
  assert.match(html,/<small class="sales-notes-delay-error" role="alert">Vehicle is at yard hold, delay removed, please raise the PO<\/small>/);
  assert.doesNotMatch(box(html,K(2)),/checked/);assert.match(html,/sales-notes-po-red">Not raised</);
  // An unconfirmed answer is an error too.
  const q=h.api.setDelay('t1',K(2),true);h.calls.at(-1).resolve({data:{tracking_id:'t1',line_key:K(2),delayed:false}});
  await new Promise(r=>setImmediate(r));h.calls.at(-1).resolve({data:{context:{role:'salesperson'},items:[h.raw]}});await q;
  assert.match(h.api.notesPanelHtml(h.row),/could not be confirmed/);
});

test('the box change is never optimistic, and unknown lines are ignored',async()=>{
  const h=harness();await ready(h);
  const target={checked:true,dataset:{accessoryVehicle:'t1',accessoryDelay:K(2)},closest(){return this;}};
  h.listeners.change({target});assert.equal(target.checked,false,'shown from the server answer only');
  assert.equal(h.calls.at(-1).name,'set_broome_sales_accessory_delay');
  const before=h.calls.length;await h.api.setDelay('t1',K(9),true);assert.equal(h.calls.length,before);
  h.listeners.change({target:{closest(){return null;}}});assert.equal(h.calls.length,before);
});

test('order row flag only when a delay has lifted, and the tick label explains the amber state',async()=>{
  const h=harness({delay_lifted_lines:1,at_or_past_yard_hold:true});await ready(h);
  assert.equal(h.api.rowFlagHtml(h.row),'<span class="sales-yard-hold-flag" role="status" title="Vehicle is at yard hold, delay removed, please raise the PO">Raise PO · at yard hold</span>');
  const g=harness();await ready(g);assert.equal(g.api.rowFlagHtml(g.row),'');
  const sales=require('./sales/sales.js'),src=fs.readFileSync('sales/sales.js','utf8');
  global.BROOME_SALES_ACCESSORIES={tickFor:()=>({state:'review',reason:'delayed_until_yard_hold'})};
  try{
    const html=sales.orderingControl({tracking_id:'t1',stock:'13000001'},'tint');
    assert.match(html,/class="ordering-status derived-review"/);assert.match(html,/Delayed until yard hold/);assert.doesNotMatch(html,/derived-red|PO not raised/);
  }finally{delete global.BROOME_SALES_ACCESSORIES;}
  assert.equal((src.match(/BROOME_SALES_ACCESSORIES\?\.rowFlagHtml\?\.\(row\)/g)||[]).length,2,'desktop and phone rows');
});

test('the delay box never becomes an unsaved notes draft, and the notes panel passes who may edit',()=>{
  const notes=fs.readFileSync('sales/vehicle-notes.js','utf8');
  assert.match(notes,/addEventListener\('input',event=>\{if\(event\.target\?\.matches\?\.\('\[data-accessory-delay\]'\)\)return;capture/);
  assert.match(notes,/notesPanelHtml\?\.\(row,\{editable:editable\(id\)\}\)/);
  const {create}=require('./sales/vehicle-notes.js'),els=new Map();
  const el=id=>{if(!els.has(id))els.set(id,{events:{},addEventListener(k,fn){this.events[k]=fn;}});return els.get(id);};
  const row={tracking_id:'t1',order:'00001',stock:'1'};let captured=0;
  const host={PDC_AUTH_CONTEXT:{userId:'u'},document:{getElementById:el},addEventListener(){},PDC_SUPABASE:{rpc:()=>new Promise(()=>{})}};
  create(host).init({getRows:()=>[row],getVisibleRows:()=>[row],getScope:()=>'',canEditRow:()=>true,isHidden:()=>false,onChanged(){}});
  el('vehicle-table').events.input({target:{matches:s=>s==='[data-accessory-delay]',closest(){captured++;return null;}}});
  assert.equal(captured,0);
});

test('migration: RLS table, invoker RPC, same access as Sales notes, yard hold trigger, pins, check and an exact undo',()=>{
  const up=fs.readFileSync('supabase/migrations/20261020233912_r418_accessory_yard_hold_delay.sql','utf8');
  const down=fs.readFileSync('supabase/rollbacks/20261020233912_r418_accessory_yard_hold_delay.down.sql','utf8');
  assert.match(up,/cdsmnqxtyyoeoznmbidd/);assert.doesNotMatch(up+down,/vjdtsswhroyguxyfjdkt/);
  assert.match(up,/ALTER TABLE pdc_sales_private\.sales_accessory_line_delays ENABLE ROW LEVEL SECURITY;/);
  assert.match(up,/CREATE POLICY sales_accessory_line_delays_rpc_only ON pdc_sales_private\.sales_accessory_line_delays FOR ALL USING \(false\) WITH CHECK \(false\);/);
  assert.match(up,/REVOKE ALL ON pdc_sales_private\.sales_accessory_line_delays FROM PUBLIC, anon, authenticated, service_role;/);
  assert.match(up,/CREATE FUNCTION public\.set_broome_sales_accessory_delay\(p_tracking_id uuid, p_line_key text, p_delayed boolean\)\nRETURNS jsonb LANGUAGE sql SECURITY INVOKER/);
  assert.match(up,/GRANT EXECUTE ON FUNCTION public\.set_broome_sales_accessory_delay\(uuid,text,boolean\) TO authenticated;/);
  assert.doesNotMatch(up,/GRANT [^;]* TO anon/);
  // Same access check as save_vehicle_notes: crm_context() and visibility_source_snapshot(false) without an identity conflict.
  assert.match(up,/ctx jsonb:=pdc_sales_private\.crm_context\(\)[\s\S]*visibility_source_snapshot\(false\)->'items'\) e\s+WHERE e->>'tracking_id'=p_tracking_id::text AND NOT coalesce\(\(e->>'identity_conflict'\)::boolean,false\)/);
  assert.match(up,/IF v_line\.po_state<>'blank' THEN RAISE EXCEPTION/);
  assert.match(up,/RAISE EXCEPTION 'Vehicle is at yard hold, delay removed, please raise the PO';/);
  assert.match(up,/SELECT upper\(btrim\(coalesce\(p_location,''\)\)\) IN \('YH','PMB','PIT','QC','RFT','COMPLETED'\) OR coalesce\(btrim\(p_pmb_arrival\),''\)<>''/);
  assert.match(up,/accessory_delay_lifted\(e->>'pmb_location',e->>'pmb_arrival_date'\) THEN 'lifted' ELSE 'delayed'/);
  assert.match(up,/WHEN base\.t->d\.c->>'state' IN \('green','grey'\) THEN \(base\.t->d\.c\)\|\|jsonb_build_object\('state','review','reason','delayed_until_yard_hold'/);
  assert.match(up,/INSERT INTO pdc_sales_private\.crm_audit\(record_id,kind,actor_id,before_data,after_data\)\s+VALUES\(p_tracking_id,'accessory_delay'/);
  assert.match(up,/'accessory_delay_lifts_at_yard_hold','F32'[\s\S]*\$chk\$,true,220,'r418'\);/);
  assert.match(up,/get_accessories\(\)','49f6feab0ef97e1f515cf9d8c5de4fd9'|prosrc_md5='ef91622d497528866f09537887c4a199'/);
  assert.match(up,/NOT BETWEEN 2 AND 45/);assert.match(down,/NOT BETWEEN 2 AND 45/);
  assert.match(down,/<>'49f6feab0ef97e1f515cf9d8c5de4fd9' THEN RAISE EXCEPTION 'r418 undo: get_accessories not restored'/);
  assert.match(down,/'accessory_delay_undo'/);assert.match(down,/DROP TABLE pdc_sales_private\.sales_accessory_line_delays;/);
  // The undo puts back the r394 body byte for byte: the old body has no delay code.
  const body=down.match(/CREATE OR REPLACE FUNCTION pdc_sales_private\.get_accessories\(\)[\s\S]*?END \$function\$;/)[0];
  assert.doesNotMatch(body,/delay|line_key/);assert.match(body,/pdc_sales_private\.sales_accessory_ticks\(coalesce\(jsonb_agg\(jsonb_build_object\('line_class',l\.line_class,'po_state',l\.po_state\)\)/);
  const log=fs.readFileSync('docs/FAULT_LOG.md','utf8');
  assert.match(log,/\| F33 \| 21 Oct 07:39 \| Craig \(feature request\) \|[^\n]*20261020233912[^\n]*accessory_delay_lifts_at_yard_hold/);
});
