'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const ui=require('./pdc-new-vehicles.js');
const source=fs.readFileSync(require.resolve('./pdc-new-vehicles.js'),'utf8');
const plain=value=>JSON.parse(JSON.stringify(value));
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function vehicle(id,departments=['138']) {
  return {vehicle_id:id,stock_number:`TEST-${id}`,status:'pending',snapshot_hash:`hash-${id}`,department_codes:[...new Set(departments)],
    has_unknown_department:departments.some(department=>!department),received_at:'2026-09-18T00:00:00Z',job_cards:[`JC-${id}`],
    operations:departments.map((department,i)=>({line_identity:`${id}-${i}`,source_line_id:`source-${id}-${i}`,department,
      description:`${department==='138'?'Fit Bus accessory':'Fit PD accessory'} ${i}`,stage_code:department==='138'?'BUS_4X4':'FITTING',
      active:true,completed:false,estimated_hours:1,source_kind:'authenticated'}))};
}
const receipt=row=>({ok:true,data:{vehicle_id:row.vehicle_id,visible_on_board:true,bookings_created:0,operations:row.operations.map(line=>({...line}))}});
function fixture(department='') {
  const calls=[],badge={},events={},state={refreshes:0,selection:department,sequence:0};
  const page={innerHTML:'',insertAdjacentHTML(_p,html){this.innerHTML+=html;},querySelector:()=>null,querySelectorAll:()=>[]};
  const context={...ui,page,console,Promise,app:{currentView:'newvehicles'},document:{visibilityState:'visible'},
    nav:{querySelector:()=>badge,setAttribute(){}},CSS:{escape:value=>value},crypto:{randomUUID:()=>`request-${++state.sequence}`},
    window:{PDC_AUTH_CONTEXT:{userId:'test-operator',role:'operator'},PDC_DEPARTMENT_FILTER:{getSelection:()=>state.selection,setSelection:value=>{
      state.selection=value;events['pdc-department-filter-changed']?.({detail:{department:value}});
    }},addEventListener:(name,handler)=>events[name]=handler},
    getPdcSupabaseAccessToken:()=> 'session-token',readable:()=>true,writable:()=>true,preserveEditorFocus:()=>()=>{},
    refreshEmailVehicleLocations:async()=>{state.refreshes++;},loadSharedNavisionVisibleRows:async()=>{},
    rpc:(name,payload)=>new Promise((resolve,reject)=>calls.push({name,payload,resolve,reject}))};
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('  let items='),source.indexOf('  const readable=')),context);
  vm.runInContext(source.slice(source.indexOf('  function message(err)'),source.indexOf('  function choose(')),context);
  vm.runInContext(source.slice(source.indexOf('  function card(row)'),source.indexOf('  const previousRender=')),context);
  vm.runInContext(source.slice(source.indexOf("  window.addEventListener('pdc-department-filter-changed'"),source.indexOf("  window.addEventListener('pdc-auth-locked'")),context);
  return {context,calls,page,badge,state,events,set:code=>vm.runInContext(code,context),get:code=>vm.runInContext(code,context),
    resolve(index,rows=[],extra={}){const call=calls[index];call.resolve({ok:true,data:{items:rows,total:rows.length,department:call.payload.p_department,...extra}});}};
}

test('department reads retain All compatibility and selected scopes never fall back',()=>{
  assert.deepEqual(ui.departmentReadRequest('list_pdc_new_vehicle_reviews',{p_offset:50,p_limit:50}),{name:'list_pdc_new_vehicle_reviews',payload:{p_offset:50,p_limit:50}});
  assert.deepEqual(ui.departmentReadRequest('list_pdc_tune_operation_changes',{p_offset:100,p_limit:50},'139'),{name:'list_pdc_tune_operation_changes_by_department',payload:{p_offset:100,p_limit:50,p_department:'139'}});
  assert.throws(()=>ui.verifyDepartmentResponse({ok:true,data:{}},'138'),/department_scope_mismatch/);
  assert.throws(()=>ui.verifyDepartmentResponse({ok:true,data:{department:'139'}},'138'),/department_scope_mismatch/);
});

