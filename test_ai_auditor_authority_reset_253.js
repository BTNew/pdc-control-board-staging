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
    pdcAuditorOperationOwner: { stale:true },
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
assert.strictEqual(context.app.pdcAuditorOperationOwner,null,'auth reset must release stale operation ownership');
assert.strictEqual(rendered,1,'auth reset must immediately rerender disabled operation controls');
console.log('AI Auditor auth-change operation-state teardown passed');

(async()=>{
  const asyncSource = fs.readFileSync('app.js','utf8').replace(/\r\n/g,'\n');
  const blockStart = asyncSource.indexOf('function pdcAuditorOperationGatewayConfig()');
  const blockEnd = asyncSource.indexOf('function pdcAuditorCategory', blockStart);
  assert.ok(blockStart >= 0 && blockEnd > blockStart, 'signed gateway block must be extractable for auth race test');
  let resolveFetch;
  let fetchCalls = 0;
  const gatewayRequests = [];
  const nodes = {
    '#ai-auditor-operation-state': { innerHTML:'' },
    '#ai-auditor-operation-apply': { disabled:true },
    '#ai-auditor-operation-undo': { disabled:true },
  };
  let snapshotLoads = 0;
  let raceAuthority = 'OLD_ACCOUNT';
  const race = vm.createContext({
    app: { pdcAuditorGeneration: 7, pdcAuditorPendingOperation:null, pdcAuditorOperationBusy:false },
    window: { confirm:()=>true, PDC_SUPABASE_CONFIG:{ auditorOperationGateway:{ url:'https://gateway.staging.example/auditor', instanceId:'gw-staging-1' } }, PDC_AUTH_CONTEXT:{ role:'administrator' } },
    $: selector => nodes[selector] || null,
    escapeHtml: value=>String(value),
    getPdcSupabaseAccessToken: ()=> raceToken,
    auditorAuthorityIdentity: ()=> raceAuthority,
    fetch: async(url, options)=> {
      fetchCalls += 1;
      gatewayRequests.push({ url, options });
      return new Promise(resolve=>{ resolveFetch=resolve; });
    },
    loadPdcAuditorSnapshot: async()=>{ snapshotLoads += 1; },
  });
  let raceToken = 'OLD_ACCOUNT_JWT';
  vm.runInContext(asyncSource.slice(blockStart, blockEnd), race);
  assert.strictEqual(race.pdcAuditorBindOperationOrigin,undefined,'receipt provenance binder must not be exported on window/global object');
  assert.strictEqual(vm.runInContext('typeof pdcAuditorBindOperationOrigin',race),'undefined','receipt provenance binder must remain inaccessible outside its closure');
  const bindCurrentOrigin = async () => {
    const receipt = JSON.parse(JSON.stringify(race.app.pdcAuditorPendingOperation));
    const trustedPromise = vm.runInContext(`callPdcAuditorOperationGateway('status', {
      config: pdcAuditorOperationGatewayConfig(), token: getPdcSupabaseAccessToken(), authority: auditorAuthorityIdentity()
    })`, race);
    resolveFetch({ ok:true, json:async()=>receipt });
    const trusted = await trustedPromise;
    assert.ok(trusted,'mocked successful status response must return a trusted receipt');
    race.app.pdcAuditorPendingOperation = trusted;
    return trusted;
  };
  const pending = vm.runInContext('loadPdcAuditorPendingOperation()', race);
  raceToken = 'NEW_ACCOUNT_JWT';
  raceAuthority = 'NEW_ACCOUNT';
  race.app.pdcAuditorGeneration = 8;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  resolveFetch({ ok:true, json: async()=>({ state:'undo_available', instance_id:'gw-staging-1', run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64) }) });
  const loaded = await pending;
  assert.strictEqual(loaded,false,'stale gateway status response must be discarded after auth reset');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,null,'old-account receipt must not survive auth reset');
  assert.strictEqual(nodes['#ai-auditor-operation-undo'].disabled,true,'undo must remain disabled after stale response');
  console.log('AI Auditor in-flight auth-reset race teardown passed');

  raceToken = 'STATUS_GENERATION_JWT';
  raceAuthority = 'STATUS_GENERATION_ACCOUNT';
  race.window.PDC_AUTH_CONTEXT.role = 'administrator';
  race.app.pdcAuditorGeneration = 8;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  race.app.pdcAuditorOperationOwner = null;
  const staleStatus = vm.runInContext('loadPdcAuditorPendingOperation()', race);
  race.app.pdcAuditorGeneration += 1;
  resolveFetch({ ok:true, json:async()=>({ state:'undo_available', instance_id:'gw-staging-1', run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64) }) });
  assert.strictEqual(await staleStatus,false,'same-authority stale-generation status result must be withheld');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,null,'stale-generation status must not publish a receipt');
  assert.strictEqual(race.app.pdcAuditorOperationBusy,false,'stale-generation status must release its own busy latch');
  assert.strictEqual(race.app.pdcAuditorOperationOwner,null,'stale-generation status must release its owner');
  console.log('AI Auditor same-authority stale status liveness passed');

  raceToken = 'STATUS_IDENTITY_JWT';
  raceAuthority = 'STATUS_IDENTITY_A';
  race.app.pdcAuditorGeneration += 1;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  race.app.pdcAuditorOperationOwner = null;
  const identityStatus = vm.runInContext('loadPdcAuditorPendingOperation()', race);
  raceAuthority = 'STATUS_IDENTITY_B';
  resolveFetch({ ok:true, json:async()=>({ state:'undo_available', instance_id:'gw-staging-1', run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64) }) });
  assert.strictEqual(await identityStatus,false,'status must be withheld after authority-identity replacement with a stable token');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,null,'old-identity status must not publish');
  assert.strictEqual(race.app.pdcAuditorOperationBusy,false,'old-identity status must release its own latch');
  assert.strictEqual(race.app.pdcAuditorOperationOwner,null,'old-identity status must release its owner');

  raceAuthority = 'STATUS_CONFIG_ACCOUNT';
  race.app.pdcAuditorGeneration += 1;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  race.app.pdcAuditorOperationOwner = null;
  const statusRequestIndex = gatewayRequests.length;
  const configStatus = vm.runInContext('loadPdcAuditorPendingOperation()', race);
  race.window.PDC_SUPABASE_CONFIG.auditorOperationGateway = { url:'https://replacement.staging.example/auditor', instanceId:'gw-staging-2' };
  resolveFetch({ ok:true, json:async()=>({ state:'undo_available', instance_id:'gw-staging-1', run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64) }) });
  assert.strictEqual(await configStatus,false,'status must be withheld after gateway replacement');
  assert.strictEqual(gatewayRequests[statusRequestIndex].url,'https://gateway.staging.example/auditor/v1/auditor-operation/status','status dispatch must use the captured gateway URL');
  assert.strictEqual(gatewayRequests[statusRequestIndex].options.headers['X-PDC-Auditor-Gateway'],'gw-staging-1','status dispatch must use the captured gateway instance');
  assert.strictEqual(gatewayRequests[statusRequestIndex].options.headers.Authorization,'Bearer STATUS_IDENTITY_JWT','status dispatch must use the captured token');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,null,'replaced-gateway status must not publish');
  assert.strictEqual(race.app.pdcAuditorOperationBusy,false,'replaced-gateway status must release its own latch');
  assert.strictEqual(race.app.pdcAuditorOperationOwner,null,'replaced-gateway status must release its owner');
  race.window.PDC_SUPABASE_CONFIG.auditorOperationGateway = { url:'https://gateway.staging.example/auditor', instanceId:'gw-staging-1' };
  console.log('AI Auditor status identity/config capture and supersession passed');

  race.app.pdcAuditorGeneration += 1;
  race.app.pdcAuditorPendingOperation = null;
  race.app.pdcAuditorOperationBusy = false;
  race.app.pdcAuditorOperationOwner = null;
  const replacedStatus = vm.runInContext('loadPdcAuditorPendingOperation()', race);
  const replacementStatusOwner = { replacement:true };
  const replacementStatusPending = { state:'none', instance_id:'gw-staging-1', message:'replacement status owns latch' };
  race.app.pdcAuditorOperationOwner = replacementStatusOwner;
  race.app.pdcAuditorOperationBusy = true;
  race.app.pdcAuditorPendingOperation = replacementStatusPending;
  resolveFetch({ ok:true, json:async()=>({ state:'undo_available', instance_id:'gw-staging-1', run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64) }) });
  assert.strictEqual(await replacedStatus,false,'owner-replaced status must be superseded');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,replacementStatusPending,'old status must not overwrite replacement pending state');
  assert.strictEqual(race.app.pdcAuditorOperationBusy,true,'old status must not release replacement busy latch');
  assert.strictEqual(race.app.pdcAuditorOperationOwner,replacementStatusOwner,'old status must not clear replacement owner');
  race.app.pdcAuditorOperationBusy = false;
  race.app.pdcAuditorOperationOwner = null;
  console.log('AI Auditor status owner-only replacement isolation passed');

  const originalPending = {
    state:'pending_apply', instance_id:'gw-staging-1',
    proposal_id:'11111111-2222-4333-8444-555555555555', proposal_version:9,
    proposal_hash:'a'.repeat(64), typed_item_set_hash:'b'.repeat(64),
    final_scope_hash:'c'.repeat(64), expected_row_versions_hash:'d'.repeat(64),
  };
  raceToken = 'OLD_MUTATION_ACCOUNT_JWT';
  raceAuthority = 'OLD_MUTATION_ACCOUNT';
  race.app.pdcAuditorGeneration = 9;
  race.app.pdcAuditorPendingOperation = originalPending;
  await bindCurrentOrigin();
  race.app.pdcAuditorOperationBusy = false;
  const confirming = vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race);
  raceToken = 'REPLACEMENT_ACCOUNT_JWT';
  raceAuthority = 'REPLACEMENT_ACCOUNT';
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
  raceAuthority = 'CURRENT_ACCOUNT';
  race.app.pdcAuditorGeneration = 11;
  race.app.pdcAuditorPendingOperation = originalPending;
  await bindCurrentOrigin();
  race.app.pdcAuditorOperationBusy = false;
  const replaced = vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race);
  race.app.pdcAuditorPendingOperation = { ...originalPending, proposal_version:10 };
  resolveFetch({ ok:true, json:async()=>({ state:'completed', instance_id:'gw-staging-1', message:'superseded binding completed' }) });
  assert.strictEqual(await replaced,false,'completion for a superseded pending binding must not report success');
  assert.strictEqual(race.app.pdcAuditorPendingOperation.proposal_version,10,'stale completion must not overwrite the replacement binding');
  assert.strictEqual(snapshotLoads,0,'superseded binding completion must not trigger an authoritative reload');
  console.log('AI Auditor pending-binding replacement race teardown passed');

  raceToken = 'MISSING_TOKEN_PROVENANCE_JWT';
  race.app.pdcAuditorGeneration = 12;
  race.app.pdcAuditorPendingOperation = originalPending;
  await bindCurrentOrigin();
  const missingTokenPending = race.app.pdcAuditorPendingOperation;
  raceToken = '';
  race.app.pdcAuditorOperationBusy = false;
  assert.strictEqual(await vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race),false,'missing token must fail before confirmation or gateway dispatch');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,missingTokenPending,'missing-token rejection must not mutate pending authority');
  console.log('AI Auditor missing-token confirmation denial passed');

  const undoPending = {
    state:'undo_available', instance_id:'gw-staging-1',
    run_id:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', run_revision_after:'e'.repeat(64),
  };

  for (const [action, pendingFromGatewayA] of [['apply', originalPending], ['undo', undoPending]]) {
    raceToken = `ORIGIN_${action.toUpperCase()}_TOKEN`;
    raceAuthority = `ORIGIN_${action.toUpperCase()}_ACCOUNT`;
    race.window.PDC_AUTH_CONTEXT.role = 'administrator';
    race.window.PDC_SUPABASE_CONFIG.auditorOperationGateway = { url:'https://gateway-a.staging.example/auditor', instanceId:'gw-staging-1' };
    race.app.pdcAuditorPendingOperation = pendingFromGatewayA;
    const trustedPendingFromGatewayA = await bindCurrentOrigin();
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
    race.window.PDC_SUPABASE_CONFIG.auditorOperationGateway = { url:'https://gateway-b.staging.example/auditor', instanceId:'gw-staging-2' };
    const callsBefore = fetchCalls;
    assert.strictEqual(await vm.runInContext(`confirmPdcAuditorPendingOperation('${action}')`, race),false,`${action} must reject a receipt loaded from a different gateway origin`);
    assert.strictEqual(fetchCalls,callsBefore,`${action} gateway-A receipt must dispatch zero requests through gateway B`);
    assert.strictEqual(race.app.pdcAuditorPendingOperation,trustedPendingFromGatewayA,`${action} origin rejection must not rewrite the stale receipt`);
    vm.runInContext('renderPdcAuditorPendingOperation()', race);
    assert.strictEqual(nodes[`#ai-auditor-operation-${action}`].disabled,true,`${action} control must be disabled when receipt origin differs from current gateway`);
  }
  race.window.PDC_SUPABASE_CONFIG.auditorOperationGateway = { url:'https://gateway.staging.example/auditor', instanceId:'gw-staging-1' };
  console.log('AI Auditor gateway-origin A-to-B Apply/Undo denial passed');

  for (const [action, initial] of [
    ['apply', { ...originalPending }],
    ['undo', { ...undoPending }],
  ]) {
    raceToken = `IN_PLACE_${action.toUpperCase()}_TOKEN`;
    raceAuthority = `IN_PLACE_${action.toUpperCase()}_ACCOUNT`;
    race.window.PDC_AUTH_CONTEXT.role = 'administrator';
    race.window.PDC_SUPABASE_CONFIG.auditorOperationGateway = { url:'https://gateway.staging.example/auditor', instanceId:'gw-staging-1' };
    race.app.pdcAuditorPendingOperation = initial;
    const trustedInitial = await bindCurrentOrigin();
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
    if (action === 'apply') trustedInitial.proposal_id = '99999999-8888-4777-8666-555555555555';
    else trustedInitial.run_id = '99999999-8888-4777-8666-555555555555';
    vm.runInContext('renderPdcAuditorPendingOperation()', race);
    assert.strictEqual(nodes[`#ai-auditor-operation-${action}`].disabled,true,`${action} control must disable after in-place receipt mutation`);
    const callsBefore = fetchCalls;
    assert.strictEqual(await vm.runInContext(`confirmPdcAuditorPendingOperation('${action}')`, race),false,`${action} must reject in-place mutation of a trusted receipt`);
    assert.strictEqual(fetchCalls,callsBefore,`${action} in-place receipt mutation must dispatch zero requests`);
  }
  console.log('AI Auditor exact receipt-content provenance passed');

  for (const [action, initial, replacement] of [
    ['apply', originalPending, { ...originalPending, proposal_id:'99999999-8888-4777-8666-555555555555' }],
    ['undo', undoPending, { ...undoPending, run_id:'99999999-8888-4777-8666-555555555555' }],
  ]) {
    raceToken = `PRE_CONFIRM_${action.toUpperCase()}_A`;
    raceAuthority = `PRE_CONFIRM_${action.toUpperCase()}_ACCOUNT_A`;
    race.window.PDC_AUTH_CONTEXT.role = 'administrator';
    race.app.pdcAuditorGeneration += 1;
    race.app.pdcAuditorPendingOperation = initial;
    await bindCurrentOrigin();
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
    const callsBefore = fetchCalls;
    race.window.confirm = ()=>{
      raceToken = `PRE_CONFIRM_${action.toUpperCase()}_B`;
      raceAuthority = `PRE_CONFIRM_${action.toUpperCase()}_ACCOUNT_B`;
      race.app.pdcAuditorGeneration += 1;
      race.app.pdcAuditorPendingOperation = replacement;
      return true;
    };
    assert.strictEqual(await vm.runInContext(`confirmPdcAuditorPendingOperation('${action}')`, race),false,`${action} must fail if confirmation changes operation ownership`);
    assert.strictEqual(fetchCalls,callsBefore,`${action} must dispatch zero gateway requests after pre-dispatch ownership change`);
    assert.strictEqual(race.app.pdcAuditorPendingOperation,replacement,`${action} must preserve replacement-session pending state`);
    assert.strictEqual(race.app.pdcAuditorOperationBusy,false,`${action} must not latch replacement-session busy state`);
  }
  race.window.confirm = ()=>true;
  console.log('AI Auditor pre-gateway Apply/Undo TOCTOU denial passed');

  for (const [action, initial] of [['apply', originalPending], ['undo', undoPending]]) {
    raceToken = `DISPATCH_${action.toUpperCase()}_TOKEN_A`;
    raceAuthority = `DISPATCH_${action.toUpperCase()}_ACCOUNT_A`;
    race.app.pdcAuditorGeneration += 1;
    race.app.pdcAuditorPendingOperation = initial;
    await bindCurrentOrigin();
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
    const requestIndex = gatewayRequests.length;
    const dispatched = vm.runInContext(`confirmPdcAuditorPendingOperation('${action}')`, race);
    assert.strictEqual(gatewayRequests.length,requestIndex + 1,`${action} must dispatch one request`);
    const request = gatewayRequests[requestIndex];
    assert.strictEqual(request.options.headers.Authorization,`Bearer DISPATCH_${action.toUpperCase()}_TOKEN_A`,`${action} must dispatch the captured token`);
    assert.strictEqual(JSON.parse(request.options.body).binding,action === 'apply' ? initial.proposal_id : initial.run_id,`${action} must dispatch the captured binding`);
    raceToken = `DISPATCH_${action.toUpperCase()}_TOKEN_B`;
    raceAuthority = `DISPATCH_${action.toUpperCase()}_ACCOUNT_B`;
    race.app.pdcAuditorGeneration += 1;
    race.app.pdcAuditorPendingOperation = action === 'apply' ? { ...initial, proposal_version:99 } : { ...initial, run_revision_after:'f'.repeat(64) };
    const replacement = race.app.pdcAuditorPendingOperation;
    resolveFetch({ ok:true, json:async()=>({ state:'completed', instance_id:'gw-staging-1', message:'stale mutation completed' }) });
    assert.strictEqual(await dispatched,false,`${action} completion must fail after post-dispatch authority replacement`);
    assert.strictEqual(race.app.pdcAuditorPendingOperation,replacement,`${action} stale completion must not overwrite replacement pending state`);
    assert.strictEqual(race.app.pdcAuditorOperationBusy,false,`${action} stale invocation must release its own busy lock`);
  }
  console.log('AI Auditor captured Apply/Undo dispatch and stale busy ownership passed');

  for (const [action, initial] of [['apply', originalPending], ['undo', undoPending]]) {
    raceToken = `OWNER_ONLY_${action.toUpperCase()}_TOKEN`;
    raceAuthority = `OWNER_ONLY_${action.toUpperCase()}_ACCOUNT`;
    race.app.pdcAuditorGeneration += 1;
    race.app.pdcAuditorPendingOperation = initial;
    const trustedOwnerPending = await bindCurrentOrigin();
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
    snapshotLoads = 0;
    const ownerOnly = vm.runInContext(`confirmPdcAuditorPendingOperation('${action}')`, race);
    const replacementOwner = { replacement:action };
    race.app.pdcAuditorOperationOwner = replacementOwner;
    race.app.pdcAuditorOperationBusy = true;
    resolveFetch({ ok:true, json:async()=>({ state:'completed', instance_id:'gw-staging-1', message:'old owner completed' }) });
    assert.strictEqual(await ownerOnly,false,`${action} must not publish after owner-only replacement`);
    assert.strictEqual(snapshotLoads,0,`${action} owner-only replacement must start zero reloads`);
    assert.strictEqual(race.app.pdcAuditorPendingOperation,trustedOwnerPending,`${action} owner-only replacement must preserve exact pending state`);
    assert.strictEqual(race.app.pdcAuditorOperationBusy,true,`${action} old continuation must not release replacement latch`);
    assert.strictEqual(race.app.pdcAuditorOperationOwner,replacementOwner,`${action} old continuation must not clear replacement owner`);
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
  }
  console.log('AI Auditor Apply/Undo owner-only replacement isolation passed');

  raceToken = 'CURRENT_SUCCESS_JWT';
  raceAuthority = 'CURRENT_SUCCESS_ACCOUNT';
  race.app.pdcAuditorGeneration = 13;
  race.app.pdcAuditorPendingOperation = originalPending;
  await bindCurrentOrigin();
  race.app.pdcAuditorOperationBusy = false;
  snapshotLoads = 0;
  race.loadPdcAuditorSnapshot = ()=>{
    snapshotLoads += 1;
    race.app.pdcAuditorGeneration += 1;
    return Promise.resolve(true);
  };
  const success = vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race);
  const successReceipt = { state:'completed', instance_id:'gw-staging-1', message:'current mutation completed' };
  resolveFetch({ ok:true, json:async()=>successReceipt });
  assert.strictEqual(await success,true,'current-authority success must own the snapshot generation increment');
  assert.strictEqual(snapshotLoads,1,'current-authority success must perform one authoritative reload');
  assert.strictEqual(race.app.pdcAuditorPendingOperation.state,'completed','successful receipt must publish after authoritative reload');
  assert.strictEqual(race.app.pdcAuditorOperationBusy,false,'successful completion must release operation busy state');
  console.log('AI Auditor current-authority success generation handoff passed');

  race.app.pdcAuditorGeneration = 15;
  race.app.pdcAuditorPendingOperation = originalPending;
  const trustedFailedReloadPending = await bindCurrentOrigin();
  race.app.pdcAuditorOperationBusy = false;
  snapshotLoads = 0;
  race.loadPdcAuditorSnapshot = ()=>{
    snapshotLoads += 1;
    race.app.pdcAuditorGeneration += 1;
    return Promise.resolve(false);
  };
  const failedReload = vm.runInContext("confirmPdcAuditorPendingOperation('apply')", race);
  resolveFetch({ ok:true, json:async()=>successReceipt });
  assert.strictEqual(await failedReload,false,'failed authoritative reload must not report mutation success');
  assert.strictEqual(snapshotLoads,1,'failed authoritative reload must be attempted once');
  assert.strictEqual(race.app.pdcAuditorPendingOperation,trustedFailedReloadPending,'failed reload must not publish the mutation receipt');
  assert.strictEqual(race.app.pdcAuditorOperationBusy,false,'failed reload under current authority must release busy state');
  console.log('AI Auditor failed-reload busy-state release passed');

  for (const [action, initial] of [['apply', originalPending], ['undo', undoPending]]) {
    raceToken = `GENERATION_${action.toUpperCase()}_TOKEN`;
    raceAuthority = `GENERATION_${action.toUpperCase()}_ACCOUNT`;
    race.app.pdcAuditorGeneration += 1;
    race.app.pdcAuditorPendingOperation = initial;
    await bindCurrentOrigin();
    race.app.pdcAuditorOperationBusy = false;
    race.app.pdcAuditorOperationOwner = null;
    snapshotLoads = 0;
    race.loadPdcAuditorSnapshot = ()=>{
      snapshotLoads += 1;
      race.app.pdcAuditorGeneration += 1;
      return Promise.resolve(true);
    };
    const sameAuthority = vm.runInContext(`confirmPdcAuditorPendingOperation('${action}')`, race);
    race.app.pdcAuditorGeneration += 1;
    resolveFetch({ ok:true, json:async()=>({ state:'completed', instance_id:'gw-staging-1', message:'same authority completed' }) });
    assert.strictEqual(await sameAuthority,true,`${action} must remain live across same-authority snapshot generation supersession`);
    assert.strictEqual(snapshotLoads,1,`${action} must reconcile with one authoritative reload`);
    assert.strictEqual(race.app.pdcAuditorPendingOperation.state,'completed',`${action} must publish receipt after reconciliation`);
    assert.strictEqual(race.app.pdcAuditorOperationBusy,false,`${action} must release busy after same-authority generation supersession`);
    assert.strictEqual(race.app.pdcAuditorOperationOwner,null,`${action} must release operation ownership`);
  }
  console.log('AI Auditor same-authority Apply/Undo generation liveness passed');
})().catch(error=>{ console.error(error); process.exit(1); });
