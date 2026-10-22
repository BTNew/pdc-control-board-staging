/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const layout = require('./pdc-workshop-departments');
const eligibility = require('./workshop-eligibility');
const appSource = fs.readFileSync(require.resolve('./app.js'), 'utf8');
const plannerSource = fs.readFileSync(require.resolve('./workshop-planner.js'), 'utf8');
const html = fs.readFileSync(require.resolve('./index.html'), 'utf8');
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function section(source, start, end) {
  const from = source.indexOf(start), to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from, start);
  return source.slice(from, to);
}
function element(id = '', dataset = {}) {
  const classes = new Set(), handlers = {};
  return { id, dataset, handlers, innerHTML: '', textContent: '',
    classList: { toggle(name, on) { on ? classes.add(name) : classes.delete(name); },
      remove(name) { classes.delete(name); }, contains: name => classes.has(name) },
    addEventListener(name, handler) { handlers[name] = handler; },
    click() { handlers.click?.({}); }, querySelector() { return null; }, replaceChildren() {} };
}
function navigationFixture(department = '', role = 'operator') {
  const nav = [...html.matchAll(/<button[^>]*class="nav-item[^>]*data-view="([^"]+)"[^>]*>/g)].map(match => element('', {
    view: match[1], workshopNavDepartment: /data-workshop-nav-department="([^"]+)"/.exec(match[0])?.[1],
  }));
  const headings = ['138', '139', 'shared'].map(owner => element('', { workshopNavDepartment: owner }));
  const views = ['dashboard', 'workshop', 'workflow', 'sublet', 'bus-pit', 'fitters'].map(id => element(id));
  const title = element('page-title'), root = element('workshop-planner-root');
  const state = { stage: 'BUS_4X4', busBayGroup: 'qa', busShowAllBays: true, date: '2026-10-19' };
  const history = [], listeners = {}, calls = { teardown: 0, renders: 0 };
  const context = { console, WORKSHOP_ELIGIBILITY: eligibility, WORKSHOP_CANONICAL_STATION_DEFS: eligibility.stationDefinitions,
    PMB_BAY_STATION_SEQUENCE: [], PRODUCTION_DEPARTMENT_VIEWS: {}, PRODUCTION_FLOW_DEFS: [],
    WORKSHOP_STAGE_SEQUENCE: eligibility.workshopPlannerStageCodes(), WORKSHOP_VISIBLE_STAGE_SEQUENCE: eligibility.workshopPlannerStageCodes(),
    app: { currentView: 'dashboard', currentRequestedView: 'dashboard', workshopPlanner: state },
    window: { PDC_WORKSHOP_DEPARTMENTS: layout, PDC_AUTH_CONTEXT: { role },
      PDC_DEPARTMENT_FILTER: { getSelection: () => department }, location: { hash: '#/dashboard' }, history: {},
      addEventListener(name, callback) { (listeners[name] ||= []).push(callback); },
      __workshopDataService: { getLastSnapshot: () => null } },
    document: { body: element(), getElementById: id => views.find(view => view.id === id),
      querySelector(selector) { return selector === '#workshop-planner-root' ? root
        : nav.find(node => selector.includes(`data-view="${node.dataset.view}"`)) || null; },
      querySelectorAll(selector) { return selector === '[data-workshop-nav-department]'
        ? [...headings, ...nav.filter(node => node.dataset.workshopNavDepartment)]
        : nav.filter(node => selector.includes(`data-view="${node.dataset.view}"`)); } },
    $: selector => selector === '#page-title' ? title : null,
    $$: selector => selector === '.view' ? views : selector === '.nav-item[data-view]' ? nav : [],
    on(node, name, callback) { node?.addEventListener(name, callback); },
    syncAdminNavigationVisibility() {}, setAdminNavigationExpanded() {},
    workshopCombinedPlannerRollbackEnabled: () => false, workshopEligibilitySharedAuthorityEnabled: () => false,
    normalizePmbStage: value => String(value || '').toUpperCase(), pmbStageLabel: String,
    workshopState: () => state, workshopSharedModeActive: () => true, workshopSyncConfigFromSharedSettings() {},
    workshopEnsureDedicatedShell: () => root, workshopStationSnapshotEmptyStateHtml: () => 'Loading station',
    workshopApplyOpenDateDefault() { delete context.app.pendingWorkshopOpenToday; },
    workshopClearSelectedDetail() {}, workshopStageBayCount: () => 10,
    cancelWorkshopPlannerRender() {}, teardownWorkshopPlannerScope() { calls.teardown++; },
    teardownWorkshopEligibilityOverview() {}, releaseHeavyViewDom() {}, ensureOperationalRefreshControls() {},
    scheduleWorkflowFloatingHeaderUpdate() {}, escapeHtml: esc,
    renderActiveView() { calls.renders++; if (context.app.currentView === 'workshop') context.renderWorkshopPlanner(); },
  };
  for (const method of ['pushState', 'replaceState']) context.window.history[method] = (_state, _title, hash) => {
    history.push({ method, hash }); context.window.location.hash = hash;
  };
  vm.createContext(context);
  const pieces = [
    section(appSource, 'const WORKSHOP_STATION_ROUTE_DEFS', 'const WORKSHOP_CONTROL_BOARD_STATIONS'),
    section(appSource, 'function workshopViewFromLocation()', 'function init()'),
    section(appSource, 'function showView(view, options)', 'const HEAVY_VIEW_HOSTS'),
    section(appSource, 'function openWorkshopPlannerForStage(', 'function controlBoardStationPipelineMetrics('),
    section(appSource, 'function pdcSyncWorkshopDepartmentNavigation()', 'function renderWorkflowBoard()'),
    section(appSource, 'function bindNav()', "  on($('#operator-profile'),") + '\n}',
    section(plannerSource, 'function workshopDepartmentLayout()', 'function workshopBayRowsHtml('),
    section(plannerSource, 'function workshopResetFocusedBooking()', 'function workshopExitFocusedBooking()'),
    section(plannerSource, 'function renderWorkshopPlanner(options', 'function bindWorkshopPlanner('),
    section(plannerSource, 'function bindWorkshopPlanner(root)', "  if (root.dataset.workshopIncrementalBound !== '1') {") + '\n}',
  ];
  pieces.forEach(piece => vm.runInContext(piece, context));
  context.bindNav();
  return { context, nav, views, title, root, state, history, calls,
    click(view) { const button = nav.find(node => node.dataset.view === view); assert.ok(button, view); button.click(); },
    visible() { return nav.filter(node => node.dataset.workshopNavDepartment && !node.classList.contains('pdc-department-hidden')).map(node => node.dataset.view); },
    selected() { return nav.filter(node => node.classList.contains('active')).map(node => node.dataset.view); },
    department(value) { department = value; listeners['pdc-department-filter-changed'].forEach(callback => callback()); },
    restore(hash, event = 'popstate') { context.window.location.hash = hash; listeners[event].forEach(callback => callback()); },
  };
}

