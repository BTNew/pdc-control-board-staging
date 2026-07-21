'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert(start >= 0, `missing ${name}`);
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

function testRollbackFailClosed() {
  const fn = vm.runInNewContext(`(${extractFunction('workshopCombinedPlannerRollbackEnabled')})`, {
    window: { PDC_SUPABASE_CONFIG: {} }
  });
  assert.strictEqual(fn(), false);
  const enabled = vm.runInNewContext(`(${extractFunction('workshopCombinedPlannerRollbackEnabled')})`, {
    window: { PDC_SUPABASE_CONFIG: { workshop: { stationRoutes: { combinedPlannerRollback: true } } } }
  });
  assert.strictEqual(enabled(), true);
}

function testMalformedHashFailsSafe() {
  const fn = vm.runInNewContext(`(${extractFunction('workshopViewFromLocation')})`, {
    window: { location: { hash: '#/%E0%A4%A' } },
    WORKSHOP_PLANNER_ROUTE_BY_PATH: {},
    workshopCombinedPlannerRollbackEnabled: () => false,
    document: { getElementById: () => null, querySelector: () => null }
  });
  assert.strictEqual(fn(), 'dashboard');
}

function testScopedRealtimeTransport() {
  const calls = [];
  const channel = {
    on(_kind, spec, callback) { calls.push({ type: 'on', spec, callback }); return this; },
    subscribe(callback) { calls.push({ type: 'subscribe', callback }); return this; }
  };
  const client = {
    channel(name) { calls.push({ type: 'channel', name }); return channel; },
    removeChannel(value) { calls.push({ type: 'remove', value }); }
  };
  const context = { window: { PDC_SUPABASE: client } };
  const fn = vm.runInNewContext(`(${extractFunction('createPdcSupabaseRealtimeSubscription')})`, context);
  const subscription = fn({}, {}, { stageCode: 'tint' });
  assert.strictEqual(calls[0].name, 'workshop-station-revision-tint');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(calls[1].spec)), {
    event: '*', schema: 'public', table: 'workshop_station_revision', filter: 'stage_code=eq.TINT'
  });
  subscription.unsubscribe();
  assert.strictEqual(calls.at(-1).type, 'remove');
}

function testRecoveryAndAuthLifecycleContracts() {
  assert.strictEqual((source.match(/__workshopRecoveryListenersInstalled/g) || []).length, 2, 'one guard and one assignment expected');
  assert(source.includes("window.addEventListener('online', () => window.__workshopRealtimeManager?.forceReconnect?.())"));
  assert(source.includes("if (app.currentView === 'workshop' && typeof initWorkshopSharedServicesIfEnabled === 'function')"));
  assert(source.includes("if (app.currentView !== 'workshop') return;"));
}

testRollbackFailClosed();
testMalformedHashFailsSafe();
testScopedRealtimeTransport();
testRecoveryAndAuthLifecycleContracts();
console.log('station_planner_app_lifecycle: PASS');
