'use strict';
// r416/r417: the Sales notes panel groups accessory lines by PO in one combined list (display only); Admin stays separate.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const acc=require('./sales/sales-accessories.js');
const line=(item,po,type='special',extra={})=>({group:'build',line:'1',item,type,sublet:'',po,
  po_state:!po?'blank':/^PO\d+$/.test(po)?'po':/^C&S ONLY$/.test(po)?'cs_only':/^SELL ONLY$/.test(po)?'sell_only':/^NO UPDATE$/.test(po)?'no_update':'other',notes:'',in_house:false,...extra});
const record=lines=>acc.normaliseRecord({tracking_id:'t',navision_record_id:'n',order:'1',stock:'1',quote:'',source_file:'Sales.xlsx',snapshot_at:null,
  derived:{build:{state:'green',reason:''},tint:{state:'grey',reason:''},tray:{state:'grey',reason:''}},lines});
const section=html=>{const start=html.indexOf('data-po-list="accessories"');assert.ok(start>=0,'combined list');const end=html.indexOf('</section>',start);return html.slice(start,end);};
const items=html=>[...html.matchAll(/<div class="sales-notes-accessory-item"><span>([^<]*)<\/span>/g)].map(m=>m[1]);
const heads=html=>[...html.matchAll(/<div class="sales-notes-po-group-head" data-po-group="([^"]*)">([^<]*)<\/div>/g)].map(m=>[m[1],m[2]]);

// Same shape as the Special (sublet) list in the 21 Oct screenshot: two POs interleaved and two Not raised lines.
const special=[line('Canopy','PO100002'),line('Winch','PO100002'),line('Battery system','PO100002'),line('Long range tank','PO100002'),
  line('Suspension upgrade','PO100002'),line('Snorkel','PO100002',undefined,{notes:'Airmax'}),line('Bullbar','PO100002'),line('Side steps','PO100002'),
  line('Telematics install',''),line('Sat phone cradle',''),line('Tyre upgrade','PO100002'),line('Light bar','PO100002'),
  line('Spare steel rim','PO100001'),line('Tint and first aid kit','PO100002')];

test('PO groups sit together in ascending PO order, export order kept inside each group, Not raised last',()=>{
  const html=section(acc.notesLinesHtml(record(special)));
  assert.deepEqual(items(html),['Spare steel rim','Canopy','Winch','Battery system','Long range tank','Suspension upgrade','Snorkel','Bullbar','Side steps',
    'Tyre upgrade','Light bar','Tint and first aid kit','Telematics install','Sat phone cradle']);
  assert.deepEqual(heads(html),[['PO100001','PO100001 · 1 line'],['PO100002','PO100002 · 11 lines'],['not-raised','Not raised · 2 lines']]);
  // Each header comes straight before the first line of its group.
  assert.ok(html.indexOf('PO100001 · 1 line')<html.indexOf('Spare steel rim')&&html.indexOf('Spare steel rim')<html.indexOf('PO100002 · 11 lines'));
  assert.ok(html.indexOf('PO100002 · 11 lines')<html.indexOf('>Canopy<')&&html.indexOf('Not raised · 2 lines')<html.indexOf('Telematics install'));
});

