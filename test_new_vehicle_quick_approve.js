'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const ui=require('./pdc-new-vehicles.js');
const source=fs.readFileSync(path.join(__dirname,'pdc-new-vehicles.js'),'utf8');
const plain=value=>JSON.parse(JSON.stringify(value));
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
function vehicle(id='one',subletHours=null){return {vehicle_id:id,stock_number:'STOCK-'+id,status:'pending',snapshot_hash:'a'.repeat(64),current_location:'PMB',received_at:'2026-09-14T01:00:00Z',customer_name:'Sample customer',vehicle_description:'Sample vehicle',job_cards:['JC-'+id],operations:[
  {line_identity:'source:'+id+'-fit',source_line_id:id+'-fit',source_kind:'authenticated',description:'Fit kit',stage_code:'FITTING',estimated_hours:1.25,active:true,completed:false},
  {line_identity:'source:'+id+'-sub',source_line_id:id+'-sub',source_kind:'authenticated',description:'External work',stage_code:'SUBLET',estimated_hours:subletHours,active:true,completed:false},
]};}
function receipt(row){return {ok:true,data:{vehicle_id:row.vehicle_id,visible_on_board:true,bookings_created:0,operations:row.operations.map(line=>({...line}))}};}
function fixture(rows=[vehicle()]){
  const state={pending:[],renders:0,refreshes:0,loads:0,focus:[],token:'token-one',sequence:0};
  const context={...ui,console,crypto:{randomUUID:()=>`key-${++state.sequence}`},CSS:{escape:value=>value},
    window:{PDC_AUTH_CONTEXT:{userId:'operator-one',role:'operator'}},
    getPdcSupabaseAccessToken:()=>state.token,
    render:()=>state.renders++,load:async()=>{state.loads++;},
    refreshEmailVehicleLocations:async()=>{state.refreshes++;},loadSharedNavisionVisibleRows:async()=>{},
    page:{querySelector:selector=>({focus:options=>state.focus.push({selector,options})})},
    rpc:(name,payload)=>{const p=deferred();state.pending.push({name,payload,...p});return p.promise;},rows};
  context.writable=()=>['operator','administrator'].includes(context.window.PDC_AUTH_CONTEXT?.role);
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('  let items='),source.indexOf('  const readable=')),context);
  vm.runInContext(source.slice(source.indexOf('  function message(err)'),source.indexOf('  async function load(')),context);
  vm.runInContext(source.slice(source.indexOf('  async function approve()'),source.indexOf('  const previousRender=')),context);
  vm.runInContext('items=rows;total=rows.length;',context);
  return {context,state,set:code=>vm.runInContext(code,context),get:code=>vm.runInContext(code,context)};
}

test('quick readiness preserves valid workshop work and optional Sublet hours',()=>{
  for(const hours of [null,0,0.5]){const row=vehicle('one',hours),before=JSON.stringify(row);assert.deepEqual(ui.quickApprovalProblems(row),[]);assert.equal(JSON.stringify(row),before);}
});

test('quick readiness rejects unresolved stations and invalid workshop hours',()=>{
  for(const hours of [null,'',0,-1,1000,0.001,'invalid',Infinity]){const row=vehicle();row.operations[0].estimated_hours=hours;assert.ok(ui.quickApprovalProblems(row).length,`hours ${hours}`);}
  const row=vehicle();row.operations[0].stage_code='UNALLOCATED_MAPPING_REVIEW';row.operations[0].department='138';
  assert.deepEqual(ui.problems(row),[],'normal review keeps its preselection behaviour');
  assert.match(ui.quickApprovalProblems(row).join(' '),/station/,'quick action cannot silently apply the department default');
});

test('quick readiness rejects completed, inactive, duplicate and nonpending input',()=>{
  for(const change of [row=>row.status='approved',row=>row.operations=[],row=>row.operations[0].completed=true,row=>row.operations[0].active=false,row=>row.operations.push({...row.operations[0]}),row=>row.snapshot_hash='',row=>row.vehicle_id='']){
    const row=vehicle();change(row);assert.ok(ui.quickApprovalProblems(row).length);
  }
  assert.ok(ui.quickApprovalProblems(null).length);
  const row=vehicle();row.operations[0].hours_provenance='craig_standard_pre_delivery_1_hour';
  assert.match(ui.quickApprovalProblems(row).join(' '),/pre-delivery/);
  row.operations[0].estimated_hours=1;assert.deepEqual(ui.quickApprovalProblems(row),[]);
});

