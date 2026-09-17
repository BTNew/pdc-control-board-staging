'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const serviceModule = require('./navision-backend-service.js');
const app = fs.readFileSync(__dirname+'/app.js','utf8');
const html = fs.readFileSync(__dirname+'/index.html','utf8');
const start=app.indexOf('function navisionClientPreflight('), end=app.indexOf('\nfunction mergeNavisionPreflightData',start);
const ctx={ normalizeBatch:v=>String(v||'').trim(), normalizeVin:v=>String(v||'').trim(), cleanNavisionText:v=>String(v||'').trim() };
vm.createContext(ctx); vm.runInContext(app.slice(start,end),ctx);
for (const dealer of ['002345','001234','14450','37047']) {
 test(dealer+' preserves scope through service preview, apply and reads',async()=>{
   const calls=[];
   const service=serviceModule.createNavisionBackendService({projectRef:serviceModule.NAVISION_STAGING_PROJECT_REF,
     client:{rpc:async(token,name,params)=>{calls.push({name,params});return {ok:true,status:200,body:{ok:true}};}},
     getAccessToken:()=> 'test-token'});
   const metadata={dealerCode:dealer};
   await service.preview([],metadata);await service.approveInitialScope([],metadata);
   await service.snapshot(metadata);await service.visibleSnapshot(metadata);await service.exportRecords(metadata);
   const result=await service.apply([],{data:{source_hash:'source',preview_hash:'preview',base_revision:1,counts:{total:0}}},
     {...metadata,confirmed:true,idempotencyKey:'test'});
   assert.equal(result.ok,true);assert.equal(calls.length,6);
   for(const c of calls)assert.equal(c.params.p_dealer_code,dealer);
   assert(html.includes('value="'+dealer+'"'));
 });
 test(dealer+' accepts declared dealer strings and numeric spreadsheet cells',()=>{
   for(const value of [dealer,Number(dealer),' '+dealer+' ']){
    const row={id:'test',stock:'99000000',navisionRawEvidence:{columns:[{header:'Dealer Code',value}]}};
    assert.equal(ctx.navisionClientPreflight([row],dealer).blocking,false);
    assert.equal(ctx.navisionClientPreflight([row],dealer==='002345'?'001234':'002345').issues[0].reason,'wrong_dealer_scope');
   }
 });
}
test('unsupported scopes and unconfirmed apply never reach shared service',async()=>{
 const service=serviceModule.createNavisionBackendService({projectRef:serviceModule.NAVISION_STAGING_PROJECT_REF,
 client:{rpc:()=>{throw new Error('must not call');}},getAccessToken:()=> 'test-token'});
 assert.equal((await service.preview([],{dealerCode:'999999'})).error,'invalid_dealer_code');
 assert.equal((await service.apply([],{}, {dealerCode:'002345'})).error,'explicit_confirmation_required');
});
test('visible refresh includes all four dealer scopes',()=>{
 assert(app.includes("['14450', '37047', '002345', '001234'].map(async dealerCode =>"));
});