test('scoped readiness excludes mixed or unknown work while All preserves existing approval rules',()=>{
  const same=vehicle('same'),mixed=vehicle('mixed',['138','139']),unknown=vehicle('unknown',['138','']);
  const metadata=vehicle('metadata');metadata.has_unknown_department=true;
  const extra=vehicle('extra');extra.department_codes.push('139');
  assert.deepEqual(ui.quickApprovalProblems(same,'138'),[]);
  for(const row of [mixed,unknown,metadata,extra]){
    assert.ok(ui.departmentApprovalProblems(row,'138').length);
    assert.doesNotMatch(ui.vehicleCardHtml(row,{canApprove:true,department:'138'}),/data-nv-quick-approve=/);
    assert.deepEqual(ui.quickApprovalProblems(row,''),[]);
  }
  const tint=vehicle('tint');tint.operations[0].description='Window tint';tint.operations[0].stage_code='TINT';
  assert.deepEqual(ui.quickApprovalProblems(tint,'138'),[],'shared Tint is still department 138 work');
});

test('scoped bulk scans every server-filtered page and approves only wholly matching vehicles',async()=>{
  const rows=[vehicle('one'),vehicle('mixed',['138','139']),vehicle('unknown',['138','']),vehicle('two')],reads=[],writes=[];
  const result=await ui.approveReadyQueue({department:'138',pageSize:2,
    listPage:async(offset,limit)=>{reads.push({offset,limit,writes:writes.length});return {ok:true,data:{department:'138',items:rows.slice(offset,offset+limit),total:rows.length,offset}};},
    approveRow:async row=>{writes.push(row.vehicle_id);return receipt(row);}});
  assert.deepEqual(reads,[{offset:0,limit:2,writes:0},{offset:2,limit:2,writes:0}]);
  assert.deepEqual(writes,['one','two']);assert.equal(result.needsReview,2);
  await assert.rejects(ui.approveReadyQueue({department:'138',listPage:async()=>({ok:true,data:{items:rows,total:rows.length}}),approveRow:async()=>{throw Error('must not write');}}),/department_scope_mismatch/);
});

test('switching department resets both pages and editor, and discards a late former-scope response',async()=>{
  const f=fixture('138');f.set("offset=100;updateOffset=50;selected={vehicle_id:'old'};queueSearch='old';");
  const first=f.context.load();assert.equal(f.calls[0].payload.p_offset,100);assert.equal(f.calls[1].payload.p_offset,50);
  f.context.window.PDC_DEPARTMENT_FILTER.setSelection('139');
  assert.equal(f.get('filterDepartment'),'139');assert.equal(f.get('selected'),null);assert.equal(f.get('offset'),0);assert.equal(f.get('updateOffset'),0);assert.equal(f.get('queueSearch'),'');
  assert.equal(f.calls.length,4);
  for(const index of [2,3]){assert.equal(f.calls[index].payload.p_department,'139');assert.equal(f.calls[index].payload.p_offset,0);}
  f.resolve(2,[vehicle('new',['139'])],{total:7});f.resolve(3,[],{total:2});await tick();
  f.resolve(0,[vehicle('old')],{total:1000});f.resolve(1,[],{total:999});await first;
  assert.equal(f.get('total'),7);assert.equal(f.get('updateTotal'),2);assert.equal(f.get('items[0].vehicle_id'),'new');
  assert.match(f.page.innerHTML,/Approve ready — 139/);assert.doesNotMatch(f.page.innerHTML,/TEST-old/);
});

test('unidentified groups and badge counts use the same department scope',async()=>{
  const f=fixture('138');f.set('unidentified=true;offset=50;');const load=f.context.load();
  assert.equal(f.calls[0].name,'list_pdc_unidentified_tune_reviews_by_department');
  assert.equal(f.calls[1].name,'get_pdc_review_counts_by_department');
  f.resolve(0,[],{total:51});f.resolve(1,[],{new_vehicles:6,operation_changes:3});await load;
  assert.equal(f.badge.textContent,'9');assert.match(f.page.innerHTML,/51 groups/);assert.match(f.page.innerHTML,/data-nv-department/);
  f.context.app.currentView='dashboard';const counts=f.context.loadCounts();
  assert.deepEqual(plain(f.calls[2].payload),{p_department:'138'});
  f.context.window.PDC_DEPARTMENT_FILTER.setSelection('139');
  f.resolve(3,[],{new_vehicles:4,operation_changes:1});await tick();
  f.resolve(2,[],{new_vehicles:100,operation_changes:100});await counts;
  assert.equal(f.badge.textContent,'5','late old-scope badge is ignored');
});