test('Vehicle Locations sidebar initializes persisted department and switches all category groups', () => {
  const f = navigationFixture('138');
  const bus = layout.BUS_WORK.map(item => item.view), shared = ['planner-tint', 'planner-tyre'];
  const pmb = ['planner-hoist', 'planner-fab', 'planner-fitting', 'planner-elec'];
  assert.deepEqual(f.visible(), [...bus, ...shared]);
  assert.equal(f.context.app.currentView, 'dashboard');
  f.department('139'); assert.deepEqual(f.visible(), [...pmb, ...shared]);
  f.department(''); assert.deepEqual(f.visible(), [...bus, ...pmb, ...shared]);
});

test('every Bus sidebar category selects its own route and bays despite a saved all-bays preference', () => {
  for (const category of layout.BUS_WORK.filter(item => !item.external)) {
    const f = navigationFixture('138');
    f.click(category.view);
    assert.equal(f.context.app.currentView, 'workshop');
    assert.equal(f.context.window.location.hash, '#/' + category.path);
    assert.equal(f.state.busBayGroup, category.id);
    assert.equal(f.state.busShowAllBays, false);
    assert.deepEqual(Array.from(f.context.workshopVisibleBays('BUS_4X4')), category.bays);
    assert.deepEqual(f.selected(), [category.view]);
    assert.equal(f.views.find(view => view.id === 'workshop').classList.contains('active'), true);
    assert.match(f.title.textContent, new RegExp(category.label));
  }
});

