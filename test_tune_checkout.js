'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const app=fs.readFileSync('app.js','utf8');
const service=fs.readFileSync('pdc-email-vehicle-location-service.js','utf8');
function map(checkout){
 const context={row:{tune_checkout:checkout},mapped:{}};vm.createContext(context);
 vm.runInContext(service.slice(service.indexOf('const checkout = row.tune_checkout;'),service.indexOf('mapped.tuneServiceLocations =')),context);
 return context.mapped.tuneCheckout;
}
const receipt={confirmed:true,source:'Tune Sub Status 99',receipt_id:'00000000-0000-4000-8000-000000000999',job_cards:[{ro:'TEST',sub_status:'99'}]};
test('checkout display requires the server receipt and checked-out job evidence',()=>{
 assert.equal(map(receipt).confirmed,true);
 for(const x of [null,{}, {...receipt,confirmed:false},{...receipt,source:'raw spreadsheet'},{...receipt,receipt_id:''},{...receipt,job_cards:[]},{...receipt,job_cards:[{sub_status:'20'}]}]) assert.equal(map(x),null);
});
test('Tune checkout has a separate RFT label without turning QC into complete',()=>{
 const ctx={statusCategory:v=>v.location,vehicleRftGateIssues:()=>['QC not signed off'],pdcRequiredJobs:()=>[],pdcJobComplete:()=>false};vm.createContext(ctx);
 vm.runInContext(app.slice(app.indexOf('function rftHomeStatus('),app.indexOf('function rftHomeRows(')),ctx);
 const vehicle={location:'rft',tuneCheckout:map(receipt),qc:false};
 assert.equal(ctx.rftHomeStatus(vehicle),'checked_out');assert.equal(ctx.rftHomeStatusLabel('checked_out'),'Checked out (Tune)');assert.equal(vehicle.qc,false);
 assert.equal(ctx.rftHomeStatus({location:'rft'}),'blocked');assert.equal(ctx.rftHomeStatus({...vehicle,location:'yh'}),'');
});
test('RFT selector includes the distinct source state and cache refreshes both readers',()=>{
 const html=fs.readFileSync('index.html','utf8');
 assert.match(html,/<select id="rft-status-filter">[\s\S]*?value="checked_out"[\s\S]*?<\/select>/);
 for(const file of ['app.js','pdc-email-vehicle-location-service.js'])assert.match(html,new RegExp(file.replaceAll('.','\\.')+'[^"\\n]*tune-checkout=2026\\.09\\.15\\.01'));
});
