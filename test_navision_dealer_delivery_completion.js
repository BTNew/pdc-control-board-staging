'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const sales=require('./sales/sales.js');
const {createFixture}=require('./qa/dashboard-render-fixture.cjs');

test('completed PMB lifecycle overrides stale running, stopped and planned sales bookings',()=>{
 for(const status of ['planned','started','stoppage']){
  const row={canonical_vehicle_id:'linked',pmb_location:'Completed',workshop_status:status,
   pmb_stoppage_started_at:'2026-10-01T00:00:00Z',bay_bookings:[{status,stage:'Bus 4x4',bay:'Bay 05'}]};
  assert.deepEqual(sales.pmbSummary(row),{status:'Completed · Delivered to dealer',location:'Completed Vehicles',bookings:[]});
  assert.equal(sales.pmbSummary({...row,pmb_location:'PMB',lifecycle_state:'completed'}).bookings.length,0);
 }
});
test('ordinary PMB bookings retain their live and queued display',()=>{
 const row={canonical_vehicle_id:'linked',pmb_location:'PMB',bay_bookings:[{status:'planned',stage:'Fitting',bay:'Bay 2'}]};
 assert.equal(sales.pmbSummary(row).status,'Booked · Fitting / Bay 2');
 assert.equal(sales.pmbSummary({...row,bay_bookings:[{status:'started',stage:'Fitting',bay:'Bay 2'}]}).status,'Work started · Fitting / Bay 2');
 assert.equal(sales.pmbSummary({...row,bay_bookings:[],workshop_status:'queued'}).status,'Awaiting bay booking');
});
test('shared import preview and receipt disclose completion and history retention',()=>{
 const f=createFixture({vehicleCount:0}),host={innerHTML:''};
 f.context.document.querySelector=selector=>selector==='#navision-status-list'?host:null;
 const data={counts:{total:2,new:0,changed:2,unchanged:0,invalid:0,conflict:0},items:[],blocking:false};
 const state={dealerCode:'broome',previewResult:{ok:true,data},previewData:data,applyResult:{ok:true,data}};
 for(const applied of [false,true]){
  f.context.renderSharedNavisionPreview(state,applied);
  assert.match(host.innerHTML,/Delivered - At Dealer/);
  assert.match(host.innerHTML,/Completed Vehicles/);
  assert.match(host.innerHTML,/booking/);
  assert.match(host.innerHTML,/History is retained|history|QC results are preserved/);
  assert.doesNotMatch(host.innerHTML,/Cars activated or moved|does not.*alter workshop bookings/);
 }
});