test('Back, hash navigation and reload restore category selection without resetting the date or refetching the station', () => {
  const f = navigationFixture('138');
  f.click('planner-bus-mechanical');
  const mechanical = f.context.window.location.hash, teardown = f.calls.teardown;
  f.state.date = '2026-10-22';
  f.click('planner-bus-electrical');
  assert.equal(f.calls.teardown, teardown, 'Category selection reuses the same station authority');
  assert.equal(f.state.date, '2026-10-22');
  const writes = f.history.length;
  f.restore(mechanical);
  assert.equal(f.history.length, writes);
  assert.equal(f.state.busBayGroup, 'mechanical');
  assert.deepEqual(f.selected(), ['planner-bus-mechanical']);
  f.restore('#/workshop/bus-4x4/qa', 'hashchange');
  assert.equal(f.state.busBayGroup, 'qa');
  const reload = navigationFixture('138');
  reload.context.window.location.hash = '#/workshop/bus-4x4/electrical';
  reload.context.showView(reload.context.workshopViewFromLocation(), { historyMode: 'replace' });
  assert.equal(reload.state.busBayGroup, 'electrical');
  assert.deepEqual(reload.selected(), ['planner-bus-electrical']);
  f.click('planner-fitting');
  assert.equal(f.calls.teardown, teardown + 1, 'Changing physical station still tears down the old scope');
});

test('all-bays routes remain available while the sidebar selects individual categories', () => {
  const f = navigationFixture('138'); f.click('planner-bus-mechanical');
  f.context.showView('planner-bus-4x4');
  assert.equal(f.context.window.location.hash, '#/workshop/bus-4x4');
  assert.equal(f.state.busShowAllBays, true);
  assert.deepEqual(Array.from(f.context.workshopVisibleBays('BUS_4X4')), [1,2,3,4,5,6,7,8,9,10]);
  f.click('planner-bus-electrical');
  assert.equal(f.state.busBayGroup, 'electrical');
  assert.equal(f.state.busShowAllBays, false);
  f.restore('#/workshop/bus-4x4');
  assert.equal(f.state.busShowAllBays, true);
  assert.deepEqual(Array.from(f.context.workshopVisibleBays('BUS_4X4')), [1,2,3,4,5,6,7,8,9,10]);
  f.restore('#/workshop/bus-4x4/electrical');
  assert.equal(f.state.busShowAllBays, false);
  assert.deepEqual(Array.from(f.context.workshopVisibleBays('BUS_4X4')), [8,9]);
  f.click('planner-bus-pit');
  assert.equal(f.context.app.currentView, 'bus-pit');
  assert.deepEqual(f.selected(), ['planner-bus-pit']);
});

test('Pit opens an external inspection view with a stable link and no physical planner scope', () => {
  const f = navigationFixture('138'); f.click('planner-bus-pit');
  assert.equal(f.context.app.currentView, 'bus-pit');
  assert.equal(f.context.app.activeWorkshopPlannerStage, '');
  assert.equal(f.context.window.location.hash, '#/workshop/bus-4x4/pit');
  assert.equal(f.views.find(view => view.id === 'bus-pit').classList.contains('active'), true);
  assert.equal(f.views.find(view => view.id === 'sublet').classList.contains('active'), false);
  f.restore('#/dashboard'); f.restore('#/workshop/bus-4x4/pit');
  assert.deepEqual(f.selected(), ['planner-bus-pit']);
  f.department('139'); assert.equal(f.context.app.currentRequestedView, 'planner-fitting');
});

