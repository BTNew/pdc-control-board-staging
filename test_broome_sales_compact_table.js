const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const tools=require('./sales/dashboard-tools.js');

function harness(){
 const elements=new Map();
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',
  dataset:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},
  events:{},addEventListener(name,fn){this.events[name]=fn;},close(){this.closed=true;},showModal(){this.closed=false;},scrollIntoView(){},focus(){this.focused=true;}});
  return elements.get(id);}
 const nav=['dashboard','pipeline','labels','finance'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 const RealDate=Date;
 const fixed=new RealDate('2026-10-20T04:00:00Z');
 class FixedDate extends RealDate{constructor(...args){super(...(args.length?args:[fixed]));}static now(){return fixed.getTime();}}
 const calls=[];
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},
  BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),PDC_AUTH_CONTEXT:{role:'salesperson',userId:'A'},
  PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(){},setInterval(){}};
 const sandbox={window,globalThis:window,module:undefined,Set,Date:FixedDate,console,Intl};
 vm.runInNewContext(fs.readFileSync('sales/dashboard-tools.js','utf8'),sandbox);
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),sandbox);
 return{calls,el};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const stocked={cosi:'Yes',salesperson_code:'BG',tracking_id:'stocked',stock:'13032821',order:'0026001',client:'Park',vehicle:'Toyota HiLux 4x4 2.8 Diesel Dual Cab',kewdale_eta:'2026-10-23',navision_notes:'Tray confirmed. Customer wants a canopy and a tow bar fitted before delivery to Broome.'};
const ordered={cosi:'Yes',salesperson_code:'BG',tracking_id:'ordered',stock:'',order:'000123',client:'Example',vehicle:'Prado',kewdale_eta:'2026-10-18',navision_notes:''};

test('stocked vehicles show only the stock number and stockless vehicles keep the Toyota order',async()=>{
 const h=harness();
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:[stocked,ordered]}});await tick();
 const cells=[...h.el('vehicle-table').innerHTML.matchAll(/<td class="vehicle-reference-cell">([\s\S]*?)<\/td>/g)].map(m=>m[1]);
 assert.equal(cells.length,2);
 assert.match(cells[0],/>13032821</);
 assert.doesNotMatch(cells[0],/Toyota Order/);
 assert.doesNotMatch(cells[0],/0026001/);
 assert.match(cells[1],/>000123</);
 assert.match(cells[1],/Toyota Order Number/);
 assert.match(cells[1],/Awaiting stock number/);
});

test('vehicle description is one line with the full text available on hover',async()=>{
 const h=harness();
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:[stocked]}});await tick();
 const html=h.el('vehicle-table').innerHTML;
 assert.match(html,/<td class="vehicle-cell"><span class="vehicle-line" title="Toyota HiLux 4x4 2\.8 Diesel Dual Cab">Toyota HiLux 4x4 2\.8 Diesel Dual Cab<\/span><\/td>/);
 const css=fs.readFileSync('sales/sales.css','utf8');
 assert.match(css,/#vehicle-table \.vehicle-line[\s\S]*?\{[^}]*overflow:hidden[^}]*text-overflow:ellipsis[^}]*white-space:nowrap/);
});

test('Kewdale ETA date and day counter share a line, with past in red and due in green',async()=>{
 const h=harness();
 h.calls[0].resolve({data:{context:{role:'salesperson'},items:[stocked,ordered]}});await tick();
 const html=h.el('vehicle-table').innerHTML;
 assert.match(html,/<td class="eta-cell"><strong>23\/10\/26<\/strong><span class="eta-counter due" title="23\/10\/2026 Due in 3 days">· 3d<\/span><\/td>/);
 assert.match(html,/<td class="eta-cell"><strong>18\/10\/26<\/strong><span class="eta-counter past" title="18\/10\/2026 2 days past ETA">· 2d past<\/span><\/td>/);
 assert.match(html,/<td class="sp-cell">[\s\S]*<span class="sp-code">BG<\/span><\/td>/);
 const css=fs.readFileSync('sales/sales.css','utf8');
 assert.match(css,/#vehicle-table \.eta-counter\{[^}]*display:inline-block/);
 assert.match(css,/\.eta-counter\.past\{[^}]*color:#b11a2c/);
 assert.match(css,/\.eta-counter\.due\{[^}]*color:#146938/);
 assert.equal(tools.etaInfo('2026-10-23','2026-10-20').tone,'due');
 assert.equal(tools.etaInfo('2026-10-18','2026-10-20').tone,'past');
});

test('compact table keeps slim rows, narrow ticks, clamped notes and a page-sticky header',()=>{
 const css=fs.readFileSync('sales/sales.css','utf8');
 assert.match(css,/#vehicle-table tbody td\{height:auto;padding:2px 4px;line-height:1\.2;white-space:nowrap/);
 assert.match(css,/#vehicle-table thead th\{position:sticky;top:0/);
 assert.match(css,/\.panel\.tracker-panel\{overflow:clip\}/);
 assert.match(css,/\.tracker-panel>\.table-wrap\{max-height:none;overflow:visible/);
 assert.match(css,/#vehicle-table \.notes-clamp\{[^}]*-webkit-line-clamp:2/);
 assert.deepEqual(tools.defaults.slice(5,8),[48,56,48]);
 assert.ok(tools.defaults[11]>150);
 assert.match(fs.readFileSync('sales/index.html','utf8'),/compact-table=2026\.10\.20\.03/);
 assert.match(css,/#vehicle-table td\.sp-cell input,#vehicle-table td\.sp-cell \.sp-code\{display:inline-block/);
 assert.match(css,/#vehicle-table td\.eta-cell\{overflow:visible/);
 assert.match(fs.readFileSync('sales/sales-accessories.css','utf8'),/prefers-reduced-motion:reduce/);
 assert.match(fs.readFileSync('sales/sales.js','utf8'),/derived-'\+derived\.state/);
});
