'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js','utf8').replace(/\r\n/g,'\n');
const start = source.indexOf('function resetPdcAuditorAuthorityState()');
const end = source.indexOf('function pdcAuditorService()', start);
assert.ok(start >= 0 && end > start, 'Auditor authority reset must be extractable');
let rendered = 0;
const context = vm.createContext({
  app: {
    pdcAuditorGeneration: 4,
    pdcAuditorService: { destroy(){} },
    pdcAuditorPendingOperation: { state:'pending_apply', proposal_id:'stale' },
    pdcAuditorOperationBusy: true,
  },
  document: { getElementById(){ return null; } },
  resetPdcAuditorRealtimeSubscription(){},
  clearAiFileAssistantUploads(){},
  renderPdcAuditorPendingOperation(){ rendered += 1; },
});
vm.runInContext(source.slice(start,end),context);
vm.runInContext('resetPdcAuditorAuthorityState()',context);
assert.strictEqual(context.app.pdcAuditorPendingOperation,null,'auth reset must discard stale proposal/run authority');
assert.strictEqual(context.app.pdcAuditorOperationBusy,false,'auth reset must release stale operation busy state');
assert.strictEqual(rendered,1,'auth reset must immediately rerender disabled operation controls');
console.log('AI Auditor auth-change operation-state teardown passed');

(async()=>{
  const asyncSource = fs.readFileSync('app.js','utf8').replace(/\r\n/g,'\n');
  const blockStart = asyncSource.indexOf('function pdcAuditorOperationGatewayConfig()');
  const blockEnd = asyncSource.indexOf('function pdcAuditorCategory', blockStart);
  assert.ok(blockStart >= 0 && blockEnd > blockStart, 'signed gateway block must be extractable for auth race test');
  let resolveFetch;
  const nodes = {
    '#ai-auditor-operation-state': { innerHTML:'' },
    '#ai-auditor-operation-apply': { disabled:true },
    '#ai-auditor-operation-undo': { disabled:true },
  };
  let snapshotLoads = 0;
  const race = vm.createContext({
    app: { pdcAuditorGeneration: 7, pdcAuditorPendingOperation:null, pdcAuditorOperationBusy:false },
    window: { confirm:()=>true, PDC_SUPABASE_CONFIG:{ auditorOperationGateway:{ url:'https://gateway.staging.example/auditor', instanceId:'gw-staging-1' } }, PDC_AUTH_CONTEXT:{ role:'administrator' } },
    $: selector => nodes[selector] || null,
    escapeHtml: value=>String(value),
    getPdcSupabaseAccessToken: ()=> raceToken,
    fetch: async()=> new Promise(resolve=>{ resolveFetch=resolve; }),
    loadPdcAuditorSnapshot: async()=>{ snapshotLoads += 1; },
  });
  let raceToken = 'OLD_ACCOUNT_JWT';
  vm.runInContext(asyncSource.slice(blockStart, blockEnd), race);
  const pending = vm.runInContext('loadPdcAuditorPendingOperation()', race);
  raceToken = 'NEW_ACCOUNT_JWT';
  race.app.pdcAuditorGeneration = 8;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  resolveFetch({ ok:true, json: async()=>({ state:'undo_available', instance_id:'gw-staging-1', run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64) }) });
  const loaded = await pending;
  assert.strictEqual(loaded,false,'stale gateway status response must be discarded after auth reset');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,null,'old-account receipt must not survive auth reset');
  assert.strictEqual(nodes['#ai-auditor-operation-undo'].disabled,true,'undo must remain disabled after stale response');
  console.log('AI Auditor in-flight auth-reset race teardown passed');

  const originalPending = {
    state:'pending_apply', instance_id:'gw-staging-1',
    proposal_id:'11111111-2222-4333-8444-555555555555', proposal_version:9,
    proposal_hash:'a'.repeat(64), typed_item_set_hash:'b'.repeat(64),
    final_scope_hash:'c'.repeat(64), expected_row_versions_hash:'d'.repeat(64),
  };
  raceToken = 'OLD_MUTATION_ACCOUNT_JWT';
  race.app.pdcAuditorGeneration = 9;
  race.app.pdcAuditorPendingOperation = originalPending;
  race.app.pdcAuditorOperationBusy = false;
  const confirming = vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race);
  raceToken = 'REPLACEMENT_ACCOUNT_JWT';
  race.app.pdcAuditorGeneration = 10;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  resolveFetch({ ok:true, json:async()=>({ state:'completed', instance_id:'gw-staging-1', message:'old mutation completed' }) });
  const confirmed = await confirming;
  assert.strictEqual(confirmed,false,'stale Apply completion must not report success after auth replacement');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,null,'stale Apply receipt must not republish old authority');
  assert.strictEqual(snapshotLoads,0,'stale Apply completion must not trigger an authoritative reload');
  assert.strictEqual(nodes['#ai-auditor-operation-apply'].disabled,true,'Apply must remain disabled after stale mutation completion');
  console.log('AI Auditor stale Apply/Undo completion teardown passed');

  raceToken = 'CURRENT_ACCOUNT_JWT';
  race.app.pdcAuditorGeneration = 11;
  race.app.pdcAuditorPendingOperation = originalPending;
  race.app.pdcAuditorOperationBusy = false;
  const replaced = vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race);
  race.app.pdcAuditorPendingOperation = { ...originalPending, proposal_version:10 };
  resolveFetch({ ok:true, json:async()=>({ state:'completed', instance_id:'gw-staging-1', message:'superseded binding completed' }) });
  assert.strictEqual(await replaced,false,'completion for a superseded pending binding must not report success');
  assert.strictEqual(race.app.pdcAuditorPendingOperation.proposal_version,10,'stale completion must not overwrite the replacement binding');
  assert.strictEqual(snapshotLoads,0,'superseded binding completion must not trigger an authoritative reload');
  console.log('AI Auditor pending-binding replacement race teardown passed');

  raceToken = '';
  race.app.pdcAuditorGeneration = 12;
  race.app.pdcAuditorPendingOperation = originalPending;
  race.app.pdcAuditorOperationBusy = false;
  assert.strictEqual(await vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race),false,'missing token must fail before confirmation or gateway dispatch');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,originalPending,'missing-token rejection must not mutate pending authority');
  console.log('AI Auditor missing-token confirmation denial passed');
})().catch(error=>{ console.error(error); process.exit(1); });