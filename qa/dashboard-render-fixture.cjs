'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

// Full application functions, synthetic vehicle data, and inert DOM/network
// boundaries. This measures HTML generation, not browser layout or network time.
function createFixture({ appPath = path.join(root, 'app.js'), vehicleCount = 102, notesPerVehicle = 0 } = {}) {
  const stats = { reads: 0, classifications: 0, renders: 0, keys: new Map() };
  const storage = new Map();
  const node = { querySelector: () => null, querySelectorAll: () => [],
    classList: { add() {}, remove() {}, contains: () => false, toggle() {} },
    style: {}, dataset: {}, addEventListener() {}, getBoundingClientRect: () => ({ width: 1200 }),
    setAttribute() {}, removeAttribute() {}, replaceChildren() {}, appendChild() {}, innerHTML: '' };
  const host = { ...node };
  const hosts = new Map([['#incoming-main-board', host], ['#kpi-grid', { ...node }]]);
  const context = { console, URL, URLSearchParams, Date, Intl, TextEncoder, TextDecoder, structuredClone,
    localStorage: {
      getItem(key) { stats.reads++; stats.keys.set(key, (stats.keys.get(key) || 0) + 1); return storage.get(key) ?? null; },
      setItem: (key, value) => storage.set(key, String(value)), removeItem: key => storage.delete(key),
    },
    document: { ...node, querySelector: key => hosts.get(key) || null, readyState: 'loading', body: node,
      documentElement: node, getElementById: key => hosts.get('#' + key) || null,
      createElement: () => ({ ...node, querySelector: () => ({ ...node }) }), head: node },
    setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {}, addEventListener() {},
    location: { hash: '#/dashboard' }, requestAnimationFrame: () => 0, innerWidth: 1400,
    getComputedStyle: () => ({ display: 'block' }),
  };
  context.window = context;
  context.globalThis = context;
  vm.createContext(context);
  for (const file of [path.join(root, 'workshop-eligibility.js'), appPath]) {
    vm.runInContext(fs.readFileSync(file, 'utf8'), context, { filename: file });
  }
  const rows = Array.from({ length: vehicleCount }, (_, i) => ({ stock: String(13070000 + i), id: 'fixture-' + i,
    source: 'Manual', pdcLocation: ['PMB', 'YH', 'IT'][i % 3], pdcSheetVisible: true,
    vehicle: 'Hilux', client: 'Fixture customer', pdcRequiresFitting: true, pdcRequiresDetailing: true,
    pdcRequiresSublet: true, pmbSubletProvider: 'Fixture provider', pmbSubletBookingDate: '2026-09-15',
    pmbSubletExpectedReturnDate: '2026-09-16' }));
  for (const row of rows) {
    if (notesPerVehicle) storage.set('vehicleTrackingCoreNotes:' + row.stock,
      JSON.stringify(Array.from({ length: notesPerVehicle }, (_, i) => 'Fixture note ' + i + ': ' + 'service reminder '.repeat(24))));
  }
  context.app.data = rows;
  context.ensureDashboardWorkshopProjectionReady = () => false;
  for (const name of ['ensureOperationalRefreshControls', 'updateInlineSelectionBars', 'updateCollapseToggleButtons',
    'bindAuthenticatedOperationSummaries', 'restoreIncomingBoardDisclosureState', 'bindVehicleLabelButtons',
    'bindFixFirstRows', 'revealSingleVehicleSearchResult', 'bindIncomingCardSelection', 'bindRftCollectedInputs']) context[name] = () => {};
  context.captureIncomingBoardDisclosureState = () => ({});
  const classify = context.incomingBucketForVehicle;
  context.incomingBucketForVehicle = (...args) => { stats.classifications++; return classify(...args); };
  const render = context.renderIncomingDashboardBoard;
  context.renderIncomingDashboardBoard = (...args) => { stats.renders++; return render(...args); };
  const resetStats = () => { stats.reads = 0; stats.classifications = 0; stats.renders = 0; stats.keys.clear(); };
  resetStats();
  return { context, stats, storage, host, rows, resetStats,
    evaluate: script => vm.runInContext(script, context),
    loadHelper: file => vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file }) };
}
module.exports = { createFixture };