test('scope mismatch and missing scoped RPC fail closed without showing an unfiltered queue',async()=>{
  for(const failure of ['wrong department','missing endpoint']){
    const f=fixture('138');const load=f.context.load();
    if(failure==='wrong department')f.resolve(0,[vehicle('wrong',['139'])],{department:'139'});else f.calls[0].reject(Error('PGRST202'));
    f.resolve(1);await load;
    assert.equal(f.get('queueLoadFailed'),true);assert.equal(f.get('items.length'),0);assert.equal(f.calls.length,2);
    assert.match(f.page.innerHTML,/Queue unavailable/);assert.doesNotMatch(f.page.innerHTML,/TEST-wrong/);
  }
});

test('mixed vehicle explicit review displays all operations with clear whole-card approval notice',()=>{
  const f=fixture('138'),row=vehicle('mixed',['138','139']);f.context.row=row;
  f.set('items=[row];total=1;selected=row;choices=reviewChoices(row);render();');
  assert.match(f.page.innerHTML,/All its operations are shown below/);
  assert.match(f.page.innerHTML,/approves all displayed operations together/);
  assert.match(f.page.innerHTML,/Fit Bus accessory 0/);assert.match(f.page.innerHTML,/Fit PD accessory 1/);
  assert.equal((f.page.innerHTML.match(/data-nv-line=/g)||[]).length,2);
});

test('quick approval waits for its receipt before applying an externally changed department',async()=>{
  const f=fixture('138'),row=vehicle('ready');f.context.row=row;f.set('items=[row];total=1;');
  const save=f.context.quickApprove('ready');assert.equal(f.calls[0].name,'approve_pdc_new_vehicle_review');
  assert.match(f.page.innerHTML,/<select data-nv-department[^>]*disabled/);
  f.context.window.PDC_DEPARTMENT_FILTER.setSelection('139');
  assert.equal(f.get('filterDepartment'),'138');assert.equal(f.get('pendingDepartment'),'139');assert.equal(f.calls.length,1);
  f.calls[0].resolve(receipt(row));await save;
  assert.equal(f.get('saving'),false);assert.equal(f.get('filterDepartment'),'139');assert.equal(f.get('pendingDepartment'),null);
  assert.equal(f.state.refreshes,1);assert.equal(f.calls.length,3);
  assert.ok(f.calls.slice(1).every(call=>call.payload.p_department==='139'));
  f.resolve(1);f.resolve(2);await tick();
});

test('external department change stops bulk after its current vehicle and loads the new scope',async()=>{
  const f=fixture('138'),rows=[vehicle('first'),vehicle('second')];f.context.rows=rows;f.set('items=rows;total=rows.length;');
  const bulk=f.context.approveAllReady();assert.equal(f.calls[0].name,'list_pdc_new_vehicle_reviews_by_department');
  f.resolve(0,rows);await tick();assert.equal(f.calls[1].name,'approve_pdc_new_vehicle_review');
  f.context.window.PDC_DEPARTMENT_FILTER.setSelection('139');assert.equal(f.get('bulkStop'),true);
  f.calls[1].resolve(receipt(rows[0]));await bulk;
  assert.equal(f.calls.filter(call=>call.name==='approve_pdc_new_vehicle_review').length,1);
  assert.equal(f.get('filterDepartment'),'139');assert.equal(f.get('saving'),false);assert.equal(f.state.refreshes,1);
  assert.ok(f.calls.slice(2).every(call=>call.payload.p_department==='139'));
  f.resolve(2);f.resolve(3);await tick();
});

test('scope selection remains disabled during operation approval and both queues refresh in the deferred scope',async()=>{
  const f=fixture('138');f.set("updateItems=[{change_id:'change',vehicle_id:'existing',status:'pending',already_on_board:true,snapshot_hash:'hash',effective_hours:1,proposed:{department:'138',operation_description:'Bus accessory'}}];updateTotal=1;");
  const save=f.context.approveUpdate('change');assert.equal(f.calls[0].name,'approve_pdc_tune_operation_change_with_schedule');
  assert.match(f.page.innerHTML,/<select data-nv-department[^>]*disabled/);
  f.context.window.PDC_DEPARTMENT_FILTER.setSelection('139');f.calls[0].reject(Error('operation_schedule_conflict'));await save;
  assert.equal(f.get('filterDepartment'),'139');assert.equal(f.calls.length,3);
  assert.ok(f.calls.slice(1).every(call=>call.payload.p_department==='139'));f.resolve(1);f.resolve(2);await tick();
});
