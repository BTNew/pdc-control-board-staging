const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const builds=require('./sales/build-requirements.js');
const record=(tracking_id='bg',order='00001',description='Towbar')=>({tracking_id,navision_record_id:'source-'+tracking_id,order,stock:'13001',items:[{description,source_rows:[7],quote_number:'Q001'}],notes:[{text:'Customer note\nKeep on separate lines',source_rows:[8]}],other_lines:[{description:'Unclear quote item',source_rows:[9],reason:'Review the quote description'}],source_file:'Sales Export.xlsx',imported_at:'2026-10-03T01:00:00Z',source_stock:'13001'});
function harness({admin=false}={}) {
  const nodes=new Map(),calls=[],events={};
  const el=id=>{if(!nodes.has(id))nodes.set(id,{id,innerHTML:'',textContent:'',hidden:false,open:false,child:{open:false},querySelector(selector){return selector==='.sales-build-other'&&this.innerHTML.includes('sales-build-other')?this.child:null;}});return nodes.get(id);};
  const h={person:'',generation:1,context:{role:admin?'administrator':'salesperson',salesperson_code:admin?null:'BG'},rows:[
    {tracking_id:'bg',navision_record_id:'source-bg',order:'00001',stock:'13001',cosi:true,source_current:true,salesperson_code:'BG'},
    {tracking_id:'pm',navision_record_id:'source-pm',order:'00002',stock:'13002',cosi:'Yes',source_current:true,salesperson_code:'PM'},
    {tracking_id:'unsold',order:'00003',stock:'13003',cosi:'No',source_current:true,salesperson_code:'BG'},
    {tracking_id:'old',order:'00004',cosi:true,source_current:false,salesperson_code:'BG'},
    {tracking_id:'hidden',order:'00005',cosi:true,source_current:true,salesperson_code:'BG',sales_hidden:true},
    {tracking_id:'conflict',order:'00006',cosi:true,source_current:true,salesperson_code:'BG',identity_conflict:true},
    {tracking_id:'foreign-code',order:'00007',cosi:true,source_current:true,salesperson_code:'XX'}]};
  h.host={PDC_AUTH_CONTEXT:{userId:'approved-user'},document:{getElementById:el},addEventListener(type,fn){events[type]=fn;},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
  h.api=builds.createBuildRequirements(h.host);h.api.init({getRows:()=>h.rows,getContext:()=>h.context,getSalesperson:()=>h.person,getToken:()=>JSON.stringify([h.host.PDC_AUTH_CONTEXT?.userId,h.generation])});
  h.resolve=(index,items,error)=>calls[index].resolve(error?{error:{message:error}}:{data:{context:{role:h.context.role},items}});
  h.open=(id='bg')=>{const row=h.rows.find(r=>r.tracking_id===id),html=h.api.detailHtml(row);el('sales-build-requirements').hidden=!html;h.api.bindDetail(id);return html;};
  Object.assign(h,{el,calls,events});return h;
}
test('build eligibility requires current visible COSI, allowed salesperson and a nonconflicting Toyota order',()=>{
  const h=harness({admin:true});assert.deepEqual(builds.eligibleRows(h.rows).map(r=>r.tracking_id),['bg','pm']);
  assert.deepEqual(builds.eligibleRows(h.rows,'BG').map(r=>r.tracking_id),['bg']);
  assert.equal(builds.eligibleRows([{tracking_id:'empty',order:'',cosi:true,salesperson_code:'BG'}]).length,0);
});
test('module initialization issues no RPC and dropdown opening shares an already running regular read',async()=>{
  const h=harness();assert.equal(h.calls.length,0);const pending=h.api.refresh();assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'get_broome_sales_builds');
  const html=h.open();assert.match(html,/Loading accessories/);assert.equal(h.calls.length,1);
  h.resolve(0,[record()]);await pending;assert.match(h.el('sales-build-content').innerHTML,/Towbar|Sales export notes/);assert.equal(h.el('sales-build-requirements').hidden,false);
});
test('a new-scope first dropdown read begins only when no scoped data has been loaded',async()=>{
  const h=harness({admin:true});h.person='BG';h.open();assert.equal(h.calls.length,1);h.resolve(0,[record()]);await new Promise(resolve=>setImmediate(resolve));
  h.open();assert.equal(h.calls.length,1);h.person='PM';h.api.syncScope();assert.equal(h.el('sales-build-content').innerHTML,'');
  h.open('pm');assert.equal(h.calls.length,2);h.resolve(1,[record('pm','00002','PM-only requirement')]);await new Promise(resolve=>setImmediate(resolve));
  assert.match(h.el('sales-build-content').innerHTML,/PM-only requirement/);assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar/);
});
test('ordinary sales records are intersected with the approved own salesperson code',async()=>{
  const h=harness();const pending=h.api.refresh();h.open();h.resolve(0,[record(),record('pm','00002','Other salesperson requirement')]);await pending;
  assert.match(h.el('sales-build-content').innerHTML,/Towbar/);assert.equal(h.api.detailHtml(h.rows[1]),'');
  assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Other salesperson requirement/);
  delete h.context.salesperson_code;h.api.syncScope();assert.equal(h.api.detailHtml(h.rows[0]),'');assert.equal(h.el('sales-build-content').innerHTML,'');
});
test('a delayed read cannot repopulate the dropdown after sign-out',async()=>{
  const h=harness();const pending=h.api.refresh();h.open();delete h.host.PDC_AUTH_CONTEXT;h.events['pdc-auth-locked']();
  h.resolve(0,[record()]);await pending;assert.equal(h.el('sales-build-content').innerHTML,'');assert.equal(h.el('sales-build-requirements').hidden,true);
});
test('a replacement account or generation cannot receive an earlier accessory read',async()=>{
  for(const change of ['user','generation']) {
    const h=harness();const pending=h.api.refresh();h.open();if(change==='user')h.host.PDC_AUTH_CONTEXT={userId:'replacement'};else h.generation++;
    h.resolve(0,[record()]);await pending;assert.equal(h.el('sales-build-content').innerHTML,'');assert.equal(h.el('sales-build-requirements').hidden,true);
  }
});
test('selected-person changes suppress delayed old-person responses without depending on a render',async()=>{
  const h=harness({admin:true});h.person='BG';const pending=h.api.refresh();h.open();h.person='PM';h.resolve(0,[record()]);await pending;
  assert.equal(h.el('sales-build-content').innerHTML,'');assert.equal(h.el('sales-build-requirements').hidden,true);assert.doesNotMatch(h.api.detailHtml(h.rows[1]),/Towbar/);
});
test('a vehicle losing current source, sold, visible or unique identity status during a read is removed',async()=>{
  for(const patch of [{source_current:false},{cosi:'No'},{sales_hidden:true},{identity_conflict:true}]) {
    const h=harness();const pending=h.api.refresh();h.open();Object.assign(h.rows[0],patch);h.resolve(0,[record()]);await pending;
    assert.equal(h.el('sales-build-content').innerHTML,'');assert.equal(h.el('sales-build-requirements').hidden,true);assert.equal(h.api.detailHtml(h.rows[0]),'');
  }
});
test('Toyota order matching preserves leading zero identity and ignores stock changes as an identity key',async()=>{
  const h=harness();h.rows[0].stock='13099';const pending=h.api.refresh();h.open();h.resolve(0,[{...record(),stock:'13099',source_stock:'13001'}]);await pending;
  assert.match(h.el('sales-build-content').innerHTML,/Towbar|Imported stock 13001/);
  const next=h.api.refresh();h.resolve(1,[record('bg','1','Wrong order requirement')]);await next;
  assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Wrong order requirement|Towbar/);assert.match(h.el('sales-build-content').innerHTML,/No accessory requirements/);
});
test('out-of-order reads cannot replace the newest source requirements',async()=>{
  const h=harness();const first=h.api.refresh();h.open();const second=h.api.refresh();h.resolve(1,[record('bg','00001','Newest requirement')]);await second;
  h.resolve(0,[record('bg','00001','Earlier requirement')]);await first;
  assert.match(h.el('sales-build-content').innerHTML,/Newest requirement/);assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Earlier requirement/);
});
test('replaced Navision source identities immediately clear cached notes while preserving the open dropdown',async()=>{
  const h=harness();const pending=h.api.refresh();h.open();h.resolve(0,[record()]);await pending;
  h.el('sales-build-requirements').open=true;const oldRead=h.api.refresh();assert.match(h.el('sales-build-content').innerHTML,/Towbar/);
  h.rows[0].navision_record_id='replacement-source';h.api.syncScope();
  assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar|Customer note|Sales Export/);assert.match(h.el('sales-build-content').innerHTML,/Loading accessories/);assert.equal(h.el('sales-build-requirements').open,true);
  h.resolve(1,[record()]);await oldRead;assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar|Customer note/);
  const current=h.api.refresh();h.resolve(2,[{...record('bg','00001','Replacement source requirement'),navision_record_id:'replacement-source'}]);await current;
  assert.match(h.el('sales-build-content').innerHTML,/Replacement source requirement/);assert.equal(h.el('sales-build-requirements').open,true);
});
test('a source replacement during the first read rejects old imports and missing source identities',async()=>{
  for(const source of ['replacement-source',undefined]) {
    const h=harness();const pending=h.api.refresh();h.open();h.rows[0].navision_record_id=source;h.resolve(0,[record()]);await pending;
    assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar|Customer note/);
  }
  const h=harness();const pending=h.api.refresh();h.open();const missing=record();delete missing.navision_record_id;h.resolve(0,[missing]);await pending;
  assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar|Customer note/);
});
test('a failed source read clears stale data and uses an explicit retry state',async()=>{
  const h=harness();const pending=h.api.refresh();h.open();h.resolve(0,[record()]);await pending;
  const failed=h.api.refresh();h.resolve(1,null,'SQL/private message <unsafe>');await failed;
  assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar|SQL\/private message|<unsafe>/);assert.match(h.el('sales-build-content').innerHTML,/could not be loaded|Refresh vehicles/);
  const recovered=h.api.refresh();h.resolve(2,[]);await recovered;assert.match(h.el('sales-build-content').innerHTML,/No accessory requirements/);assert.doesNotMatch(h.el('sales-build-content').innerHTML,/could not be loaded/);
});
test('never-imported vehicles and an explicitly empty import remain distinct',async()=>{
  const h=harness();const pending=h.api.refresh();h.open();h.resolve(0,[]);await pending;assert.match(h.el('sales-build-content').innerHTML,/have been imported/);
  const empty=h.api.refresh();h.resolve(1,[{...record(),items:[],notes:[],other_lines:[]}]);await empty;
  assert.match(h.el('sales-build-content').innerHTML,/This import recorded no/);assert.match(h.el('sales-build-content').innerHTML,/Sales Export.xlsx/);
});
test('native dropdown and secondary review expansion survive polling content updates',async()=>{
  const h=harness();const pending=h.api.refresh();h.open();h.resolve(0,[record()]);await pending;
  const panel=h.el('sales-build-requirements'),body=h.el('sales-build-content');panel.open=true;body.child.open=true;
  const next=h.api.refresh();h.resolve(1,[record('bg','00001','Updated requirement')]);await next;
  assert.equal(panel.open,true);assert.equal(body.child.open,true);assert.match(body.innerHTML,/Updated requirement/);
  h.api.closeDetail();assert.equal(panel.open,false);assert.equal(body.innerHTML,'');
});
test('source descriptions and multiline notes are escaped and displayed without editable progress controls',()=>{
  const source={...record(),items:[{description:'<img src=x onerror=alert(1)>',source_rows:[7,'<unsafe>'],quote_number:'<quote>'}],notes:[{text:'First line\n<script>second line</script>',source_rows:[8]}],other_lines:[{description:'<other>',source_rows:[9],reason:'<reason>'}],source_file:'C:\\private\\<file>.xlsx',amount:12345};
  const html=builds.recordContent(builds.normaliseRecord(source));assert.match(html,/&lt;img|&lt;script&gt;|&lt;other&gt;|&lt;reason&gt;|&lt;file&gt;/);assert.match(html,/First line\n/);assert.match(html,/Source row 7/);
  assert.doesNotMatch(html,/<img|<script>|C:\\private|12345|type="checkbox"|<form|data-ordering|Completed|Orders Raised/);
});
test('malformed or duplicate imported identities fail without keeping the earlier source',async()=>{
  for(const invalid of [[record(),record('bg','00001','Duplicate')],[{...record(),notes:'not an array'}]]) {
    const h=harness();const pending=h.api.refresh();h.open();h.resolve(0,[record()]);await pending;
    const next=h.api.refresh();h.resolve(1,invalid);await next;assert.match(h.el('sales-build-content').innerHTML,/could not be loaded/);assert.doesNotMatch(h.el('sales-build-content').innerHTML,/Towbar|Duplicate/);
  }
});
test('Sales entrypoint includes isolated accessory assets and modal content lives outside editable CRM',()=>{
  const index=fs.readFileSync('sales/index.html','utf8'),source=fs.readFileSync('sales/sales.js','utf8'),module=fs.readFileSync('sales/build-requirements.js','utf8');
  assert.match(index,/build-requirements\.css\?v=2026\.10\.03\.02/);assert.match(index,/build-requirements\.js\?v=2026\.10\.03\.02/);assert.match(index,/build-requirements=2026\.10\.03\.02/);
  assert.match(source,/sales-pmb-live[\s\S]{0,100}BROOME_SALES_BUILDS\?\.detailHtml\(r\)[\s\S]{0,30}BROOME_SALES_CRM\?\.detailHtml\(r\)/);
  assert.doesNotMatch(module,/localStorage|sessionStorage|\.from\(|save_broome|import_broome|update_pdc|insert\(|<input|<form/);assert.match(module,/rpc\('get_broome_sales_builds'\)/);
});
function integratedHarness({crm=false}={}) {
  const elements=new Map(),events=new Map(),calls=[];
  const el=id=>{
    if(!elements.has(id)) {
      let content='';const node={id,writes:0,textContent:'',hidden:false,disabled:false,value:'',open:false,dataset:{},events:{},classList:{toggle(){}},setAttribute(){},removeAttribute(){},querySelector(){return null;},addEventListener(name,fn){this.events[name]=fn;},close(){this.open=false;this.events.close?.();},showModal(){this.open=true;}};
      Object.defineProperty(node,'innerHTML',{get:()=>content,set:value=>{node.writes++;content=value;}});elements.set(id,node);
    }
    return elements.get(id);
  };
  const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>[],addEventListener(){}},PDC_AUTH_CONTEXT:{userId:'A',role:'salesperson'},BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),
    PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(name,fn){if(!events.has(name))events.set(name,[]);events.get(name).push(fn);},setInterval(){}};
  if(crm)window.BROOME_SALES_CRM={init(){},clear(){},syncScope(){},render(){},setWorkspace(){},detailHtml(){return '<section id="sales-crm-detail">Customer form</section>';},bindDetail(){}};
  const sandbox={window,globalThis:window,module:undefined,Set,Map,Date,console};
  vm.runInNewContext(fs.readFileSync('sales/build-requirements.js','utf8'),sandbox);vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),sandbox);
  return {window,el,calls,dispatch(name){for(const fn of events.get(name)||[])fn();}};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const snapshot=()=>({data:{context:{role:'salesperson',salesperson_code:'BG'},items:[{tracking_id:'bg',navision_record_id:'source-bg',order:'00001',stock:'13001',cosi:true,source_current:true,salesperson_code:'BG'}]}});
