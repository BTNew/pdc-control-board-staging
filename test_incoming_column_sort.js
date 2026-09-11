'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const context = {
  escapeHtml: s => String(s), vehicleKeyNumber: v => v.key, displayStockNumber: v => v.stock,
  vehicleJobcardNumber: v => v.jobcard, vehicleCustomerName: v => v.customer, displayVehicle: v => v.vehicle,
  pmbEnteredTimestamp: v => v.entered, navisionEtaForVehicle: v => v.eta,
  parseIsoTimestamp: s => s ? new Date(s) : null, parseDateAU: s => s ? new Date(s) : null,
};
vm.createContext(context);
vm.runInContext(source.slice(source.indexOf('function incomingSortHeadingHtml'), source.indexOf('function renderIncomingDashboardBoard')), context);
const rows = [{stock:'100',key:'10',jobcard:'J10',customer:'Zulu',vehicle:'Hilux 10'},
  {stock:'20',key:'2',jobcard:'J2',customer:'Alpha',vehicle:'Hilux 2'},
  {stock:'IS9',key:'',jobcard:'—',customer:'',vehicle:''}];
const sorted = (list, key, direction='asc', bucket='pmb') => [...list].sort((a,b) => context.incomingCompareVehicles(a,b,{key,direction},bucket));
assert.deepEqual(sorted(rows,'stock').map(v=>v.stock), ['20','100','IS9']);
assert.deepEqual(sorted(rows,'stock','desc').map(v=>v.stock), ['IS9','100','20']);
for (const key of ['key','jobcard','customer','vehicle']) {
  assert.deepEqual(sorted(rows,key).map(v=>v.stock), ['20','100','IS9']);
  assert.deepEqual(sorted(rows,key,'desc').map(v=>v.stock), ['100','20','IS9'], 'missing remains last in either direction');
}
const ages = [{stock:'1',entered:'2026-09-01',eta:'2026-09-15'},
  {stock:'2',entered:'2026-09-05',eta:'2026-09-10'}, {stock:'3',eta:'2026-09-01'}];
assert.deepEqual(sorted(ages,'age').map(v=>v.stock), ['1','2','3'], 'PMB sorts recorded entry, without guessing from ETA');
assert.deepEqual(sorted(ages,'age','desc').map(v=>v.stock), ['2','1','3']);
assert.deepEqual(sorted(ages,'age','asc','transit').map(v=>v.stock), ['3','2','1'], 'transit uses shown ETA');
assert.equal(rows[0].stock,'100','sorting a copy never mutates source order');
assert.match(context.incomingSortHeadingHtml('Stock','stock',{}), /Sort Stock: ascending/);
assert.match(context.incomingSortHeadingHtml('Stock','stock',{key:'stock',direction:'asc'}), /Sort Stock: descending/);
assert.match(context.incomingSortHeadingHtml('Age / ETA','age',{key:'age',direction:'desc'}), /oldest age \/ earliest ETA first/);
console.log('Vehicle Locations column sort: PASS');
