'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

function between(start, end) {
  const from = source.indexOf(start);
  assert.notEqual(from, -1, `Missing application integration: ${start}`);
  const to = source.indexOf(end, from + start.length);
  assert.notEqual(to, -1, `Missing integration boundary: ${end}`);
  return source.slice(from, to);
}

function element(id, view) {
  const classes = new Set();
  return {
    id, dataset: view ? { view } : {}, hidden: false, textContent: '', attributes: {},
    classList: {
      toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); },
      remove(name) { classes.delete(name); },
      contains(name) { return classes.has(name); }
    },
    setAttribute(name, value) { this.attributes[name] = value; },
    getAttribute(name) { return this.attributes[name]; },
    replaceChildren() { this.textContent = ''; }
  };
}

function harness(role = 'administrator') {
  const calls = [];
  const handlers = {};
  const names = ['dashboard', 'fitters', 'update-history', 'user-management', 'workshop'];
  const views = names.map(id => element(id));
  const nav = names.map(id => element(`nav-${id}`, id));
  const nodes = new Map([...views, ...nav, ...[
    'nav-admin-toggle', 'nav-admin-menu', 'nav-admin-group', 'page-title', 'pmb-workflow-board'
  ].map(id => element(id))].map(node => [node.id, node]));
  const context = {
    app: { currentView: 'dashboard', currentRequestedView: 'dashboard', selectedRows: new Set() },
    window: {
      PDC_AUTH_CONTEXT: role ? { role, userId: 'synthetic-admin' } : null,
      location: { hash: '#/dashboard' },
      history: {},
      addEventListener(name, handler) { (handlers[name] ||= []).push(handler); },
      PdcUpdateHistory: {
        open() { calls.push('history-open'); },
        close() { calls.push('history-close'); },
        reset() { calls.push('history-reset'); },
        syncAccess() { calls.push('history-access'); }
      },
      PdcFitters: { open() { calls.push('fitter-open'); }, close() { calls.push('fitter-close'); } }
    },
    document: {
      body: element('body'),
      getElementById(id) { return nodes.get(id) || null; },
      querySelector(selector) {
        const match = selector.match(/data-view="([^"]+)"/);
        return match ? nav.find(node => node.dataset.view === match[1]) || null : null;
      }
    },
    $(selector) { return nodes.get(selector.replace(/^#/, '')) || null; },
    $$(selector) { return selector === '.view' ? views : selector === '.nav-item[data-view]' ? nav : []; },
    WORKSHOP_PLANNER_VIEWS: { 'planner-fitting': 'fitting' },
    WORKSHOP_PLANNER_ROUTE_BY_PATH: { 'workshop/fitting': 'planner-fitting' },
    WORKSHOP_STATION_ROUTE_DEFS: [{ view: 'planner-fitting', path: 'workshop/fitting' }],
    PRODUCTION_DEPARTMENT_VIEWS: {}, PRODUCTION_FLOW_DEFS: [],
    USER_MANAGEMENT_STATE: { generation: 0, rows: [] }, activeRenderJsonCache: null,
    syncUserManagementAccess() { return context.window.PDC_AUTH_CONTEXT?.role === 'administrator'; },
    vehicleLifecycleAdministratorActive() { return context.window.PDC_AUTH_CONTEXT?.role === 'administrator'; },
    workshopCombinedPlannerRollbackEnabled() { return false; },
    workshopEligibilitySharedAuthorityEnabled() { return false; },
    pmbStageLabel(stage) { return stage; }
  };
  for (const method of ['pushState', 'replaceState']) {
    context.window.history[method] = (state, title, hash) => {
      calls.push([method, hash]); context.window.location.hash = hash;
    };
  }
  for (const name of [
    'resetUserManagementAuthorityState', 'resetDeletedVehicleAuthorityState',
    'invalidateVehicleLocationsRefresh', 'workshopResetFocusedBooking', 'teardownWorkshopPlannerScope',
    'teardownWorkshopEligibilityOverview', 'releaseHeavyViewDom', 'ensureOperationalRefreshControls',
    'scheduleWorkflowFloatingHeaderUpdate', 'ensureAppDataAvailable', 'renderKpis',
    'renderIncomingDashboardBoard', 'renderWorkshopPlannerWhenReady', 'closeVehicleModal',
    'resetPdcAuditorAuthorityState', 'resetServerAiIntakeAuthorityState', 'initServerAiIntakeIfAvailable',
    'refreshServerAiIntake', 'loadSharedNavisionVisibleRows', 'initEmailVehicleLocationsIfAvailable',
    'resetEmailVehicleLocations', 'cancelWorkshopPlannerRender', 'removeWorkshopRecoveryListeners',
    'clearSharedNavisionVisibilityReconnectTimer', 'releaseSharedNavisionVisibilityChannel'
  ]) context[name] = () => calls.push(name);
  vm.createContext(context);
  vm.runInContext([
    between('function workshopViewFromLocation()', '\nfunction init()'),
    between('function setAdminNavigationExpanded(', '\nfunction resetDeletedVehicleAuthorityState()'),
    between('function userManagementAdministratorActive()', '\nfunction resetUserManagementAuthorityState()'),
    between('function showView(view, options)', '\nconst HEAVY_VIEW_HOSTS'),
    between('function renderActiveView()', '\nfunction navisionOrderType(')
  ].join('\n'), context);
  for (const name of ['pdc-auth-ready', 'pdc-auth-locked']) {
    const start = source.indexOf(`window.addEventListener?.('${name}', () => {`);
    const end = source.indexOf('\n});', start) + '\n});'.length;
    vm.runInContext(source.slice(start, end), context);
  }
  return { context, calls, nodes, emit(name) { handlers[name].forEach(handler => handler()); } };
}

test('an administrator hash link opens Update history and expands the Admin menu', () => {
  const { context, calls, nodes } = harness();
  context.window.location.hash = '#/update-history';
  const route = context.workshopViewFromLocation();
  assert.equal(route, 'update-history');
  context.showView(route, { historyMode: 'replace' });
  assert.equal(context.app.currentView, 'update-history');
  assert.equal(nodes.get('page-title').textContent, 'Update history');
  assert.equal(nodes.get('update-history').classList.contains('active'), true);
  assert.equal(nodes.get('nav-update-history').classList.contains('active'), true);
  assert.equal(nodes.get('nav-admin-toggle').getAttribute('aria-expanded'), 'true');
  assert.equal(nodes.get('nav-admin-menu').hidden, false);
  assert.equal(calls.filter(call => call === 'history-open').length, 1);
});

test('browser history navigation opens the page without creating another history entry', () => {
  const { context, calls } = harness();
  context.window.location.hash = '#/update-history';
  context.showView(context.workshopViewFromLocation(), { historyMode: 'none' });
  assert.equal(calls.some(call => Array.isArray(call)), false);
  assert.equal(calls.includes('history-open'), true);
});

for (const role of [null, 'viewer', 'operator', 'importer']) {
  test(`${role || 'signed-out'} cannot open the administrator update report directly`, () => {
    const { context, calls, nodes } = harness(role);
    context.window.location.hash = '#/update-history';
    context.showView(context.workshopViewFromLocation());
    assert.equal(context.app.currentView, 'dashboard');
    assert.equal(context.window.location.hash, '#/dashboard');
    assert.equal(calls.includes('history-reset'), true);
    assert.equal(calls.includes('history-open'), false);
    assert.equal(nodes.get('update-history').classList.contains('active'), false);
  });
}

test('leaving Update history closes its report lifecycle while the next view renders', () => {
  const { context, calls } = harness();
  context.showView('update-history');
  context.showView('dashboard');
  assert.equal(calls.filter(call => call === 'history-close').length, 1);
  assert.equal(context.app.currentView, 'dashboard');
});

test('losing the administrator role clears Update history and replaces its route', () => {
  const { context, calls, emit } = harness();
  context.showView('update-history');
  context.window.PDC_AUTH_CONTEXT = { role: 'operator', userId: 'synthetic-admin' };
  emit('pdc-auth-ready');
  assert.equal(context.app.currentView, 'dashboard');
  assert.equal(calls.includes('history-reset'), true);
  assert.ok(calls.some(call => Array.isArray(call) && call[0] === 'replaceState' && call[1] === '#/dashboard'));
});

test('sign-out clears the open report and collapses the administrator navigation', () => {
  const { context, calls, nodes, emit } = harness();
  context.showView('update-history');
  context.window.PDC_AUTH_CONTEXT = null;
  emit('pdc-auth-locked');
  assert.equal(calls.includes('history-reset'), true);
  assert.equal(context.app.currentView, 'dashboard');
  assert.equal(nodes.get('nav-admin-group').hidden, true);
  assert.equal(nodes.get('nav-admin-menu').hidden, true);
  assert.equal(nodes.get('nav-admin-toggle').getAttribute('aria-expanded'), 'false');
});

test('fitter-only routing remains authoritative even with an administrator hash', () => {
  const { context, calls, emit } = harness('fitter');
  context.showView('update-history');
  assert.equal(context.app.currentView, 'fitters');
  assert.equal(context.window.location.hash, '#/fitters');
  assert.equal(calls.includes('history-open'), false);
  assert.equal(calls.includes('fitter-open'), true);
  emit('pdc-auth-ready');
  assert.equal(context.app.currentView, 'fitters');
  assert.equal(calls.includes('initServerAiIntakeIfAvailable'), false);
});
