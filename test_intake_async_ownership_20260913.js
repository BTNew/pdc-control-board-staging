'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const ui=require('./pdc-new-vehicles.js');
const source=fs.readFileSync(path.join(__dirname,'pdc-new-vehicles.js'),'utf8');
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
const newVehicle=(id='new-vehicle')=>({vehicle_id:id,stock_number:id,status:'pending',snapshot_hash:'snapshot-'+id,operations:[{line_identity:'line-'+id,source_line_id:'source-'+id,stage_code:'HOIST',description:'Fit tank',estimated_hours:2,active:true,completed:false}]});
const update={change_id:'update',vehicle_id:'existing',stock_number:'12657478',status:'pending',already_on_board:true,change_kind:'added',effective_hours:2,snapshot_hash:'update-hash',proposed:{proposed_station:'HOIST',operation_description:'Fit tank'}};

function fixture(){
  const state={pending:[],renders:0,token:'session-token',refreshes:0};
  const context={...ui,console,crypto:{randomUUID:()=>`request-${state.pending.length}`},window:{PDC_AUTH_CONTEXT:{userId:'operator-1'}},
    getPdcSupabaseAccessToken:()=>state.token,readable:()=>true,writable:()=>true,
    render:()=>state.renders++,refreshEmailVehicleLocations:async()=>{state.refreshes++;},loadSharedNavisionVisibleRows:async()=>{},
    rpc:(name,payload)=>{const pending=deferred();state.pending.push({name,payload,...pending});return pending.promise;}};
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('  let items='),source.indexOf('  const readable=')),context);
  vm.runInContext(source.slice(source.indexOf('  function message(err)'),source.indexOf('  function choose(row)')),context);
  vm.runInContext(source.slice(source.indexOf('  async function approveUpdate('),source.indexOf('  function bindUpdates(')),context);
  vm.runInContext(source.slice(source.indexOf('  async function approve()'),source.indexOf('  const previousRender=')),context);
  return {context,state,set:code=>vm.runInContext(code,context),get:code=>vm.runInContext(code,context)};
}
function receipt(row){return {ok:true,data:{vehicle_id:row.vehicle_id,visible_on_board:true,bookings_created:0,operations:row.operations.map(line=>({...line}))}};}
const empty={ok:true,data:{items:[],total:0}};

test('new vehicle and operation queues start together, and an intake outage does not hide valid operation changes',async()=>{
  const f=fixture(),loading=f.context.load({silent:true});
  assert.deepEqual(f.state.pending.map(row=>row.name),['list_pdc_new_vehicle_reviews','list_pdc_tune_operation_changes']);
  assert.equal(f.state.renders,1,'silent loading updates navigation state before awaiting data');
  f.state.pending[0].reject(new Error('offline'));
  f.state.pending[1].resolve({ok:true,data:{items:[update],total:1}});
  await loading;
  assert.equal(f.get('updateTotal'),1);assert.equal(f.get('updateItems[0].change_id'),'update');assert.equal(f.get('queueLoadFailed'),true);
});

test('stale list responses cannot repopulate a newly signed-in session',async()=>{
  const f=fixture(),old=f.context.load();
  f.set('generation++;sessionGeneration++;loading=false;items=[];updateItems=[];');
  f.state.pending[0].resolve({ok:true,data:{items:[newVehicle('old-account')],total:1}});
  f.state.pending[1].resolve({ok:true,data:{items:[update],total:1}});
  await old;
  assert.equal(f.get('items.length'),0);assert.equal(f.get('updateItems.length'),0);
});

test('review queue destination and cursors are captured when the request starts',async()=>{
  const f=fixture();f.set('offset=50;updateOffset=100;');const loading=f.context.load();
  f.set('unidentified=true;offset=0;updateOffset=0;');
  f.state.pending[0].resolve({ok:true,data:{items:[newVehicle()],total:51}});f.state.pending[1].resolve(empty);await loading;
  assert.equal(f.state.pending[0].payload.p_offset,50);assert.equal(f.state.pending[1].payload.p_offset,100);
  assert.equal(f.get('items[0].vehicle_id'),'new-vehicle');assert.equal(f.get('unidentifiedItems.length'),0);
});

