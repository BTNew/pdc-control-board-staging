/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const finance=require('./sales/finance-pipeline.js');
const css=fs.readFileSync(path.join(__dirname,'sales/finance-pipeline.css'),'utf8');
const js=fs.readFileSync(path.join(__dirname,'sales/finance-pipeline.js'),'utf8');
const html=fs.readFileSync(path.join(__dirname,'sales/index.html'),'utf8');
test('r428: Approval Yes/No map to finance-yes/finance-no and blank stays plain',()=>{
 assert.equal(finance.approvalStateClass('Yes'),'finance-yes');
 assert.equal(finance.approvalStateClass('No'),'finance-no');
 for(const v of ['','—',null,undefined,'yes'])assert.equal(finance.approvalStateClass(v),'');
});
test('r428: only the Approval cell carries the finance-approval scope class',()=>{
 assert.match(js,/k==='approval'\?'finance-approval':''/);
 assert.match(js,/if\(key==='approval'\)\{const cell=tr\.querySelector\('td\.finance-approval'\)/);
});
test('r428: Approval Yes is solid dark green and No solid dark red with white bold text',()=>{
 assert.match(css,/td\.finance-approval\.finance-yes\{background:#2e7d32;color:#fff;font-weight:700\}/);
 assert.match(css,/td\.finance-approval\.finance-no\{background:#c62828;color:#fff;font-weight:700\}/);
 assert.match(css,/td\.finance-approval\.finance-yes select\{background-color:#2e7d32;[^}]*color:#fff;font-weight:700/);
 assert.match(css,/td\.finance-approval\.finance-no select\{background-color:#c62828;[^}]*color:#fff;font-weight:700/);
 assert.match(css,/td\.finance-approval select option\{background:#fff;color:#173b57/);
});
// r488 (F101): Access / Payout Complete now also get Approval's solid colours via td.finance-yesno; the pale shared rules stay (Settlement uses them).
test('r428: the original pale shared styling rules are kept',()=>{
 assert.match(css,/\.finance-pipeline-table \.finance-yes\{background:#d6fae8\}/);
 assert.match(css,/\.finance-pipeline-table \.finance-no\{background:#ffe1e5\}/);
});
test('r428: cache-busting version bumped',()=>{
 assert.match(html,/finance-pipeline\.css\?v=2026\.10\.06\.01&amp;approval-dark=2026\.10\.21\.01/);
 assert.match(html,/finance-pipeline\.js\?v=2026\.10\.06\.01&amp;approval-dark=2026\.10\.21\.01/);
});
