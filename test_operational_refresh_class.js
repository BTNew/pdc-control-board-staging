'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { createPdcOperationalRefreshCoordinator } = require('./vehicle-locations-refresh.js');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');

function deferred() {
  let resolve;
  return { promise: new Promise(done => { resolve = done; }), resolve };
}

async function testRouteAdaptersAndStaleIsolation() {
  const first = deferred();
  const second = deferred();
  const calls = [];
  const finishes = [];
  const coordinator = createPdcOperationalRefreshCoordinator({
    getRoute: () => 'parts',
    routeAdapters: {
      parts: { authoritative: ({ route, generation }) => { calls.push([route, generation]); return first.promise; } },
      rft: { authoritative: ({ route, generation }) => { calls.push([route, generation]); return second.promise; } },
    },
    onFinish: result => finishes.push(result),
  });
  const oldRun = coordinator.refresh({ route: 'parts' });
  const currentRun = coordinator.refresh({ route: 'rft', supersede: true });
  second.resolve({ ok: true, revision: 44 });
  const currentResult = await currentRun;
  first.resolve({ ok: true, revision: 43 });
  const oldResult = await oldRun;
  assert.strictEqual(currentResult.route, 'rft');
  assert.strictEqual(currentResult.ok, true);
  assert.strictEqual(oldResult.stale, true);
  assert.deepStrictEqual(calls, [['parts', 1], ['rft', 2]]);
  assert.deepStrictEqual(finishes.map(result => result.route), ['rft']);
}

async function testDoubleClickCoalescesPerCoordinator() {
  const pending = deferred();
  let count = 0;
  const coordinator = createPdcOperationalRefreshCoordinator({
    routeAdapters: { dashboard: { snapshot: () => { count += 1; return pending.promise; } } },
  });
  const first = coordinator.refresh({ route: 'dashboard' });
  const second = coordinator.refresh({ route: 'dashboard' });
  assert.strictEqual(first, second);
  assert.strictEqual(count, 1);
  pending.resolve({ ok: true });
  await first;
  assert.strictEqual(coordinator.isRefreshing(), false);
}

function testRouteMatrixAndSafetyContracts() {
  const expectedRoutes = ['dashboard', 'qc', 'workflow', 'workshop', 'visibility', 'tv', 'schedule', 'department', 'parts', 'sublet', 'rft', 'completed', 'collected', 'deleted', 'backend', 'emailreview', 'ai-auditor'];
  expectedRoutes.forEach(route => assert.match(app, new RegExp(`['\\"]${route}['\\"]`), `route ${route} is included in the coordinator matrix`));
  assert.match(app, /createPdcOperationalRefreshCoordinator/);
  assert.match(app, /routeAdapters/);
  assert.match(app, /captureOperationalRefreshViewState/);
  assert.match(app, /restoreOperationalRefreshViewState/);
  assert.match(app, /operationalRefreshDraftConflicts/);
  assert.match(app, /data-pdc-operational-refresh/);
  assert.match(app, /refreshEmailVehicleLocations\(\{ refreshGeneration: generation \}\)/);
  assert.match(app, /loadSharedNavisionVisibleRows\(\{ force: true, refreshGeneration: generation \}\)/);
  assert.match(app, /if \(route !== 'workshop'\) return \{ ok: true, skipped: true \};/);
  assert.match(app, /service\.loadSnapshot\(`operational_refresh:\$\{route\}`\)/);
  assert.match(app, /window\.__workshopRealtimeManager\?\.start/);
  const refreshSlice = app.slice(app.indexOf('function operationalRefreshCommonLoaders'), app.indexOf('function getOperationalRefreshCoordinator'));
  assert.doesNotMatch(refreshSlice, /localStorage|loadJson/);
  assert.match(refreshSlice, /Promise\.all\(refreshes\)/);
  assert.match(app, /inFlight = null/);
  assert.match(app, /invalidateVehicleLocationsRefresh\(\)/);
  assert.doesNotMatch(app, /(?:window\.)?location\.reload\s*\(/);
  assert.doesNotMatch(index, /vjdtsswhroyguxyfjdkt\.supabase\.co/);
  assert.match(index, /vehicle-locations-refresh\.js/);
  assert.match(index, /vehicle-locations-refresh-ui\.js/);
  assert.match(styles, /\.pdc-operational-refresh-control/);
  assert.match(styles, /\.pdc-operational-refresh-button/);
  assert.match(styles, /@media \(max-width: 720px\)/);
}

async function testUiDelegationUsesRouteAndBusyFeedback() {
  const ui = fs.readFileSync(path.join(root, 'vehicle-locations-refresh-ui.js'), 'utf8');
  const context = { console, Promise, setTimeout, clearTimeout, globalThis: null };
  context.window = context;
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(ui, context, { filename: 'vehicle-locations-refresh-ui.js' });
  const listeners = [];
  const rootElement = {
    addEventListener(name, listener) { listeners.push({ name, listener }); },
    contains() { return true; },
  };
  const button = {
    disabled: false,
    textContent: 'Refresh',
    dataset: { pdcRefreshRoute: 'parts' },
    closest() { return this; },
    setAttribute(name, value) { this[name] = value; },
    removeAttribute(name) { delete this[name]; },
  };
  const pending = deferred();
  let route = '';
  const delegation = context.PDC_OPERATIONAL_REFRESH_UI.createOperationalRefreshClickDelegation({
    root: rootElement,
    refresh(value) { route = value; return pending.promise; },
  });
  assert.strictEqual(delegation.bind(), true);
  assert.strictEqual(delegation.bind(), false);
  const event = { target: button, preventDefault() {}, stopPropagation() {} };
  listeners[0].listener(event);
  listeners[0].listener(event);
  assert.strictEqual(route, 'parts');
  assert.strictEqual(button.disabled, true);
  assert.strictEqual(button.textContent, 'Refreshing…');
  assert.strictEqual(button['aria-busy'], 'true');
  pending.resolve({ ok: true });
  await new Promise(resolve => setImmediate(resolve));
  assert.strictEqual(button.disabled, false);
  assert.strictEqual(button.textContent, 'Refresh');
}

(async () => {
  await testRouteAdaptersAndStaleIsolation();
  await testDoubleClickCoalescesPerCoordinator();
  await testUiDelegationUsesRouteAndBusyFeedback();
  testRouteMatrixAndSafetyContracts();
  console.log('Class-level operational refresh regression passed.');
})().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
