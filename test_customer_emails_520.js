/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const customer=require('./sales/customer-emails.js');
require('./sales/dashboard-tools.js');

test('r520: no signature block and no em/en dashes in any customer template',()=>{
 for(const [kind] of customer.types){
  const t=customer.template(kind);
  const text=t.subject+'\n'+t.body;
  assert.doesNotMatch(text,/[—–−]/);
  assert.doesNotMatch(text,/Kind Regards|Broome Toyota|salesperson_phone|salesperson_email|\{\{salesperson_/);
 }
});

test('r520: Open email uses temporary anchor helper',()=>{
 const src=fs.readFileSync(require.resolve('./sales/customer-emails.js'),'utf8');
 assert.match(src,/function openMailto/);
 assert.match(src,/Open while still in the click gesture/);
 assert.match(src,/p_action:rpcAction/);
 assert.match(src,/kind==='dismiss'\?'skip'/);
 assert.doesNotMatch(src,/salesperson_phone|signatureName|Kind Regards/);
});

test('r520: Dismiss is in the dialog header before message fields',()=>{
 const html=fs.readFileSync(require.resolve('./sales/index.html'),'utf8');
 const dialog=html.slice(html.indexOf('customer-email-dialog'),html.indexOf('</dialog>',html.indexOf('customer-email-dialog')));
 assert.ok(dialog.indexOf('customer-email-dismiss')<dialog.indexOf('customer-email-body'));
 assert.match(dialog,/Dismiss removes this update from the awaiting list and keeps its history/);
});