test('late new-vehicle approval failure cannot unlock or overwrite a newer operator save',async()=>{
  const f=fixture();f.context.first=newVehicle('first');f.set('selected=first;choices=reviewChoices(first);');
  const first=f.context.approve();
  f.set('generation++;sessionGeneration++;saving=false;approvalRequest=null;requestKey="";error="";');
  f.context.window.PDC_AUTH_CONTEXT.userId='operator-2';f.state.token='new-token';f.context.second=newVehicle('second');f.set('selected=second;choices=reviewChoices(second);');
  const second=f.context.approve();
  f.state.pending[0].reject(new Error('session_changed'));await first;
  assert.equal(f.get('saving'),true);assert.equal(f.get('error'),'');assert.equal(f.get('selected.vehicle_id'),'second');
  assert.equal(f.get('approvalRequest.p_vehicle_id'),'second');
  f.state.pending[1].reject(new Error('offline'));await second;
  assert.equal(f.get('saving'),false);assert.match(f.get('error'),/could not be confirmed/);
});

test('unconfirmed approval keeps exactly the same idempotency key and assignments on a manual retry',async()=>{
  const f=fixture();f.context.row=newVehicle();f.set('selected=row;choices=reviewChoices(row);hourDrafts={};');
  const first=f.context.approve();f.state.pending[0].reject(new Error('offline'));await first;
  const retry=f.context.approve();assert.equal(f.state.pending[0].payload,f.state.pending[1].payload);
  f.state.pending[1].reject(new Error('offline'));await retry;
});

test('a refreshed token does not accept an old response or leave intake permanently saving',async()=>{
  const f=fixture(),row=newVehicle();f.context.row=row;f.set('selected=row;choices=reviewChoices(row);');
  const approval=f.context.approve();f.state.token='refreshed-token';f.state.pending[0].resolve(receipt(row));await approval;
  assert.equal(f.get('saving'),false);assert.equal(f.get('selected.vehicle_id'),row.vehicle_id);assert.equal(f.state.refreshes,0);
  assert.match(f.get('error'),/sign-in session changed/);
});

test('new-vehicle approval invalidates an older read so it cannot put an approved row back in the queue',async()=>{
  const f=fixture(),row=newVehicle();f.context.row=row;f.set('selected=row;choices=reviewChoices(row);');
  const oldLoad=f.context.load({silent:true});const approval=f.context.approve();
  f.state.pending[2].resolve(receipt(row));await approval;
  assert.equal(f.get('selected'),null);assert.match(f.get('notice'),/approved and added/);
  f.state.pending[0].resolve({ok:true,data:{items:[row],total:1}});f.state.pending[1].resolve(empty);await oldLoad;
  assert.equal(f.get('items.length'),0);assert.equal(f.get('loading'),true,'new post-approval refresh owns the loading state');
  f.state.pending[3].resolve(empty);f.state.pending[4].resolve(empty);
});

test('operation approval also invalidates older queue reads while saving',async()=>{
  const f=fixture();f.context.change=update;f.set('updateItems=[change];');const oldLoad=f.context.load({silent:true});
  const approval=f.context.approveUpdate('update');const before=f.get('generation');
  f.state.pending[0].resolve(empty);f.state.pending[1].resolve({ok:true,data:{items:[{...update,stock_number:'stale'}],total:1}});await oldLoad;
  assert.equal(f.get('updateItems[0].stock_number'),'12657478');assert.equal(f.get('saving'),true);assert.equal(f.get('generation'),before);
  f.state.pending[2].reject(new Error('offline'));await approval;assert.equal(f.get('saving'),false);
});
