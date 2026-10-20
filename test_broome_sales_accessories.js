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
test('notes panel lists accessory types in order, then other, with Admin collapsed',()=>{
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
  const at=type=>html.indexOf('data-accessory-type="'+type+'"');
  assert.ok(at('accessory')<at('aftermarket')&&at('aftermarket')<at('miscacc')&&at('miscacc')<at('special')&&at('special')<at('other'));
  assert.ok(html.indexOf('Canopy')<html.indexOf('Towbar'));
  assert.ok(html.indexOf('Snorkel')<html.indexOf('>Lid<'));
  assert.match(html,/Canopy<\/span><span class="sales-notes-accessory-po">C&amp;S ONLY<\/span><small class="sales-notes-accessory-note">Black<\/small>/);
  assert.match(html,/Towbar<\/span><span class="sales-notes-accessory-po">SELL ONLY<\/span>/);
  assert.match(html,/Lid<\/span><span class="sales-notes-accessory-po">NO UPDATE<\/span>/);
  assert.match(html,/Sublet winch<\/span><span class="sales-notes-accessory-po">PO1<\/span>/);
  assert.match(html,/Misc mat<\/span><span class="sales-accessory-po-missing">Not raised<\/span>/);
  assert.match(html,/Blank type<\/span><span class="sales-accessory-po-missing">Not raised<\/span>/);
  assert.match(html,/Custom paint<\/span><span class="sales-notes-accessory-po">WEIRD<\/span>/);
  assert.match(html,/<details class="sales-accessory-admin"><summary>Admin · 1 line<\/summary>/);
  assert.doesNotMatch(html,/<details class="sales-accessory-admin" open/);
  assert.ok(html.indexOf('data-accessory-type="other"')<html.indexOf('sales-accessory-admin'));
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
  assert.match(h.api.notesPanelHtml(h.rows[0]),/data-accessory-type="accessory"/);assert.equal(h.api.detailHtml(h.rows[0]),'');
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
  assert.match(index,/sales-accessories\.css\?v=2026\.10\.20\.03&amp;notes-lines=2026\.10\.20\.05/);
  assert.match(index,/sales\.css\?[^"]*notes-lines=2026\.10\.20\.05/);
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
  assert.match(content,/Towbar/);assert.doesNotMatch(content,/Accessory and PO lines|sales-accessory-table|data-accessory-type|sales-build-earlier/);
  assert.doesNotMatch(api.detailHtml(row),/Accessory and PO lines|sales-accessory-table|data-accessory-type/);
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
    assert.ok(html.indexOf('data-accessory-type="accessory"')<html.indexOf('>Vehicle notes<'));
    assert.match(html,/Canopy<\/span><span class="sales-notes-accessory-po">PO55<\/span>/);
    assert.match(html,/<details class="sales-accessory-admin"><summary>Admin · 1 line/);
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
