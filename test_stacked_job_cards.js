/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const context = { cleanNavisionText: value => String(value || '').trim(), escapeHtml,
 vehicleJobcardNumber: v => v.jobcard || v.jobCardNumber || v.job_card_number || '', vehicleKey: v => v.id, vehicleIdentityTitle: () => 'Vehicle',
 truncate: (s,n) => s.slice(0,n), vehicleIdentityCells: v => [{label:'JC',className:'identity-jc',value:v.jobcard || v.jobCardNumber || ''}] };
vm.createContext(context);
vm.runInContext(source.slice(source.indexOf('function vehicleIdentityStackHtml'),source.indexOf('function vehiclePmbKeyNumber')),context);
context.vehicleWorkshopCompactLinesHtml = group => `<div class="vehicle-workshop-lines">${(group.lines || []).map(line => line.job_card_number).join(',')}</div>`;
context.authenticatedOperationSummaryLines = vehicle => vehicle.pdcEmailOperationLines || [];
context.authenticatedEmailOperationLinesHtml = () => '<div class="authenticated-email-operations"><div class="authenticated-email-operations-heading"><b>Operations</b></div></div>';
vm.runInContext(fs.readFileSync('pdc-stacked-jobcards.js','utf8'),context);
const v={id:'canonical-id',jobcard:'',pdcEmailOperationLines:[{job_card_number:'J139125148'},{job_card_number:'J139125578'},{job_card_number:'J139125148'}]};
const before=JSON.stringify(v);
const html=context.vehicleIdentityStackHtml(v,{className:'incoming-identity',stackJobCards:true});
assert.match(html,/<span>J139125148<\/span><span>J139125578<\/span>/);
assert.equal(JSON.stringify(v),before);
assert.equal((html.match(/<span>J139125148<\/span>/g)||[]).length,1);
assert.match(context.vehicleIdentityStackHtml(v),/pdc-stacked-jobcards/);
assert.doesNotMatch(context.vehicleIdentityStackHtml({jobcard:'J1'},{className:'incoming-identity',stackJobCards:true}),/pdc-stacked-jobcards/);
assert.match(context.vehicleIdentityStackHtml({},{className:'incoming-identity',stackJobCards:true}),/—/);
assert.doesNotMatch(context.vehicleIdentityStackHtml({pdcJobCardNumbers:['<img src=x>','J2']},{className:'incoming-identity',stackJobCards:true}),/<img/);

const stock12710970 = {
  id: 'f5a9700a-8dae-4715-a30e-d84f2862932d', jobcard: 'J139125898', jobCardNumber: 'J139125898',
  pdcJobCardNumbers: ['J139125207', 'J139125898'],
  pdcEmailOperationLines: [
    { job_card_number: 'J139125207', estimatedHours: 1.5, sub_status: '22' },
    { job_card_number: 'J139125898', estimatedHours: 0.5, sub_status: '40' },
  ],
};
const board = context.vehicleIdentityStackHtml(stock12710970, { className: 'control-board-work-identity' });
const qc = context.vehicleIdentityStackHtml(stock12710970, { className: 'qc-identity' });
const stockTable = context.vehicleIdentityStackHtml(stock12710970, { button: true });
assert.match(board, /<span>J139125898<\/span><span>J139125207<\/span>/);
assert.match(qc, /<span>J139125898<\/span><span>J139125207<\/span>/);
assert.match(stockTable, /<span>J139125898<\/span><span>J139125207<\/span>/);
assert.equal(JSON.stringify(context.pdcOpenJobCards(stock12710970)), JSON.stringify(['J139125898', 'J139125207']));

const mixed = { jobcard: 'J138000823', pdcEmailOperationLines: [
  { job_card_number: 'J138000823', sub_status: '22' },
  { job_card_number: 'J139126027', sub_status: '40' },
]};
assert.equal(JSON.stringify(context.pdcOpenJobCards(mixed)), JSON.stringify(['J138000823', 'J139126027']));

const rego = { jobcard: 'J139125787', pdcJobCardNumbers: ['J139125711', 'J139125787'] };
assert.equal(JSON.stringify(context.pdcOpenJobCards(rego)), JSON.stringify(['J139125787', 'J139125711']));

const oneClosed = { jobcard: 'J139125898', pdcEmailOperationLines: [
  { job_card_number: 'J139125898', sub_status: '99' },
  { job_card_number: 'J139125207', sub_status: '22' },
]};
assert.equal(JSON.stringify(context.pdcOpenJobCards(oneClosed)), JSON.stringify(['J139125207']));

const detail = context.vehicleWorkshopCompactLinesHtml({ lines: stock12710970.pdcEmailOperationLines }, 'Not booked', stock12710970, []);
assert.match(detail, /data-job-card="J139125898"[\s\S]*0\.50 h[\s\S]*data-job-card="J139125207"[\s\S]*1\.50 h/);
const summary = context.authenticatedEmailOperationLinesHtml(stock12710970);
assert.match(summary, /Open cards · 2\.00 h/);
assert.match(summary, /J139125898/);
assert.match(summary, /J139125207/);

const mapping=fs.readFileSync('pdc-email-vehicle-location-service.js','utf8');
const start=mapping.indexOf('  mapped.pdcJobCardNumbers =');
const end=mapping.indexOf('  mapped.pdcEmailOperationLines =',start);
const mapper={mapped:{},row:{operation_lines:[...Array.from({length:50},()=>({job_card_number:'J1'})),{job_card_number:'J2'}]}};
vm.runInNewContext(mapping.slice(start,end),mapper);
assert.deepEqual(Array.from(mapper.mapped.pdcJobCardNumbers),['J1','J2']);
assert.match(fs.readFileSync('control-board-overview.js','utf8'), /pdcOpenJobCards\(vehicle\)/);
assert.match(fs.readFileSync('workshop-planner.js','utf8'), /pdcOpenJobCardLabel\(vehicle\)/);
assert.match(fs.readFileSync('pdc-vehicle-slideout.js','utf8'), /pdcOpenJobCards\(vehicle\)/);
assert.match(fs.readFileSync('index.html','utf8'), /pdc-stacked-jobcards\.js\?v=2026\.10\.27\.r572/);
console.log('Stacked job cards: every board view, primary first, 80/99 card hidden, subtotals PASS');
