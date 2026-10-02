'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createFixture}=require('./qa/dashboard-render-fixture.cjs');
const {createNavisionBackendService,NAVISION_STAGING_PROJECT_REF}=require('./navision-backend-service.js');
function reviewedFixture(profile='broome'){
 const f=createFixture({vehicleCount:0}),c=f.context,calls=[],prompts=[];
 c.PDC_AUTH_CONTEXT={role:'administrator'};
 const pending={dealerCode:profile,rows:[{order:'EXAMPLE',stock:'',cosi:'Yes'}],metadata:{dealerCode:profile,sourceName:'example.tsv'},clientPreflight:{issues:[]},
  previewResult:{data:{}},previewData:{counts:{total:260,missing:121,invalid:0,conflict:0},blocking:true,
  safety:{blocking:true,reason:'suspicious_partial_snapshot'},dealer_groups:[{dealer_code:profile==='broome'?'37047':'14450',blocking:true,counts:{total:260,missing:121},safety:{reason:'suspicious_partial_snapshot'}}]}};
 let current=true;
 c.navisionSharedPendingStillCurrent=()=>current;c.navisionSharedApplyAuthorityIdentity=()=> 'same-admin';
 c.renderSharedNavisionPreview=()=>{};c.updateNavisionImportButton=()=>{};
 c.confirm=message=>{prompts.push(message);return true;};c.alert=message=>calls.push(['alert',message]);
 const service={reviewCompleteSnapshot:async(...a)=>{calls.push(['review',...a]);return{ok:true};},
  preview:async(...a)=>{calls.push(['preview',...a]);return {ok:true,data:{...pending.previewData,blocking:false,safety:{blocking:false},source_hash:'exact',preview_hash:'reviewed',base_revision:2}};}};
 return {c,pending,service,calls,prompts,invalidate:()=>{current=false;}};
}
test('large omission reviews exact Broome and Pilbara files, then refreshes preview before applying',async()=>{
 for(const profile of ['broome','pilbara']){
  const f=reviewedFixture(profile);
  assert.equal(await f.c.reviewNavisionCompleteSnapshot(f.pending,f.service),true);
  assert.deepEqual(f.calls.map(x=>x[0]),['review','preview']);
  assert.equal(f.calls[0][1],f.pending.rows);assert.equal(f.pending.previewData.preview_hash,'reviewed');
  assert.match(f.prompts[0],/260 in this file; 121 not in this file/);assert.match(f.prompts[0],/full export, not a filtered or partial list/);
  assert.match(f.prompts[0],/confirm the import separately/);
 }
});
test('invalid, conflicting, unknown safety and non-administrator scopes cannot be reviewed',async()=>{
 for(const change of [f=>f.pending.previewData.counts.invalid=1,f=>f.pending.previewData.counts.conflict=1,
  f=>f.pending.previewData.dealer_groups[0].safety.reason='cross_dealer_identity_overlap',
  f=>f.pending.previewData.dealer_groups.push({blocking:true,safety:{reason:'suspicious_empty_scope'}}),
  f=>f.c.PDC_AUTH_CONTEXT.role='importer',f=>f.pending.dealerCode='combined']){
  const f=reviewedFixture();change(f);assert.equal(await f.c.reviewNavisionCompleteSnapshot(f.pending,f.service),false);assert.equal(f.calls.length,0);assert.equal(f.prompts.length,0);
 }
});
test('cancel, changed input and lost authority never dispatch or adopt a reviewed preview',async()=>{
 let f=reviewedFixture();f.c.confirm=()=>false;assert.equal(await f.c.reviewNavisionCompleteSnapshot(f.pending,f.service),false);assert.equal(f.calls.length,0);
 f=reviewedFixture();f.c.confirm=()=>{f.invalidate();return true;};assert.equal(await f.c.reviewNavisionCompleteSnapshot(f.pending,f.service),false);assert.equal(f.calls.length,0);
 f=reviewedFixture();f.service.reviewCompleteSnapshot=async()=>{f.invalidate();return{ok:true};};assert.equal(await f.c.reviewNavisionCompleteSnapshot(f.pending,f.service),false);assert.equal(f.calls.length,0);
});
test('rejected review keeps the blocked preview and performs no apply',async()=>{
 const f=reviewedFixture();f.service.reviewCompleteSnapshot=async()=>({ok:false,code:'stale_revision'});
 assert.equal(await f.c.reviewNavisionCompleteSnapshot(f.pending,f.service),false);assert.equal(f.pending.previewData.blocking,true);
 assert.equal(f.calls[0][0],'alert');assert.match(f.calls[0][1],/changed while this file/);
});
test('complete snapshot RPC binds profile, rows, source, preview hash and revision',async()=>{
 const calls=[],svc=createNavisionBackendService({projectRef:NAVISION_STAGING_PROJECT_REF,getAccessToken:()=> 'fixture',client:{rpc:async(t,name,params)=>{calls.push({name,params});return{ok:true,body:{ok:true},status:200};}}});
 const rows=[{order:'example'}],p={data:{source_hash:'source',preview_hash:'preview',base_revision:8}};
 await svc.reviewCompleteSnapshot(rows,p,{dealerCode:'broome',sourceName:'export.xlsx',sourceTimestamp:null});
 assert.equal(calls[0].name,'review_navision_complete_snapshot');
 assert.deepEqual(calls[0].params,{p_profile:'broome',p_rows:rows,p_source_name:'export.xlsx',p_source_timestamp:null,p_source_hash:'source',p_preview_hash:'preview',p_expected_revision:8});
 assert.equal((await svc.reviewCompleteSnapshot(rows,p,{dealerCode:'37047'})).error,'invalid_upload_profile');
 assert.equal((await svc.reviewCompleteSnapshot(rows,{data:{}},{dealerCode:'pilbara'})).error,'valid_preview_required');
 assert.equal(calls.length,1);
});

test('upload scan counters include COSI orders without Batch in both profile tabs',()=>{
 for(const profile of ['broome','pilbara']){
  const f=createFixture({vehicleCount:0});f.loadHelper('navision-vin.js');
  const fields={};const card={querySelector:s=>fields[s]||(fields[s]={textContent:''})};
  const inputs={'#navision-scan-card':card,'#navision-dealer-code':{value:profile},'#navision-paste':{value:'Order\tBatch\tCOSI\tDealer\tSalesperson\tModel Description\tETA At Kewdale Yard\tSub Location Description\n123\t\tYes\t037047\tBG\tHiLux\t15/11/2026\tProduction Planned\n124\t13000001\tYes\t037047\tBG\tHiAce\t16/11/2026\tProduction Planned'}};
  f.context.document.querySelector=s=>inputs[s]||null;
  f.context.navisionImportOptionsFromDom=()=>({});
  f.context.updateNavisionControlStats();
  assert.equal(fields['.navision-detected strong'].textContent,'2 rows');
  assert.equal(fields['.navision-updated strong'].textContent,'Ready to import');
 }
});
