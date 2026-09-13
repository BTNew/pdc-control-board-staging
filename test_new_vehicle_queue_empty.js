'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const ui=require('./pdc-new-vehicles.js');
const source=fs.readFileSync(path.join(__dirname,'pdc-new-vehicles.js'),'utf8');
const update={change_id:'added-tank',vehicle_id:'existing-vehicle',stock_number:'12657478',status:'pending',already_on_board:true,change_kind:'added',effective_hours:2,received_at:'2026-09-13T01:16:54Z',proposed:{proposed_station:'HOIST',operation_description:'ARB LONG RANGE TANK'}};

function fixture() {
  const page={innerHTML:'',insertAdjacentHTML(_position,html){this.innerHTML+=html;},querySelector(){return null;},querySelectorAll(){return [];}};
  const badge={};
  const context={...ui,console,page,nav:{querySelector:()=>badge,setAttribute(){}},app:{currentView:'newvehicles'},
    readable:()=>true,writable:()=>true,preserveEditorFocus:()=>()=>{},bindUpdates(){},card:row=>`<article>${row.stock_number}</article>`,
    rpc:async name=>({ok:true,data:name==='list_pdc_tune_operation_changes'?{items:[update],total:1}:{items:[{stock_number:'13042994',snapshot_hash:'new'}],total:1}})};
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('  let items='),source.indexOf('  const readable=')),context);
  vm.runInContext(source.slice(source.indexOf('  function message(err)'),source.indexOf('  function choose(row)')),context);
  vm.runInContext(source.slice(source.indexOf('  function render({'),source.indexOf('  async function approve()')),context);
  return {context,page,set:code=>vm.runInContext(code,context)};
}

test('an operation approval error does not make a loaded vehicle queue unavailable or hide pending changes',async()=>{
  const f=fixture();
  await f.context.load();
  f.set("queueSearch='12657478';error='The operation and booking times could not be saved safely.';render();");
  assert.match(f.page.innerHTML,/No vehicles on this page match/);
  assert.match(f.page.innerHTML,/Clear the search or try another page/);
  assert.doesNotMatch(f.page.innerHTML,/Queue unavailable/);
  assert.match(f.page.innerHTML,/role="alert">The operation and booking times could not be saved safely/);
  assert.match(f.page.innerHTML,/12657478 · Added operation/);
  assert.match(f.page.innerHTML,/Approve change &amp; update bookings|Approve change & update bookings/);
});

test('a failed queue load shows unavailable, and successful refresh clears only the load failure state',async()=>{
  const f=fixture();
  f.context.rpc=async()=>{throw Error('offline');};
  await f.context.load();
  assert.match(f.page.innerHTML,/Queue unavailable/);
  assert.match(f.page.innerHTML,/Refresh to load the new vehicle queue/);
  f.context.rpc=async()=>({ok:true,data:{items:[],total:0}});
  await f.context.load();
  f.set("error='An unrelated approval was not confirmed.';render();");
  assert.match(f.page.innerHTML,/No new vehicles waiting/);
  assert.doesNotMatch(f.page.innerHTML,/Queue unavailable/);
});

test('an operation update list failure does not relabel a successful empty new vehicle queue',async()=>{
  const f=fixture();
  f.context.rpc=async name=>{
    if(name==='list_pdc_tune_operation_changes')throw Error('offline');
    return {ok:true,data:{items:[],total:0}};
  };
  await f.context.load();
  assert.match(f.page.innerHTML,/No new vehicles waiting/);
  assert.match(f.page.innerHTML,/Updated operation lines could not be loaded/);
  assert.doesNotMatch(f.page.innerHTML,/Queue unavailable/);
});
