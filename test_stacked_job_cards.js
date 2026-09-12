'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const context = { cleanNavisionText: value => String(value || '').trim(), escapeHtml,
 vehicleJobcardNumber: v => v.jobcard || '', vehicleKey: v => v.id, vehicleIdentityTitle: () => 'Vehicle',
 truncate: (s,n) => s.slice(0,n), vehicleIdentityCells: v => [{label:'JC',className:'identity-jc',value:v.jobcard || ''}] };
vm.createContext(context);
vm.runInContext(source.slice(source.indexOf('function vehicleIdentityStackHtml'),source.indexOf('function vehiclePmbKeyNumber')),context);
vm.runInContext(fs.readFileSync('pdc-stacked-jobcards.js','utf8'),context);
const v={id:'canonical-id',jobcard:'',pdcEmailOperationLines:[{job_card_number:'J139125148'},{job_card_number:'J139125578'},{job_card_number:'J139125148'}]};
const before=JSON.stringify(v);
const html=context.vehicleIdentityStackHtml(v,{className:'incoming-identity',stackJobCards:true});
assert.match(html,/<span>J139125148<\/span><span>J139125578<\/span>/);
assert.equal(JSON.stringify(v),before);
assert.equal((html.match(/<span>J139125148<\/span>/g)||[]).length,1);
assert.doesNotMatch(context.vehicleIdentityStackHtml(v),/pdc-stacked-jobcards/);
assert.doesNotMatch(context.vehicleIdentityStackHtml({jobcard:'J1'},{className:'incoming-identity',stackJobCards:true}),/pdc-stacked-jobcards/);
assert.match(context.vehicleIdentityStackHtml({},{className:'incoming-identity',stackJobCards:true}),/—/);
assert.doesNotMatch(context.vehicleIdentityStackHtml({pdcJobCardNumbers:['<img src=x>','J2']},{className:'incoming-identity',stackJobCards:true}),/<img/);
const mapping=fs.readFileSync('pdc-email-vehicle-location-service.js','utf8');
const start=mapping.indexOf('  mapped.pdcJobCardNumbers =');
const end=mapping.indexOf('  mapped.pdcEmailOperationLines =',start);
const mapper={mapped:{},row:{operation_lines:[...Array.from({length:50},()=>({job_card_number:'J1'})),{job_card_number:'J2'}]}};
vm.runInNewContext(mapping.slice(start,end),mapper);
assert.deepEqual(Array.from(mapper.mapped.pdcJobCardNumbers),['J1','J2']);
console.log('Stacked job cards: source preservation, deduplication, escaping and full projection PASS');