test('explicit identity and board state guards block quick approval before dispatch',async()=>{
  const active=vehicle();active.lifecycle_state='active';active.visible_on_board=false;
  assert.deepEqual(ui.quickApprovalProblems(active),[]);
  for(const fields of [{details_source:'identity_review'},{lifecycle_state:'completed'},{lifecycle_state:'rft'},{visible_on_board:true}]){
    const row={...vehicle(),...fields};assert.ok(ui.quickApprovalProblems(row).length);
    assert.doesNotMatch(ui.vehicleCardHtml(row,{canApprove:true}),/data-nv-quick-approve=/);
    const f=fixture([row]);await f.context.quickApprove(row.vehicle_id);assert.equal(f.state.pending.length,0);
  }
});

test('compact card has independent review/approval controls and escapes source text',()=>{
  const row=vehicle();row.customer_name='<img src=x onerror=bad>';row.stock_number='"bad<stock>';
  const html=ui.vehicleCardHtml(row,{canApprove:true,error:'<script>bad</script>'});
  assert.match(html,/^<article /);assert.match(html,/data-nv-open=/);assert.match(html,/data-nv-quick-approve=/);
  let buttons=0;for(const tag of html.match(/<\/?button\b[^>]*>/g)||[]){buttons+=tag.startsWith('</')?-1:1;assert.ok(buttons>=0&&buttons<=1,'buttons are not nested');}assert.equal(buttons,0);
  assert.doesNotMatch(html,/<img|<script/);assert.match(html,/&lt;img/);assert.match(html,/aria-label="Approve stock &quot;bad&lt;stock&gt; to board"/);
  assert.match(html,/role="alert"/);
});

test('quick control is absent for read-only or incomplete cards and disabled during refresh/save',()=>{
  const row=vehicle();assert.doesNotMatch(ui.vehicleCardHtml(row),/data-nv-quick-approve=/);
  const invalid=vehicle();invalid.operations[0].estimated_hours=0;assert.doesNotMatch(ui.vehicleCardHtml(invalid,{canApprove:true}),/data-nv-quick-approve=/);
  for(const options of [{refreshing:true},{busy:true,savingId:row.vehicle_id}]){
    const html=ui.vehicleCardHtml(row,{canApprove:true,...options});assert.match(html,/<button[^>]*data-nv-quick-approve[^>]*disabled/);
  }
  assert.match(ui.vehicleCardHtml(row,{canApprove:true,busy:true,savingId:row.vehicle_id}),/Saving…/);
});

test('quick approval sends unchanged mixed assignments and removes only the verified vehicle',async()=>{
  const row=vehicle(),other=vehicle('two'),before=JSON.stringify(row),f=fixture([row,other]);
  f.set('queueSearch="STOCK";listScroll=480;');const run=f.context.quickApprove('one');
  assert.equal(f.state.pending.length,1);assert.equal(f.state.pending[0].name,'approve_pdc_new_vehicle_review');
  assert.deepEqual(plain(f.state.pending[0].payload.p_assignments),[
    {line_identity:'source:one-fit',stage_code:'FITTING',estimated_hours:1.25},
    {line_identity:'source:one-sub',stage_code:'SUBLET'},
  ]);
  assert.equal(f.get('selected'),null,'quick approval does not open the editor');assert.equal(f.get('quickSavingId'),'one');
  f.state.pending[0].resolve(receipt(row));await run;
  assert.equal(JSON.stringify(row),before);assert.deepEqual(plain(f.get('items.map(row=>row.vehicle_id)')),['two']);
  assert.equal(f.get('total'),1);assert.equal(f.get('saving'),false);assert.equal(f.get('quickSavingId'),'');
  assert.equal(f.get('queueSearch'),'STOCK');assert.equal(f.get('listScroll'),480);
  assert.equal(f.state.refreshes,1);assert.equal(f.state.loads,1);assert.match(f.get('notice'),/No workshop booking was created/);
  assert.match(f.state.focus[0].selector,/two/);assert.equal(f.state.focus[0].options.preventScroll,true);
});

test('quick dispatch blocks read-only roles, loading/outage, selected editor and invalid rows',async()=>{
  for(const role of ['viewer','importer',undefined]){const f=fixture();f.context.window.PDC_AUTH_CONTEXT.role=role;await f.context.quickApprove('one');assert.equal(f.state.pending.length,0);}
  for(const setup of ['loading=true;','queueLoadFailed=true;','saving=true;','selected=items[0];','items[0].operations[0].estimated_hours=0;']){
    const f=fixture();f.set(setup);await f.context.quickApprove('one');assert.equal(f.state.pending.length,0,setup);
  }
  const f=fixture();await f.context.quickApprove('missing');assert.equal(f.state.pending.length,0);
});