test('new category links retain fitter routing and unknown category paths fail closed', () => {
  const f = navigationFixture('138', 'fitter'); f.click('planner-bus-pit');
  assert.equal(f.context.app.currentView, 'fitters');
  assert.equal(f.context.window.location.hash, '#/fitters');
  const normal = navigationFixture(); normal.restore('#/workshop/bus-4x4/invented');
  assert.equal(normal.context.app.currentView, 'workflow');
});

function pitVehicle(overrides = {}) {
  return { stock: 'PIT-1', __emailVehicleServerAuthoritative: true, pdcQcOperationLinesProjectionPresent: true,
    pdcQcOperationLines: [{ lineIdentity: 'source:fixture', description: 'External inspection', department: '138', stageCode: 'PIT_INSPECTION', active: true, completed: false }], ...overrides };
}
test('Pit list uses only active outstanding Pit lines from canonical projections', () => {
  const vehicle = pitVehicle(), line = vehicle.pdcQcOperationLines[0];
  const before = JSON.stringify(vehicle);
  // r406 (F18): Pit by stage or wording in any department; a non-Pit description on another stage is not Pit.
  for (const change of [{ stageCode: 'SUBLET' }, { stageCode: 'BUS_4X4' }, { active: false }, { completed: true }, { rejected: true }]) {
    assert.deepEqual(layout.externalPitLines(pitVehicle({ pdcQcOperationLines: [{ ...line, ...change }] })), []);
  }
  for (const change of [{ __emailVehicleServerAuthoritative: false }, { pdcQcOperationLinesProjectionPresent: false }, { tuneCheckout: { confirmed: true } },
    { pdcLifecycleState: 'completed' }, { pdcLifecycleState: 'collected' }, { pdcLifecycleState: 'deleted' },
    { pdcLocation: 'Completed' }, { completedVehicle: true }, { vehicleCollectedState: true }]) {
    assert.deepEqual(layout.externalPitLines(pitVehicle(change)), []);
  }
  assert.deepEqual(layout.externalPitLines(vehicle), [line]);
  assert.equal(JSON.stringify(vehicle), before);
});

test('Pit renderer distinguishes loading, failed, incomplete and confirmed-empty sources and opens current vehicles', () => {
  let vehicles = [], clicked;
  const host = element(), button = element('', { openStock: 'PIT-1' });
  const context = { app: { currentView: 'bus-pit', emailVehicleLocationRevision: null, sharedNavisionVisibleState: 'loading' },
    window: { PDC_WORKSHOP_DEPARTMENTS: layout }, $: () => host, $$: () => [button], escapeHtml: esc,
    vehicleLocationBoardRows: () => vehicles, displayStockNumber: row => row.stock, vehicleKey: row => row.stock,
    vehicleCustomerName: () => 'Fixture', displayVehicle: () => 'Bus', vehicleJobcardNumber: () => 'JOB',
    vehiclePdcLocation: () => 'PIT', openVehicleModal: stock => { clicked = stock; }, renderBackEndData() {},
    // r401: optional Pit tick column (rendered by app.js helpers, stubbed here).
    pdcPitTickCheckboxHtml: () => '<input type="checkbox" data-pit-tick-line="x" />', pdcPitTickFor: () => null };
  vm.createContext(context);
  vm.runInContext(section(appSource, 'function renderBusPitInspections()', 'function subletRows()'), context);
  vm.runInContext(section(appSource, 'function renderSharedNavisionVisibilityState()', 'function clearSharedNavisionVisibilityReconnectTimer()'), context);
  vm.runInContext(section(appSource, 'function resetEmailVehicleLocations()', 'async function refreshEmailVehicleLocations('), context);
  context.renderBusPitInspections(); assert.match(host.innerHTML, /Loading Pit/); assert.doesNotMatch(host.innerHTML, /No open/);
  context.app.emailVehicleLocationError = 'snapshot_failed';
  context.renderBusPitInspections(); assert.match(host.innerHTML, /unavailable/); assert.doesNotMatch(host.innerHTML, /No open/);
  Object.assign(context.app, { emailVehicleLocationError: '', emailVehicleLocationRevision: 0, sharedNavisionVisibleState: 'ready' });
  vehicles = [pitVehicle({ pdcQcOperationLinesProjectionPresent: false })];
  context.renderBusPitInspections(); assert.match(host.innerHTML, /incomplete/);
  vehicles = []; context.renderBusPitInspections(); assert.match(host.innerHTML, /No open Bus Pit/);
  vehicles = [pitVehicle()]; vehicles[0].pdcQcOperationLines[0].description = 'Inspection <fixture>';
  context.renderBusPitInspections(); assert.match(host.innerHTML, /Inspection &lt;fixture&gt;/);
  assert.doesNotMatch(host.innerHTML, /data-workshop-drop-bay|data-sublet-field/);
  button.click(); assert.equal(clicked, 'PIT-1');
  context.app.operationalRefreshState = 'refreshing'; context.app.operationalRefreshRoute = 'bus-pit';
  context.renderBusPitInspections(); assert.match(host.innerHTML, /Loading Pit/);
  context.app.operationalRefreshState = 'idle';
  context.app.sharedNavisionVisibleState = 'loading';
  context.renderBusPitInspections(); assert.match(host.innerHTML, /Loading Pit/);
  context.app.sharedNavisionVisibleState = 'ready';
  context.renderSharedNavisionVisibilityState(); assert.match(host.innerHTML, /Inspection &lt;fixture&gt;/, 'A later Navision read repaints the inspection list');
  context.app.sharedNavisionVisibleState = 'error';
  context.renderSharedNavisionVisibilityState(); assert.match(host.innerHTML, /unavailable/);
  context.app.sharedNavisionVisibleState = 'ready';
  context.resetEmailVehicleLocations(); assert.match(host.innerHTML, /Loading Pit/); assert.doesNotMatch(host.innerHTML, /PIT-1/);
});

