const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const acc=require('./sales/sales-accessories.js');
const line=(group,po='PO1',extra={})=>({group,line:'1',item:group+' item',type:'accessory',sublet:'SUB',po,po_state:po?(/^PO\d+$/.test(po)?'po':'cs_only'):'blank',notes:'',in_house:false,...extra});
const record=(patch={})=>({tracking_id:'bg',navision_record_id:'source-bg',order:'00001',stock:'13001',quote:'47439',source_file:'Sales.xlsx',snapshot_at:'2026-10-20T07:12:00Z',
  derived:{build:{state:'red',reason:'po_not_raised'},tint:{state:'grey',reason:'not_on_quote'},tray:{state:'green',reason:'po_raised'}},
  lines:[line('build',''),line('build','PO11205500'),line('tray','PO2'),line('admin','',{item:'Freight'})],...patch});
const row={tracking_id:'bg',navision_record_id:'source-bg',order:'00001',stock:'13001',cosi:true,source_current:true,salesperson_code:'BG'};
function harness(){
  const calls=[],updates=[];
  const host={PDC_AUTH_CONTEXT:{userId:'u'},addEventListener(){},PDC_SUPABASE:{rpc(name){return new Promise(resolve=>calls.push({name,resolve}));}}};
  const api=acc.createSalesAccessories(host);const rows=[{...row}];
  api.init({getRows:()=>rows,getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getSalesperson:()=>'',getToken:()=>'t',onUpdate:()=>updates.push(1)});
  return {api,calls,updates,rows,host};
}
test('r417: notes panel shows one PO-grouped list across every accessory type, with Admin always visible',()=>{
  const html=acc.notesLinesHtml(acc.normaliseRecord(record({lines:[
    line('build','PO1',{type:'special',item:'Sublet winch',notes:'Fit before delivery'}),
    line('tray','',{type:'miscacc',item:'Misc mat'}),
    line('tint','PO9',{type:'Aftermarket',item:'Snorkel'}),
    line('build','C&S ONLY',{type:'Accessory',item:'Canopy',notes:'Black'}),
    line('tray','SELL ONLY',{type:'accessory',item:'Towbar',po_state:'sell_only'}),
    line('tint','NO UPDATE',{type:'aftermarket',item:'Lid',po_state:'no_update'}),
    line('build','',{type:'',item:'Blank type'}),
    line('tray','WEIRD',{type:'paint',item:'Custom paint',po_state:'other'}),
    line('admin','',{type:'accessory',item:'Freight'})
  ]})));
  const order=['Sublet winch','Snorkel','Canopy','>Lid<','Towbar','Custom paint','Misc mat','Blank type'].map(item=>html.indexOf(item));
  assert.ok(order.every((at,i)=>at>=0&&(i===0||order[i-1]<at)),'PO1, PO9, C&S ONLY, NO UPDATE, SELL ONLY, WEIRD, then Not raised');
  assert.equal((html.match(/data-po-list="accessories"/g)||[]).length,1);
  assert.doesNotMatch(html,/data-accessory-type=|>Accessories<|>Aftermarket<|>Miscam<|Special \(sublet\)|>Other</);
  assert.ok(html.indexOf('Canopy')<html.indexOf('Towbar'));
  assert.ok(html.indexOf('Snorkel')<html.indexOf('>Lid<'));
  assert.match(html,/Canopy<\/span><small class="sales-notes-accessory-note">Black<\/small><\/div><div class="sales-notes-accessory-po sales-notes-po-green">C&amp;S ONLY<\/div>/);
  assert.match(html,/Towbar<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-green">SELL ONLY<\/div>/);
  assert.match(html,/Lid<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-green">NO UPDATE<\/div>/);
  assert.match(html,/Sublet winch<\/span><small class="sales-notes-accessory-note">Fit before delivery<\/small><\/div><div class="sales-notes-accessory-po sales-notes-po-green">PO1<\/div>/);
  assert.match(html,/Misc mat<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-red">Not raised<\/div>/);
  assert.match(html,/Blank type<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-red">Not raised<\/div>/);
  assert.match(html,/Custom paint<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-review">WEIRD<\/div>/);
  assert.match(html,/class="sales-notes-accessory-line"/);
  assert.match(html,/data-po-group="not-raised">Not raised · 2 lines</);
  assert.match(html,/<section class="sales-notes-accessory-type sales-notes-admin-list" data-admin-list="admin"><h3 class="sales-notes-accessory-head">Admin · 1 line<\/h3>/);
  assert.doesNotMatch(html,/<details|<summary/);
  assert.ok(html.indexOf('Blank type')<html.indexOf('data-admin-list="admin"'));
  assert.equal(html.indexOf('Freight'),html.lastIndexOf('Freight'));
  assert.doesNotMatch(html,/sales-accessory-table|data-accessory-group=/);
});
test('source text is escaped',()=>{
  const html=acc.notesLinesHtml(acc.normaliseRecord(record({lines:[line('build','',{item:'<img src=x onerror=1>',notes:'<script>'})]})));
  assert.match(html,/&lt;img/);assert.doesNotMatch(html,/<img|<script>/);
});
test('malformed tick or line groups are rejected',()=>{
  assert.throws(()=>acc.normaliseRecord(record({derived:{build:{state:'orange'},tint:{state:'grey'},tray:{state:'grey'}}})));
  assert.throws(()=>acc.normaliseRecord(record({lines:[{group:'other'}]})));
});
test('r394: derived ticks ignore every manual state, including tray Orders Raised',async()=>{
  const h=harness();const p=h.api.refresh();assert.equal(h.calls[0].name,'get_broome_sales_accessories');
  h.calls[0].resolve({data:{context:{role:'salesperson'},items:[record()]}});await p;assert.equal(h.updates.length,1);
  for(const manual of ['not_decided','orders_raised','completed','not_needed']){
    assert.equal(h.api.tickFor(h.rows[0],'build_po',manual).state,'red');assert.equal(h.api.tickFor(h.rows[0],'tint',manual).state,'grey');
  }
  assert.equal(h.api.tickFor({...h.rows[0],tray_ordered:true,tray_complete:true},'tray_ordered').state,'green');
  assert.equal(h.api.tickFor(h.rows[0],'jita'),null);
});
test('records for another source identity or order are ignored and a failed read clears data',async()=>{
  const h=harness();let p=h.api.refresh();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[record({navision_record_id:'other'}),record({tracking_id:'x'})]}});await p;
  assert.equal(h.api.tickFor(h.rows[0],'build_po','not_decided'),null);assert.equal(h.api.detailHtml(h.rows[0]),'');
  assert.match(h.api.notesPanelHtml(h.rows[0]),/No accessory lines in the latest sales export\./);
  p=h.api.refresh();h.calls[1].resolve({data:{context:{role:'salesperson'},items:[record()]}});await p;
  assert.match(h.api.notesPanelHtml(h.rows[0]),/data-po-list="accessories"/);assert.equal(h.api.detailHtml(h.rows[0]),'');
  assert.equal(h.api.tickFor(h.rows[0],'build_po').state,'red');
  p=h.api.refresh();h.calls[2].resolve({error:{message:'x'}});await p;assert.equal(h.api.detailHtml(h.rows[0]),'');assert.equal(h.api.notesPanelHtml(h.rows[0]),'');
  h.rows[0].navision_record_id='replaced';assert.equal(h.api.tickFor(h.rows[0],'build_po','not_decided'),null);
});
test('a delayed read cannot populate after sign-out',async()=>{
  const h=harness();const p=h.api.refresh();delete h.host.PDC_AUTH_CONTEXT;h.calls[0].resolve({data:{context:{role:'salesperson'},items:[record()]}});await p;
  h.host.PDC_AUTH_CONTEXT={userId:'u'};assert.equal(h.api.detailHtml(h.rows[0]),'');
});
test('dashboard ticks are read-only derived cells and flashing respects reduced motion',()=>{
  const css=fs.readFileSync('sales/sales-accessories.css','utf8');
  assert.match(css,/\.ordering-status\.derived-red\{[^}]*animation:sales-accessory-flash/);
  assert.match(css,/@media \(prefers-reduced-motion:reduce\)\{\.ordering-status\.derived-red\{animation:none/);
  assert.match(css,/span\.ordering-status\{cursor:default\}/);
  const sales=require('./sales/sales.js');
  global.BROOME_SALES_ACCESSORIES={tickFor:(r,key)=>({state:key==='tint'?'grey':'red'})};
  try{
    for(const manual of [{},{build_complete:true},{build_not_required:true},{build_po:true}]){
      const html=sales.orderingControl({...row,...manual},'build_po',{key:'build_po',status:'completed'});
      assert.match(html,/class="ordering-status derived-red"/);assert.match(html,/PO not raised/);assert.doesNotMatch(html,/<button|data-ordering-id|disabled/);
    }
  }finally{delete global.BROOME_SALES_ACCESSORIES;}
});
test('Sales entrypoint loads the accessory module before build requirements and bumps cache tokens',()=>{
  const index=fs.readFileSync('sales/index.html','utf8'),module=fs.readFileSync('sales/sales-accessories.js','utf8');
  assert.match(index,/sales-accessories\.js\?v=2026\.10\.20\.03&amp;notes-lines=2026\.10\.20\.05[\s\S]*build-requirements\.js\?v=2026\.10\.03\.02&amp;sales-accessories=2026\.10\.20\.01&amp;notes-lines=2026\.10\.20\.05[\s\S]*vehicle-notes\.js\?v=2026\.10\.06\.01&amp;notes-lines=2026\.10\.20\.05[\s\S]*sales\.js\?[^"]*sales-accessories=2026\.10\.20\.01/);
  assert.match(index,/sales-accessories\.css\?v=2026\.10\.20\.03&amp;notes-lines=2026\.10\.20\.05&amp;po-column=2026\.10\.20\.06/);
  assert.match(index,/sales\.css\?[^"]*po-column=2026\.10\.20\.06/);
  assert.match(index,/vehicle-notes\.js\?[^"]*po-column=2026\.10\.20\.06/);
  assert.match(index,/sales-accessories\.js\?[^"]*tick-scope=2026\.10\.20\.07/);
  assert.match(index,/vehicle-notes\.js\?[^"]*tick-scope=2026\.10\.20\.07/);
  assert.match(index,/sales\.js\?v=2026\.10\.06\.01[^"]*tick-scope=2026\.10\.20\.07/);
  assert.match(fs.readFileSync('sales/sales-accessories.css','utf8'),/\.sales-notes-accessory-line\{[^}]*grid-template-columns:minmax\(0,1fr\) 124px/);
  assert.match(fs.readFileSync('sales/sales-accessories.css','utf8'),/\.sales-notes-po-review\{[^}]*#ffe4ba/);
  assert.match(fs.readFileSync('sales/sales-accessories.css','utf8'),/\.sales-notes-po-red\{[^}]*#fde2e2/);
  assert.doesNotMatch(module,/localStorage|sessionStorage|\.from\(|insert\(|<input|<form|set_ordering|import_sales/);assert.match(module,/rpc\('get_broome_sales_accessories'\)/);
});
test('migration keeps the importer management-only and the read RPC signed-in only',()=>{
  const sql=fs.readFileSync('supabase/migrations/20261020074958_r392_sales_accessory_lines.sql','utf8');
  assert.match(sql,/management_connection\(\)/);assert.match(sql,/UPDATE auth\.users SET banned_until=NULL WHERE id=importer_id/);assert.match(sql,/UPDATE auth\.users SET banned_until=prior_ban WHERE id=importer_id/);
  assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION pdc_sales_private\.import_sales_accessories/);
  assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.get_broome_sales_accessories\(\) TO authenticated;/);
  assert.doesNotMatch(sql,/(UPDATE|INSERT INTO|DELETE FROM) public\.vehicles|sales_build_orders\s+SET|INSERT INTO pdc_sales_private\.ordering_progress/i);
});
test('a successful read with no accessory record says so, and a failed read does not',async()=>{
  const h=harness();let p=h.api.refresh();h.calls[0].resolve({data:{context:{role:'salesperson'},items:[]}});await p;
  assert.match(h.api.notesPanelHtml(h.rows[0]),/No accessory lines in the latest sales export\./);
  assert.equal(h.api.detailHtml(h.rows[0]),'');assert.equal(h.api.tickFor(h.rows[0],'tint'),null);
  p=h.api.refresh();h.calls[1].resolve({error:{message:'x'}});await p;assert.equal(h.api.notesPanelHtml(h.rows[0]),'');
});
test('stock detail keeps the earlier import and does not repeat the sales-export line list',async()=>{
  const builds=require('./sales/build-requirements.js'),calls=[],nodes=new Map();
  const el=id=>{if(!nodes.has(id))nodes.set(id,{id,innerHTML:'',textContent:'',hidden:false,open:false,querySelector(){return null;}});return nodes.get(id);};
  const host={PDC_AUTH_CONTEXT:{userId:'u'},document:{getElementById:el},addEventListener(){},PDC_SUPABASE:{rpc(name){return new Promise(resolve=>calls.push({name,resolve}));}},
    BROOME_SALES_ACCESSORIES:{detailHtml:()=>'<h3>Accessory and PO lines</h3><table class="sales-accessory-table"></table>'}};
  const api=builds.createBuildRequirements(host);api.init({getRows:()=>[row],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getSalesperson:()=>'',getToken:()=>'t'});
  const p=api.refresh();api.bindDetail('bg');
  calls[0].resolve({data:{context:{role:'salesperson'},items:[{tracking_id:'bg',navision_record_id:'source-bg',order:'00001',stock:'13001',items:[{description:'Towbar',source_rows:[7]}],notes:[],other_lines:[]}]}});await p;
  const content=el('sales-build-content').innerHTML;
  assert.match(content,/Towbar/);assert.doesNotMatch(content,/Accessory and PO lines|sales-accessory-table|data-accessory-type|data-po-list|sales-build-earlier/);
  assert.doesNotMatch(api.detailHtml(row),/Accessory and PO lines|sales-accessory-table|data-accessory-type|data-po-list/);
});
test('expanded notes place the accessory lines before the note fields',()=>{
  const {create}=require('./sales/vehicle-notes.js'),elements=new Map();
  const el=id=>{if(!elements.has(id))elements.set(id,{events:{},addEventListener(k,fn){this.events[k]=fn;}});return elements.get(id);};
  const calls=[];
  const host={PDC_AUTH_CONTEXT:{userId:'u'},document:{getElementById:el},addEventListener(){},
    PDC_SUPABASE:{rpc(){return new Promise(resolve=>calls.push({resolve}));}}};
  const accessories=acc.createSalesAccessories(host);
  accessories.init({getRows:()=>[row],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getSalesperson:()=>'',getToken:()=>'t'});
  host.BROOME_SALES_ACCESSORIES=accessories;
  const notes=create(host).init({getRows:()=>[row],getVisibleRows:()=>[row],getScope:()=>'',canEditRow:()=>true,isHidden:()=>false,reference:r=>'Stock '+r.stock,onChanged(){}});
  const listed=accessories.refresh();
  calls[0].resolve({data:{context:{role:'salesperson'},items:[record({lines:[line('build','PO55',{item:'Canopy',type:'Accessory'}),line('admin','',{item:'Freight'})]})]}});
  return listed.then(()=>{
    el('sales-expand-notes').events.click();
    const html=notes.rowHtml(row);
    assert.ok(html.indexOf('data-po-list="accessories"')>=0&&html.indexOf('data-po-list="accessories"')<html.indexOf('>Custom information<'));
    assert.match(html,/Canopy<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-green">PO55<\/div>/);
    assert.doesNotMatch(html,/name="notes"|Vehicle notes/);
    assert.match(html,/data-admin-list="admin"><h3 class="sales-notes-accessory-head">Admin · 1 line<\/h3>/);assert.doesNotMatch(html,/<details/);
    assert.doesNotMatch(html,/sales-accessory-table/);
    assert.equal(accessories.detailHtml(row),'');
    assert.equal(accessories.tickFor(row,'build_po').state,'red');
    assert.match(html,/class="vehicle-notes-layout"/);
  });
});
test('r394 migration refuses sales ordering writes and drops the in-house exemption',()=>{
  const sql=fs.readFileSync('supabase/migrations/20261020083610_r394_ticks_derived_only.sql','utf8');
  assert.match(sql,/FUNCTION pdc_sales_private\.set_ordering_status[\s\S]*?RAISE EXCEPTION 'TINT, BUILD and TRAY now follow/);
  assert.match(sql,/FUNCTION pdc_sales_private\.set_ordering_flag[\s\S]*?RAISE EXCEPTION 'TINT, BUILD and TRAY now follow/);
  assert.doesNotMatch(sql,/in_house'\)::boolean|ordering_progress\s+(SET|op)|UPDATE |DELETE |INSERT INTO/i);
});
test('r396 import accepts OOXML .xls names and eastern-time stamps without widening access',()=>{
  const sql=fs.readFileSync('supabase/migrations/20261020092338_r396_import_xls_tz.sql','utf8');
  const down=fs.readFileSync('supabase/rollbacks/20261020092338_r396_import_xls_tz.down.sql','utf8');
  assert.match(sql,/a \.xls file name needs container ooxml/);assert.match(sql,/container must be ooxml/);
  assert.match(sql,/'Australia\/Perth','Australia\/Brisbane','Australia\/Sydney','Australia\/Melbourne'/);
  assert.match(sql,/ELSE ARRAY\['Australia\/Perth'\] END/);assert.match(sql,/snapshot_at_utc does not match the extract stamp/);
  assert.match(sql,/is later than received_at; check extract_tz/);assert.match(sql,/file_sha_snapshot_conflict/);
  assert.match(sql,/CHECK \(file_name ~\* '\\\.xlsx\?\$' AND length\(file_name\) <= 255\)/);
  assert.match(sql,/import_sales_accessories_20261020\(p_action text, p_envelope jsonb, p_rows jsonb DEFAULT NULL::jsonb, p_expected_preview_hash text DEFAULT NULL::text\)/);
  assert.match(sql,/UPDATE auth\.users SET banned_until=NULL WHERE id=importer_id/);assert.match(sql,/UPDATE auth\.users SET banned_until=prior_ban WHERE id=importer_id/);
  assert.doesNotMatch(sql,/GRANT |REVOKE |SECURITY DEFINER|(UPDATE|INSERT INTO|DELETE FROM) public\.vehicles|sales_build_orders\s+SET|ordering_progress/i);
  assert.match(down,/418b21e32ad877a6e18ec96b836b5e76/);assert.match(down,/9801ff7658e60fee649387f0a45f69b2/);assert.match(down,/receipts named \.xls exist/);
});
test('changing the salesperson filter or a vehicle salesperson keeps derived ticks',async()=>{
  const calls=[],updates=[];
  const host={PDC_AUTH_CONTEXT:{userId:'u'},addEventListener(){},PDC_SUPABASE:{rpc(name){return new Promise(resolve=>calls.push({name,resolve}));}}};
  const bg={...row},aw={...row,tracking_id:'aw',navision_record_id:'source-aw',order:'00002',stock:'13900021',salesperson_code:'AW'};
  const rows=[bg,aw];let selected='';
  const api=acc.createSalesAccessories(host);
  api.init({getRows:()=>rows,getContext:()=>({role:'administrator'}),getSalesperson:()=>selected,getToken:()=>'t',onUpdate:()=>updates.push(1)});
  const p=api.refresh();
  calls[0].resolve({data:{context:{role:'administrator'},items:[record(),record({tracking_id:'aw',navision_record_id:'source-aw',order:'00002',stock:'13900021',
    derived:{build:{state:'green',reason:'po_raised'},tint:{state:'red',reason:'po_not_raised'},tray:{state:'review',reason:'review'}}})]}});
  await p;
  selected='AW';
  assert.equal(api.tickFor(aw,'tint').state,'red');assert.equal(api.tickFor(aw,'tray_ordered').state,'review');assert.equal(api.tickFor(bg,'build_po').state,'red');
  selected='BG';
  assert.equal(api.tickFor(bg,'tint').state,'grey');assert.equal(api.tickFor(bg,'tray_ordered').state,'green');assert.equal(api.tickFor(aw,'build_po').state,'green');
  assert.equal(calls.length,1,'a filter change re-derives ticks without another accessory read');
  bg.salesperson_code='CW';
  assert.equal(api.tickFor(bg,'build_po').state,'red');assert.equal(api.tickFor(bg,'tint').state,'grey');
  const sales=fs.readFileSync('sales/sales.js','utf8'),module=fs.readFileSync('sales/sales-accessories.js','utf8');
  assert.match(sales,/BROOME_SALES_ACCESSORIES\?\.init\(\{\.\.\.moduleOptions\(\),getRows:\(\)=>scopeRows\(state\.items,''\),getSalesperson:\(\)=>''/);
  assert.match(sales,/BROOME_VEHICLE_NOTES\?\.reveal\?\.\(id\)/);
  assert.match(module,/dashboard salesperson filter is a view, not a cache key/);
  assert.doesNotMatch(module,/getSalesperson|currentScope/);
});
test('a signed-in salesperson still only sees their own ticks',async()=>{
  const calls=[];
  const host={PDC_AUTH_CONTEXT:{userId:'u'},addEventListener(){},PDC_SUPABASE:{rpc(name){return new Promise(resolve=>calls.push({name,resolve}));}}};
  const bg={...row},aw={...row,tracking_id:'aw',navision_record_id:'source-aw',order:'00002',stock:'13900021',salesperson_code:'AW'};
  const api=acc.createSalesAccessories(host);
  api.init({getRows:()=>[bg,aw],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getSalesperson:()=>'AW',getToken:()=>'t'});
  const p=api.refresh();
  calls[0].resolve({data:{context:{role:'salesperson'},items:[record(),record({tracking_id:'aw',navision_record_id:'source-aw',order:'00002',stock:'13900021'})]}});
  await p;
  assert.equal(api.tickFor(bg,'build_po').state,'red');assert.equal(api.tickFor(aw,'build_po'),null);
});