test('rapid quick clicks cannot submit duplicate or concurrent vehicle approvals',async()=>{
  const f=fixture([vehicle(),vehicle('two')]);const first=f.context.quickApprove('one');
  await f.context.quickApprove('one');await f.context.quickApprove('two');assert.equal(f.state.pending.length,1);
  f.state.pending[0].reject(new Error('offline'));await first;assert.equal(f.get('saving'),false);assert.match(f.get('quickErrors.one'),/could not be confirmed/);
});

test('uncertain quick requests retain their exact payload per card on retries',async()=>{
  const f=fixture([vehicle(),vehicle('two')]);
  const runOne=f.context.quickApprove('one');f.state.pending[0].reject(new Error('offline'));await runOne;
  const runTwo=f.context.quickApprove('two');assert.notEqual(f.state.pending[1].payload.p_idempotency_key,f.state.pending[0].payload.p_idempotency_key);assert.equal(f.state.pending[1].payload.p_vehicle_id,'two');
  f.state.pending[1].reject(new Error('offline'));await runTwo;
  const retry=f.context.quickApprove('one');assert.equal(f.state.pending[2].payload,f.state.pending[0].payload);f.state.pending[2].reject(new Error('offline'));await retry;
  f.set('items[0]={...items[0],snapshot_hash:"b".repeat(64)};');const changed=f.context.quickApprove('one');assert.notEqual(f.state.pending[3].payload.p_idempotency_key,f.state.pending[0].payload.p_idempotency_key);f.state.pending[3].reject(new Error('review_changed'));await changed;
  assert.equal(f.get('items.length'),2);assert.match(f.get('quickErrors.one'),/changed/);
});

test('invalid receipts never remove a card or report approval success',async()=>{
  for(const mutate of [r=>r.data.vehicle_id='wrong',r=>r.data.bookings_created=1,r=>r.data.operations[0].description='changed',r=>r.data.operations[0].source_line_id='wrong',r=>r.data.operations[0].estimated_hours=9,r=>r.data.operations[1].estimated_hours=0,r=>r.data.operations[0].completed=true]){
    const row=vehicle(),f=fixture([row]),run=f.context.quickApprove('one'),result=receipt(row);mutate(result);f.state.pending[0].resolve(result);await run;
    assert.equal(f.get('items.length'),1);assert.equal(f.get('notice'),'');assert.equal(f.state.refreshes,0);assert.match(f.get('quickErrors.one'),/could not be confirmed/);
  }
});

test('a token or role change prevents a late success from being accepted',async()=>{
  for(const change of [f=>f.state.token='new-token',f=>f.context.window.PDC_AUTH_CONTEXT.role='viewer']){
    const row=vehicle(),f=fixture([row]),run=f.context.quickApprove('one');change(f);f.state.pending[0].resolve(receipt(row));await run;
    assert.equal(f.get('items.length'),1);assert.equal(f.get('saving'),false);assert.equal(f.get('notice'),'');assert.equal(f.state.refreshes,0);assert.match(f.get('quickErrors.one'),/session changed/);
  }
});

test('a late former-session result cannot alter a new operator save',async()=>{
  const row=vehicle(),f=fixture([row,vehicle('two')]),first=f.context.quickApprove('one');
  f.set('generation++;sessionGeneration++;saving=false;approvalRequest=null;requestKey="";quickRequests={};quickErrors={};quickSavingId="";');
  f.context.window.PDC_AUTH_CONTEXT.userId='operator-two';f.state.token='token-two';const second=f.context.quickApprove('two');
  f.state.pending[0].resolve(receipt(row));await first;
  assert.equal(f.get('saving'),true);assert.equal(f.get('quickSavingId'),'two');assert.equal(f.get('notice'),'');assert.equal(f.state.refreshes,0);
  f.state.pending[1].reject(new Error('offline'));await second;assert.equal(f.get('saving'),false);assert.match(f.get('quickErrors.two'),/could not be confirmed/);
});

