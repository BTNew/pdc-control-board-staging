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
  const race = vm.createContext({
    app: { pdcAuditorGeneration: 7, pdcAuditorPendingOperation:null, pdcAuditorOperationBusy:false },
    window: { PDC_SUPABASE_CONFIG:{ auditorOperationGateway:{ url:'https://gateway.staging.example/auditor', instanceId:'gw-staging-1' } }, PDC_AUTH_CONTEXT:{ role:'administrator' } },
    $: selector => nodes[selector] || null,
    escapeHtml: value=>String(value),
    getPdcSupabaseAccessToken: ()=> raceToken,
    fetch: async()=> new Promise(resolve=>{ resolveFetch=resolve; }),
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
})().catch(error=>{ console.error(error); process.exit(1); });