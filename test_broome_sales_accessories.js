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
test('line table groups Build, Tray, Tint and Admin with Admin collapsed and a red Not raised PO',()=>{
  const html=acc.recordHtml(acc.normaliseRecord(record()));
  assert.match(html,/<th scope="col">Line<\/th><th scope="col">Item<\/th><th scope="col">Type<\/th><th scope="col">Sublet<\/th><th scope="col">PO #<\/th><th scope="col">Notes<\/th>/);
  assert.ok(html.indexOf('data-accessory-group="build"')<html.indexOf('data-accessory-group="tray"'));
  assert.match(html,/<details class="sales-accessory-admin"><summary>Admin · 1 line/);assert.doesNotMatch(html,/<details class="sales-accessory-admin" open/);
  assert.match(html,/sales-accessory-po-missing">Not raised/);assert.doesNotMatch(html,/data-accessory-group="tint"/);
});
test('source text is escaped',()=>{
  const html=acc.recordHtml(acc.normaliseRecord(record({lines:[line('build','',{item:'<img src=x onerror=1>',notes:'<script>'})]})));
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
  p=h.api.refresh();h.calls[1].resolve({data:{context:{role:'salesperson'},items:[record()]}});await p;assert.match(h.api.detailHtml(h.rows[0]),/Accessory and PO lines/);
  p=h.api.refresh();h.calls[2].resolve({error:{message:'x'}});await p;assert.equal(h.api.detailHtml(h.rows[0]),'');
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
  assert.match(index,/sales-accessories\.js\?v=2026\.10\.20\.03[\s\S]*build-requirements\.js\?v=2026\.10\.03\.02&amp;sales-accessories=2026\.10\.20\.01[\s\S]*sales\.js\?[^"]*sales-accessories=2026\.10\.20\.01/);
  assert.match(index,/sales-accessories\.css\?v=2026\.10\.20\.03/);
  assert.doesNotMatch(module,/localStorage|sessionStorage|\.from\(|insert\(|<input|<form|set_ordering|import_sales/);assert.match(module,/rpc\('get_broome_sales_accessories'\)/);
});
test('migration keeps the importer management-only and the read RPC signed-in only',()=>{
  const sql=fs.readFileSync('supabase/migrations/20261020074958_r392_sales_accessory_lines.sql','utf8');
  assert.match(sql,/management_connection\(\)/);assert.match(sql,/UPDATE auth\.users SET banned_until=NULL WHERE id=importer_id/);assert.match(sql,/UPDATE auth\.users SET banned_until=prior_ban WHERE id=importer_id/);
  assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION pdc_sales_private\.import_sales_accessories/);
  assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.get_broome_sales_accessories\(\) TO authenticated;/);
  assert.doesNotMatch(sql,/(UPDATE|INSERT INTO|DELETE FROM) public\.vehicles|sales_build_orders\s+SET|INSERT INTO pdc_sales_private\.ordering_progress/i);
});
test('stock detail dropdown shows the line table first and keeps the earlier import collapsed',async()=>{
  const builds=require('./sales/build-requirements.js'),calls=[],nodes=new Map();
  const el=id=>{if(!nodes.has(id))nodes.set(id,{id,innerHTML:'',textContent:'',hidden:false,open:false,querySelector(){return null;}});return nodes.get(id);};
  const host={PDC_AUTH_CONTEXT:{userId:'u'},document:{getElementById:el},addEventListener(){},PDC_SUPABASE:{rpc(name){return new Promise(resolve=>calls.push({name,resolve}));}},
    BROOME_SALES_ACCESSORIES:{detailHtml:r=>r.tracking_id==='bg'?acc.recordHtml(acc.normaliseRecord(record())):''}};
  const api=builds.createBuildRequirements(host);api.init({getRows:()=>[row],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getSalesperson:()=>'',getToken:()=>'t'});
  const p=api.refresh();const html=api.detailHtml(row);assert.match(html,/Accessory and PO lines/);api.bindDetail('bg');
  calls[0].resolve({data:{context:{role:'salesperson'},items:[{tracking_id:'bg',navision_record_id:'source-bg',order:'00001',stock:'13001',items:[{description:'Towbar',source_rows:[7]}],notes:[],other_lines:[]}]}});await p;
  const content=el('sales-build-content').innerHTML;assert.ok(content.indexOf('Accessory and PO lines')<content.indexOf('Earlier accessory import'));assert.match(content,/<details class="sales-build-earlier">/);
});
test('r394 migration refuses sales ordering writes and drops the in-house exemption',()=>{
  const sql=fs.readFileSync('supabase/migrations/20261020083610_r394_ticks_derived_only.sql','utf8');
  assert.match(sql,/FUNCTION pdc_sales_private\.set_ordering_status[\s\S]*?RAISE EXCEPTION 'TINT, BUILD and TRAY now follow/);
  assert.match(sql,/FUNCTION pdc_sales_private\.set_ordering_flag[\s\S]*?RAISE EXCEPTION 'TINT, BUILD and TRAY now follow/);
  assert.doesNotMatch(sql,/in_house'\)::boolean|ordering_progress\s+(SET|op)|UPDATE |DELETE |INSERT INTO/i);
});