test('normal reviewed approval still uses the shared saver and explicit edited hours',async()=>{
  const row=vehicle(),f=fixture([row]);f.set('selected=items[0];choices=reviewChoices(selected);hourDrafts={[selected.operations[0].line_identity]:2.5};');
  const run=f.context.approve();assert.equal(f.state.pending[0].payload.p_assignments[0].estimated_hours,2.5);
  const result=receipt(row);result.data.operations[0].estimated_hours=2.5;f.state.pending[0].resolve(result);await run;
  assert.equal(f.get('selected'),null);assert.equal(f.get('items.length'),0);assert.match(f.get('notice'),/approved and added/);
});

test('bulk button checks all pages and refreshes the board once after the batch',async()=>{
  const rows=[vehicle('one'),vehicle('two')],f=fixture(rows);
  f.set('queueSearch="only-one-card";offset=50;');
  const run=f.context.approveAllReady();
  await f.context.approveAllReady();await f.context.quickApprove('one');
  assert.equal(f.state.pending.length,1,'repeat clicks and individual saves are blocked while checking');
  assert.equal(f.state.pending[0].name,'list_pdc_new_vehicle_reviews');
  assert.equal(f.state.pending[0].payload.p_offset,0,'bulk starts from the whole queue, not the current page');
  f.state.pending[0].resolve({ok:true,data:{items:rows,total:2,offset:0,has_more:false}});
  await new Promise(setImmediate);
  assert.equal(f.state.pending[1].name,'approve_pdc_new_vehicle_review');
  assert.equal(f.state.pending[1].payload.p_vehicle_id,'one');
  f.state.pending[1].resolve(receipt(rows[0]));await new Promise(setImmediate);
  assert.equal(f.state.refreshes,0,'there is no full board refresh per vehicle');
  f.state.pending[2].resolve(receipt(rows[1]));await run;
  assert.equal(f.get('saving'),false);assert.equal(f.get('bulkState'),null);assert.equal(f.get('items.length'),0);
  assert.equal(f.state.refreshes,1);assert.equal(f.state.loads,1);assert.equal(f.get('offset'),0);
  assert.match(f.get('notice'),/2 vehicles approved/);
});

test('bulk preflight failures stay visible and never start approvals or a clearing reload',async()=>{
  const f=fixture(),run=f.context.approveAllReady();
  f.state.pending[0].resolve({ok:true,data:{items:[vehicle(),vehicle()],total:2}});await run;
  assert.equal(f.state.pending.length,1);assert.equal(f.state.refreshes,0);assert.equal(f.state.loads,0);
  assert.match(f.get('error'),/queue changed/);assert.equal(f.get('saving'),false);
});

test('bulk unknown saves retain an identical request on retry',async()=>{
  const row=vehicle(),f=fixture([row]);
  const first=f.context.approveAllReady();f.state.pending[0].resolve({ok:true,data:{items:[row],total:1}});await new Promise(setImmediate);
  f.state.pending[1].reject(new Error('offline'));await first;
  assert.equal(f.get('items.length'),1);assert.match(f.get('notice'),/could not be confirmed/);
  const retry=f.context.approveAllReady();f.state.pending[2].resolve({ok:true,data:{items:[row],total:1}});await new Promise(setImmediate);
  assert.equal(f.state.pending[3].payload,f.state.pending[1].payload);
  f.state.pending[3].resolve(receipt(row));await retry;assert.equal(f.get('items.length'),0);
});

test('bulk approval ownership cannot leak into another signed-in session',async()=>{
  const row=vehicle(),f=fixture([row]),first=f.context.approveAllReady();
  f.state.pending[0].resolve({ok:true,data:{items:[row],total:1}});await new Promise(setImmediate);
  f.set('generation++;sessionGeneration++;bulkState=null;saving=false;bulkStop=true;');
  f.context.window.PDC_AUTH_CONTEXT.userId='operator-two';f.state.token='token-two';
  f.set('saving=true;notice="New session action";');
  f.state.pending[1].resolve(receipt(row));await first;
  assert.equal(f.get('saving'),true);assert.equal(f.get('notice'),'New session action');
  assert.equal(f.state.refreshes,0);assert.equal(f.get('items.length'),1);
});

test('bulk token expiry unlocks the UI without accepting a late receipt',async()=>{
  const row=vehicle(),f=fixture([row]),run=f.context.approveAllReady();
  f.state.pending[0].resolve({ok:true,data:{items:[row],total:1}});await new Promise(setImmediate);
  f.state.token='refreshed-token';f.state.pending[1].resolve(receipt(row));await run;
  assert.equal(f.get('saving'),false);assert.equal(f.get('items.length'),1);assert.equal(f.state.loads,0);
  assert.match(f.get('error'),/session changed/);assert.equal(f.state.refreshes,0);
});
