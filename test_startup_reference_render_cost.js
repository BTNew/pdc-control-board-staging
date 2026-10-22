/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createWorkshopReferenceDataService } = require('./workshop-reference-data-service');

const source = fs.readFileSync(require.resolve('./app.js'), 'utf8').replace(/\r\n/g, '\n');
const tick = () => new Promise(resolve => setImmediate(resolve));
function section(start, end) {
  const begin = source.indexOf(start);
  const finish = source.indexOf(end, begin);
  assert.ok(begin >= 0 && finish > begin, `Missing application section: ${start}`);
  return source.slice(begin, finish);
}

// Exercise the actual reference service and application callbacks with inert
// clients. No authentication, customer records or network are used here.
function fixture(route) {
  const stats = { referenceReads: [], backupReads: [], adminRenders: 0,
    kpiRenders: 0, configSyncs: 0, plannerSchedules: 0, shownMechanics: [] };
  const subscriptions = new Map();
  const backupHost = { innerHTML: '' };
  const backupPanel = { hidden: false };
  const mechanicHost = {};
  let mechanicName = 'Fixture mechanic';
  const backupClient = {
    from(table) {
      return { select() { return this; }, eq() { return this; }, order() { return this; },
        limit() {
          stats.backupReads.push(table);
          return Promise.resolve({ data: [], error: null });
        } };
    },
  };
  const context = {
    console, Date, Promise, Map, activeRenderJsonCache: null,
    PRODUCTION_SUPABASE_PROJECT_REF: 'production-fixture',
    app: { currentView: route },
    window: {
      PDC_AUTH_CONTEXT: { role: 'administrator', userId: 'fixture-user' },
      PDC_SUPABASE_CONFIG: { projectRef: 'fixture-project' },
      PDC_SUPABASE: backupClient,
    },
    $: key => ({ '#backup-status-panel': backupPanel,
      '#backup-status-content': backupHost, '#mechanic-list-admin': mechanicHost })[key] || null,
    $$: () => [],
    workshopSharedModeEnabled: () => true,
    workshopReferenceDataRoleCanRead: () => true,
    createWorkshopReferenceSupabaseClient: () => ({ rpc: async (_token, name) => {
      stats.referenceReads.push(name);
      return { ok: true, status: 200, body: name === 'get_workshop_configuration' ? {}
        : name === 'list_technicians' ? [{ name: mechanicName }] : [] };
    } }),
    createWorkshopReferenceDataService,
    getPdcSupabaseAccessToken: () => 'fixture-session',
    createPdcSupabaseTableRealtimeSubscription: (table, handlers) => {
      subscriptions.set(table, handlers);
      return { unsubscribe() {} };
    },
    workshopSyncConfigFromSharedSettings: () => { stats.configSyncs++; },
    renderKpis: () => { stats.kpiRenders++; },
    scheduleWorkshopPlannerRender: () => { stats.plannerSchedules++; },
    workshopTechnicianAdminCanMutate: () => true,
    renderAdminList: (host, rows) => {
      if (host === mechanicHost) stats.shownMechanics = rows.map(row => row.name);
    },
    loadMechanics: () => context.window.__workshopReferenceDataService?.getCachedTechnicians().rows || [],
    renderSubletProviderAdminList() {}, loadSalespersons: () => [], escapeHtml: String,
    startWorkshopReferenceDataReconciliationTimer() {}, stopWorkshopReferenceDataReconciliationTimer() {},
    ensureAppDataAvailable() {},
  };
  vm.createContext(context);
  for (const code of [
    section('function initWorkshopReferenceDataServiceIfAvailable()', '// Lazily constructs the shared workshop data service'),
    section('function renderAdminLists(', '// ---------------------------------------------------------------------\n// Administrator-only User Management screen.'),
    section('function refreshWorkshopReferenceData()', '// Periodic lightweight reconciliation'),
    section('function renderActiveView()', 'function navisionOrderType('),
  ]) vm.runInContext(code, context);
  const renderAdminLists = context.renderAdminLists;
  context.renderAdminLists = options => { stats.adminRenders++; return renderAdminLists(options); };
  return { context, stats, subscriptions, backupHost, setMechanicName: name => { mechanicName = name; } };
}

