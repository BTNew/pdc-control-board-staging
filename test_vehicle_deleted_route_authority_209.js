'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
function extractFunction(source, signature) {
  const start = source.indexOf(signature);
  assert(start >= 0, `missing ${signature}`);
  const brace = source.indexOf('{', start);
  let depth = 0;
  for (let i = brace; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`unterminated ${signature}`);
}
const navSource = extractFunction(app, 'function resetDeletedVehicleAuthorityState(');
const showSource = extractFunction(app, 'function showView(');
assert(navSource.includes('deletedVehicleSnapshotGeneration += 1'));
assert(showSource.indexOf("requestedView === 'deleted'") < showSource.indexOf('app.currentRequestedView = requestedView'));

const calls = { history: [], expanded: [], release: 0 };
const elements = new Map();
const makeElement = () => ({ classList: { toggle() {}, remove() {}, add() {} }, dataset: {}, hidden: false, setAttribute() {}, getAttribute() { return 'false'; } });
const context = {
  app: { currentView: 'deleted', currentRequestedView: 'deleted', deletedVehicleSnapshotRows: [{ id: 'secret' }], deletedVehicleSnapshotState: 'ready', deletedVehicleSnapshotError: 'secret', deletedVehicleSnapshotGeneration: 2, activePmbBayStage: '', pmbSubFilter: '' },
  vehicleLifecycleAdministratorActive: () => false,
  WORKSHOP_PLANNER_VIEWS: {}, PRODUCTION_DEPARTMENT_VIEWS: {}, PRODUCTION_FLOW_DEFS: [],
  workshopCombinedPlannerRollbackEnabled: () => false,
  releaseHeavyViewDom: () => { calls.release += 1; }, updateWorkshopBrowserRoute: (v, mode) => calls.history.push([v, mode]),
  teardownWorkshopPlannerScope() {}, teardownWorkshopEligibilityOverview() {}, setAdminNavigationExpanded: value => calls.expanded.push(value),
  syncAdminNavigationVisibility: () => true, renderDashboard() {}, renderAll() {}, renderActiveView() {},
  scheduleWorkflowFloatingHeaderUpdate() {}, workshopEligibilitySharedAuthorityEnabled: () => false, loadWorkshopEligibilitySnapshot() {},
  pmbStageLabel: value => value,
  document: { body: { dataset: {}, classList: { remove() {} } }, getElementById: id => { if (!elements.has(id)) elements.set(id, makeElement()); return elements.get(id); }, querySelector: () => makeElement(), querySelectorAll: () => [] },
  window: {}, console,
  $: selector => { if (!elements.has(selector)) elements.set(selector, makeElement()); return elements.get(selector); },
  $$: () => [],
  Set, Boolean, String,
};
vm.createContext(context);
vm.runInContext(`${navSource}\n${showSource}\nthis.showViewUnderTest=showView;`, context);
context.showViewUnderTest('deleted', { historyMode: 'replace' });
assert.strictEqual(context.app.currentRequestedView, 'dashboard', 'non-admin direct Deleted route redirects before state mutation');
assert.strictEqual(context.app.currentView, 'dashboard');
assert.strictEqual(context.app.deletedVehicleSnapshotRows.length, 0, 'privileged tombstone rows are cleared');
assert.strictEqual(context.app.deletedVehicleSnapshotState, 'idle');
assert.strictEqual(context.app.deletedVehicleSnapshotError, '');
assert.deepStrictEqual(calls.history[0], ['dashboard', 'replace']);
console.log('Deleted Vehicle direct-route denial and authority-state clearing passed');