test('combined Sales lifecycle fetches requirements after the snapshot without replacing the customer modal',async()=>{
  const h=integratedHarness();assert.equal(h.calls[0].name,'get_broome_sales_snapshot');h.calls[0].resolve(snapshot());await tick();
  assert.equal(h.calls[1].name,'get_broome_sales_builds');
  h.el('vehicle-table').events.click({target:{closest:selector=>selector==='[data-open]'?{dataset:{open:'bg'}}:null}});
  const writes=h.el('sales-detail-content').writes;assert.equal(h.calls.length,2);
  h.el('sales-crm-detail').innerHTML='Unsaved customer form';h.el('sales-build-requirements').open=true;
  h.calls[1].resolve({data:{context:{role:'salesperson'},items:[record()]}});await tick();
  assert.match(h.el('sales-build-content').innerHTML,/Towbar/);assert.equal(h.el('sales-detail-content').writes,writes);assert.equal(h.el('sales-crm-detail').innerHTML,'Unsaved customer form');assert.equal(h.el('sales-build-requirements').open,true);
  h.el('sales-refresh').events.click();h.calls[2].resolve(snapshot());await tick();assert.equal(h.calls[3].name,'get_broome_sales_builds');h.calls[3].resolve({data:{context:{role:'salesperson'},items:[record('bg','00001','Second import')]}});await tick();
  assert.equal(h.el('sales-detail-content').writes,writes);assert.match(h.el('sales-build-content').innerHTML,/Second import/);
});
test('an old Sales refresh stops after a delayed build read when the account is replaced',async()=>{
  const h=integratedHarness({crm:true});h.calls[0].resolve(snapshot());await tick();assert.equal(h.calls[1].name,'get_broome_sales_builds');
  h.window.PDC_AUTH_CONTEXT={userId:'B',role:'salesperson'};h.dispatch('pdc-auth-ready');assert.equal(h.calls[2].name,'get_broome_sales_snapshot');
  h.calls[1].resolve({data:{context:{role:'salesperson'},items:[record()]}});await tick();
  assert.equal(h.calls.filter(call=>call.name==='get_broome_sales_workspace').length,0);assert.equal(h.el('sales-build-content').innerHTML,'');
  h.calls[2].resolve({error:{message:'Not approved'}});await tick();assert.equal(h.el('sales-build-content').innerHTML,'');
});
