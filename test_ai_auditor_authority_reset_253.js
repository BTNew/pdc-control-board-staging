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