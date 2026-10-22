/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
const intake=fs.readFileSync('pdc-new-vehicles.js','utf8');
test('retired Operation Updates deep link opens Vehicle Locations without exposing approval controls',()=>{
  const calls=[];
  const fn=intake.slice(intake.indexOf('  showView=function(view,options){'),intake.indexOf("  window.addEventListener('pdc-auth-ready'"));
  const context={previousView:(...args)=>calls.push(args)};vm.createContext(context);vm.runInContext(fn,context);
  context.showView('operationupdates',{historyMode:'push'});
  assert.equal(calls[0][0],'dashboard');assert.equal(calls[0][1].historyMode,'replace');
  assert.doesNotMatch(intake,/appendChild\(updateNav\)|appendChild\(updatePage\)/);
});
test('unresolved additions stay visible on their own card without a mutation control or unsafe markup',()=>{
 const context={escapeHtml:value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')};vm.createContext(context);
 vm.runInContext(source.slice(source.indexOf('function vehicleImportedAdditionsHtml('),source.indexOf('function renderVehicleWorkshopWorkPage(')),context);
 assert.equal(context.vehicleImportedAdditionsHtml({}),'');
 const html=context.vehicleImportedAdditionsHtml({imported_additions:[{description:'<script>unsafe</script>',job_card:'J-ONE',line_number:4,status:'completed_station_requires_rework_review'}]});
 assert.match(html,/J-ONE · Line 4/);assert.match(html,/Existing completed work retained/);assert.match(html,/&lt;script&gt;/);
 assert.doesNotMatch(html,/<script>|<button|Approve/);
});
