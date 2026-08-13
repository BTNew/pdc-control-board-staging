'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app.js','utf8').replace(/\r\n/g,'\n');
const start = source.indexOf('function pdcAuditorOperationGatewayConfig');
const end = source.indexOf('function pdcAuditorCategory', start);
assert.ok(start >= 0 && end > start, 'signed gateway UI block must be extractable');
function button(){ return { disabled:true }; }
const nodes = {
  '#ai-auditor-operation-state': { innerHTML:'' },
  '#ai-auditor-operation-apply': button(),
  '#ai-auditor-operation-undo': button(),
};
const context = vm.createContext({
  window: { PDC_SUPABASE_CONFIG:{}, PDC_AUTH_CONTEXT:{ role:'administrator' }, confirm:()=>true },
  app: { pdcAuditorPendingOperation:null, pdcAuditorOperationBusy:false },
  $: selector => nodes[selector] || null,
  getPdcSupabaseAccessToken: ()=>'human-admin-token',
  escapeHtml: value=>String(value),
  fetch: async()=>{ throw new Error('must not fetch without config'); },
  loadPdcAuditorSnapshot: async()=>true,
});
vm.runInContext(source.slice(start,end),context);
assert.strictEqual(vm.runInContext('pdcAuditorOperationGatewayConfig()',context),null);
vm.runInContext('renderPdcAuditorPendingOperation()',context);
assert.ok(nodes['#ai-auditor-operation-state'].innerHTML.includes('No direct database fallback exists'));
assert.strictEqual(nodes['#ai-auditor-operation-apply'].disabled,true);
const proposal={state:'pending_apply',instance_id:'gw-staging-1',proposal_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',proposal_version:1,proposal_hash:'a'.repeat(64),typed_item_set_hash:'b'.repeat(64),final_scope_hash:'c'.repeat(64),expected_row_versions_hash:'d'.repeat(64)};
context.window.PDC_SUPABASE_CONFIG.auditorOperationGateway={url:'https://gateway.staging.example/auditor',instanceId:'gw-staging-1'};
context.app.pdcAuditorPendingOperation=proposal;
vm.runInContext('renderPdcAuditorPendingOperation()',context);
assert.strictEqual(nodes['#ai-auditor-operation-apply'].disabled,false);
assert.strictEqual(nodes['#ai-auditor-operation-undo'].disabled,true);
assert.strictEqual(vm.runInContext('pdcAuditorOperationReceipt({state:"pending_apply",instance_id:"gw-staging-1",proposal_id:"bad"})',context),null);
context.window.PDC_AUTH_CONTEXT.role='viewer';
vm.runInContext('renderPdcAuditorPendingOperation()',context);
assert.strictEqual(nodes['#ai-auditor-operation-apply'].disabled,true);
assert.ok(nodes['#ai-auditor-operation-state'].innerHTML.includes('Administrator authority required'));

(async()=>{
  let request=null;
  context.window.PDC_AUTH_CONTEXT.role='administrator';
  context.app.pdcAuditorPendingOperation={state:'undo_available',instance_id:'gw-staging-1',run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',run_revision_after:'e'.repeat(64)};
  context.fetch=async(url,options)=>{ request={url,options}; return {ok:true,json:async()=>({state:'completed',instance_id:'gw-staging-1',message:'undone'})}; };
  const receipt=await vm.runInContext("callPdcAuditorOperationGateway('undo')",context);
  assert.strictEqual(receipt.state,'completed');
  assert.ok(request.url.endsWith('/v1/auditor-operation/undo'));
  assert.deepStrictEqual(JSON.parse(request.options.body),{confirmation:'Undo the selected Auditor run',binding:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'});
  console.log('AI Auditor signed-gateway browser control contracts passed');
})().catch(error=>{ console.error(error); process.exit(1); });