test('reference refreshes never fetch hidden Setup history or rebuild unrelated counters', async () => {
  for (const route of ['dashboard', 'workshop', 'parts', 'qc', 'sublet', 'workflow']) {
    const f = fixture(route);
    assert.equal((await f.context.refreshWorkshopReferenceData()).ok, true);
    await tick();
    assert.equal(f.stats.referenceReads.length, 5, `${route}: all shared reference reads remain`);
    assert.equal(f.stats.adminRenders, 0, `${route}: hidden Setup stays untouched`);
    assert.equal(f.stats.backupReads.length, 0, `${route}: no unrelated backup queries`);
    assert.equal(f.stats.kpiRenders, route === 'dashboard' ? 9 : 0, `${route}: only visible counters update`);
    assert.equal(f.stats.configSyncs, 9, `${route}: configuration remains synchronized`);
    assert.equal(f.stats.plannerSchedules, route === 'workshop' ? 9 : 0, `${route}: planner notifications preserved`);
  }
});

test('visible Setup lists update after reference reads without multiplying backup-history requests', async () => {
  const f = fixture('lists');
  f.context.renderActiveView();
  await tick();
  assert.equal(f.stats.backupReads.length, 3, 'opening Setup reads each backup-history source once');
  await f.context.refreshWorkshopReferenceData();
  await tick();
  assert.equal(f.stats.adminRenders, 10, 'entry plus all reference-state updates still render Setup');
  assert.deepEqual(f.stats.shownMechanics, ['Fixture mechanic']);
  assert.equal(f.stats.backupReads.length, 3, 'reference responses do not reload independent backup history');
  assert.equal(f.stats.kpiRenders, 0);
  assert.equal(f.stats.configSyncs, 9);
  await f.context.renderBackupStatusPanel();
  assert.equal(f.stats.backupReads.length, 6, 'the explicit backup refresh remains fresh');
  assert.match(f.backupHost.innerHTML, /Last recorded success/);
  f.context.renderActiveView();
  await tick();
  assert.equal(f.stats.backupReads.length, 6, 'a fresh Setup re-render does not poll backup history again');
});

test('Setup backup history stays quiet while the page is hidden and reloads once it is stale', async () => {
  const hidden = fixture('lists');
  hidden.context.document = { visibilityState: 'hidden', addEventListener() {} };
  hidden.context.renderActiveView();
  await tick();
  assert.equal(hidden.stats.backupReads.length, 0, 'a hidden Setup view does not poll');
  hidden.context.document.visibilityState = 'visible';
  hidden.context.renderActiveView();
  await tick();
  assert.equal(hidden.stats.backupReads.length, 3, 'showing Setup loads history once');
  hidden.context.renderActiveView();
  await tick();
  assert.equal(hidden.stats.backupReads.length, 3, 'the visible view keeps that result');
  hidden.context.app.backupStatusLoadedAt = Date.now() - (15 * 60 * 1000 + 1);
  hidden.context.renderActiveView();
  await tick();
  assert.equal(hidden.stats.backupReads.length, 6, 'the slow poll window loads history again');
});

test('opening Setup after a hidden realtime update shows current references and loads backup history', async () => {
  const f = fixture('parts');
  await f.context.refreshWorkshopReferenceData();
  f.setMechanicName('Updated fixture mechanic');
  f.subscriptions.get('workshop_technicians').onChange({});
  await tick();
  assert.equal(f.stats.backupReads.length, 0);
  assert.equal(f.stats.adminRenders, 0);
  f.context.app.currentView = 'lists';
  f.context.renderActiveView();
  await tick();
  assert.deepEqual(f.stats.shownMechanics, ['Updated fixture mechanic']);
  assert.equal(f.stats.backupReads.length, 3);
  assert.equal(f.stats.configSyncs, 11, 'hidden realtime changes still sync configuration');
});

test('reference-only Setup updates immediately hide backup history after an administrator downgrade', async () => {
  const f = fixture('lists');
  f.context.renderActiveView();
  await tick();
  await f.context.refreshWorkshopReferenceData();
  const panel = f.context.$('#backup-status-panel');
  assert.equal(panel.hidden, false);
  assert.equal(f.stats.backupReads.length, 3);
  f.context.window.PDC_AUTH_CONTEXT.role = 'operator';
  const refresh = f.context.refreshWorkshopReferenceData();
  assert.equal(panel.hidden, true, 'authority is enforced before reference requests finish');
  await refresh;
  await tick();
  assert.equal(panel.hidden, true);
  assert.equal(f.stats.backupReads.length, 3, 'hiding unavailable history makes no additional backup reads');
});
