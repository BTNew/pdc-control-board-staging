'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(require('path').join(__dirname, 'app.js'), 'utf8');
function functionBlock(name) {
  let start = source.indexOf(`function ${name}(`);
  assert(start >= 0, name);
  if (source.slice(Math.max(0, start - 6), start) === 'async ') start -= 6;
  const brace = source.indexOf('{', start);
  let depth = 0;
  for (let i = brace; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(name);
}

async function lateFailureCase(status) {
  let handlers = null;
  let fetches = 0;
  let subscriptions = 0;
  let unsubscribeCalls = 0;
  let timerCallback = null;
  let resolveDeferred = null;
  const app = {
    workshopEligibilityRealtime: null,
    workshopEligibilityReconnectTimer: null,
    workshopEligibilityRevisionPending: false,
    workshopEligibilitySnapshot: null,
    workshopEligibilityState: 'idle',
    workshopEligibilityError: '',
    workshopEligibilityRequestGeneration: 0,
    currentView: 'workflow',
  };
  const context = {
    app,
    console,
    window: null,
    getPdcSupabaseAccessToken: () => 'token',
    renderWorkflowBoard: () => {},
    setTimeout: callback => { timerCallback = callback; return subscriptions + 10; },
    clearTimeout: () => { timerCallback = null; },
    createPdcSupabaseRealtimeSubscription: (_config, next) => {
      subscriptions += 1;
      handlers = next;
      return { unsubscribe() { unsubscribeCalls += 1; } };
    },
    fetch: async () => {
      fetches += 1;
      if (fetches === 1) await new Promise(resolve => { resolveDeferred = resolve; });
      return { ok: true, json: async () => ({ stages: [], candidates: [], revision: fetches }) };
    },
    WORKSHOP_ELIGIBILITY: { canonicalWorkshopStage: value => value },
    workshopEligibilityCandidateVehicle: value => value,
    displayStockNumber: () => '',
    vehicleKey: () => '',
  };
  context.window = context;
  context.PDC_SUPABASE_CONFIG = { url: 'https://staging.invalid', publishableKey: 'public', workshop: { sharedData: true } };
  vm.runInNewContext([
    functionBlock('workshopEligibilitySharedAuthorityEnabled'),
    functionBlock('failWorkshopEligibilityOverviewSubscription'),
    functionBlock('workshopEligibilityOverviewSubscribe'),
    functionBlock('loadWorkshopEligibilitySnapshot'),
    functionBlock('authoritativeWorkshopVehiclesForStage'),
  ].join('\n'), context);

  context.workshopEligibilityOverviewSubscribe();
  assert.strictEqual(subscriptions, 1);
  const failedHandlers = handlers;
  const pending = failedHandlers.onSubscribed();
  await new Promise(resolve => setImmediate(resolve));
  assert.strictEqual(app.workshopEligibilityState, 'loading');
  if (status === 'CLOSED') failedHandlers.onClosed(status);
  else failedHandlers.onError(status);
  assert.strictEqual(app.workshopEligibilitySnapshot, null);
  assert.strictEqual(app.workshopEligibilityState, 'reconnecting');
  assert.strictEqual(app.workshopEligibilityRealtime, null);
  assert.strictEqual(unsubscribeCalls, 1, `${status}: failed channel cleaned once`);
  assert(timerCallback, `${status}: replacement timer scheduled`);

  // Supabase commonly emits CLOSED after ERROR/TIMED_OUT. The stale callback
  // must not create a second timer or clean the channel twice.
  failedHandlers.onClosed('CLOSED');
  assert.strictEqual(unsubscribeCalls, 1, `${status}: duplicate failure callback inert`);

  resolveDeferred();
  await pending;
  assert.strictEqual(app.workshopEligibilitySnapshot, null, `${status}: late response cannot restore snapshot`);
  assert.strictEqual(app.workshopEligibilityState, 'reconnecting', `${status}: late response cannot restore connected state`);
  assert.strictEqual(context.authoritativeWorkshopVehiclesForStage('HOIST').length, 0, `${status}: late candidates remain non-actionable`);

  const retry = timerCallback;
  retry();
  assert.strictEqual(subscriptions, 2, `${status}: exactly one replacement subscription`);
  await handlers.onSubscribed();
  assert.strictEqual(fetches, 2, `${status}: replacement performs fresh resync`);
  assert.strictEqual(app.workshopEligibilityState, 'connected');
  assert.strictEqual(app.workshopEligibilitySnapshot.revision, 2);
}

async function pendingRevisionCase() {
  let handlers;
  let fetches = 0;
  let deferredResolve;
  let defer = false;
  const app = { workshopEligibilityRealtime: null, workshopEligibilityReconnectTimer: null, workshopEligibilityRevisionPending: false, workshopEligibilitySnapshot: null, workshopEligibilityState: 'idle', workshopEligibilityError: '', workshopEligibilityRequestGeneration: 0, currentView: 'workflow' };
  const context = { app, console, window: null, getPdcSupabaseAccessToken: () => 'token', renderWorkflowBoard: () => {}, setTimeout, clearTimeout,
    createPdcSupabaseRealtimeSubscription: (_config, next) => { handlers = next; return { unsubscribe() {} }; },
    fetch: async () => { fetches += 1; if (defer) { defer = false; await new Promise(resolve => { deferredResolve = resolve; }); } return { ok: true, json: async () => ({ stages: [], candidates: [], revision: fetches }) }; },
    WORKSHOP_ELIGIBILITY: { canonicalWorkshopStage: value => value }, workshopEligibilityCandidateVehicle: value => value, displayStockNumber: () => '', vehicleKey: () => '' };
  context.window = context;
  context.PDC_SUPABASE_CONFIG = { url: 'https://staging.invalid', publishableKey: 'public', workshop: { sharedData: true } };
  vm.runInNewContext([functionBlock('workshopEligibilitySharedAuthorityEnabled'), functionBlock('failWorkshopEligibilityOverviewSubscription'), functionBlock('workshopEligibilityOverviewSubscribe'), functionBlock('loadWorkshopEligibilitySnapshot')].join('\n'), context);
  context.workshopEligibilityOverviewSubscribe();
  await handlers.onSubscribed();
  defer = true;
  const racing = context.loadWorkshopEligibilitySnapshot('race');
  await new Promise(resolve => setImmediate(resolve));
  handlers.onChange();
  assert.strictEqual(app.workshopEligibilityRevisionPending, true);
  deferredResolve();
  await racing;
  assert.strictEqual(fetches, 3, 'revision during resync forces one trailing authoritative fetch');
  assert.strictEqual(app.workshopEligibilitySnapshot.revision, 3);
}

(async () => {
  for (const status of ['CHANNEL_ERROR', 'TIMED_OUT', 'CLOSED']) await lateFailureCase(status);
  await pendingRevisionCase();
  console.log('All-station Realtime generation, failure and trailing-resync authority: passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
