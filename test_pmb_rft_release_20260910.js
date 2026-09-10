'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {controls,qcSigned,ready,collected}=require('./pdc-rft-actions.js');
const qc={__emailVehicleServerAuthoritative:true,__emailVehicleId:'fixture-id',__emailVehicleVersion:10,
 pdcQcComplete:true,pdcQcCompleteAt:'2026-09-10T01:00:00Z',rftTransferredAt:'2026-09-10T01:00:01Z',pdcLocation:'RFT'};
const opts={key:'fixture',allowed:true,authority:true,inFlight:false,collectionEnabled:false};
const button=(html,key)=>html.match(new RegExp('<button[^>]+data-'+key+'[^>]*>'))?.[0];
test('mobile QC shows QC tick and PMB release button; email and collection remain disabled',()=>{
 const html=controls(qc,opts);
 assert.equal(qcSigned(qc),true);assert.equal(ready(qc),false);
 assert.match(html,/QC’d/);
 assert.match(html,/Mark RFT’d/);
 assert.doesNotMatch(button(html,'pmb-rft-release-key'),/disabled/);
 assert.match(button(html,'rft-transport-booked-key'),/disabled/);
 assert.match(button(html,'rft-collected-key'),/disabled/);
});
test('PMB confirmation for this inspection enables email without collecting',()=>{
 const v={...qc,rftConfirmedAt:'2026-09-10T01:05:00Z'};
 assert.equal(ready(v),true);assert.equal(collected(v),false);
 const html=controls(v,opts);
 assert.match(html,/QC’d/);assert.match(html,/RFT’d/);
 assert.equal(button(html,'pmb-rft-release-key'),undefined);
 assert.doesNotMatch(button(html,'rft-transport-booked-key'),/disabled/);
 assert.match(button(html,'rft-collected-key'),/disabled/);
});
test('old-cycle, missing or invalid confirmations cannot unlock email',()=>{
 for(const rftConfirmedAt of [undefined,'','invalid','2026-09-09T23:00:00Z'])
  assert.equal(ready({...qc,rftConfirmed:true,rftConfirmedAt}),false);
});
test('viewer, untrusted, unsigned and busy rows cannot release',()=>{
 for(const [v,o] of [[qc,{...opts,allowed:false}],[qc,{...opts,authority:false}],
 [qc,{...opts,inFlight:true}],[{...qc,pdcQcComplete:false},opts]])
  assert.match(button(controls(v,o),'pmb-rft-release-key'),/disabled/);
});
function harness(options={}){
 const source=fs.readFileSync('pdc-rft-actions.js','utf8');
 const calls=[],alerts=[];let busy=false;
 const ctx={selectedVehicle:()=>qc,vehicleRftLifecycleRoleAllowed:()=>options.allowed!==false,
 authority:()=>true,qcSigned,ready,collected,sessions:new Map(),displayStockNumber:()=> 'TEST',
 beginRftTransportAction:()=>{if(busy)return null;busy=true;return {};},
 finishRftTransportAction:()=>{busy=false;},rftTransportActionIsCurrent:()=>true,
 salespersonAssignmentIdempotencyKey:()=> 'request-id',renderAll(){},message:code=>code,
 window:{confirm:()=>options.confirm!==false,alert:x=>alerts.push(x)},
 app:{emailVehicleLocationService:{setRftConfirmation736:async(...args)=>{
 calls.push(args);return options.response||{ok:true,data:{vehicle_id:'fixture-id',rft_confirmed:true,receipt_id:'receipt',vehicle_version_after:11}};
 }}},refreshEmailVehicleLocations:async()=>options.refresh!==false};
 vm.createContext(ctx);
 vm.runInContext(source.slice(source.indexOf('  markRftConfirmation = async function'),source.indexOf("  document.addEventListener('click'")),ctx);
 return {ctx,calls,alerts};
}
test('PMB button writes exact vehicle/version once and requires readback',async()=>{
 const h=harness();
 assert.equal(await h.ctx.markRftConfirmation('fixture',true),true);
 assert.deepEqual(h.calls,[['fixture-id',10,true,'request-id']]);
 const failed=harness({refresh:false});
 assert.equal(await failed.ctx.markRftConfirmation('fixture',true),false);
 assert.match(failed.alerts[0],/Refresh/);
});
test('cancel and viewer never write, stale server response never claims confirmation',async()=>{
 for(const options of [{confirm:false},{allowed:false}]){
  const h=harness(options);assert.equal(await h.ctx.markRftConfirmation('fixture',true),false);assert.equal(h.calls.length,0);
 }
 const h=harness({response:{ok:false,code:'rft_confirmation_stale_version'}});
 assert.equal(await h.ctx.markRftConfirmation('fixture',true),false);
 assert.equal(h.alerts[0],'rft_confirmation_stale_version');
});
test('mismatched receipt cannot be presented as saved',async()=>{
 const h=harness({response:{ok:true,data:{vehicle_id:'another-vehicle',rft_confirmed:true,receipt_id:'x',vehicle_version_after:11}}});
 assert.equal(await h.ctx.markRftConfirmation('fixture',true),false);
 assert.match(h.alerts[0],/could not be verified/);
});