test('unchanged background recovery repaints a Pit error once while coordinated and healthy checks keep their existing paint owner', async () => {
  let response = { ok: false, code: 'snapshot_unavailable' }, paints = 0;
  const context = {
    app: { currentView: 'bus-pit', emailVehicleLocationGeneration: 0, emailVehicleLocationRevision: 7,
      vehicleLocationsRefreshGeneration: 3, emailVehicleLocationService: { snapshot: async () => response } },
    window: { PDC_AUTH_CONTEXT: { userId: 'fixture-user' } }, getPdcSupabaseAccessToken: () => 'fixture-session',
    renderBusPitInspections() { paints++; },
    renderAll() { throw new Error('Unchanged data must not rebuild unrelated views'); },
  };
  vm.createContext(context);
  vm.runInContext(section(appSource, 'async function refreshEmailVehicleLocations(', 'function initEmailVehicleLocationsIfAvailable('), context);
  assert.equal(await context.refreshEmailVehicleLocations(), false);
  assert.equal(paints, 1, 'The failed background read displays its error');
  response = { ok: true, unchanged: true };
  assert.equal(await context.refreshEmailVehicleLocations({ checkRevision: true }), true);
  assert.equal(context.app.emailVehicleLocationError, '');
  assert.equal(paints, 2, 'Successful reconnect clears the visible error even without new rows');
  await context.refreshEmailVehicleLocations({ checkRevision: true });
  assert.equal(paints, 2, 'Healthy unchanged revision checks do not repaint');
  response = { ok: false, code: 'snapshot_unavailable' };
  await context.refreshEmailVehicleLocations({ refreshGeneration: 3 });
  response = { ok: true, unchanged: true };
  await context.refreshEmailVehicleLocations({ checkRevision: true, refreshGeneration: 3 });
  assert.equal(context.app.emailVehicleLocationError, '');
  assert.equal(paints, 2, 'The coordinated refresh retains sole responsibility for its final paint');
  context.app.currentView = 'dashboard';
  context.app.emailVehicleLocationError = 'snapshot_unavailable';
  await context.refreshEmailVehicleLocations({ checkRevision: true });
  assert.equal(paints, 2, 'A hidden Pit view is not rebuilt on recovery');
});
