'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {mapServerVehicle,reconcileVehicleRows}=require('./pdc-email-vehicle-location-service.js');
const {ready,controls}=require('./pdc-rft-actions.js');
const options={key:'SYNTHETIC',allowed:true,authority:true,inFlight:false,collectionEnabled:false};
const raw={id:'00000000-0000-4000-8000-000000000111',permanent_vehicle_id:'SYNTHETIC-QC',
 stock_number:'SYNTHETIC',version:39,current_location:'RFT',lifecycle_state:'rft',
 qc_completed_at:'2026-09-10T00:01:54.043702+00:00',qc_completed_by:'00000000-0000-4000-8000-000000000222',
 rft_transferred_at:'2026-09-10T00:01:54.053215+00:00',rft_collected_at:null};
test('omitted feed timestamps reproduce Awaiting QC despite RFT location',()=>{
 const {qc_completed_at,qc_completed_by,rft_transferred_at,...omitted}=raw;
 assert.match(controls(mapServerVehicle(omitted),options),/Awaiting QC/);
});
test('canonical snapshot maps through reconciliation to QC signed off awaiting PMB',()=>{
 const mapped=mapServerVehicle(raw);
 const stale={...mapped,pdcQcComplete:false,pdcQcCompleteAt:'',rftTransferredAt:''};
 const reconciled=reconcileVehicleRows([stale],[raw],{authoritative:true}).rows;
 assert.equal(reconciled.length,1);
 assert.equal(ready(reconciled[0]),false);
 const html=controls(reconciled[0],options);
 assert.match(html,/QC’d/); assert.doesNotMatch(html,/Awaiting QC/);
 assert.match(html.match(/<button[^>]+data-rft-transport-booked-key[^>]*>/)[0],/disabled/);
 assert.doesNotMatch(html.match(/<button[^>]+data-pmb-rft-release-key[^>]*>/)[0],/disabled/);
 assert.match(html.match(/<button[^>]+data-rft-collected-key[^>]*>/)[0],/disabled/);
 assert.equal(reconciled[0].pdcQcCompleteAt,raw.qc_completed_at);
});
test('fresh reinspection nulls replace a stale previous signed-off state',()=>{
 const old=mapServerVehicle(raw);
 const fresh={...raw,version:40,current_location:'QC',lifecycle_state:'active',
  qc_completed_at:null,qc_completed_by:null,rft_transferred_at:null};
 const v=reconcileVehicleRows([old],[fresh],{authoritative:true}).rows[0];
 assert.equal(ready(v),false); assert.equal(v.pdcQcComplete,false);
 assert.equal(v.pdcQcCompleteAt,''); assert.equal(v.rftTransferredAt,'');
 assert.match(controls(v,options),/Awaiting QC/);
});
test('RFT location or a transfer timestamp alone never invents sign-off',()=>{
 for(const patch of [{qc_completed_at:null},{rft_transferred_at:null}])
  assert.equal(ready(mapServerVehicle({...raw,...patch})),false);
 assert.equal(ready({...mapServerVehicle(raw),__emailVehicleServerAuthoritative:false}),false);
});
test('migration is staging guarded, canonical UUID scoped and does not write vehicle state',()=>{
 const sql=fs.readFileSync('supabase/staging_only/20260910002538_qc_rft_snapshot_reconciliation.sql','utf8');
 assert.match(sql,/pdc_monitor_staging_guard/);
 assert.match(sql,/canonical.id=\(row_value->>''id''\)::uuid/);
 for(const field of ['qc_completed_at','qc_completed_by','rft_transferred_at'])
  assert.ok(sql.includes('canonical.'+field));
 assert.doesNotMatch(sql,/UPDATE\s+public\.vehicles|INSERT\s+INTO|DELETE\s+FROM|finalize_pdc_qc/i);
});