test('every line stays its own boxed line with the PO in its own column, and nothing is added or dropped',()=>{
  const html=section(acc.notesLinesHtml(record(special)));
  assert.equal((html.match(/<div class="sales-notes-accessory-line">/g)||[]).length,special.length);
  assert.match(html,/Snorkel<\/span><small class="sales-notes-accessory-note">Airmax<\/small><\/div><div class="sales-notes-accessory-po sales-notes-po-green">PO100002<\/div><\/div>/);
  assert.match(html,/Telematics install<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-red">Not raised<\/div><\/div>/);
  for(const {item} of special)assert.equal(html.split('>'+item+'<').length,2,item);
  // The headers are plain text rows, never boxed lines, inputs or buttons.
  assert.doesNotMatch(html,/<input|<button|<details|data-accessory-group=/);
});

test('r417: a single PO group still shows its header so the PO is clear',()=>{
  const lines=[line('Tub liner','PO100001','accessory'),line('Seat covers','PO100001','aftermarket'),line('Towbar','PO100001','special')];
  const html=section(acc.notesLinesHtml(record(lines)));
  assert.deepEqual(items(html),['Tub liner','Seat covers','Towbar']);
  assert.deepEqual(heads(html),[['PO100001','PO100001 · 3 lines']]);
  const blank=section(acc.notesLinesHtml(record([line('A','','aftermarket'),line('B','','miscacc')])));
  assert.deepEqual(items(blank),['A','B']);assert.deepEqual(heads(blank),[['not-raised','Not raised · 2 lines']]);
});

test('r417: every accessory type shares one PO-grouped list, and Admin stays an always-visible section at the bottom',()=>{
  const html=acc.notesLinesHtml(record([line('S','PO2','special'),line('M','','miscacc'),line('F','PO3','aftermarket'),line('A','PO1','accessory'),
    line('O','PO1','paint'),line('Pit and weigh','PO1','accessory',{group:'admin'}),line('Transport','','accessory',{group:'admin'})]));
  const list=section(html);
  assert.deepEqual(items(list),['A','O','S','F','M']);
  assert.deepEqual(heads(list),[['PO1','PO1 · 2 lines'],['PO2','PO2 · 1 line'],['PO3','PO3 · 1 line'],['not-raised','Not raised · 1 line']]);
  assert.doesNotMatch(html,/data-accessory-type=|>Accessories<|>Aftermarket<|>Miscam<|Special \(sublet\)|>Other</);
  assert.equal((html.match(/data-po-list=/g)||[]).length,1);
  assert.doesNotMatch(list,/Pit and weigh|Transport/);
  assert.ok(html.indexOf('data-po-list="accessories"')<html.indexOf('data-admin-list="admin"'));
  assert.match(html,/data-admin-list="admin"><h3 class="sales-notes-accessory-head">Admin · 2 lines<\/h3><div class="sales-notes-po-group-head" data-po-group="PO1">PO1 · 1 line<\/div>/);
  const admin=html.slice(html.indexOf('data-admin-list="admin"'));
  assert.ok(admin.indexOf('Pit and weigh')<admin.indexOf('Not raised · 1 line')&&admin.indexOf('Not raised · 1 line')<admin.indexOf('>Transport<'));
  // r417: no collapsible boxes anywhere in the order dropdown; Admin is always visible.
  assert.doesNotMatch(html,/<details|<summary/);
});

test('PO numbers sort numerically, other raised values follow, review text groups, and Not raised stays last',()=>{
  const lines=[line('n1',''),line('cs1','C&S ONLY'),line('p10','PO10'),line('weird','check with Bob'),line('p9a','PO9'),line('sell','SELL ONLY'),
    line('p9b',' po9 '),line('cs2','c&s only',undefined,{po_state:'cs_only'}),line('n2','  '),line('p10b','PO10')];
  const groups=acc.poGroups(record(lines).lines);
  assert.deepEqual(groups.map(g=>g.key),['PO9','PO10','C&S ONLY','CHECK WITH BOB','SELL ONLY','']);
  assert.deepEqual(groups.map(g=>g.lines.map(l=>l.item)),[['p9a','p9b'],['p10','p10b'],['cs1','cs2'],['weird'],['sell'],['n1','n2']]);
  const html=section(acc.notesLinesHtml(record(lines)));
  assert.match(html,/data-po-group="CHECK WITH BOB">check with Bob · 1 line</);
  assert.match(html,/weird<\/span><\/div><div class="sales-notes-accessory-po sales-notes-po-review">check with Bob<\/div>/);
  assert.match(html,/data-po-group="not-raised">Not raised · 2 lines</);
});

test('grouping never reorders or changes the stored record',()=>{
  const rec=record(special),before=JSON.stringify(rec);
  acc.notesLinesHtml(rec);acc.poGroups(rec.lines);
  assert.equal(JSON.stringify(rec),before);
});

test('r417: Admin keeps the r416 rule (header only with more than one group) and an Admin-only record shows no empty list',()=>{
  const html=acc.notesLinesHtml(record([line('Pit and weigh','PO5','accessory',{group:'admin'}),line('Transport','PO5','accessory',{group:'admin'})]));
  assert.doesNotMatch(html,/data-po-list=|sales-notes-po-group-head/);
  assert.match(html,/data-admin-list="admin"><h3 class="sales-notes-accessory-head">Admin · 2 lines<\/h3><div class="sales-notes-accessory-line">/);
  const empty=acc.notesLinesHtml(record([]));
  assert.match(empty,/No accessory lines in the latest sales export\./);assert.doesNotMatch(empty,/data-po-list=/);
});

test('header text is escaped',()=>{
  const html=acc.notesLinesHtml(record([line('a','<b>x</b>'),line('b','')]));
  assert.match(html,/&lt;b&gt;x&lt;\/b&gt; · 1 line/);assert.doesNotMatch(html,/<b>x<\/b>/);
});

test('subtle header style, cache tokens bumped, and the module stays read-only',()=>{
  const css=fs.readFileSync('sales/sales-accessories.css','utf8'),index=fs.readFileSync('sales/index.html','utf8'),module=fs.readFileSync('sales/sales-accessories.js','utf8');
  assert.match(css,/\.sales-notes-po-group-head\{[^}]*font-size:10px[^}]*color:#7a8b9a/);
  assert.doesNotMatch(css.match(/\.sales-notes-po-group-head\{[^}]*\}/)[0],/border|background/);
  assert.match(css,/\.sales-notes-accessory-line\{[^}]*grid-template-columns:minmax\(0,1fr\) 124px/);
  assert.match(index,/sales-accessories\.css\?[^"]*po-groups=2026\.10\.21\.01/);
  assert.match(index,/sales-accessories\.js\?[^"]*tick-scope=2026\.10\.20\.07&amp;po-groups=2026\.10\.21\.01&amp;po-list=2026\.10\.21\.02"/);
  assert.match(index,/sales-accessories\.css\?[^"]*po-groups=2026\.10\.21\.01&amp;po-list=2026\.10\.21\.02"/);
  assert.match(css,/\.sales-notes-po-list>\.sales-notes-po-group-head:first-child/);
  assert.doesNotMatch(module,/typeSections|Special \(sublet\)|'Aftermarket'|'Miscam'/);
  assert.doesNotMatch(module,/localStorage|sessionStorage|\.from\(|insert\(|<input|<form|set_ordering|import_sales/);
});

test('the Sales release cannot reload fitter screens, and fitters never reload over unsaved notes',()=>{
  // Fitter screens only update when the pdc-fitters.js token in the root index.html changes; the Sales page does not load it.
  const fitters=require('./pdc-fitters.js'),sales=fs.readFileSync('sales/index.html','utf8'),root=fs.readFileSync('index.html','utf8');
  assert.doesNotMatch(sales,/pdc-fitters\.js/);
  assert.equal(fitters.fitterScriptToken(sales),'');
  assert.notEqual(fitters.fitterScriptToken(root),'');
  const src=fs.readFileSync('pdc-fitters.js','utf8');
  assert.match(src,/function updateNow\(\) \{\s*if \(unsavedWork\(\)\) \{/);
  assert.match(src,/function unsavedWork\(\) \{ return saving \|\| loading \|\| drafts\.size > 0 \|\| conversionNotes\.size > 0/);
  assert.match(src,/if \(unsavedWork\(\)\) render\(\); else updateNow\(\);/);
});

test('one notes row open at a time and custom information only, with grouped lines inside',async()=>{
  const {create}=require('./sales/vehicle-notes.js'),elements=new Map(),calls=[];
  const el=id=>{if(!elements.has(id))elements.set(id,{events:{},addEventListener(k,fn){this.events[k]=fn;}});return elements.get(id);};
  const host={PDC_AUTH_CONTEXT:{userId:'u'},document:{getElementById:el},addEventListener(){},PDC_SUPABASE:{rpc(){return new Promise(resolve=>calls.push({resolve}));}}};
  const rowA={tracking_id:'a',navision_record_id:'na',order:'00001',stock:'1',cosi:true,source_current:true,salesperson_code:'BG'};
  const rowB={...rowA,tracking_id:'b',navision_record_id:'nb',order:'00002',stock:'2'};
  const accessories=acc.createSalesAccessories(host);
  accessories.init({getRows:()=>[rowA,rowB],getContext:()=>({role:'salesperson',salesperson_code:'BG'}),getToken:()=>'t'});
  host.BROOME_SALES_ACCESSORIES=accessories;
  const notes=create(host).init({getRows:()=>[rowA,rowB],getVisibleRows:()=>[rowA,rowB],getScope:()=>'',canEditRow:()=>true,isHidden:()=>false,reference:r=>'Stock '+r.stock,onChanged(){}});
  const p=accessories.refresh();
  const raw=l=>({...l});
  calls[0].resolve({data:{context:{role:'salesperson'},items:[{tracking_id:'a',navision_record_id:'na',order:'00001',stock:'1',derived:{build:{state:'green'},tint:{state:'grey'},tray:{state:'grey'}},
    lines:[raw(line('Winch','PO100002')),raw(line('Rim','PO100001')),raw(line('Phone',''))]}]}});
  await p;
  assert.equal(notes.reveal('a'),true);
  let html=notes.rowHtml(rowA);
  assert.deepEqual(items(html),['Rim','Winch','Phone']);
  assert.deepEqual(heads(html).map(h=>h[1]),['PO100001 · 1 line','PO100002 · 1 line','Not raised · 1 line']);
  assert.match(html,/name="custom_information"/);assert.doesNotMatch(html,/name="notes"|Vehicle notes/);
  assert.equal(notes.reveal('b'),true);
  assert.equal(notes.rowHtml(rowA),'');assert.notEqual(notes.rowHtml(rowB),'');
});
